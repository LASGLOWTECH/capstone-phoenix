# TaskApp

Capstone project for the completion of Phoenix's DevOps Engineering course, by **austinoasaz**.

🔗 **Live app:** http://myapp.api.euclaseresources.com/

---

## Overview

TaskApp is a full-stack task management application, containerized and deployed to a
self-managed **Kubernetes (k3s)** cluster via automated CI/CD pipelines. Each service
(frontend and backend) has its own build, test, and deployment workflow, publishing
Docker images to GitHub Container Registry (GHCR) and rolling them out to the cluster
with zero manual intervention.

**Stack:**
- **Frontend:** React + Vite, served via Nginx (static build, containerized)
- **Backend:** Flask + PostgreSQL (Gunicorn WSGI server, Alembic migrations)
- **Database:** PostgreSQL (Amazon RDS)
- **Containerization:** Docker, images published to GHCR
- **Orchestration:** Kubernetes (k3s) — 1 control-plane node + 2 worker nodes
- **Infrastructure provisioning:** Terraform (AWS VPC, subnets, security groups, EC2 instances, RDS)
- **Configuration management:** Ansible (k3s install and cluster bootstrap on top of the provisioned EC2s)
- **CI/CD:** GitHub Actions (separate pipelines per service)
- **Hosting:** AWS EC2 (Ubuntu 22.04 LTS)

---

## Architecture

```
                        ┌─────────────────────────┐
                        │   Terraform (AWS infra)  │
                        │  VPC, subnets, SGs,      │
                        │  EC2 instances, RDS      │
                        └────────────┬─────────────┘
                                     │ provisions
                                     ▼
                        ┌─────────────────────────┐
                        │   Ansible (config mgmt)  │
                        │  installs k3s on the      │
                        │  provisioned EC2 nodes    │
                        └────────────┬─────────────┘
                                     │
                                     ▼
                        ┌─────────────────────────┐
                        │   GitHub Actions (CI/CD) │
                        │  build → test → push     │
                        │  image → deploy to k3s    │
                        └────────────┬─────────────┘
                                     │
                                     ▼
                        ┌─────────────────────────┐
                        │   GHCR (image registry)  │
                        └────────────┬─────────────┘
                                     │
                                     ▼
        ┌────────────────────────────────────────────────────┐
        │                  k3s Cluster (3 nodes)              │
        │                                                      │
        │   control-plane-1        worker-1        worker-2    │
        │  (k3s server, etcd)    (taskapp pods)  (taskapp pods) │
        │                                                      │
        │   Namespace: taskapp                                 │
        │   ├─ taskapp-frontend (Deployment, 2 replicas)        │
        │   ├─ taskapp-backend  (Deployment, 2 replicas)        │
        │   ├─ ConfigMaps / Secrets (env config, DB creds)      │
        │   └─ Services (LoadBalancer via k3s ServiceLB)        │
        └───────────────────────────┬──────────────────────────┘
                                     │
                                     ▼
                        ┌─────────────────────────┐
                        │  PostgreSQL (Amazon RDS)  │
                        └─────────────────────────┘
```

- `myapp.api.euclaseresources.com` → frontend Service
- `api.euclaseresources.com` → backend API Service (separate origin; CORS-enabled)

---

## CI/CD Pipelines

Each service is built, tested, and deployed independently, triggered on pushes to `main`
that touch relevant paths.

### Frontend

- **CI** (`ci.yml`) — installs dependencies, lints, type-checks, builds a production
  Vite bundle, and uploads it as a build artifact for verification.
- **CD** (`cd-k8s.yml`) — builds a Docker image (Nginx serving the static Vite build),
  passing `VITE_API_URL` as a build-time argument so the compiled bundle points at the
  correct backend origin, pushes the image to GHCR, and updates the
  `taskapp-frontend` Deployment in the `taskapp` namespace, forcing a rollout restart
  and waiting for it to complete.

### Backend

- **CI** (`ci.yml`) — runs linting (flake8, black, isort), a security scan (Bandit),
  and the test suite (pytest) against a throwaway Postgres service container, running
  Alembic migrations first to set up the test schema.
- **CD** (`cd.yml`) — builds and pushes the Flask Docker image to GHCR, updates the
  `taskapp-backend` Deployment, forces a rollout restart, waits for it to complete,
  and runs `alembic upgrade head` against the production database as a final
  verification step.

### Database migrations

Alembic migrations run automatically on every backend container start (handled in
`docker-entrypoint.sh`, which waits for the database to accept connections, runs
`alembic upgrade head`, then starts Gunicorn). This makes schema updates self-healing
on every pod restart, in addition to the explicit migration step in the CD pipeline.

---

## Configuration

Backend configuration is supplied via Kubernetes `Secret` and `ConfigMap` objects in
the `taskapp` namespace (database credentials, `SECRET_KEY`, `CORS_ORIGINS`, `PORT`,
`WORKERS`, etc.), so no sensitive values are baked into images or committed to source
control.

Frontend configuration (the backend API URL) is supplied at **build time** via the
`VITE_API_URL` build argument, since Vite inlines environment variables into the
compiled JS bundle rather than reading them at runtime.

---

## Local Development

**Frontend**
```bash
npm install
npm run dev
```

**Frontend build**
```bash
npm run build
```

**Backend**
```bash
pip install -r requirements.txt
alembic upgrade head
flask --app run run --debug
```

---

## Infrastructure

Infrastructure is split into two distinct layers:

- **Terraform** provisions the underlying AWS resources from scratch: the VPC,
  public/private subnets, security groups, the three EC2 instances (one control-plane,
  two workers), and the RDS PostgreSQL instance. No AWS resources were created manually
  through the console — everything is defined as code and reproducible.
- **Ansible** takes over once the EC2 instances exist, installing and configuring k3s
  across the three nodes (control plane + workers) and any base OS packages needed,
  defined in `infrastructure/`. The Ansible inventory describes the resulting
  three-node cluster topology.

Application deployment itself (building images, pushing to GHCR, rolling out to the
cluster, running migrations) is handled entirely by the GitHub Actions CI/CD pipelines
and Kubernetes manifests — Terraform and Ansible are only responsible for standing up
the infrastructure and the cluster, not for deploying or updating the application.