# WFP Docker 가이드

`Finetuning-Pipeline-worker`, `Finetuning-Pipeline-frontend`, 인프라(PostgreSQL/Redis/MinIO)를
Docker Compose로 동시에 구동하는 방법.

---

## 파일 목록

| 파일 | 용도 |
|------|------|
| [`compose.dev.yaml`](./compose.dev.yaml) | 개발 베이스 — CPU 모드, 인증 우회, 포트 노출 |
| [`compose.dev.gpu.yaml`](./compose.dev.gpu.yaml) | 개발 GPU 오버라이드 — worker만 GPU 빌드 + nvidia 디바이스 |
| [`compose.prod.yaml`](./compose.prod.yaml) | 운영 베이스 — HTTP (Traefik, **IP 접속 가능**), CPU, 백업 사이드카 |
| [`compose.prod.gpu.yaml`](./compose.prod.gpu.yaml) | 운영 GPU 오버라이드 |
| [`compose.prod.tls.yaml`](./compose.prod.tls.yaml) | 운영 TLS 오버라이드 (실제 도메인 + Let's Encrypt) |
| [`compose.infra.yaml`](./compose.infra.yaml) | 인프라 전용 — 호스트 직접 실행 시 (Apple Silicon MPS 등) |
| [`.env.example`](./.env.example) | 환경 변수 템플릿 (SUPERVISOR/DB/Redis/MinIO/NextAuth 비번 + `WFP_WORKER_DIR`) |
| [`../../Finetuning-Pipeline-worker/Dockerfile`](../../Finetuning-Pipeline-worker/Dockerfile) | 워커 CPU 이미지 — multi-stage `python:3.12-slim` |
| [`../../Finetuning-Pipeline-worker/Dockerfile.gpu`](../../Finetuning-Pipeline-worker/Dockerfile.gpu) | 워커 GPU 이미지 — `python:3.12-slim` + PyTorch `+cu121` 휠 (CUDA 런타임 번들) |
| [`../../Finetuning-Pipeline-frontend/Dockerfile`](../../Finetuning-Pipeline-frontend/Dockerfile) | 프론트엔드 (Node 22 + Next.js standalone) |

### Override 패턴

GPU 모드는 `compose.dev.yaml` (또는 `compose.prod.yaml`) **베이스**에 `compose.*.gpu.yaml` **오버라이드**를 합쳐 사용한다. GPU 오버라이드는 `worker` 서비스의 `build.dockerfile`과 `deploy.resources.reservations.devices`만 교체. 인프라(postgres/redis/minio 등)는 베이스 그대로.

```bash
# CPU
docker compose -f compose.dev.yaml up -d --build
# GPU
docker compose -f compose.dev.yaml -f compose.dev.gpu.yaml up -d --build
```

Makefile이 `nvidia-smi`로 GPU 유무를 자동 감지해 적절한 조합 선택:

```bash
make docker-dev      # 자동 — GPU 있으면 GPU, 없으면 CPU
make docker-dev-cpu  # 강제 CPU
make docker-dev-gpu  # 강제 GPU
make docker-info     # 현재 감지 결과 출력
```

---

## dev/prod 기능 대칭

dev와 prod는 동일 코드/도구 체인. 차이는 빌드 옵션 / 검증 강도 / Traefik 유무.

| 항목 | dev | prod |
|---|---|---|
| Worker | `uvicorn --reload` | `uvicorn --workers 1` |
| Web | `pnpm dev` (HMR) | `pnpm build → pnpm start` |
| env-check | `dev-env-check` (SUPERVISOR_*만) | `env-check` (8개 키) |
| Reverse proxy | 직접 포트 (3000/8000) | Traefik (PathPrefix `/ws`→worker, `/`→web) |
| TLS | — | `compose.prod.tls.yaml` 오버라이드 |
| PM2 min_uptime | 10s | 30s |
| 자동화 | HW probe, nvidia-smi fallback, WFP-0203 force, 잡 prefill 재실행 모두 **dev/prod 동일** |

## 1. 빠른 시작 (개발 환경)

### 사전 요구사항

| 도구 | 버전 |
|------|------|
| Docker Engine | 24+ |
| Docker Compose | v2 (`docker compose` 명령) |
| RAM | 8GB+ (PostgreSQL + Redis + MinIO + Node + Python) |
| 디스크 | 10GB+ (이미지 + 볼륨) |

### 실행

권장 — 루트의 Makefile 사용:

```bash
cd Finetuning-Pipeline-ops
cp docker/.env.example docker/.env

make docker-dev           # GPU 자동 감지 (백그라운드)
# 또는:
make docker-dev-cpu       # CPU 강제
make docker-dev-gpu       # GPU 강제 (nvidia 런타임 필요)
```

수동:

```bash
cd Finetuning-Pipeline-ops/docker
cp .env.example .env

# CPU
docker compose -f compose.dev.yaml up -d --build
# GPU (베이스 + 오버라이드)
docker compose -f compose.dev.yaml -f compose.dev.gpu.yaml up -d --build
```

### 접속

| 서비스 | URL | 비고 |
|--------|-----|------|
| 웹 UI | http://localhost:3000 | Next.js 14 |
| worker API | http://localhost:8000 | Swagger: `/docs` |
| MinIO 콘솔 | http://localhost:9101 | `wfp-minio` / `wfp-minio-secret` (외부 9101, 컨테이너 9001) |
| MinIO S3 API | http://localhost:9100 | 컨테이너 내부는 `minio:9000` |
| MailHog UI | http://localhost:8125 | 회원가입 이메일 트랩 (외부 8125, 컨테이너 8025) |
| PostgreSQL | localhost:5532 | `wfp` / `wfp-dev` / DB `wfp` (외부 5532, 컨테이너 5432) |
| Redis | localhost:6479 | 개발은 비번 없음 (외부 6479, 컨테이너 6379) |

> 호스트 포트가 5xxx/6xxx/8xxx/9xxx 대역으로 재매핑되어 다른 로컬 서비스(다른 MinIO/Redis/Postgres 등)와 충돌하지 않는다.
> 컨테이너 간 통신은 표준 포트 유지 (`postgres:5432`, `redis:6379`, `minio:9000`).

### 첫 잡 생성 확인

브라우저에서 http://localhost:3000 → `새 잡 생성` 클릭 → 5-step 위자드 진행.
워커 컨테이너 로그 모니터링:

```bash
docker compose -f compose.dev.yaml logs -f worker
```

### 하이브리드 모드 — 인프라(Docker) + worker/web(호스트)

전체 컨테이너 모드는 Docker for Mac의 Linux VM 제약으로 MPS/호스트 GPU에 직접 접근 불가. 인프라만 docker로 두고 worker/web을 호스트에서 직접 실행하면:
- Apple Silicon MPS, 호스트 NVIDIA GPU 직접 접근
- 코드 변경 즉시 반영 (uvicorn `--reload` + Next.js HMR)
- 직접 디버깅 (IDE 디버거, breakpoint)

**원커맨드** (PM2 백그라운드 관리):

```bash
make docker-dev-via-host    # 인프라 + PM2 start wfp-worker-dev/wfp-web-dev
make docker-prod-via-host   # 인프라 + pnpm build + PM2 start wfp-worker-prod/wfp-web-prod

make host-status            # pm2 list
make host-logs              # pm2 logs (worker + web 통합)
make host-logs-worker       # pm2 logs wfp-worker-*
make host-logs-web          # pm2 logs wfp-web-*
make host-restart           # pm2 restart 전체 (코드 변경 반영)
make host-monit             # pm2 monit (실시간 CPU/메모리)
make host-down              # pm2 delete all + pm2 kill (daemon) + 포트 8000/3000 좀비 정리
```

**foreground 타겟** (별도 터미널, Ctrl+C 정지):

| 타겟 | 명령 | 모드 |
|---|---|---|
| `dev-worker` | `uvicorn ... --reload` | 핫리로드 |
| `dev-web` | `pnpm dev` | HMR |
| `prod-worker` | `uvicorn ... --workers 1` | 단일 worker (in-memory _jobs 일관성) |
| `prod-web` | `pnpm build && pnpm start` | 프로덕션 (수동) |

**PM2 ecosystem** (`scripts/ecosystem.config.cjs`):

| 앱 이름 | cwd | 명령 | 옵션 |
|---|---|---|---|
| `wfp-worker-dev` | `$WORKER_DIR` | `bash -c '.env 로드 + uvicorn --reload'` | autorestart, max_restarts=10 |
| `wfp-worker-prod` | `$WORKER_DIR` | `bash -c '.env 로드 + uvicorn --workers 1'` | autorestart, min_uptime=30s |
| `wfp-web-dev` | `$FRONTEND_DIR` | `bash -c 'pnpm dev'` | autorestart |
| `wfp-web-prod` | `$FRONTEND_DIR` | `bash -c 'pnpm start'` (빌드는 Makefile 사전 실행) | autorestart |

via-host 내부 동작:
- `docker-infra-start` 의존 → postgres/redis/minio/mailhog 컨테이너 기동 (메시지 없음)
- `host-deps-check` 의존 → `.venv/bin/uvicorn` + `pnpm` + `pm2` 존재 검증 + 누락 시 `make bootstrap` 안내
- `pm2 start` + `--only <앱이름>` → ecosystem에서 해당 앱만 기동
- 자동 재시작 / 신호 처리 / 좀비 정리는 PM2 책임
- 로그는 `.host-logs/{worker,web}.{log,error.log}` (PM2 `out_file`/`error_file`)

**bootstrap 자동 설치**:

`make bootstrap`이 다음을 자동 설치 (미설치 시):
- **uv** — `curl -LsSf https://astral.sh/uv/install.sh | sh` → `~/.local/bin/uv`
- **pnpm** — `corepack enable && corepack prepare pnpm@11 --activate`
- **pm2** — `npm i -g pm2`
- worker venv 생성 + 의존성 설치
- frontend `pnpm install`

**수동 infra만**:

```bash
make docker-infra   # 인프라만, 별도 터미널에서 dev-*/prod-* 수동
```

`compose.infra.yaml`은 worker/web 서비스 미포함. dev/prod compose의 인프라 서비스만 추출한 형태.

---

## 2. 운영 환경

### 사전 준비

1. 도메인(예: `wfp.example.com`) DNS A 레코드를 서버 IP로 설정
2. 80/443 포트 방화벽 개방
3. NVIDIA GPU 노드면 **NVIDIA Container Toolkit** 설치
4. `.env`에 모든 필수 값 채움 (`?required` 표시 변수)

### NVIDIA Container Toolkit 설치 (Ubuntu)

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# 검증
docker run --rm --gpus all nvidia/cuda:12.1.1-base-ubuntu22.04 nvidia-smi
```

### 기동

#### A. IP 기반 (도메인 없음, HTTP만)

가장 간단한 배포 형태. 서버 IP로 바로 접속 가능. `.env`에 도메인/ACME 설정 불필요.

```bash
cd Finetuning-Pipeline-ops/docker
cp .env.example .env
# 필수: POSTGRES_PASSWORD, REDIS_PASSWORD, NEXTAUTH_SECRET, MINIO_ROOT_*, HF_TOKEN, SUPERVISOR_*
# NEXTAUTH_URL=http://<서버-IP>  ← 외부 IP일 경우 localhost → 실제 IP로 변경
cd ..

make docker-prod           # GPU 자동 감지 — 권장
# 또는 강제:
make docker-prod-cpu
make docker-prod-gpu
```

접속: `http://<서버-IP>/`

Traefik이 80 포트에서 받아 web/worker로 PathPrefix 기반 라우팅 (`/ws` → worker, 나머지 → web).

#### B. 도메인 + TLS (Let's Encrypt 자동 인증서)

실제 도메인 보유, DNS A 레코드 설정, 80/443 외부 개방, ACME_EMAIL 설정 완료 시.

```bash
# .env에 추가
# DOMAIN=wfp.example.com
# ACME_EMAIL=admin@example.com
# NEXTAUTH_URL=https://wfp.example.com

make docker-prod-tls       # CPU + TLS
make docker-prod-tls-gpu   # GPU + TLS
```

`compose.prod.tls.yaml` 오버라이드가:
- HTTPS(443) 엔트리포인트 추가
- HTTP → HTTPS 강제 리다이렉트
- Host 헤더 기반 라우팅 (catch-all 제거)
- Let's Encrypt TLS challenge

접속: `https://<도메인>/`

#### 로그 확인

```bash
make docker-logs
docker compose -f docker/compose.prod.yaml logs -f traefik
```

### TLS 인증서 발급 확인

```bash
curl -I https://wfp.example.com
# HTTP/2 200
# server: traefik
```

---

## 3. 이미지 빌드 옵션

### 단일 이미지 빌드 (compose 없이)

```bash
# Finetuning-Pipeline-worker (CPU)
docker build -t wfp-worker:latest ../../Finetuning-Pipeline-worker/

# Finetuning-Pipeline-worker (GPU)
docker build -f ../../Finetuning-Pipeline-worker/Dockerfile.gpu -t wfp-worker:gpu ../../Finetuning-Pipeline-worker/

# Finetuning-Pipeline-frontend
docker build -t wfp-frontend:latest ../../Finetuning-Pipeline-frontend/
```

### 캐시 마운트로 빠른 재빌드

```bash
DOCKER_BUILDKIT=1 docker build \
  --cache-from wfp-worker:latest \
  -t wfp-worker:latest ../../Finetuning-Pipeline-worker/
```

### 멀티 아키텍처 (ARM64 + x86_64)

```bash
docker buildx create --use --name wfp-builder
docker buildx build --platform linux/amd64,linux/arm64 \
  -t wfp-worker:latest --push ../../Finetuning-Pipeline-worker/
```

---

## 4. 볼륨 / 영속화

| 볼륨 | 마운트 위치 | 내용 |
|------|-------------|------|
| `wfp_cache` | `/home/wfp/.wfp` (워커) | HF 모델 캐시, 데이터셋, 체크포인트, 아티팩트 |
| `pg_data` | `/var/lib/postgresql/data` | PostgreSQL 데이터 |
| `redis_data` | `/data` | Redis AOF |
| `minio_data` | `/data` | S3 호환 객체 (운영 시 외부 S3 권장) |
| `traefik_certs` | `/letsencrypt` | Let's Encrypt 인증서 (운영) |

### 백업

운영 환경의 `backup` 사이드카가 일 1회 PostgreSQL dump → MinIO `wfp-backups` 버킷.

수동 백업:

```bash
docker compose -f compose.prod.yaml exec postgres \
  pg_dump -U wfp wfp | gzip > backup-$(date +%Y%m%d).sql.gz
```

---

## 5. 운영 명령 모음

Makefile 단축 (권장):

```bash
make docker-info        # 현재 감지 모드 (GPU/CPU + 경로)
make docker-ps          # 컨테이너 상태
make docker-logs        # 워커 로그 추적
make docker-down        # 전체 정지 — PM2(daemon kill) + dev/prod/infra compose + 포트 좀비
make docker-clean       # 전체 정지 + 볼륨 삭제 (데이터 손실)
```

`docker-down`이 정리하는 대상:

| 종류 | 명령 |
|---|---|
| PM2 앱 (via-host로 띄운 worker/web) | `pm2 delete all` |
| PM2 daemon (자동 재시작 차단) | `pm2 kill` |
| 좀비 uvicorn/next-server/pnpm/multiprocessing | `pkill -f <pattern>` |
| 포트 8000(worker)/3000(web) 점유 PID | `lsof -ti :PORT` → SIGTERM → SIGKILL |
| Docker compose | dev/dev.gpu/prod/prod.gpu/prod.tls/infra 모든 조합 down |

수동 (compose 직접):

```bash
# 상태 확인
docker compose -f compose.dev.yaml ps

# 특정 서비스 재시작
docker compose -f compose.dev.yaml restart worker

# 워커 컨테이너 쉘 진입
docker compose -f compose.dev.yaml exec worker bash

# 잡 큐 클리어 (Redis)
docker compose -f compose.dev.yaml exec redis redis-cli FLUSHDB

# 전체 정지 + 볼륨 삭제 (주의 — 데이터 삭제됨)
docker compose -f compose.dev.yaml down -v
```

---

## 6. 문제 해결

### Docker 컨테이너 모드

| 증상 | 원인 | 해결 |
|------|------|------|
| `worker` 컨테이너 OOM 종료 | RAM 부족 | Docker Desktop 메모리 16GB+ 할당 |
| HF 다운로드 401 | `HF_TOKEN` 미설정 | `.env`에 토큰 추가 후 `docker compose restart worker` |
| Traefik 인증서 발급 실패 | DNS 미전파 / 80포트 차단 | `docker compose logs traefik` 확인 |
| `worker` GPU 미인식 | NVIDIA Container Toolkit 미설치 | `docker run --rm --gpus all nvidia/cuda:12.1.1-base nvidia-smi`로 검증 |
| MinIO 콘솔 접속 안 됨 | 9001 포트 충돌 | `compose.dev.yaml`에서 포트 변경 |
| 빌드가 항상 처음부터 실행 | `.dockerignore` 미적용 | 빌드 컨텍스트에 큰 파일 포함 여부 확인 |
| Mailpit `exec format error` | 옛 mailhog 멀티아키 깨짐 | `docker rmi mailhog/mailhog:latest` 후 git pull (mailpit으로 교체됨) |

### via-host (PM2) 모드

| 증상 | 원인 | 해결 |
|------|------|------|
| `make host-down` 도중 `Terminated` | (구) pkill 패턴이 부모 bash argv 매칭 | `scripts/host-down.sh` 별도 파일 사용 — git pull로 적용 |
| 잡 목록 flicker (나타났다 사라짐) | 옛 `uvicorn --workers 2` — in-memory `_jobs` 프로세스마다 분리 | git pull + restart — 단일 worker로 통일 |
| Login `InvalidKeyError: HMAC key must not be empty` | `NEXTAUTH_SECRET=` 또는 `JWT_SECRET=` 빈 값 | docker/.env에 `NEXTAUTH_SECRET=$(openssl rand -base64 32)` 설정 + restart |
| WFP-0203 HW 사양 매칭 안 됨 | YAML 미발견 + 내장 fallback도 매칭 실패 | `WFP_RULES_PATH=/path/to/rules.yaml make docker-prod-via-host` 강제 |
| 대시보드 "0 GPU" + nvidia-smi 정상 | pynvml 실패 + worker venv 옛 코드 | `uv pip uninstall wfp-worker && uv pip install -e ".[dev]"` 재설치 |
| `host-deps-check` 통과 후 bootstrap 실패 | uv/pnpm/pm2 일부 누락 (수동 환경) | 자동: `make bootstrap` 재실행 / 수동: 메시지의 명령 실행 |
| 외부 IP에서 3000/8000 접속 안 됨 | ufw / iptables 차단 (Docker는 우회) | `sudo ufw allow from <LAN>/24 to any port 3000 proto tcp` |
| Next.js IPv6만 listen (`:::3000`) | (구) `next start -p 3000` (호스트 미지정) | git pull frontend — `-H 0.0.0.0` 명시됨 |

### 진단 명령

```bash
make traefik-diag       # 라우팅 / 라벨 / 네트워크
make docker-info        # 경로 + GPU 자동 감지
make docker-logs        # PM2/compose 자동 감지 후 로그
make host-status        # PM2 프로세스 상태
make env-check          # docker/.env 필수 키 검증 (prod — 8개 키)
make dev-env-check      # SUPERVISOR_* 만 검증 (dev — 나머지 compose default)
```

---

## 7. CI/CD 연동 (참고)

GitHub Actions 예시 (`.github/workflows/build.yml` — 향후 추가 예정):

```yaml
- name: Build & push worker
  uses: docker/build-push-action@v6
  with:
    context: .
    file: ./Dockerfile
    push: true
    tags: ghcr.io/${{ github.repository }}/worker:${{ github.sha }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

---

## 8. 보안 권장

- **운영 비번은 모두 랜덤** (`openssl rand -base64 32`)
- `.env` 파일은 절대 커밋 금지 (`.gitignore` 적용됨)
- `SUPERVISOR_ID` / `SUPERVISOR_PASSWORD` 반드시 강한 값으로 설정 — 미설정 시 ADMIN 계정 없음
- 운영 환경에서 `NEXT_PUBLIC_AUTH_DISABLED=true` 절대 사용 금지
- MinIO는 운영에서 외부 S3(AWS / Cloudflare R2)로 교체 권장
- Traefik 대시보드(`--api.dashboard=true`)는 절대 외부 노출 금지
- 비루트 유저 실행은 Dockerfile에 이미 적용됨 (`wfp`, `nextjs`)
