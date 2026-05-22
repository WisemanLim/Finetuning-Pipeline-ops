# WFP Docker 가이드

`Finetuning-Pipeline-worker`, `Finetuning-Pipeline-frontend`, 인프라(PostgreSQL/Redis/MinIO)를
Docker Compose로 동시에 구동하는 방법.

---

## 파일 목록

| 파일 | 용도 |
|------|------|
| [`compose.dev.yaml`](./compose.dev.yaml) | 개발 베이스 — CPU 모드, 인증 우회, 포트 노출 |
| [`compose.dev.gpu.yaml`](./compose.dev.gpu.yaml) | 개발 GPU 오버라이드 — worker만 GPU 빌드 + nvidia 디바이스 |
| [`compose.prod.yaml`](./compose.prod.yaml) | 운영 베이스 — CPU + Traefik TLS + 백업 사이드카 |
| [`compose.prod.gpu.yaml`](./compose.prod.gpu.yaml) | 운영 GPU 오버라이드 |
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

```bash
cd Finetuning-Pipeline-ops/docker
cp .env.example .env
# .env 모든 값 채우기 (특히 POSTGRES_PASSWORD, REDIS_PASSWORD, NEXTAUTH_SECRET, DOMAIN, ACME_EMAIL)
cd ..

make docker-prod           # GPU 자동 감지 — 권장
# 또는 강제:
make docker-prod-cpu       # CPU 강제
make docker-prod-gpu       # GPU 강제

# 로그 확인
make docker-logs
docker compose -f docker/compose.prod.yaml logs -f traefik
```

수동 (Makefile 없이):

```bash
cd Finetuning-Pipeline-ops/docker
# CPU
docker compose -f compose.prod.yaml up -d --build
# GPU
docker compose -f compose.prod.yaml -f compose.prod.gpu.yaml up -d --build
```

Traefik이 Let's Encrypt에서 인증서를 자동 발급한다 (`ACME_EMAIL` 필수).

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
make docker-down        # 정지 (dev + prod 둘 다)
make docker-clean       # 정지 + 볼륨 삭제 (데이터 손실)
```

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

| 증상 | 원인 | 해결 |
|------|------|------|
| `worker` 컨테이너 OOM 종료 | RAM 부족 | Docker Desktop 메모리 16GB+ 할당 |
| HF 다운로드 401 | `HF_TOKEN` 미설정 | `.env`에 토큰 추가 후 `docker compose restart worker` |
| Traefik 인증서 발급 실패 | DNS 미전파 / 80포트 차단 | `docker compose logs traefik` 확인 |
| `worker` GPU 미인식 | NVIDIA Container Toolkit 미설치 | `docker run --rm --gpus all nvidia/cuda:12.1.1-base nvidia-smi`로 검증 |
| MinIO 콘솔 접속 안 됨 | 9001 포트 충돌 | `compose.dev.yaml`에서 포트 변경 |
| 빌드가 항상 처음부터 실행 | `.dockerignore` 미적용 | 빌드 컨텍스트에 큰 파일 포함 여부 확인 |

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
