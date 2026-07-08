# Runbook

> **Note on GitOps:** the template below assumes an ArgoCD/GitOps flow (`kubectl apply
> -f gitops/`, "prefer a git commit so Argo stays the source of truth"). **This project
> does not currently use ArgoCD or any pull-based GitOps tool.** Deployment is
> **push-based**: GitHub Actions CD workflows build the image, push it to GHCR, and run
> `kubectl set image` / `kubectl rollout restart` directly against the cluster. Wherever
> the template says "commit and let Argo sync," the real equivalent in this project is
> **"push to `main`"** (which triggers the CD workflow), or a manual `workflow_dispatch`
> run from the Actions tab. This is called out as a real gap/next-step in
> `Architecture.md` — GitOps would be a good hardening step, but isn't in place yet.

---

## Provision from zero

```bash
# 1. Infra (AWS: VPC, subnets, security groups, EC2 instances, RDS)
cd infra/terraform
terraform init
terraform apply
# outputs the 3 EC2 public/private IPs and the RDS endpoint —
# these feed the Ansible inventory and the app's DATABASE_HOST secret

# 2. Cluster bootstrap (installs k3s across control-plane + 2 workers)
cd ../ansible          # this repo's actual path is `infrastructure/`
ansible-playbook -i inventory.yml site.yml
# inventory.yml defines control-plane-1 (10.10.10.99), worker-1 (10.10.11.240),
# worker-2 (10.10.12.135) — workers join via the control plane's PRIVATE ip on :6443

# 3. Kubeconfig
scp ubuntu@<control-plane-public-ip>:/etc/rancher/k3s/k3s.yaml ./kubeconfig
# edit the `server:` line in kubeconfig to point at the control-plane's public IP
export KUBECONFIG=./kubeconfig
kubectl get nodes -o wide     # expect 3 nodes, all Ready

# 4. Platform components
# Traefik + CoreDNS + local-path-provisioner + metrics-server ship bundled with k3s —
# no separate install step needed. cert-manager and ArgoCD are NOT installed
# (see GitOps note above and TLS note in Architecture.md — both are open next-steps).

# 5. Namespace + config
kubectl create namespace taskapp
kubectl apply -f k8s/configmaps/          # CORS_ORIGINS, PORT, WORKERS, etc.
kubectl apply -f k8s/secrets/             # DATABASE_*, SECRET_KEY (populate values out-of-band first — do not commit real values)

# 6. Application deploy
# From here, deployment is handled by the GitHub Actions CD workflows, not manually:
#   push to main (or Actions tab → "Run workflow") on the frontend repo → cd-k8s.yml
#   push to main (or Actions tab → "Run workflow") on the backend repo  → cd.yml
# Each pipeline builds+pushes the image to GHCR, then runs kubectl set image +
# rollout restart + rollout status against the taskapp-frontend / taskapp-backend
# Deployments. The backend CD also runs `alembic upgrade head` as an explicit
# post-deploy step (in addition to it running automatically in the entrypoint).
```

## Day-2 operations

- **Scale a tier:**
  ```bash
  kubectl scale deployment/taskapp-backend -n taskapp --replicas=3
  ```
  Since there's no GitOps tool reconciling from git, this change is **not**
  persisted anywhere except live cluster state — it will be silently reverted to
  whatever replica count is in the Deployment manifest the next time
  `kubectl apply -f k8s/` (or the CD pipeline, if it ever applies manifests rather
  than just `set image`) runs. **Update the replica count in the manifest in source
  control first**, then apply, rather than scaling live-only, or the change won't
  survive the next deploy.

- **Roll back a bad deploy:**
  ```bash
  kubectl rollout history deployment/taskapp-backend -n taskapp
  kubectl rollout undo deployment/taskapp-backend -n taskapp
  # or to a specific revision:
  kubectl rollout undo deployment/taskapp-backend -n taskapp --to-revision=<n>
  kubectl rollout status deployment/taskapp-backend -n taskapp
  ```
  Because both Deployments use `:latest` as the image tag, `rollout undo` only
  reverts the **replica set** (env vars, resource limits, etc.) — it does **not**
  pull a different image, since `:latest` looks identical to Kubernetes before and
  after a bad push. To actually roll back the *code*, re-push/re-tag the previous
  known-good image to `:latest` in GHCR (or re-run the CD workflow from the last-good
  commit) and force a fresh rollout:
  ```bash
  kubectl rollout restart deployment/taskapp-backend -n taskapp
  ```
  **Known next-step:** switch image tags to the Git SHA (`:${{ github.sha }}`)
  instead of `:latest` so `rollout undo` and `set image` behave correctly and a bad
  deploy can be reverted by tag alone, without needing to re-push anything.

