# Wise Fine-tuning Pipeline (WFP)

> **분야(KSIC) 선택만으로 도메인 특화 LLM 파인튜닝 자동화.**

비기술 사용자가 업종을 선택하는 것만으로 **데이터 수집 → 정제 → 학습 → 평가 → 패키징**
전 과정을 자동 수행하는 1-click 파인튜닝 플랫폼.

- **백엔드 (Finetuning-Pipeline-worker)**: Python 3.12 + FastAPI 9-Stage 파이프라인
- **프론트엔드 (Finetuning-Pipeline-frontend)**: Next.js 14 + shadcn/ui 5-step 위자드
- **운영 (ops)**: Docker Compose, HW 규칙 YAML, GitHub Actions

---

## 목차

1. [프로젝트 구조](#1-프로젝트-구조)
2. [9-Stage 파이프라인](#2-9-stage-파이프라인)
3. [빠른 시작](#3-빠른-시작)
4. [컴포넌트별 가이드](#4-컴포넌트별-가이드)
5. [아키텍처](#5-아키텍처)
6. [개발 워크플로우](#6-개발-워크플로우)
7. [배포](#7-배포)
8. [문서](#8-문서)

---

## 1. 프로젝트 구조

```
# 독립 저장소 3개로 구성

DA(Python,R,...)/
└── Finetuning-Pipeline-worker/   # Python 백엔드 — FastAPI + 9 Stage 파이프라인
    ├── src/wfp_worker/            # stage1_init ~ stage9_package + common + server.py
    ├── tests/                     # pytest 90개 시나리오 + results MD
    ├── pyproject.toml             # uv 의존성 관리
    ├── Dockerfile / Dockerfile.gpu
    └── README.md

Web(Node,Script)/
├── Finetuning-Pipeline-frontend/ # Next.js 14 프론트엔드
│   ├── app/                      # App Router — (marketing) (auth) (app) (admin)
│   ├── components/               # ui/ (shadcn) + layout/ + jobs/
│   ├── lib/                      # api, ws, ksic, store(Zustand), utils
│   ├── types/api.ts              # Finetuning-Pipeline-worker Pydantic 1:1 매핑
│   ├── messages/                 # next-intl ko/en
│   └── README.md
│
└── Finetuning-Pipeline-ops/      # 운영 (본 저장소)
    ├── rules/
    │   └── hw_to_plan.yaml       # GPU/CPU → 파이프라인 플랜 규칙 (외부화)
    ├── docker/
    │   ├── compose.dev.yaml      # 개발 베이스 — CPU + 인증 우회
    │   ├── compose.dev.gpu.yaml  # 개발 GPU 오버라이드 (nvidia 런타임)
    │   ├── compose.prod.yaml     # 운영 베이스 — HTTP/IP 접속 + Traefik + 백업
    │   ├── compose.prod.gpu.yaml # 운영 GPU 오버라이드 (nvidia 런타임)
    │   ├── compose.prod.tls.yaml # 운영 TLS 오버라이드 (도메인 + Let's Encrypt)
    │   ├── compose.infra.yaml    # 인프라 전용 (호스트 직접 실행용 — Apple MPS 등)
    │   ├── .env.example
    │   └── README.md             # Docker 통합 가이드
    ├── scripts/
    │   └── reaper.py             # 자원 회수 사이드카
    ├── Makefile                  # bootstrap / dev / test / build / docker-*
    └── README.md                 # 본 문서
```

추후 추가될 컴포넌트 (PRD §7):
- `backend/api-gateway/`, `backend/job-service/`, ... — NestJS 마이크로서비스
- `database/migrations/` — Prisma + SQLite/PostgreSQL 듀얼 지원
- `frontend/desktop/` — Tauri WebView 데스크탑 패키지

---

## 2. 9-Stage 파이프라인

PRD §4의 9 스테이지를 Finetuning-Pipeline-worker가 자동으로 순차 실행.

| Stage | 책임 | 주요 모듈 |
|-------|------|-----------|
| **1. Init** | KSIC + 태스크 검증 → JobSpec 생성 | `stage1_init/goal_builder.py` |
| **2. HW Probe** | psutil/pynvml로 사양 수집 → 플랜 결정 | `stage2_hw_probe/{prober,plan_recommender}.py` |
| **3. Env Setup** | Python/패키지/드라이버 검증 | `stage3_env_setup/env_manager.py` |
| **4. Model** | HF 카탈로그 → 자동/수동 선택 + 다운로드 | `stage4_model/{catalog,picker,downloader}.py` |
| **5. Data** | 수집(4모드) → 정제(6단계) → 분할 | `stage5_data/{collector,cleaner,formatter}.py` |
| **6. Train Config** | HW 플랜 → TrainConfig 자동 빌드 | `stage6_train_config/config_builder.py` |
| **7. Train Run** | SFTTrainer + LoRA/QLoRA 실행 | `stage7_train/trainer.py` |
| **8. Eval** | PPL/ROUGE/F1 + 재시도 판정 | `stage8_eval/evaluator.py` |
| **9. Package** | adapter/GGUF/model_card/ZIP | `stage9_package/packager.py` |

각 단계는 진행 이벤트를 WebSocket으로 발행하여 프론트엔드 실시간 표시.

---

## 3. 빠른 시작

### 3-1. 사전 요구사항

| 도구 | 최소 버전 | 용도 |
|------|-----------|------|
| Python | 3.12 | Finetuning-Pipeline-worker |
| uv | 최신 | Python 패키지 관리 |
| Node.js | 20.x LTS | Finetuning-Pipeline-frontend |
| pnpm | 9.x | Node 패키지 관리 |
| Docker | 최신 (선택) | DB/스토리지 통합 실행 |
| CUDA / MPS | 12.1+ / N/A | GPU 학습 (선택) |

### 3-2. 백엔드(Finetuning-Pipeline-worker) 실행

```bash
cd ~/Developer/DA\(Python,R,...\)/Finetuning-Pipeline-worker
uv venv .venv --python 3.12
uv pip install -e ".[dev]" --python .venv/bin/python
cp .env.example .env          # SUPERVISOR_ID / SUPERVISOR_PASSWORD 설정
.venv/bin/python -m pytest tests/ -v             # 90개 시나리오 검증
# ops에서: make dev-worker  (.env 자동 로드)
.venv/bin/uvicorn wfp_worker.server:app --port 8000 --reload
```

서버: `http://localhost:8000` · Swagger: `http://localhost:8000/docs`

### 3-3. 프론트엔드(Finetuning-Pipeline-frontend) 실행

별도 터미널:

```bash
cd ~/Developer/Web\(Node,Script\)/Finetuning-Pipeline-frontend
pnpm install
cp .env.example .env.local
pnpm dev
```

브라우저: `http://localhost:3000`

### 3-4. Docker 통합 실행 (권장)

전체 스택(워커 + 웹 + DB + Redis + MinIO + MailHog)을 단일 명령으로 기동. Makefile이 호스트의 GPU 유무를 자동 감지해 CPU/GPU 모드를 선택한다.

```bash
make docker-dev      # GPU 자동 감지 (nvidia-smi 검사 → 있으면 GPU 모드)
make docker-dev-cpu  # CPU 강제
make docker-dev-gpu  # GPU 강제 (nvidia 런타임 필요)
make docker-info     # 현재 감지 결과 확인 (경로 + GPU)
```

수동 실행:

```bash
cd docker && cp .env.example .env
# CPU
docker compose -f compose.dev.yaml up -d --build
# GPU (베이스 + 오버라이드)
docker compose -f compose.dev.yaml -f compose.dev.gpu.yaml up -d --build
```

접속:

| URL | 서비스 |
|-----|--------|
| http://localhost:3000 | Next.js 프론트엔드 |
| http://localhost:8000 | Finetuning-Pipeline-worker API + Swagger `/docs` |
| http://localhost:9101 | MinIO 콘솔 (`wfp-minio` / `wfp-minio-secret`) |
| http://localhost:8125 | MailHog (이메일 트랩) |

#### 하이브리드 모드 — 인프라(Docker) + worker/web(호스트)

Docker for Mac은 Linux VM 안에서 동작 → MPS 미접근. 호스트의 Apple Silicon GPU/MPS, 빠른 핫리로드, 직접 디버깅을 활용하려면 인프라만 컨테이너로 두고 worker/web을 호스트에서 직접 실행.

**원커맨드** (백그라운드 + PID 추적):

```bash
make docker-dev-via-host   # 인프라 → 호스트 worker(uvicorn --reload) + web(pnpm dev)
make docker-prod-via-host  # 인프라 → 호스트 worker(workers=2) + web(pnpm build/start)

make host-status           # 프로세스 상태
make host-logs             # worker + web 로그 동시 tail
make host-down             # 호스트 프로세스 정지
```

PID/로그는 `.host-pids/`, `.host-logs/`에 저장 (gitignore 적용).

**수동** (foreground, 별도 터미널 권장):

```bash
make docker-infra   # postgres/redis/minio/mailhog만 기동
make dev-worker     # 별도 터미널 — 호스트 venv에서 uvicorn 실행 (MPS 자동 사용)
make dev-web        # 별도 터미널 — pnpm dev
```

상세 가이드 + 운영 환경(Traefik TLS + GPU + 백업): [`docker/README.md`](docker/README.md)

### 3-5. 첫 잡 생성

1. `http://localhost:3000/jobs/new/step-1-category` 진입
2. KSIC 분야 카드 선택 (예: J 정보통신업)
3. 태스크(예: code) + 설명(10자 이상) 입력
4. 모델 자동 선택 → 데이터 모드 선택 → 학습 설정 권장값 → 시작
5. 모니터링 페이지 자동 이동 → WebSocket 진행 스트림 + 손실 그래프
6. Stage 9 완료 → 아티팩트 다운로드 + Gradio Playground 추론 시연

---

## 4. 컴포넌트별 가이드

| 컴포넌트 | README | 핵심 내용 |
|----------|--------|-----------|
| **Finetuning-Pipeline-worker** | `Finetuning-Pipeline-worker/README.md` (별도 저장소) | 9 Stage 단독 실행 예시, REST API, HW 규칙 수정, 테스트 결과 |
| **Finetuning-Pipeline-frontend** | `Finetuning-Pipeline-frontend/README.md` (별도 저장소) | 페이지 구조, 라우팅 그룹, WS 클라이언트, 5-step 위자드 흐름 |
| **PRD** | [.doc/PRD.md](.doc/PRD.md) | 16장 전체 명세 (제품 비전, 비기능, 로드맵) |

### Finetuning-Pipeline-worker REST 요약

JWT Bearer 토큰 인증 (signup/login으로 발급). `🔒` = 인증 필요, `👑` = ADMIN.

| 메서드 | 경로 | 설명 | Auth |
|--------|------|------|:----:|
| `GET` | `/health` | 헬스체크 | |
| `GET` | `/hw/caps` | 현재 HW 스냅샷 | |
| `POST` | `/auth/signup` | 회원가입 + 즉시 토큰 (USER 권한) | |
| `POST` | `/auth/login` | 이메일+비번 로그인 | |
| `GET` | `/auth/me` | 현재 사용자 | 🔒 |
| `PATCH` | `/users/me` | 프로필 수정 (이름) | 🔒 |
| `POST` | `/users/me/hf-token` | HF 토큰 저장 | 🔒 |
| `DELETE` | `/users/me/hf-token` | HF 토큰 삭제 | 🔒 |
| `GET` | `/models/` | 모델 카탈로그 (HW 기반 필터) | |
| `POST` | `/jobs` | 잡 생성 + 비동기 파이프라인 | 🔒 |
| `GET` | `/jobs` | 본인 잡 목록 | 🔒 |
| `GET` | `/jobs/{id}` | 잡 상태 (소유자만) | 🔒 |
| `DELETE` | `/jobs/{id}` | 잡 취소 | 🔒 |
| `GET` | `/jobs/{id}/artifacts/{kind}` | 아티팩트 파일 다운로드 | 🔒 |
| `WS` | `/ws/{id}` | 실시간 진행 스트림 | |
| `GET` | `/admin/stats` | 대시보드 카드 (사용자/잡/타이밍/GPU) — PRD §10.1 | 👑 |
| `GET` | `/admin/resources` | GPU/큐/디스크 현황 | 👑 |
| `GET` | `/admin/users` | 사용자 목록 | 👑 |
| `PATCH` | `/admin/users/{id}` | 권한/활성 토글 | 👑 |
| `GET` | `/admin/jobs` | 전체 잡 (필터: state/user_id/ksic_section/date_from/date_to) | 👑 |
| `GET` | `/admin/jobs/{id}` | 잡 상세 + 이벤트 로그 — PRD §10.2 | 👑 |
| `POST` | `/admin/jobs/{id}/cancel` | 강제 취소 — PRD §10.2 | 👑 |
| `PATCH` | `/admin/jobs/{id}/priority` | 우선순위 변경 (1~9) — PRD §10.2 | 👑 |
| `POST` | `/admin/reaper/run` | Reaper 수동 트리거 — PRD §10.3 | 👑 |
| `GET/POST/PATCH/DELETE` | `/admin/catalog/models[/{id}]` | 모델 카탈로그 CRUD — PRD §10.4 | 👑 |
| `GET/POST/PATCH/DELETE` | `/admin/data-sources[/{id}]` | 데이터 소스 화이트리스트 CRUD — PRD §10.4 | 👑 |
| `GET/POST/PATCH/DELETE` | `/admin/presets[/{id}]` | 카테고리/프리셋 CRUD — PRD §10.4 | 👑 |
| `GET` | `/admin/audit` | 감사 로그 (필터: actor_email/action/date) — PRD §10.5 | 👑 |
| `GET` | `/admin/env/status` | 호스트 환경 진단 (Python/CUDA/MPS/패키지) | 👑 |
| `POST` | `/admin/env/install` | 학습 패키지 자동 설치 | 👑 |

### Finetuning-Pipeline-frontend 라우팅 그룹

| 그룹 | 인증 | 페이지 |
|------|------|--------|
| `(marketing)` | ✗ | 랜딩, 요금 |
| `(auth)` | ✗ | login, signup, callback |
| `(app)` | USER | dashboard, jobs/new(5-step), jobs/[id], playground, artifacts, settings |
| `(admin)` | ADMIN | users, jobs, resources, catalog, audit |

---

## 5. 아키텍처

```
┌────────────────┐      ┌────────────────┐
│ Finetuning-Pipeline-frontend    │      │ Desktop (Tauri)│
│ Next.js 14     │      │ — 예정         │
└──────┬─────────┘      └──────┬─────────┘
       │ HTTPS / WS            │
       ▼                       ▼
┌──────────────────────────────────────────┐
│ API Gateway (NestJS) — 예정              │
│  ↓ 현재는 Next.js BFF가 직접 Finetuning-Pipeline-worker로  │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│ Finetuning-Pipeline-worker (FastAPI, Python 3.12)         │
│ ┌──────────────────────────────────────┐ │
│ │ 9-Stage Pipeline (wfp_worker)        │ │
│ │ Stage1 → Stage2 → ... → Stage9       │ │
│ └──────────────────────────────────────┘ │
└──────┬───────────────────────────────────┘
       │
       ├──→ HuggingFace Hub (모델 다운로드)
       ├──→ ~/.wfp/  (로컬 캐시 + 체크포인트)
       └──→ Gradio Playground (Stage 9 완료 후)
```

자세한 다이어그램: [.doc/architecture.png](.doc/architecture.png) · [.doc/architecture.svg](.doc/architecture.svg)

### HW 규칙 (외부화)

`rules/hw_to_plan.yaml`에서 GPU/RAM → 권장 전략을 정의.
파일 수정만으로 코드 재시작 없이 다음 잡부터 반영.

```yaml
rules:
  - id: nvidia_16gb
    condition:
      gpu_vendor: nvidia
      vram_gb_min: 16
      vram_gb_max: 23
    plan:
      max_model_params_b: 8
      strategies: [qlora]
      recommended_strategy: qlora
      recommended_quant: int4
      max_seq_length: 2048
      batch_size: 2
      gradient_accumulation: 8
```

---

## 6. 개발 워크플로우

### 디렉토리 캐시

| 경로 | 내용 |
|------|------|
| `~/.wfp/models/<org>__<name>/<rev>/` | HF 모델 캐시 |
| `~/.wfp/jobs/<job_id>/raw/` | 원시 수집 데이터 |
| `~/.wfp/jobs/<job_id>/dataset/` | 정제·분할된 데이터셋 |
| `~/.wfp/checkpoints/<job_id>/` | 학습 체크포인트 |
| `~/.wfp/artifacts/<job_id>/` | 최종 패키지 |

### 테스트

```bash
# Finetuning-Pipeline-worker (별도 저장소)
cd ~/Developer/DA\(Python,R,...\)/Finetuning-Pipeline-worker
.venv/bin/python -m pytest tests/ -v --cov=wfp_worker
# 결과: 110 passed (90 unit + 20 E2E API)

# 단위만
.venv/bin/python -m pytest tests/ -v --ignore=tests/test_e2e_api.py
# 통합 API (TestClient + sqlite)만
.venv/bin/python -m pytest tests/test_e2e_api.py -v

# Finetuning-Pipeline-frontend (별도 저장소)
cd ~/Developer/Web\(Node,Script\)/Finetuning-Pipeline-frontend
pnpm typecheck
pnpm lint
# E2E (브라우저): Playwright (TODO)
```

### DB 정책

| 환경 | 엔진 | 위치 | 비고 |
|------|------|------|------|
| 로컬 / dev | **SQLite** | `~/.wfp/wfp.db` 또는 `/data/wfp.db` (컨테이너) | `DATABASE_URL` 미지정 시 기본 |
| 운영 (compose.prod) | **PostgreSQL 16** | `postgres` 서비스 | `DATABASE_URL=postgresql://...` 명시 |
| 테스트 (pytest) | **SQLite** (임시 파일) | `/tmp/wfp_e2e_test.db` | 매 테스트 drop+create |

DB 모드 전환: `.env`에서 `DATABASE_URL` 설정만 변경 → 컨테이너 재시작.

### 인증 흐름

1. **회원가입** `POST /auth/signup` → access_token 즉시 발급 (USER 권한)
2. **관리자 계정** `SUPERVISOR_ID` / `SUPERVISOR_PASSWORD` 환경변수로 서버 시작 시 자동 생성/보장 (ADMIN 권한)
3. **로그인** `POST /auth/login` → access_token 발급 (만료 7일, `JWT_ACCESS_EXPIRE_MIN`으로 조정)
4. 이후 모든 보호 엔드포인트에 `Authorization: Bearer <token>` 헤더
5. Finetuning-Pipeline-frontend는 `localStorage.wfp_access_token`에 저장, 401 수신 시 `/login`으로 자동 리다이렉트

```bash
# CLI에서 직접 호출
TOKEN=$(curl -s -X POST http://localhost:8000/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{"email":"alice@example.com","password":"secret123"}' \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["access_token"])')

curl http://localhost:8000/auth/me -H "Authorization: Bearer $TOKEN"
```

### 코딩 표준

- **Python**: ruff (lint+format) · mypy (가능 범위) · pytest · snake_case
- **TypeScript**: eslint + prettier · tsc --strict · camelCase / PascalCase / UPPER_SNAKE
- **API**: REST kebab-case 경로, camelCase 응답, RFC 7807 에러
- **DB**: snake_case 테이블/컬럼, uuid v7 PK, `<table>_id` FK
- **Git**: Conventional Commits (`feat:`, `fix:`, `chore:`)
- **버전**: SemVer · 태그 `v0.1.0`

### 에러 코드

`WFP-XXYY` (XX=Stage, YY=일련번호). 전체 목록: `Finetuning-Pipeline-worker/README.md §9` (별도 저장소).

---

## 7. 배포

### Docker Compose (개발)

```bash
make docker-dev          # GPU 자동 감지
# 또는 명시:
make docker-dev-cpu      # CPU 강제
make docker-dev-gpu      # GPU 강제 (nvidia 런타임 필요)
```

서비스: `worker` (FastAPI), `web` (Next.js), `postgres` (16), `redis` (7), `minio`, `mailhog`, `reaper` 사이드카.
상세: [`docker/README.md`](docker/README.md)

### Docker Compose (운영)

기본 운영 배포는 **HTTP/IP 기반**. 도메인 + TLS는 별도 오버라이드.

```bash
# 첫 실행 — .env 없으면 자동 복사 + 중단 (값 채우라 안내)
make docker-prod
# → docker/.env.example 복사됨. 아래 8개 키를 강한 랜덤으로 채울 것:
#   SUPERVISOR_ID, SUPERVISOR_PASSWORD, POSTGRES_PASSWORD, REDIS_PASSWORD,
#   MINIO_ROOT_USER, MINIO_ROOT_PASSWORD, NEXTAUTH_SECRET, HF_TOKEN

vim docker/.env       # 값 채우기

# 재실행 — env-check 통과 후 빌드
make docker-prod          # GPU 자동 감지
make docker-prod-cpu      # CPU 강제
make docker-prod-gpu      # GPU 강제 (nvidia 런타임 필요)
```

접속: `http://<서버-IP>/`

#### TLS + 도메인 (선택)

실제 도메인 보유 + DNS A 레코드 + 80/443 외부 개방 + `DOMAIN`/`ACME_EMAIL` env 설정 완료 시.

```bash
# docker/.env에 추가
# DOMAIN=wfp.example.com
# ACME_EMAIL=admin@example.com
# NEXTAUTH_URL=https://wfp.example.com

make docker-prod-tls        # CPU + TLS
make docker-prod-tls-gpu    # GPU + TLS
```

`compose.prod.tls.yaml` 오버라이드가 HTTPS(443) + HTTP→HTTPS 리다이렉트 + Let's Encrypt TLS challenge + Host 헤더 기반 라우팅을 추가.

#### 운영 추가 사항

- **Traefik** reverse proxy (HTTP 기본, TLS 옵션)
- **GPU 워커** — `Dockerfile.gpu`: `python:3.12-slim` 베이스 + PyTorch `+cu121` 휠로 CUDA 런타임 번들 (nvidia/cuda 베이스 미사용 → 빌드 빠름, 이미지 슬림)
- **백업 사이드카** — 일 1회 PostgreSQL → MinIO dump
- **env-check** — `.env` 누락 또는 필수 키 비어있으면 빌드 전 차단
- **PathPrefix 라우팅** — `/ws` → worker, 나머지 → web (Host 헤더 무관)

### Makefile 명령

```bash
make help                   # 명령 목록
make bootstrap              # uv + pnpm 의존성 설치
make docker-info            # 현재 감지된 환경 (경로 + GPU)
make env-check              # docker/.env 존재 + 필수 키 검증
make test                   # Finetuning-Pipeline-worker pytest
make build                  # Docker 이미지 빌드 (worker + web)

# 스택 기동 — GPU 자동 감지 (env-check 자동 의존)
make docker-dev             # 개발 (백그라운드)
make docker-prod            # 운영 (HTTP/IP)
make docker-prod-tls        # 운영 + TLS (DOMAIN/ACME_EMAIL 필요)

# 강제 모드
make docker-dev-cpu         # CPU 강제 (dev)
make docker-dev-gpu         # GPU 강제 (dev)
make docker-prod-cpu        # CPU 강제 (prod)
make docker-prod-gpu        # GPU 강제 (prod)
make docker-prod-tls-gpu    # TLS + GPU (prod)

# 하이브리드 — 인프라(Docker) + worker/web(호스트 background, PID 추적)
make docker-dev-via-host    # dev 모드 (uvicorn --reload + pnpm dev)
make docker-prod-via-host   # prod 모드 (uvicorn workers=2 + pnpm build/start)
make host-status            # 호스트 프로세스 상태
make host-logs              # worker + web 로그 동시 tail
make host-logs-worker       # worker 로그만
make host-logs-web          # web 로그만
make host-down              # 호스트 프로세스 정지

# 인프라만 (수동 실행 — 별도 터미널에서 dev-worker/dev-web 직접)
make docker-infra           # postgres/redis/minio/mailhog
make dev-worker             # 호스트에서 워커 직접 실행 (foreground)
make dev-web                # 호스트에서 프론트엔드 직접 실행 (foreground)

# 관리
make docker-logs            # 워커 로그 추적
make docker-ps              # 컨테이너 상태
make docker-down            # 정지 (dev + prod 둘 다)
make docker-clean           # 정지 + 볼륨 삭제 (데이터 손실)
make ci                     # lint + typecheck + test
```

### 환경 자동 감지

Makefile은 두 가지를 자동 감지한다:

1. **컴포넌트 경로** — `WORKER_DIR` / `FRONTEND_DIR`:
   - 우선순위: env var → 시블링 디렉토리 → macOS 워크스페이스 fallback
   - 서버: ops와 worker/frontend가 같은 부모 디렉토리에 있으면 자동 인식
   - override: `WORKER_DIR=/custom/path make docker-prod`

2. **GPU 유무** — `HAS_GPU`:
   - `nvidia-smi -L`로 검사 → GPU 인식 시 `compose.*.gpu.yaml` 오버라이드 추가
   - macOS / 드라이버 미설치 → 자동 CPU 모드

`make docker-info`로 현재 감지 결과 확인.

### 향후 작업

- **CI**: GitHub Actions — lint/test/build → ghcr.io 푸시 → Trivy 스캔 (예정)
- **Kubernetes**: Helm chart (예정)
- **데스크탑**: Tauri auto-update (예정)

### 환경 변수 표준

| 컴포넌트 | 변수 | 설명 |
|----------|------|------|
| Finetuning-Pipeline-worker | `SUPERVISOR_ID` | 관리자 계정 이메일 (서버 시작 시 자동 생성/보장) |
| Finetuning-Pipeline-worker | `SUPERVISOR_PASSWORD` | 관리자 계정 비밀번호 |
| Finetuning-Pipeline-worker | `JWT_SECRET` | JWT 서명 키 (미설정 시 NEXTAUTH_SECRET 사용) |
| Finetuning-Pipeline-worker | `JWT_ACCESS_EXPIRE_MIN` | 토큰 만료(분), 기본 10080 (7일) |
| Finetuning-Pipeline-worker | `HF_TOKEN` | HuggingFace Hub 토큰 |
| Finetuning-Pipeline-frontend | `WFP_WORKER_URL` | Finetuning-Pipeline-worker FastAPI URL |
| Finetuning-Pipeline-frontend | `NEXTAUTH_SECRET` | 세션 암호화 키 |
| Finetuning-Pipeline-frontend | `GRADIO_BASE_URL` | Playground iframe URL |

---

## 8. 문서

| 문서 | 내용 |
|------|------|
| [.doc/PRD.md](.doc/PRD.md) | 16장 제품 요구사항 명세 (v0.1) |
| [.doc/PRD.pdf](.doc/PRD.pdf) | PRD PDF 변환본 |
| [.doc/architecture.mmd](.doc/architecture.mmd) | Mermaid 아키텍처 소스 |
| [.doc/architecture.png](.doc/architecture.png) | 렌더된 PNG (2400×1800) |
| [.doc/architecture.svg](.doc/architecture.svg) | 벡터 SVG |
| [.doc/Perplexity-파인튜닝 진행.md](.doc/Perplexity-파인튜닝%20진행.md) | 8-Stage 원본 조사 |
| [.doc/Perplexity-ISIC,KSIC,NACE,NAICS 분류 조사 및 정리.md](.doc/Perplexity-ISIC,KSIC,NACE,NAICS%20분류%20조사%20및%20정리.md) | 산업 분류 체계 조사 |
| `Finetuning-Pipeline-worker/README.md` (별도 저장소) | Finetuning-Pipeline-worker 단독 가이드 |
| `Finetuning-Pipeline-frontend/README.md` (별도 저장소) | Finetuning-Pipeline-frontend 단독 가이드 |
| `Finetuning-Pipeline-worker/tests/results/test_results.md` (별도 저장소) | 90개 테스트 시나리오 결과 |

---

## 로드맵 (PRD §14)

| 마일스톤 | 범위 | 시점 |
|----------|------|------|
| M0 Spec Lock | PRD 확정 | +1주 |
| M1 Skeleton | 모놀리포 + 인증 + Job CRUD | +4주 |
| M2 Single-Path FT | J/M 카테고리 end-to-end | +8주 |
| M3 HW Adapter | NVIDIA/Apple Silicon 자동 플랜 | +10주 |
| M4 Multi-category | 상위 8종 + 데이터 모드 A/B/C/D | +14주 |
| M5 Admin & Reaper | 어드민 + 자원 회수 + 감사 | +16주 |
| M6 Web+Desktop Parity | 두 클라이언트 기능 동등 | +18주 |
| M7 Beta | 외부 베타 | +22주 |
| v1.0 GA | — | +26주 |

---

## 라이선스 / 컴플라이언스

- HF 모델 사용 시 각 모델 라이선스(Llama, Qwen, Gemma 등) 명시 + 동의 체크박스 필수.
- 인터넷 수집 데이터는 robots.txt 준수 + 도메인 화이트리스트만.
- 사용자 업로드 데이터는 사용자 소유, 시스템은 학습 목적으로만 처리.
- PII/민감정보 자동 마스킹 (이메일·전화·주민번호·카드·IP·URL).

---

## 기여

이슈/PR 환영. PR 전 체크리스트:

1. `cd ~/Developer/DA\(Python,R,...\)/Finetuning-Pipeline-worker && pytest tests/ -v` 통과
2. `cd ~/Developer/Web\(Node,Script\)/Finetuning-Pipeline-frontend && pnpm typecheck && pnpm lint` 통과
3. Conventional Commits 메시지 (`feat:`, `fix:`, ...)
4. CLA 서명 (필요 시)

문의: bclim@edentns.com (Wiseman)
