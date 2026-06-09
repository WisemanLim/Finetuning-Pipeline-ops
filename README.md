# Finetuning-Pipeline-ops — Wise Fine-tuning Pipeline 운영 허브

**한국어** | [English](./README.en.md)

Wise Fine-tuning Pipeline(Worktro Finetuning Pipeline 단순화 분기) 의 빌드/배포/운영 단일 진입점.
**via-host 모드 만 지원** — 컨테이너는 인프라(postgres/redis/minio/mailpit)만 담당하고,
worker/web 은 호스트에서 PM2 로 직접 실행해 호스트 GPU/MPS 를 그대로 사용한다.

---

## 목차

1. [설계 원칙](#1-설계-원칙)
2. [디렉토리 구조](#2-디렉토리-구조)
3. [세 가지 모드](#3-세-가지-모드)
4. [사전 요구사항](#4-사전-요구사항)
5. [최초 설치 (bootstrap)](#5-최초-설치-bootstrap)
6. [환경 변수](#6-환경-변수)
7. [Makefile 명령 전체 사용 가이드](#7-makefile-명령-전체-사용-가이드)
8. [일반 운영 흐름](#8-일반-운영-흐름)
9. [PM2 운영 (logs / restart / monit)](#9-pm2-운영-logs--restart--monit)
10. [Docker 인프라 운영](#10-docker-인프라-운영)
11. [트러블슈팅](#11-트러블슈팅)
12. [업그레이드 / 코드 반영](#12-업그레이드--코드-반영)
13. [백업 / 복구](#13-백업--복구)
14. [Worktro Finetuning Pipeline → WFP 변경 요약](#14-worktro-finetuning-pipeline--wfp-변경-요약)

---

## 1. 설계 원칙

- **via-host 만 지원.** Docker 안에서는 호스트 GPU/MPS 일관 사용 불가 → worker/web 은 호스트 PM2.
- **단일 명령.** `make dev` / `make prod` / `make local` 만 알면 운영 가능.
- **인프라만 컨테이너.** postgres / redis / minio / mailpit — 의존성 폭주 회피.
- **PM2 가 nohup 대체.** 자동 재시작 + 중앙 로그 + 상태 모니터링.
- **idempotent.** 의존성 누락 감지 시 `bootstrap` 자동 호출.

기존 Worktro Finetuning Pipeline 의 `docker-dev` / `docker-prod` / TLS / GPU compose 빌드 경로는
모두 제거. via-host 3 모드로 집약.

---

## 2. 디렉토리 구조

```
Finetuning-Pipeline-ops/
├── Makefile                루트 명령. 모든 운영은 여기서 시작
├── README.md               이 문서
├── ADMIN-README.md         관리자 운영 매뉴얼 (기존 보존)
├── need-to-debug.md        Worktro FP 코드 결함 + WFP 수정 가이드
├── docker/
│   ├── compose.infra.yaml  인프라 컨테이너 (postgres/redis/minio/mailpit)
│   ├── .env.example        모든 환경 변수의 source of truth
│   └── .env                실제 비밀 (직접 생성, .gitignore)
├── scripts/
│   ├── ecosystem.config.cjs  PM2 worker/web 정의 (dev/prod/local 변형)
│   ├── host-down.sh          PM2 + 좀비 + 포트 강제 정리
│   └── reaper.py             자원 회수 cron (heartbeat / 디스크 임계)
├── rules/
│   └── hw_to_plan.yaml     HW → 학습 plan 규칙 (worker 가 마운트 안 함, 직접 읽음)
├── samples/                업로드 샘플 데이터셋
├── .doc/                   PRD / 아키텍처 다이어그램
└── .host-logs/             PM2 로그 출력 (자동 생성)
```

`WORKER_DIR` / `FRONTEND_DIR` 은 Makefile 이 sibling 자동 감지:

```
parent/
├── Finetuning-Pipeline-ops/        (당신이 있는 곳)
├── Finetuning-Pipeline-worker/     ../Finetuning-Pipeline-worker 자동 감지
└── Finetuning-Pipeline-frontend/   ../Finetuning-Pipeline-frontend 자동 감지
```

sibling 디렉토리명은 별칭도 자동 탐색 (우선순위 순):
- worker: `Finetuning-Pipeline-worker` → `FP-worker` → `worker`
- frontend: `Finetuning-Pipeline-frontend` → `FP-frontend` → `frontend`

다른 위치라면 `export WORKER_DIR=...` / `export FRONTEND_DIR=...` 로 override.

---

## 3. 세 가지 모드

| 모드          | 인프라 | DB              | worker/web 실행 | 용도 |
|---------------|--------|-----------------|-----------------|------|
| `make local`  | ✗      | SQLite          | 호스트 PM2      | Docker 없는 노트북 / 빠른 데모 |
| `make dev`    | ✓ Docker | Postgres (또는 SQLite) | 호스트 PM2 (hot-reload) | 일상 개발 |
| `make prod`   | ✓ Docker | Postgres       | 호스트 PM2 (build 후) | IP 노출 운영 |

모두 worker/web 은 호스트에서 PM2 로 실행 → 호스트 GPU/MPS 그대로 사용.
TLS / 도메인 라우팅은 nginx/Caddy 같은 호스트 리버스 프록시로 별도 구성 (compose 책임 아님).

---

## 4. 사전 요구사항

| 항목      | 최소 | 비고 |
|-----------|------|------|
| OS        | Linux (Ubuntu 22.04+) / macOS 13+ | Apple Silicon MPS 지원 |
| Python    | 3.12 | `uv venv .venv --python 3.12` |
| Node.js   | 20 LTS (또는 18+) | pnpm@10 (Node 22.13+ 는 pnpm@11) |
| Docker    | 24+ + compose v2 | `make dev` / `make prod` 만 필요 |
| GPU 드라이버 | NVIDIA 535+ 또는 macOS native | via-host 라 nvidia-container-toolkit 불필요 |
| 디스크    | 50GB+ | 모델 캐시 + 인프라 볼륨 |

`make bootstrap` 이 uv / pnpm / pm2 를 `~/.local/bin` 에 설치하므로 sudo 불필요.

---

## 5. 최초 설치 (bootstrap)

```bash
# 1. 저장소 배치 (sibling 구조 권장)
parent/
├── Finetuning-Pipeline-ops/
├── Finetuning-Pipeline-worker/
└── Finetuning-Pipeline-frontend/

# 2. ops 디렉토리로 이동
cd parent/Finetuning-Pipeline-ops

# 3. .env 생성 + 비밀 값 채우기
cp docker/.env.example docker/.env
$EDITOR docker/.env          # SUPERVISOR_*, POSTGRES_PASSWORD 등 교체

# 4. 전체 의존성 자동 설치 (uv / pnpm / pm2 / Python deps / Node deps)
make bootstrap

# 5. 학습 패키지 (torch / transformers / bitsandbytes — 환경별 wheel)
make install-deps

# 6. 환경 진단 (선택)
make env-status
```

`~/.local/bin` 이 PATH 에 없으면 안내 메시지가 출력됨:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## 6. 환경 변수

모든 비밀은 `docker/.env` 단일 파일. ecosystem.config.cjs 가 worker/web 양쪽에 주입.

### 필수 (모든 모드)

| 키                       | 예시                              | 비고 |
|--------------------------|-----------------------------------|------|
| `SUPERVISOR_ID`          | `admin@example.com`               | 부팅 시 자동 생성/admin 보장 |
| `SUPERVISOR_PASSWORD`    | `s3cr3t-strong-pass`              | 위 계정 비밀번호 |

### prod 추가 필수

| 키                       | 비고 |
|--------------------------|------|
| `POSTGRES_PASSWORD`      | DB 인증 |
| `REDIS_PASSWORD`         | Redis 인증 (`requirepass` 적용) |
| `MINIO_ROOT_USER` / `_PASSWORD` | S3 인증 |
| `NEXTAUTH_SECRET`        | `openssl rand -base64 32` |
| `HF_TOKEN`               | 비공개 HF 모델 다운로드 |

### 선택

| 키                       | 비고 |
|--------------------------|------|
| `DATABASE_URL`           | Postgres 강제 (`postgresql://wfp:...@localhost:5532/wfp`). 미지정 시 SQLite |
| `REDIS_URL`              | `redis://localhost:6479/0` (dev 인프라) |
| `S3_ENDPOINT` / `_BUCKET`| `http://localhost:9100` (MinIO) |
| `JWT_SECRET`             | 미지정 시 `NEXTAUTH_SECRET` 사용 |
| `NEXT_PUBLIC_WS_BASE`    | WebSocket 베이스 (운영) |
| `NEXT_PUBLIC_WORKER_WS_PORT` | 자동 추론 시 worker 포트 (기본 8000) |
| `GOOGLE_/GITHUB_/KAKAO_CLIENT_*` | OAuth 공급자 |
| `WFP_RULES_PATH`         | `rules/hw_to_plan.yaml` override |
| `WFP_TORCH_INDEX`        | PyTorch wheel index override |
| `WFP_LLAMA_CPP_DIR`      | GGUF 변환용 llama.cpp 위치 (`make install-convert-tools` 클론 경로). 미지정 시 PATH 탐색 |
| `WFP_CONVERT_TIMEOUT`    | 모델 변환 서브프로세스 타임아웃(초). 기본 1800 |
| `GRADIO_BASE_URL`        | Stage 9 추론 시연 |

`make dev` 는 `dev-env-check` 가 `SUPERVISOR_*` 만 검증, `make prod` 는 `env-check` 가 모든 운영 비밀 검증.

---

## 7. Makefile 명령 전체 사용 가이드

`make` 만 입력하면 노출 명령 6 개 (`help` / `info` / `dev` / `prod` / `local` / `down`) 만 표시.
나머지 명령은 숨겨졌을 뿐 모두 동작 — 정확한 타깃명으로 직접 호출 가능 (예: `make bootstrap`, `make logs`).
아래는 카테고리별 전체 명령 레퍼런스:

### 7.1 모드 진입 (별칭 + 정식명)

| 별칭        | 정식명                    | 동작 |
|-------------|---------------------------|------|
| `make dev`  | `docker-dev-via-host`     | 인프라 기동 → PM2 dev (`wfp-worker-dev` + `wfp-web-dev`, hot-reload) |
| `make prod` | `docker-prod-via-host`    | 인프라 기동 → `pnpm build` → PM2 prod (`wfp-worker-prod` + `wfp-web-prod`) |
| `make local`| `docker-local-via-host`   | SQLite + PM2 local (`wfp-worker-local` + `wfp-web-local`, Docker 무관) |
| `make down` | host-down + infra down    | PM2 daemon + 좀비 + 인프라 컨테이너 모두 정지 |

### 7.2 설치 / 갱신

| 명령                    | 동작 |
|-------------------------|------|
| `make bootstrap`        | uv + pnpm + pm2 + Python/Node deps 전체 설치 |
| `make env-status`       | OS/GPU 진단 + 누락 패키지 표시 |
| `make env-status-json`  | 진단 JSON (CI 용) |
| `make install-deps`     | 학습 패키지(torch/transformers/…) 환경별 자동 설치 |
| `make install-convert-tools` | 모델 변환 도구(mlx-lm/onnx/optimum + llama.cpp) 설치 — bootstrap 포함 |
| `make reinstall-worker` | `git pull` 후 worker uninstall + reinstall + PM2 재시작 |
| `make sync`             | `reinstall-worker` 별칭 |
| `make worker-editable`  | editable install 보장 (idempotent) |
| `make pull`             | worker + web 각각 `git pull --ff-only` (로컬 변경 있으면 건너뜀) |
| `make deploy`           | **두 레포 동시 배포** — `pull` → worker 재설치 → web `pnpm install`(+prod면 `build`) → PM2 재시작. `GIT_PULL=0` 로 pull 생략 |
| `make redeploy`         | `deploy` 별칭 |

> **worker·web 동시 변경 시** `make deploy` 한 명령으로 반영. 실행 중인 모드(prod/dev/local)를 자동 감지해 prod web 이면 `pnpm build` 까지 수행한다. 커밋 전 로컬 편집만 반영하려면 `make deploy GIT_PULL=0`.

### 7.3 호스트 직접 실행 (foreground, PM2 없이)

| 명령                | 동작 |
|---------------------|------|
| `make dev-worker`   | `uvicorn --reload` 직접 실행 (.env 자동 로드) |
| `make prod-worker`  | `uvicorn --workers 1` |
| `make dev-web`      | `pnpm dev` |
| `make prod-web`     | `pnpm build && pnpm start` |

### 7.4 테스트 / 검증

| 명령              | 동작 |
|-------------------|------|
| `make test`       | worker pytest 전체 |
| `make test-cov`   | 커버리지 포함 |
| `make lint`       | ruff + eslint |
| `make typecheck`  | mypy + tsc |
| `make ci`         | lint + typecheck + test |

### 7.5 카탈로그 / 운영

| 명령                  | 동작 |
|-----------------------|------|
| `make catalog-refresh`| HF Hub trending 기반 모델 카탈로그 갱신 |
| `make restart` / `make host-restart` | PM2 앱 재시작 + env reload |
| `make logs` / `make host-logs`       | PM2 통합 로그 (worker + web) |
| `make logs-worker`    | worker 로그만 |
| `make logs-web`       | web 로그만 |
| `make status`         | PM2 프로세스 상태 표 |
| `make monit`          | PM2 실시간 모니터 |

### 7.6 인프라 / 정리

| 명령                      | 동작 |
|---------------------------|------|
| `make docker-infra-start` | 인프라 컨테이너만 기동 |
| `make docker-infra-down`  | 인프라 컨테이너만 정지 |
| `make host-down`          | PM2 + 좀비 + 포트 8000/3000 강제 정리 |
| `make clean`              | `__pycache__` / `.pytest_cache` / `.next` 삭제 |
| `make docker-clean`       | 인프라 정지 + 볼륨 삭제 (**데이터 손실**) |
| `make info`               | 감지된 경로 + GPU 출력 |

---

## 8. 일반 운영 흐름

### 8.1 로컬 노트북 (Docker 없음, MPS / CPU)

```bash
make local              # SQLite + PM2
make logs               # 진행 확인
# 브라우저: http://localhost:3000  worker: http://localhost:8000
make down               # 종료
```

### 8.2 일상 개발 (Linux 워크스테이션 / mac)

```bash
make dev                # 인프라 컨테이너 + PM2 (hot-reload)
make logs               # 로그
# 코드 수정 시 worker 는 uvicorn --reload, web 은 next dev 가 자동 반영
# 의존성 추가 시:
make reinstall-worker   # 또는 cd ../Finetuning-Pipeline-worker && uv pip install ...
make down               # 종료
```

### 8.3 IP 노출 운영 (단일 서버, TLS 없음)

```bash
# 사전 — docker/.env 의 모든 prod 비밀 채움
make prod               # pnpm build + PM2 prod 기동
make status             # 상태 확인
make logs-worker        # 학습 로그 모니터링
```

운영 서버 80/443 TLS 가 필요하면 호스트 nginx/Caddy/Traefik 으로 별도 구성하고
`localhost:3000` (web) / `localhost:8000` (worker) 로 프록시. WebSocket 은 `Upgrade` 헤더 전달 필수.

---

## 9. PM2 운영 (logs / restart / monit)

PM2 는 `~/.local/bin/pm2` 에 user-local 설치. 아래는 `make logs` 가 호출하는 명령들의 직접 사용 방법:

```bash
# 등록된 앱 목록 + 상태
pm2 list

# 실시간 로그 (전체)
pm2 logs

# 특정 앱만
pm2 logs wfp-worker-dev
pm2 logs wfp-web-prod

# 재시작 + env 갱신 (docker/.env 수정 후)
WORKER_DIR=... FRONTEND_DIR=... HOST_LOG_DIR=... \
  pm2 restart wfp-worker-prod --update-env

# 실시간 모니터 (CPU / 메모리)
pm2 monit

# 영속 등록 (서버 부팅 시 자동 시작)
pm2 startup            # 안내된 명령 sudo 로 실행
pm2 save               # 현재 등록된 앱 영속화
```

PM2 앱 이름 규칙:
- `wfp-worker-dev` / `wfp-worker-prod` / `wfp-worker-local`
- `wfp-web-dev` / `wfp-web-prod` / `wfp-web-local`

로그 파일: `.host-logs/worker.log` / `.host-logs/web.log` (+ `*.error.log`).

---

## 10. Docker 인프라 운영

```bash
# 단독 기동 / 정지
make docker-infra-start
make docker-infra-down

# 직접 docker compose
cd docker
docker compose -f compose.infra.yaml ps
docker compose -f compose.infra.yaml logs -f postgres
docker compose -f compose.infra.yaml restart redis
```

포트 매핑 (외부 ↔ 컨테이너):

| 서비스    | 외부 | 내부 | 비고 |
|-----------|------|------|------|
| postgres  | 5532 | 5432 | 다른 PG 와 충돌 회피 |
| redis     | 6479 | 6379 |
| minio API | 9100 | 9000 |
| minio UI  | 9101 | 9001 | http://localhost:9101 (root user/pass 로 로그인) |
| mailpit SMTP | 1125 | 1025 | 회원가입 이메일 인증 트랩 |
| mailpit UI   | 8125 | 8025 | http://localhost:8125 |

볼륨: `pg_data` / `redis_data` / `minio_data` — `make docker-clean` 으로만 삭제.

---

## 11. 트러블슈팅

### 11.1 포트 충돌 (8000 / 3000 점유)

```bash
make host-down          # PM2 + 좀비 + 포트 강제 정리
lsof -i :8000           # 잔여 프로세스 확인
```

### 11.2 PM2 가 PATH 못 찾음

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
which pm2               # ~/.local/bin/pm2 출력되어야
```

### 11.3 worker 가 모듈을 못 찾음 (`ModuleNotFoundError: wfp_worker`)

editable install 깨짐. 재설치:

```bash
make reinstall-worker
```

### 11.4 학습 시 CUDA 비활성 (NVIDIA GPU 있는데)

PyTorch wheel 이 CPU-only. 환경별 재설치:

```bash
make install-deps       # env_check 가 CUDA wheel index 선택
# aarch64 (Jetson/Grace) + Blackwell:
WFP_TORCH_INDEX=https://download.pytorch.org/whl/nightly/cu128 make install-deps
```

### 11.5 web 빌드 실패 (`make prod`)

```bash
tail -50 .host-logs/web-build.log
cd ../Finetuning-Pipeline-frontend && pnpm build       # 직접 재시도 + 에러 확인
```

### 11.6 인프라 컨테이너 healthcheck 실패

```bash
docker logs wfp-postgres
docker compose -f docker/compose.infra.yaml restart postgres
```

### 11.7 잡 상태가 디스크에 안 남음

`~/.wfp/jobs_state.json` 또는 (Docker 모드에서) `/data/jobs_state.json` 확인. throttle 로 2초 이내 연속 호출은 skip — 종료 시 lifespan 이 force=True 로 명시 저장.

### 11.8 WebSocket 끊김 / 진행 스트림 안 보임

브라우저는 worker `/ws/{job_id}` 에 **직접 연결** (Next.js proxy 없음). 운영 reverse proxy 사용 시:
- `Upgrade` / `Connection` 헤더 전달
- `proxy_read_timeout` 충분 (학습 중 ping 30초 간격)
- `NEXT_PUBLIC_WS_BASE` 또는 `NEXT_PUBLIC_WORKER_WS_PORT` 빌드 타임 주입 후 `make prod` 재빌드

---

## 12. 업그레이드 / 코드 반영

```bash
# 1. 코드 pull
cd ../Finetuning-Pipeline-worker && git pull
cd ../Finetuning-Pipeline-frontend && git pull
cd ../Finetuning-Pipeline-ops && git pull

# 2. worker 의존성 갱신
cd ../Finetuning-Pipeline-ops
make reinstall-worker   # uninstall + reinstall + PM2 재시작

# 3. web 갱신 (dev 모드는 hot-reload, prod 는 재빌드 필요)
make restart            # dev 면 충분
make prod               # prod 는 pnpm build 다시 돌림
```

`.env` 값만 바꾼 경우:
```bash
make restart            # PM2 --update-env 로 새 값 주입
```

---

## 13. 백업 / 복구

### 13.1 잡 상태 파일

- 로컬: `~/.wfp/jobs_state.json` (+ `.1` ~ `.5` 회전 백업)
- Docker 모드: 컨테이너 안 `/data/jobs_state.json` — worker 컨테이너 사용 안 함 (via-host) 이므로 호스트 `~/.wfp/` 동일

### 13.2 Postgres dump

```bash
docker exec wfp-postgres pg_dump -U wfp wfp | gzip > wfp-$(date +%F).sql.gz
```

### 13.3 MinIO 데이터

```bash
docker run --rm -v wfp-infra_minio_data:/data alpine \
  tar czf - /data > minio-$(date +%F).tar.gz
```

---

## 14. Worktro Finetuning Pipeline → WFP 변경 요약

1. **빌드/배포 단순화**
   - Dockerfile / Dockerfile.gpu (worker, frontend) 삭제
   - compose.dev.yaml / compose.prod*.yaml / compose.*.gpu.yaml / compose.prod.tls.yaml 삭제
   - **남은 compose: `compose.infra.yaml` 하나 (인프라 전용)**
   - via-host 3 모드만 — `make dev` / `make prod` / `make local`

2. **Makefile 정리**
   - `build-*` / `docker-dev*` / `docker-prod*` / `docker-prod-tls*` / `traefik-diag` 제거
   - `dev` / `prod` / `local` / `down` / `restart` / `logs` 짧은 별칭 도입

3. **버그 수정**
   - `runtime.save_state` throttle (2초) — WS 이벤트 폭주 시 디스크 I/O 완화
   - `env_check._check_imports` 가 `importlib.util.find_spec` 사용 — bitsandbytes CUDA init side-effect 회피
   - 상세는 [`need-to-debug.md`](need-to-debug.md)

4. **PM2 ecosystem 코멘트만 갱신** — 로직은 동일 (dev/prod/local 변형 그대로 사용)

5. **sibling 자동 감지 별칭 확장** — `WORKER_DIR`/`FRONTEND_DIR` 이 `FP-worker`/`worker`, `FP-frontend`/`frontend` 디렉토리명도 탐색

6. **worker admin 모델 관리 확장** — 카탈로그 CRUD / HF 검색 / 모델 업로드·다운로드 / 프리셋 / 데이터 소스 화이트리스트 + 구조화 에러 코드(`WFPErrorCode`). 상세는 worker/frontend README 참조.

기존 Worktro 코드의 잠재적 결함과 수정 가이드는 [`need-to-debug.md`](need-to-debug.md) 참고.

---

## 부록 — 관련 문서

- [Finetuning-Pipeline-worker README](../Finetuning-Pipeline-worker/README.md) — 9-Stage 파이프라인 상세 ([EN](../Finetuning-Pipeline-worker/README.en.md))
- [Finetuning-Pipeline-frontend README](../Finetuning-Pipeline-frontend/README.md) — 라우트 / WS 연결 ([EN](../Finetuning-Pipeline-frontend/README.en.md))
- [ADMIN-README.md](ADMIN-README.md) — 관리자 운영 매뉴얼 (기존 보존)
- [need-to-debug.md](need-to-debug.md) — 원본 결함 + 수정 가이드
- [.doc/](.doc/) — PRD / 아키텍처 다이어그램
