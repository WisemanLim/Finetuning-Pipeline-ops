# Finetuning-Pipeline-ops — Wise Fine-tuning Pipeline Operations Hub

[한국어](./README.md) | **English**

The single entrypoint for building/deploying/operating the Wise Fine-tuning Pipeline (a simplified fork of the Worktro Finetuning Pipeline).
**via-host mode only** — containers run only infrastructure (postgres/redis/minio/mailpit), while
worker/web run directly on the host via PM2, using the host GPU/MPS as-is.

---

## Table of Contents

1. [Design Principles](#1-design-principles)
2. [Directory Layout](#2-directory-layout)
3. [Three Modes](#3-three-modes)
4. [Prerequisites](#4-prerequisites)
5. [Initial Install (bootstrap)](#5-initial-install-bootstrap)
6. [Environment Variables](#6-environment-variables)
7. [Full Makefile Command Guide](#7-full-makefile-command-guide)
8. [Common Operations Flow](#8-common-operations-flow)
9. [PM2 Operations (logs / restart / monit)](#9-pm2-operations-logs--restart--monit)
10. [Docker Infrastructure Operations](#10-docker-infrastructure-operations)
11. [Troubleshooting](#11-troubleshooting)
12. [Upgrade / Applying Code Changes](#12-upgrade--applying-code-changes)
13. [Backup / Restore](#13-backup--restore)
14. [Worktro Finetuning Pipeline → WFP Change Summary](#14-worktro-finetuning-pipeline--wfp-change-summary)

---

## 1. Design Principles

- **via-host only.** Consistent host GPU/MPS use is impossible inside Docker → worker/web run on host PM2.
- **Single command.** Knowing `make dev` / `make prod` / `make local` is enough to operate.
- **Infra only in containers.** postgres / redis / minio / mailpit — avoids dependency sprawl.
- **PM2 replaces nohup.** Auto-restart + central logs + status monitoring.
- **Idempotent.** Auto-calls `bootstrap` when missing dependencies are detected.

The legacy Worktro `docker-dev` / `docker-prod` / TLS / GPU compose build paths are all removed,
consolidated into the 3 via-host modes.

---

## 2. Directory Layout

```
Finetuning-Pipeline-ops/
├── Makefile                Root commands. All operations start here
├── README.md               This document (Korean)
├── README.en.md            English version
├── ADMIN-README.md         Admin operations manual (preserved)
├── need-to-debug.md        Worktro FP code defects + WFP fix guide
├── docker/
│   ├── compose.infra.yaml  Infra containers (postgres/redis/minio/mailpit)
│   ├── .env.example        Source of truth for all env vars
│   └── .env                Actual secrets (create manually, .gitignore)
├── scripts/
│   ├── ecosystem.config.cjs  PM2 worker/web definitions (dev/prod/local variants)
│   ├── host-down.sh          PM2 + zombie + port force cleanup
│   └── reaper.py             Resource reclaim cron (heartbeat / disk threshold)
├── rules/
│   └── hw_to_plan.yaml     HW → training plan rules (worker reads directly, not mounted)
├── samples/                Sample upload datasets
├── .doc/                   PRD / architecture diagrams
└── .host-logs/             PM2 log output (auto-generated)
```

The Makefile auto-detects sibling `WORKER_DIR` / `FRONTEND_DIR`:

```
parent/
├── Finetuning-Pipeline-ops/        (where you are)
├── Finetuning-Pipeline-worker/     ../Finetuning-Pipeline-worker auto-detected
└── Finetuning-Pipeline-frontend/   ../Finetuning-Pipeline-frontend auto-detected
```

Sibling directory names are also probed by alias (in priority order):
- worker: `Finetuning-Pipeline-worker` → `FP-worker` → `worker`
- frontend: `Finetuning-Pipeline-frontend` → `FP-frontend` → `frontend`

For other locations, override with `export WORKER_DIR=...` / `export FRONTEND_DIR=...`.

---

## 3. Three Modes

| Mode          | Infra  | DB              | worker/web run | Use case |
|---------------|--------|-----------------|----------------|----------|
| `make local`  | ✗      | SQLite          | host PM2       | Docker-less laptop / quick demo |
| `make dev`    | ✓ Docker | Postgres (or SQLite) | host PM2 (hot-reload) | Daily development |
| `make prod`   | ✓ Docker | Postgres       | host PM2 (after build) | IP-exposed operation |

In all modes worker/web run on host PM2 → host GPU/MPS used as-is.
TLS / domain routing is configured separately via a host reverse proxy like nginx/Caddy (not compose's job).

---

## 4. Prerequisites

| Item        | Minimum | Note |
|-------------|---------|------|
| OS          | Linux (Ubuntu 22.04+) / macOS 13+ | Apple Silicon MPS supported |
| Python      | 3.12 | `uv venv .venv --python 3.12` |
| Node.js     | 20 LTS (or 18+) | pnpm@10 (pnpm@11 on Node 22.13+) |
| Docker      | 24+ + compose v2 | Only needed for `make dev` / `make prod` |
| GPU driver  | NVIDIA 535+ or macOS native | via-host → no nvidia-container-toolkit needed |
| Disk        | 50GB+ | Model cache + infra volumes |

`make bootstrap` installs uv / pnpm / pm2 into `~/.local/bin`, so no sudo needed.

---

## 5. Initial Install (bootstrap)

```bash
# 1. Place repos (sibling layout recommended)
parent/
├── Finetuning-Pipeline-ops/
├── Finetuning-Pipeline-worker/
└── Finetuning-Pipeline-frontend/

# 2. cd into the ops directory
cd parent/Finetuning-Pipeline-ops

# 3. Create .env + fill in secrets
cp docker/.env.example docker/.env
$EDITOR docker/.env          # replace SUPERVISOR_*, POSTGRES_PASSWORD, etc.

# 4. Auto-install all dependencies (uv / pnpm / pm2 / Python deps / Node deps)
make bootstrap

# 5. Training packages (torch / transformers / bitsandbytes — per-environment wheels)
make install-deps

# 6. Environment diagnosis (optional)
make env-status
```

If `~/.local/bin` is not on PATH, a guidance message is printed:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## 6. Environment Variables

All secrets live in the single `docker/.env` file. ecosystem.config.cjs injects into both worker/web.

### Required (all modes)

| Key                      | Example                           | Note |
|--------------------------|-----------------------------------|------|
| `SUPERVISOR_ID`          | `admin@example.com`               | Auto-created/admin-guaranteed on boot |
| `SUPERVISOR_PASSWORD`    | `s3cr3t-strong-pass`              | Password for the account above |

### Additional required for prod

| Key                      | Note |
|--------------------------|------|
| `POSTGRES_PASSWORD`      | DB auth |
| `REDIS_PASSWORD`         | Redis auth (`requirepass` applied) |
| `MINIO_ROOT_USER` / `_PASSWORD` | S3 auth |
| `NEXTAUTH_SECRET`        | `openssl rand -base64 32` |
| `HF_TOKEN`               | Private HF model download |

### Optional

| Key                      | Note |
|--------------------------|------|
| `DATABASE_URL`           | Force Postgres (`postgresql://wfp:...@localhost:5532/fp`). SQLite if unset |
| `REDIS_URL`              | `redis://localhost:6479/0` (dev infra) |
| `S3_ENDPOINT` / `_BUCKET`| `http://localhost:9100` (MinIO) |
| `JWT_SECRET`             | Falls back to `NEXTAUTH_SECRET` if unset |
| `NEXT_PUBLIC_WS_BASE`    | WebSocket base (production) |
| `NEXT_PUBLIC_WORKER_WS_PORT` | Worker port for auto-inference (default 8000) |
| `GOOGLE_/GITHUB_/KAKAO_CLIENT_*` | OAuth providers |
| `WFP_RULES_PATH`         | `rules/hw_to_plan.yaml` override |
| `WFP_TORCH_INDEX`        | PyTorch wheel index override |
| `WFP_LLAMA_CPP_DIR`      | llama.cpp location for GGUF conversion (path cloned by `make install-convert-tools`). Probes PATH if unset |
| `WFP_CONVERT_TIMEOUT`    | Model-conversion subprocess timeout (sec). Default 1800 |
| `GRADIO_BASE_URL`        | Stage 9 inference demo |

`make dev` validates only `SUPERVISOR_*` via `dev-env-check`; `make prod` validates all production secrets via `env-check`.

---

## 7. Full Makefile Command Guide

Typing just `make` shows only the 6 exposed commands (`help` / `info` / `dev` / `prod` / `local` / `down`).
The rest are merely hidden — they all work and can be called directly by exact target name (e.g. `make bootstrap`, `make logs`).
Below is the full per-category command reference:

### 7.1 Mode Entry (aliases + full names)

| Alias       | Full name                 | Action |
|-------------|---------------------------|--------|
| `make dev`  | `docker-dev-via-host`     | Start infra → PM2 dev (`wfp-worker-dev` + `wfp-web-dev`, hot-reload) |
| `make prod` | `docker-prod-via-host`    | Start infra → `pnpm build` → PM2 prod (`wfp-worker-prod` + `wfp-web-prod`) |
| `make local`| `docker-local-via-host`   | SQLite + PM2 local (`wfp-worker-local` + `wfp-web-local`, Docker-independent) |
| `make down` | host-down + infra down    | Stop PM2 daemon + zombies + infra containers |

### 7.2 Install / Update

| Command                 | Action |
|-------------------------|--------|
| `make bootstrap`        | Install all of uv + pnpm + pm2 + Python/Node deps |
| `make env-status`       | OS/GPU diagnosis + show missing packages |
| `make env-status-json`  | Diagnosis JSON (for CI) |
| `make install-deps`     | Auto-install training packages (torch/transformers/…) per environment |
| `make install-convert-tools` | Install model-conversion tools (mlx-lm/onnx/optimum + llama.cpp) — included in bootstrap |
| `make reinstall-worker` | After `git pull`: worker uninstall + reinstall + PM2 restart |
| `make sync`             | Alias for `reinstall-worker` |
| `make worker-editable`  | Ensure editable install (idempotent) |
| `make pull`             | `git pull --ff-only` on both worker + web (skips if locally dirty) |
| `make deploy`           | **Deploy both repos at once** — `pull` → worker reinstall → web `pnpm install` (+`build` if prod) → PM2 restart. Use `GIT_PULL=0` to skip pull |
| `make redeploy`         | Alias for `deploy` |

> **When changing worker and web together,** `make deploy` applies everything in one command. It auto-detects the running mode (prod/dev/local) and runs `pnpm build` when prod web is up. To reflect local edits before committing, use `make deploy GIT_PULL=0`.

### 7.3 Direct Host Run (foreground, no PM2)

| Command             | Action |
|---------------------|--------|
| `make dev-worker`   | Run `uvicorn --reload` directly (.env auto-loaded) |
| `make prod-worker`  | `uvicorn --workers 1` |
| `make dev-web`      | `pnpm dev` |
| `make prod-web`     | `pnpm build && pnpm start` |

### 7.4 Test / Verify

| Command           | Action |
|-------------------|--------|
| `make test`       | Full worker pytest |
| `make test-cov`   | With coverage |
| `make lint`       | ruff + eslint |
| `make typecheck`  | mypy + tsc |
| `make ci`         | lint + typecheck + test |

### 7.5 Catalog / Operations

| Command               | Action |
|-----------------------|--------|
| `make catalog-refresh`| Refresh model catalog from HF Hub trending |
| `make restart` / `make host-restart` | PM2 app restart + env reload |
| `make logs` / `make host-logs`       | PM2 unified logs (worker + web) |
| `make logs-worker`    | Worker logs only |
| `make logs-web`       | Web logs only |
| `make status`         | PM2 process status table |
| `make monit`          | PM2 live monitor |

### 7.6 Infra / Cleanup

| Command                   | Action |
|---------------------------|--------|
| `make docker-infra-start` | Start infra containers only |
| `make docker-infra-down`  | Stop infra containers only |
| `make host-down`          | Force cleanup PM2 + zombies + ports 8000/3000 |
| `make clean`              | Delete `__pycache__` / `.pytest_cache` / `.next` |
| `make docker-clean`       | Stop infra + delete volumes (**data loss**) |
| `make info`               | Print detected paths + GPU |

---

## 8. Common Operations Flow

### 8.1 Local laptop (no Docker, MPS / CPU)

```bash
make local              # SQLite + PM2
make logs               # check progress
# Browser: http://localhost:3000  worker: http://localhost:8000
make down               # stop
```

### 8.2 Daily development (Linux workstation / mac)

```bash
make dev                # infra containers + PM2 (hot-reload)
make logs               # logs
# On code edits, worker uses uvicorn --reload, web uses next dev (auto-applied)
# When adding dependencies:
make reinstall-worker   # or cd ../Finetuning-Pipeline-worker && uv pip install ...
make down               # stop
```

### 8.3 IP-exposed operation (single server, no TLS)

```bash
# First — fill all prod secrets in docker/.env
make prod               # pnpm build + start PM2 prod
make status             # check status
make logs-worker        # monitor training logs
```

If you need 80/443 TLS on a production server, configure it separately with host nginx/Caddy/Traefik
and proxy to `localhost:3000` (web) / `localhost:8000` (worker). WebSocket requires forwarding the `Upgrade` header.

---

## 9. PM2 Operations (logs / restart / monit)

PM2 is installed user-local at `~/.local/bin/pm2`. Below is how to directly use the commands `make logs` calls:

```bash
# Registered app list + status
pm2 list

# Live logs (all)
pm2 logs

# A specific app only
pm2 logs wfp-worker-dev
pm2 logs wfp-web-prod

# Restart + env refresh (after editing docker/.env)
WORKER_DIR=... FRONTEND_DIR=... HOST_LOG_DIR=... \
  pm2 restart wfp-worker-prod --update-env

# Live monitor (CPU / memory)
pm2 monit

# Persist registration (auto-start on server boot)
pm2 startup            # run the printed command with sudo
pm2 save               # persist currently registered apps
```

PM2 app naming convention:
- `wfp-worker-dev` / `wfp-worker-prod` / `wfp-worker-local`
- `wfp-web-dev` / `wfp-web-prod` / `wfp-web-local`

Log files: `.host-logs/worker.log` / `.host-logs/web.log` (+ `*.error.log`).

---

## 10. Docker Infrastructure Operations

```bash
# Start / stop standalone
make docker-infra-start
make docker-infra-down

# Direct docker compose
cd docker
docker compose -f compose.infra.yaml ps
docker compose -f compose.infra.yaml logs -f postgres
docker compose -f compose.infra.yaml restart redis
```

Port mapping (external ↔ container):

| Service     | External | Internal | Note |
|-------------|----------|----------|------|
| postgres    | 5532 | 5432 | Avoid clashing with other PG |
| redis       | 6479 | 6379 |
| minio API   | 9100 | 9000 |
| minio UI    | 9101 | 9001 | http://localhost:9101 (login with root user/pass) |
| mailpit SMTP| 1125 | 1025 | Signup email verification trap |
| mailpit UI  | 8125 | 8025 | http://localhost:8125 |

Volumes: `pg_data` / `redis_data` / `minio_data` — deleted only by `make docker-clean`.

---

## 11. Troubleshooting

### 11.1 Port conflict (8000 / 3000 occupied)

```bash
make host-down          # force cleanup PM2 + zombies + ports
lsof -i :8000           # check residual processes
```

### 11.2 PM2 not on PATH

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
which pm2               # should print ~/.local/bin/pm2
```

### 11.3 Worker can't find module (`ModuleNotFoundError: wfp_worker`)

Editable install broken. Reinstall:

```bash
make reinstall-worker
```

### 11.4 CUDA inactive during training (despite an NVIDIA GPU)

PyTorch wheel is CPU-only. Reinstall per environment:

```bash
make install-deps       # env_check picks the CUDA wheel index
# aarch64 (Jetson/Grace) + Blackwell:
WFP_TORCH_INDEX=https://download.pytorch.org/whl/nightly/cu128 make install-deps
```

### 11.5 Web build failure (`make prod`)

```bash
tail -50 .host-logs/web-build.log
cd ../Finetuning-Pipeline-frontend && pnpm build       # retry directly + see errors
```

### 11.6 Infra container healthcheck failure

```bash
docker logs wfp-postgres
docker compose -f docker/compose.infra.yaml restart postgres
```

### 11.7 Job state not persisting to disk

Check `~/.wfp/jobs_state.json` or (in Docker mode) `/data/jobs_state.json`. Throttle skips consecutive calls within 2s — on shutdown the lifespan explicitly saves with force=True.

### 11.8 WebSocket drops / progress stream not showing

The browser connects **directly** to the worker `/ws/{job_id}` (no Next.js proxy). When using a production reverse proxy:
- Forward `Upgrade` / `Connection` headers
- Sufficient `proxy_read_timeout` (ping every 30s during training)
- Inject `NEXT_PUBLIC_WS_BASE` or `NEXT_PUBLIC_WORKER_WS_PORT` at build time, then rebuild with `make prod`

---

## 12. Upgrade / Applying Code Changes

```bash
# 1. Pull code
cd ../Finetuning-Pipeline-worker && git pull
cd ../Finetuning-Pipeline-frontend && git pull
cd ../Finetuning-Pipeline-ops && git pull

# 2. Update worker dependencies
cd ../Finetuning-Pipeline-ops
make reinstall-worker   # uninstall + reinstall + PM2 restart

# 3. Update web (dev mode is hot-reload, prod needs rebuild)
make restart            # enough for dev
make prod               # prod re-runs pnpm build
```

If only `.env` values changed:
```bash
make restart            # inject new values via PM2 --update-env
```

---

## 13. Backup / Restore

### 13.1 Job state file

- Local: `~/.wfp/jobs_state.json` (+ `.1` ~ `.5` rotation backups)
- Docker mode: `/data/jobs_state.json` inside the container — worker container is unused (via-host), so host `~/.wfp/` is identical

### 13.2 Postgres dump

```bash
docker exec wfp-postgres pg_dump -U wfp wfp | gzip > wfp-$(date +%F).sql.gz
```

### 13.3 MinIO data

```bash
docker run --rm -v wfp-infra_minio_data:/data alpine \
  tar czf - /data > minio-$(date +%F).tar.gz
```

---

## 14. Worktro Finetuning Pipeline → WFP Change Summary

1. **Simplified build/deploy**
   - Removed Dockerfile / Dockerfile.gpu (worker, frontend)
   - Removed compose.dev.yaml / compose.prod*.yaml / compose.*.gpu.yaml / compose.prod.tls.yaml
   - **Remaining compose: just `compose.infra.yaml` (infra only)**
   - Only 3 via-host modes — `make dev` / `make prod` / `make local`

2. **Makefile cleanup**
   - Removed `build-*` / `docker-dev*` / `docker-prod*` / `docker-prod-tls*` / `traefik-diag`
   - Introduced short aliases `dev` / `prod` / `local` / `down` / `restart` / `logs`

3. **Bug fixes**
   - `runtime.save_state` throttle (2s) — eases disk I/O during WS event floods
   - `env_check._check_imports` uses `importlib.util.find_spec` — avoids bitsandbytes CUDA init side-effects
   - See [`need-to-debug.md`](need-to-debug.md) for details

4. **PM2 ecosystem comments only updated** — logic unchanged (dev/prod/local variants used as-is)

5. **Sibling auto-detect alias expansion** — `WORKER_DIR`/`FRONTEND_DIR` also probe `FP-worker`/`worker`, `FP-frontend`/`frontend` directory names

6. **Worker admin model management expansion** — catalog CRUD / HF search / model upload·download / presets / data-source whitelist + structured error codes (`WFPErrorCode`). See worker/frontend READMEs for details.

See [`need-to-debug.md`](need-to-debug.md) for potential defects in the original Worktro code and the fix guide.

---

## Appendix — Related Documents

- [Finetuning-Pipeline-worker README](../Finetuning-Pipeline-worker/README.en.md) — 9-stage pipeline details ([KO](../Finetuning-Pipeline-worker/README.md))
- [Finetuning-Pipeline-frontend README](../Finetuning-Pipeline-frontend/README.en.md) — routes / WS connection ([KO](../Finetuning-Pipeline-frontend/README.md))
- [ADMIN-README.md](ADMIN-README.md) — admin operations manual (preserved)
- [need-to-debug.md](need-to-debug.md) — original defects + fix guide
- [.doc/](.doc/) — PRD / architecture diagrams
