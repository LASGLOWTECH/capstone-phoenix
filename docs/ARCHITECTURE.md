# Architecture

## 1. Topology diagram

```
Internet ──DNS──▶ myapp.api.euclaseresources.com  /  api.euclaseresources.com
        │
        ▼
  Traefik ingress controller (k3s built-in, node: control-plane-1)
        │  plain HTTP — TLS not yet terminated (see §5, Trade-offs)
        │
        ├──────────────────────────────┐
        ▼                              ▼
  frontend Service               backend Service
        │                              │
        ▼                              ▼
  frontend Pods                  backend Pods
  (nodes: worker-1, worker-2)    (nodes: worker-1, worker-2)
        │
        │  browser calls http://api.euclaseresources.com/api directly
        │  (separate origin, not proxied through the frontend — see §3)
        └────────────────────────────────────────▶│
                                                    ▼
                                       Amazon RDS (PostgreSQL)
                                       taskapp-dev-db.cg7auciogyzi.us-east-1.rds.amazonaws.com:5432
                                       (managed service, outside the k3s cluster —
                                        no in-cluster StatefulSet/PVC for the database)
```

## 2. Node & network

**Nodes** (AWS EC2, `us-east-1`, provisioned via Terraform):

| Node | Role | Private IP | Notes |
|---|---|---|---|
| control-plane-1 | k3s control-plane, master | 10.10.10.99 | Runs k3s server, etcd (embedded), CoreDNS, Traefik, metrics-server, local-path-provisioner |
| worker-1 | k3s worker | 10.10.11.240 | Runs `taskapp` application Pods |
| worker-2 | k3s worker | 10.10.12.135 | Runs `taskapp` application Pods |

*(instance sizes / AMI: Ubuntu 22.04 LTS — [fill in exact instance type, e.g. t3.medium])*

- **CIDR / subnet choices:** Each node sits in its own `/24` off a shared VPC block
  (`10.10.10.0/24` for the control plane, `10.10.11.0/24` and `10.10.12.0/24` for the
  workers), so each role gets an isolated address range and room to grow without
  overlap. Inside the cluster, k3s uses its default overlay ranges: `10.42.0.0/16`
  for Pod IPs and `10.43.0.0/16` for cluster-internal Service IPs, both private to
  the cluster and never routed externally. *(fill in your actual VPC CIDR and public
  vs. private subnet split if applicable)*
- **Firewall:** Security groups only expose what the internet actually needs:
  - **Open to the world:** `80` (and `443` once TLS is added) on the ingress path,
    plus `22` for SSH management.
  - **Internal only:** `6443` (k3s/Kubernetes API server) is restricted to
    traffic *between cluster nodes* — worker nodes join the control plane via its
    **private** IP (`k3s_server_url: https://10.10.10.99:6443` in the Ansible
    inventory), never through a public address. `6443` is deliberately **not**
    exposed publicly: it's the cluster's root of trust — anyone who can reach it
    could potentially schedule arbitrary workloads or read Secrets if they also
    had the join token, so it's kept off the public internet entirely and only
    reachable inside the VPC.
  - The RDS security group only accepts inbound `5432` from the EC2 nodes'
    security group, not from the public internet.

## 3. Request flow

