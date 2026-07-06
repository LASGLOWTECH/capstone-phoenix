# TaskApp

Capstone project for the completion of Phoenix's DevOps Engineering course, by **austinoasaz**.

🔗 **Live app:** [myapp.euclaseresources.com](https://myapp.euclaseresources.com)

---

## Overview

TaskApp is a full-stack task management application, containerized and deployed
using a CI/CD pipeline with automated build, test, and production deployment stages.

**Stack:**
- Frontend: React + Vite, served via Nginx
- Backend: Flask + PostgreSQL
- CI/CD: GitHub Actions
- Hosting: Ubuntu server (production)

---

## CI/CD Pipeline

- **CI** (`ci.yaml`) — lints, type-checks, tests, and builds the frontend on every push/PR to `main`
- **CD** (`cd.yaml`) — deploys the built artifact to production automatically after CI succeeds on `main`

---

## Local Development

```bash
npm install
npm run dev
```

## Build

```bash
npm run build
```