- **Run a new migration safely:**
  Migrations run automatically via `docker-entrypoint.sh` (`alembic upgrade head`
  before Gunicorn starts on every Pod boot) and are re-run explicitly as a CD
  pipeline step after rollout. Alembic's transactional DDL + `alembic_version`
  tracking makes `upgrade head` idempotent, so concurrent Pods starting at once
  and re-running it is safe. To run one manually (e.g. to debug or to apply a
  migration without a full deploy):
  ```bash
  kubectl exec -it deploy/taskapp-backend -n taskapp -- alembic upgrade head
  ```
  To check current DB schema state:
  ```bash
  kubectl exec -it deploy/taskapp-backend -n taskapp -- python -c "
  from app import create_app, db
  from sqlalchemy import inspect
  app = create_app()
  with app.app_context():
      print(inspect(db.engine).get_table_names())
  "
  ```

- **Rotate a secret:**
  ```bash
  kubectl create secret generic backend-secret -n taskapp \
    --from-literal=DATABASE_PASSWORD='<new-password>' \
    --from-literal=SECRET_KEY='<new-key>' \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl rollout restart deployment/taskapp-backend -n taskapp
  ```
  A Secret change alone does **not** restart Pods automatically — always follow
  with an explicit `rollout restart`, or the running Pods keep using the old
  values from their environment until they're next recreated.

## Failure recovery

- **A worker node dies / is drained:**
  With 2 replicas per Deployment spread across `worker-1`/`worker-2`, losing one
  worker leaves the other replica still serving traffic through the Service —
  no full outage, reduced capacity only. Kubernetes reschedules the lost Pods onto
  the surviving worker automatically once the node is marked `NotReady` (default
  `node-monitor-grace-period` ~40s, then a `pod-eviction-timeout` before
  rescheduling — expect roughly 1–5 minutes to full recovery depending on image
  pull time, since `imagePullPolicy: Always` means the image is fetched again on
  the new node).
  ```bash
  kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
  kubectl get pods -n taskapp -o wide -w      # watch Pods reschedule onto the remaining worker
  kubectl get nodes                            # confirm the drained node is SchedulingDisabled
  # to bring it back into rotation:
  kubectl uncordon <node-name>
  ```

- **A backend Pod crashloops:**
  ```bash
  kubectl get pods -n taskapp -l app=taskapp-backend
  kubectl describe pod <pod-name> -n taskapp     # check Events at the bottom first —
                                                   # often shows the real cause (OOMKilled,
                                                   # failed probe, image pull error) before
                                                   # you even need the logs
  kubectl logs <pod-name> -n taskapp              # current attempt's output
  kubectl logs <pod-name> -n taskapp --previous   # the crashed attempt's output, if it already restarted
  ```
  Things actually hit and fixed during this project that are worth checking first:
  - **`imagePullPolicy` set to `Never`** instead of `Always` — new pushes silently
    fail to pull (`ErrImageNeverPull`) since the node never re-fetches the image:
    ```bash
    kubectl get deployment taskapp-backend -n taskapp -o jsonpath='{.spec.template.spec.containers[0].imagePullPolicy}'
    ```
  - **A `command`/`args` override on the container spec** bypassing
    `docker-entrypoint.sh` entirely (and therefore skipping the DB-wait and
    migration step):
    ```bash
    kubectl get deployment taskapp-backend -n taskapp -o jsonpath='{.spec.template.spec.containers[0].command}'
    kubectl get deployment taskapp-backend -n taskapp -o jsonpath='{.spec.template.spec.containers[0].args}'
    # if either returns a value, remove it:
    kubectl patch deployment taskapp-backend -n taskapp --type=json \
      -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/command"}]'
    ```
  - **Migration failure** (e.g. `relation "users" does not exist`) — check for an
    Alembic traceback in the logs; usually means the DB was fresh/reset and
    migrations hadn't been run yet, or the entrypoint script wasn't actually being
    executed (see the `command` override cause above).

- **A bad migration:**
  Since the database is **Amazon RDS**, not an in-cluster Postgres, DB-level
  recovery is via RDS's own mechanisms rather than a PVC:
  ```bash
  # roll the migration back one step (if the migration defines a working downgrade()):
  kubectl exec -it deploy/taskapp-backend -n taskapp -- alembic downgrade -1
  ```
  If the migration already corrupted data beyond what `downgrade()` can undo,
  restore from an RDS automated snapshot or point-in-time recovery
  (via the AWS Console or `aws rds restore-db-instance-to-point-in-time`), then
  update `DATABASE_HOST` in `backend-secret` to point at the restored instance and
  restart the backend Deployment. *(Confirm current RDS backup retention window /
  Multi-AZ status and note it here — not something this session verified.)*

- **Database (RDS) reachability issues:**
  There's no in-cluster Postgres Pod/PVC to fail over in this architecture — the
  equivalent failure mode is the backend losing connectivity to RDS. Diagnose with:
  ```bash
  kubectl exec -it deploy/taskapp-backend -n taskapp -- nc -zv <DATABASE_HOST> 5432
  ```
  and check the RDS security group still allows inbound `5432` from the EC2
  nodes' security group, and that the RDS instance itself is `Available` in the
  AWS Console. **Known next-step:** RDS Multi-AZ isn't confirmed enabled — if it
  isn't, a single AZ outage takes the database down with no automatic failover;
  worth verifying and enabling before relying on this in a real production sense.