A browser first resolves `myapp.api.euclaseresources.com` to the cluster's public IP
and hits Traefik (k3s's built-in ingress/ServiceLB), which routes the request by
`Host` header to the `taskapp-frontend` Service, load-balanced across two frontend
Pods on `worker-1`/`worker-2`, which serve the static React/Vite build over Nginx.
The compiled JS was built with `VITE_API_URL` baked in at image-build time to point
at `http://api.euclaseresources.com/api`, so when the app makes an API call (e.g.
`POST /api/auth/login`), the browser opens a **second, separate** connection directly
to `api.euclaseresources.com` — a different origin — which Traefik again routes by
`Host` header, this time to the `taskapp-backend` Service, load-balanced across two
Gunicorn-served Flask Pods. The backend authenticates the request, queries Postgres
over `5432` at the RDS endpoint, and returns JSON; the frontend origin is explicitly
allowlisted in the backend's `CORS_ORIGINS` config so the cross-origin call succeeds.

## 4. The single-server assumptions we fixed

| Single-server assumption | Why it breaks at scale | How we fixed it |
|---|---|---|
| Migrate-on-boot in the entrypoint (`alembic upgrade head` before starting Gunicorn) | With 2+ replicas starting concurrently, multiple Pods can race to run the same migration against the same database simultaneously | Alembic's own transactional DDL + `alembic_version` row makes re-running `upgrade head` idempotent, so concurrent/duplicate runs are safe no-ops rather than conflicting; the CD pipeline also runs `alembic upgrade head` once explicitly as an authoritative post-deploy step, independent of individual Pod startup timing |
| Database living on the same box as the app (e.g. `localhost:5432` fallback in the config) | A Postgres data directory tied to one host's local disk means a Pod reschedule to another node loses the data entirely | Moved the database out of the cluster altogether onto **Amazon RDS**, a managed, independently-available Postgres instance addressed by DNS (`DATABASE_HOST`) instead of `localhost` — no in-cluster PVC/StatefulSet for data, so Pods are fully stateless and freely reschedulable |
| `docker run -p 5000:5000` / a fixed host port for the app | Only one process can bind a given host port per node; doesn't scale past one replica per machine and gives no single stable address as Pods move | Kubernetes **Services** (`ClusterIP`) give the frontend and backend each a stable virtual IP/DNS name that transparently load-balances across however many Pod replicas are currently healthy, on whichever node they land on |
| Assuming the app process just stays up (manual restart if it dies) | A crashed process on a single VM needs a human (or a fragile cron/systemd retry) to notice and restart it | Kubernetes **Deployments** continuously reconcile actual vs. desired replica count — a crashed container is automatically restarted, and a failed node's Pods are automatically rescheduled onto healthy nodes |
| Deploying by SSH-ing in, pulling code, and restarting the process in place | That's a hard cutover — the app is down (or serving half-updated code) for the whole restart window | Deployments use a **RollingUpdate** strategy: new Pods are started and confirmed healthy before old ones are terminated, so `kubectl rollout status` only reports success once traffic can be fully served by the new version with no gap |
| Config and credentials hardcoded into the app or a local `.env` file on the server | Every new server needs the same secrets copied/typed in by hand, and secrets end up committed to git or scattered across machines | Non-sensitive config lives in Kubernetes **ConfigMaps** (`CORS_ORIGINS`, `PORT`, `WORKERS`); credentials live in Kubernetes **Secrets** (`DATABASE_*`, `SECRET_KEY`), both injected as environment variables at Pod start — nothing sensitive is baked into the image or committed to source control |

## 5. Choices & trade-offs

- **Raw YAML vs. Helm vs. kustomize:** Used raw Kubernetes YAML manifests directly.
  For a two-service app at this scale, Helm's templating and kustomize's overlay
  system add abstraction the project doesn't yet need — raw manifests keep exactly
  what's deployed fully visible and easy to reason about. This is a clear next
  step if the app grows more environments (dev/staging/prod) that need to share a
  base with small per-environment differences.
- **ingress-nginx vs. k3s Traefik:** Kept k3s's bundled Traefik rather than installing
  ingress-nginx separately. Traefik ships and self-configures automatically with k3s
  (zero extra install/maintenance step), and its `Host`-header-based routing was
  sufficient for splitting `myapp.api.euclaseresources.com` and
  `api.euclaseresources.com` to their respective Services — there was no feature in
  ingress-nginx this project actually needed that Traefik didn't already provide.
- **CNI / NetworkPolicy enforcement:** Using k3s's default CNI (Flannel), with **no
  NetworkPolicies currently enforced** — the `taskapp` namespace's Pods can reach
  each other and the internet freely. This is a known gap: the next hardening step
  would be a default-deny `NetworkPolicy` in the `taskapp` namespace that only
  explicitly allows frontend→backend and backend→egress-to-RDS traffic, since
  right now any compromised Pod in the namespace could reach anything else in it.
- **Secrets approach:** Used plain Kubernetes `Secret` objects (base64-encoded,
  not encrypted-at-rest by default in vanilla k3s) rather than Sealed Secrets or
  External Secrets Operator. This was the fastest path to get credentials out of
  source control and into the cluster for a capstone timeline, but it's a
  deliberate trade-off: raw Secrets aren't safe to commit to git even
  base64-encoded, and anyone with `kubectl exec`/`get secret` access in the
  namespace can read them in plaintext. A production hardening pass would swap
  this for **Sealed Secrets** (encrypt secrets so the encrypted form is safe to
  commit to git) or **External Secrets Operator** pulling from AWS Secrets Manager,
  so no raw secret material ever needs to touch the cluster's etcd unencrypted or
  a git repo at all.

**Also worth noting — TLS:** the current setup serves both `myapp.api.euclaseresources.com`
and `api.euclaseresources.com` over plain HTTP; **cert-manager/TLS termination is not
yet implemented**. The next step here would be installing cert-manager with a
Let's Encrypt `ClusterIssuer` and adding TLS-enabled Ingress resources (or Traefik
`IngressRoute`s) for both hostnames, which would also let the backend's CORS and
cookie settings be tightened to `Secure`-only cookies.