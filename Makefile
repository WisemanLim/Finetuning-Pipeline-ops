# =============================================================================
# Wise Fine-tuning Pipeline (WFP) — 루트 Makefile
#
# 설계 원칙: 단순함. via-host 모드만 제공.
#   - 컨테이너는 인프라(postgres/redis/minio/mailhog)만 담당
#   - worker / web 은 호스트에서 PM2 로 직접 실행
#     → Apple Silicon MPS / 호스트 NVIDIA GPU 직접 사용
#     → Docker 안에서는 호스트 GPU/MPS 일관 사용 불가 → via-host 채택
#
# 모드:
#   make dev    — 인프라(Docker) + worker/web (PM2 dev)        [docker-dev-via-host]
#   make prod   — 인프라(Docker) + worker/web (PM2 prod build) [docker-prod-via-host]
#   make local  — Docker 없이 SQLite + worker/web (PM2)         [docker-local-via-host]
#   make down   — 전체 정지
# =============================================================================

SHELL := /bin/bash

export PATH := $(HOME)/.local/bin:$(PATH)

PM2 := $(shell command -v pm2 2>/dev/null || echo $(HOME)/.local/bin/pm2)

.PHONY: help bootstrap env-status install-deps install-convert-tools reinstall-worker sync worker-editable \
        dev prod local down restart logs logs-worker logs-web status monit info \
        deploy pull redeploy \
        dev-worker dev-web prod-worker prod-web \
        test test-cov lint typecheck ci clean \
        catalog-refresh \
        docker-dev-via-host docker-prod-via-host docker-local-via-host \
        docker-infra-start docker-infra-down docker-clean \
        env-check dev-env-check host-deps-check \
        host-down host-restart host-logs host-logs-worker host-logs-web host-status host-monit

# -----------------------------------------------------------------------------
# 컴포넌트 디렉토리 자동 감지
#   1) export WORKER_DIR=... 으로 override
#   2) Makefile 부모의 시블링 (Finetuning-Pipeline-worker / Finetuning-Pipeline-frontend)
#   3) macOS 워크스페이스 fallback
# -----------------------------------------------------------------------------
MAKEFILE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

WORKER_DIR ?= $(abspath $(strip \
  $(if $(wildcard $(MAKEFILE_DIR)/../Finetuning-Pipeline-worker),$(MAKEFILE_DIR)/../Finetuning-Pipeline-worker, \
  $(if $(wildcard $(MAKEFILE_DIR)/../FP-worker),$(MAKEFILE_DIR)/../FP-worker, \
  $(if $(wildcard $(MAKEFILE_DIR)/../worker),$(MAKEFILE_DIR)/../worker, \
  /Users/wise/Developer/DA(Python,R,...)/Finetuning-Pipeline-worker)))))

FRONTEND_DIR ?= $(abspath $(strip \
  $(if $(wildcard $(MAKEFILE_DIR)/../Finetuning-Pipeline-frontend),$(MAKEFILE_DIR)/../Finetuning-Pipeline-frontend, \
  $(if $(wildcard $(MAKEFILE_DIR)/../FP-frontend),$(MAKEFILE_DIR)/../FP-frontend, \
  $(if $(wildcard $(MAKEFILE_DIR)/../frontend),$(MAKEFILE_DIR)/../frontend, \
  /Users/wise/Developer/Web(Node,Script)/Finetuning-Pipeline-frontend)))))

# GPU 감지 (정보 표시용 — via-host 모드는 호스트 GPU 그대로 사용)
HAS_GPU := $(shell command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L 2>/dev/null | grep -q '^GPU' && echo 1 || echo 0)
ifeq ($(HAS_GPU),1)
GPU_MSG := GPU 감지됨 → 호스트 PM2 가 그대로 사용 (CUDA 휠 필요 시 make install-deps)
else
GPU_MSG := GPU 미감지 → CPU/MPS 모드
endif

.DEFAULT_GOAL := help

help: ## 명령 목록
	@echo ""
	@echo "Wise Fine-tuning Pipeline — 단순화 Makefile (via-host 기본)"
	@echo ""
	@grep -E '^(help|info|dev|prod|local|down|deploy|pull):.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-26s\033[0m %s\n", $$1, $$2}'
	@echo ""

# =============================================================================
# Setup
# =============================================================================
bootstrap: ## 전체 의존성 설치 (uv + pnpm + pm2, user-local — sudo 불필요)
	@if ! command -v npm >/dev/null 2>&1; then \
	  echo "✗ npm 미설치 — Node.js 20 LTS 이상 설치 필요"; \
	  echo "  Ubuntu/Debian: curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt-get install -y nodejs"; \
	  echo "  macOS:         brew install node@20"; \
	  exit 1; \
	fi
	@node_major=$$(node -v | sed 's/v\([0-9]*\).*/\1/'); \
	if [ "$$node_major" -lt 18 ]; then \
	  echo "✗ Node $$node_major 너무 낮음 (≥18 필요)"; exit 1; \
	fi; \
	echo "→ Node v$$(node -v | tr -d 'v'), npm $$(npm -v) 감지"
	@mkdir -p "$$HOME/.local/bin"
	@if [ ! -x "$$HOME/.local/bin/uv" ]; then \
	  echo "→ uv 자동 설치 → ~/.local/bin/uv"; \
	  curl -LsSf https://astral.sh/uv/install.sh | sh; \
	fi
	@node_major=$$(node -v | sed 's/v\([0-9]*\).*/\1/'); \
	node_minor=$$(node -v | sed 's/v[0-9]*\.\([0-9]*\).*/\1/'); \
	if [ "$$node_major" -gt 22 ] || { [ "$$node_major" -eq 22 ] && [ "$$node_minor" -ge 13 ]; }; then \
	  PNPM_VER=11; \
	else \
	  PNPM_VER=10; \
	fi; \
	if [ ! -x "$$HOME/.local/bin/pnpm" ]; then \
	  echo "→ pnpm@$$PNPM_VER 설치 → ~/.local (sudo 불필요)"; \
	  npm install -g --prefix="$$HOME/.local" pnpm@$$PNPM_VER || \
	    { echo "✗ pnpm 설치 실패"; exit 1; }; \
	fi
	@if [ ! -x "$$HOME/.local/bin/pm2" ]; then \
	  echo "→ pm2 설치 → ~/.local"; \
	  npm install -g --prefix="$$HOME/.local" pm2 || \
	    { echo "✗ pm2 설치 실패"; exit 1; }; \
	fi
	@if ! echo "$$PATH" | grep -q "$$HOME/.local/bin"; then \
	  echo ""; \
	  echo "⚠  ~/.local/bin 이 셸 PATH 에 없음. 영구 추가 권장:"; \
	  echo "   echo 'export PATH=\"\$$HOME/.local/bin:\$$PATH\"' >> ~/.bashrc"; \
	  echo "   source ~/.bashrc"; \
	  echo ""; \
	fi
	@echo "→ Finetuning-Pipeline-worker (Python 3.12 + uv)"
	@cd '$(WORKER_DIR)' && "$$HOME/.local/bin/uv" venv .venv --python 3.12 && \
	  "$$HOME/.local/bin/uv" pip install -e ".[dev]" --python .venv/bin/python
	@echo "→ Finetuning-Pipeline-frontend (Node 20 + pnpm)"
	@cd '$(FRONTEND_DIR)' && "$$HOME/.local/bin/pnpm" install
	@echo "→ 모델 변환 도구 (mlx-lm/onnx/optimum + llama.cpp)"
	-@$(MAKE) -s -C '$(MAKEFILE_DIR)' install-convert-tools
	@echo "✓ bootstrap 완료"
	-@$(MAKE) env-status

env-status: ## 호스트 환경 진단 (OS·GPU + 누락 패키지)
	cd '$(WORKER_DIR)' && .venv/bin/python -m wfp_worker.env_check

env-status-json: ## 환경 진단 JSON 출력 (CI용)
	@cd '$(WORKER_DIR)' && .venv/bin/python -m wfp_worker.env_check --json

install-deps: ## 학습 패키지 자동 설치 (torch / transformers 등 환경별)
	cd '$(WORKER_DIR)' && WFP_PROJECT_DIR=$$(pwd) .venv/bin/python -m wfp_worker.env_check --install

install-convert-tools: ## 모델 변환 도구 설치 (mlx-lm/onnx/optimum + llama.cpp clone)
	@echo "→ Python 변환 패키지 (wfp-worker[convert])"
	@cd '$(WORKER_DIR)' && "$$HOME/.local/bin/uv" pip install -e ".[convert]" --python .venv/bin/python || \
	  echo "⚠  일부 변환 패키지 설치 실패 (mlx-lm 은 Apple Silicon 전용)"
	@LLAMA_DIR="$(WORKER_DIR)/.tools/llama.cpp"; \
	if [ ! -d "$$LLAMA_DIR/.git" ]; then \
	  echo "→ llama.cpp clone → $$LLAMA_DIR"; \
	  git clone --depth 1 https://github.com/ggerganov/llama.cpp "$$LLAMA_DIR" || \
	    { echo "⚠  llama.cpp clone 실패 — GGUF 변환 비활성"; exit 0; }; \
	else \
	  echo "→ llama.cpp 이미 존재 ($$LLAMA_DIR) — git pull"; \
	  git -C "$$LLAMA_DIR" pull --ff-only || true; \
	fi; \
	echo "→ llama.cpp convert 의존성 설치"; \
	cd '$(WORKER_DIR)' && "$$HOME/.local/bin/uv" pip install -r "$$LLAMA_DIR/requirements.txt" --python .venv/bin/python || true; \
	echo ""; \
	echo "✓ 변환 도구 준비. GGUF 양자화(llama-quantize)까지 쓰려면 빌드 필요:"; \
	echo "   cmake -B $$LLAMA_DIR/build $$LLAMA_DIR && cmake --build $$LLAMA_DIR/build -j --target llama-quantize"; \
	echo "  docker/.env 에 다음 추가 후 make restart:"; \
	echo "   WFP_LLAMA_CPP_DIR=$$LLAMA_DIR"

reinstall-worker: ## worker venv 재설치 + PM2 재시작 (git pull 후 강제 반영)
	@echo "→ worker uninstall + reinstall"
	cd '$(WORKER_DIR)' && "$$HOME/.local/bin/uv" pip uninstall wfp-worker --python .venv/bin/python
	cd '$(WORKER_DIR)' && "$$HOME/.local/bin/uv" pip install -e ".[dev]" --python .venv/bin/python
	@$(MAKE) -s host-restart

sync: reinstall-worker ## git pull 후 worker 재설치 + 재시작 (별칭)

worker-editable: ## worker editable 보장 (idempotent)
	@cd '$(WORKER_DIR)' && \
	  UV_BIN="$$( [ -x .venv/bin/uv ] && echo .venv/bin/uv || command -v uv 2>/dev/null )"; \
	  if [ -n "$$UV_BIN" ]; then \
	    "$$UV_BIN" pip install -e . --no-deps --quiet --python .venv/bin/python && \
	    echo "✓ wfp_worker editable OK"; \
	  else \
	    echo "⚠ uv 미설치 — editable 건너뜀"; \
	  fi

# =============================================================================
# 배포 — 두 레포(worker + web) 변경을 호스트 PM2 에 한 번에 반영
#   worker/web 둘 다 손대는 변경(예: 새 API + UI)을 한 명령으로 배포.
#   GIT_PULL=0 으로 pull 생략 (커밋 전 로컬 편집만 반영할 때).
#   실행 중인 모드(prod/dev/local)를 자동 감지 — prod web 이면 pnpm build 수행.
# =============================================================================
GIT_PULL ?= 1

pull: ## worker + web 각각 git pull (변경사항 있으면 건너뜀)
	@for d in '$(WORKER_DIR)' '$(FRONTEND_DIR)'; do \
	  if [ -d "$$d/.git" ]; then \
	    if [ -n "$$(cd "$$d" && git status --porcelain)" ]; then \
	      echo "⚠  $$d 로컬 변경 있음 — git pull 건너뜀 (커밋/스태시 후 재실행)"; \
	    else \
	      echo "→ $$d git pull --ff-only"; \
	      (cd "$$d" && git pull --ff-only) || echo "✗ $$d pull 실패 (수동 확인)"; \
	    fi; \
	  fi; \
	done

deploy: host-deps-check ## 두 레포 변경 반영: worker 재설치 + web 빌드 + PM2 재시작 (GIT_PULL=0 로 pull 생략)
	@mkdir -p '$(HOST_LOG_DIR)'
	@if [ "$(GIT_PULL)" = "1" ]; then $(MAKE) -s pull; else echo "→ GIT_PULL=0 — git pull 생략 (로컬 편집 반영)"; fi
	@echo "→ worker editable 재설치 (Python 코드 반영)"
	@cd '$(WORKER_DIR)' && "$$HOME/.local/bin/uv" pip install -e ".[dev]" --python .venv/bin/python --quiet
	@echo "→ web 의존성 동기화"
	@cd '$(FRONTEND_DIR)' && (pnpm install --frozen-lockfile || pnpm install)
	@if $(PM2) jlist 2>/dev/null | grep -q '"name":"wfp-web-prod"'; then \
	  echo "→ prod web 감지 — pnpm build ($(HOST_LOG_DIR)/web-build.log)"; \
	  cd '$(FRONTEND_DIR)' && pnpm build > '$(HOST_LOG_DIR)/web-build.log' 2>&1 || { \
	    echo "✗ web 빌드 실패. 최근 로그:"; tail -30 '$(HOST_LOG_DIR)/web-build.log'; exit 1; \
	  }; \
	  echo "✓ web 빌드 성공"; \
	else \
	  echo "→ dev/local web (hot-reload) — 빌드 생략"; \
	fi
	@$(MAKE) -s host-restart
	@echo ""
	@echo "✓ deploy 완료 — worker/web PM2 재시작됨 (코드 + env 반영)"
	@echo "  상태: make status / 로그: make logs"

redeploy: deploy ## (별칭) deploy

# =============================================================================
# 호스트 직접 실행 (foreground, PM2 미사용)
# =============================================================================
WORKER_UVICORN_DEV  := .venv/bin/uvicorn wfp_worker.server:app --host 0.0.0.0 --port 8000 --reload
WORKER_UVICORN_PROD := .venv/bin/uvicorn wfp_worker.server:app --host 0.0.0.0 --port 8000 --workers 1

dev-worker: worker-editable ## worker foreground (uvicorn --reload, .env 자동)
	cd '$(WORKER_DIR)' && bash -c 'set -a; [ -f .env ] && source .env; set +a; exec $(WORKER_UVICORN_DEV)'

prod-worker: worker-editable ## worker foreground (uvicorn workers=1, .env 자동)
	cd '$(WORKER_DIR)' && bash -c 'set -a; [ -f .env ] && source .env; set +a; exec $(WORKER_UVICORN_PROD)'

dev-web: ## web foreground (pnpm dev)
	cd '$(FRONTEND_DIR)' && pnpm dev

prod-web: ## web foreground (pnpm build → pnpm start)
	cd '$(FRONTEND_DIR)' && pnpm build && exec pnpm start

# =============================================================================
# 테스트 / Lint
# =============================================================================
test: ## worker pytest
	cd '$(WORKER_DIR)' && .venv/bin/python -m pytest tests/ -v

test-cov: ## 커버리지 테스트
	cd '$(WORKER_DIR)' && .venv/bin/python -m pytest tests/ --cov=wfp_worker --cov-report=term-missing

lint: ## ruff + eslint
	cd '$(WORKER_DIR)' && .venv/bin/ruff check src/ tests/
	cd '$(FRONTEND_DIR)' && pnpm lint

typecheck: ## mypy + tsc
	cd '$(WORKER_DIR)' && .venv/bin/mypy src/
	cd '$(FRONTEND_DIR)' && pnpm typecheck

ci: lint typecheck test ## CI 파이프라인

# =============================================================================
# 카탈로그 운영
# =============================================================================
catalog-refresh: ## Worker 카탈로그/프리셋 자동 갱신 (HF Hub trending)
	cd '$(WORKER_DIR)' && .venv/bin/python -m wfp_worker.admin_tools.refresh_cli

# =============================================================================
# Docker 인프라 (postgres / redis / minio / mailpit)
# =============================================================================
docker-infra-start: ## 인프라 컨테이너만 기동
	@cd docker && docker compose -f compose.infra.yaml up -d

docker-infra-down: ## 인프라 컨테이너 정지
	@cd docker && docker compose -f compose.infra.yaml down

# =============================================================================
# 환경 변수 검증 — via-host 모드 사전 검사
# =============================================================================
dev-env-check: ## dev/local 최소 env 검증 (SUPERVISOR_* 만 필수)
	@if [ ! -f docker/.env ]; then \
	  if [ -f docker/.env.example ]; then \
	    echo "⚠ docker/.env 없음 → docker/.env.example 복사"; \
	    cp docker/.env.example docker/.env; \
	    echo "✗ docker/.env 열어 SUPERVISOR_ID / SUPERVISOR_PASSWORD 설정 후 재실행"; \
	    exit 1; \
	  else \
	    echo "✗ docker/.env / docker/.env.example 모두 없음"; exit 1; \
	  fi; \
	fi
	@missing=""; \
	for k in SUPERVISOR_ID SUPERVISOR_PASSWORD; do \
	  if ! grep -q "^$$k=" docker/.env || grep -qE "^$$k=$$" docker/.env; then \
	    missing="$$missing $$k"; \
	  fi; \
	done; \
	if [ -n "$$missing" ]; then \
	  echo "✗ docker/.env 누락:$$missing"; exit 1; \
	fi
	@echo "✓ docker/.env dev/local 최소 검증 통과"

env-check: ## prod env 검증 (운영 비밀 모두 필수)
	@if [ ! -f docker/.env ]; then \
	  if [ -f docker/.env.example ]; then \
	    echo "⚠  docker/.env 없음 → docker/.env.example 복사"; \
	    cp docker/.env.example docker/.env; \
	    echo "✗ docker/.env placeholder 값 교체 필요. 키: SUPERVISOR_*, POSTGRES_PASSWORD, REDIS_PASSWORD, MINIO_ROOT_*, NEXTAUTH_SECRET, HF_TOKEN"; \
	    exit 1; \
	  else \
	    echo "✗ docker/.env / docker/.env.example 모두 없음"; exit 1; \
	  fi; \
	fi
	@missing=""; \
	for k in SUPERVISOR_ID SUPERVISOR_PASSWORD POSTGRES_PASSWORD REDIS_PASSWORD MINIO_ROOT_USER MINIO_ROOT_PASSWORD NEXTAUTH_SECRET HF_TOKEN; do \
	  if ! grep -q "^$$k=" docker/.env || grep -qE "^$$k=$$" docker/.env; then \
	    missing="$$missing $$k"; \
	  fi; \
	done; \
	if [ -n "$$missing" ]; then \
	  echo "✗ docker/.env 누락:$$missing"; exit 1; \
	fi
	@echo "✓ docker/.env prod 검증 통과"

# =============================================================================
# via-host 핵심 — 인프라(Docker) + worker/web(호스트 PM2)
# =============================================================================
HOST_LOG_DIR := $(MAKEFILE_DIR)/.host-logs
PM2_ECO      := $(MAKEFILE_DIR)/scripts/ecosystem.config.cjs
PM2_ENV      := WORKER_DIR='$(WORKER_DIR)' FRONTEND_DIR='$(FRONTEND_DIR)' HOST_LOG_DIR='$(HOST_LOG_DIR)'

host-deps-check: ## 의존성 사전 검증 (누락 시 bootstrap 자동)
	@need_bootstrap=0; \
	[ ! -x '$(WORKER_DIR)/.venv/bin/uvicorn' ] && need_bootstrap=1; \
	command -v pnpm >/dev/null 2>&1 || need_bootstrap=1; \
	command -v pm2 >/dev/null 2>&1 || need_bootstrap=1; \
	if [ $$need_bootstrap -eq 1 ]; then \
	  echo "⚠  의존성 누락 → make bootstrap 자동 실행"; \
	  $(MAKE) -s -C '$(MAKEFILE_DIR)' bootstrap || { \
	    echo "✗ bootstrap 실패. 수동 설치 필요"; exit 1; \
	  }; \
	fi
	@if [ ! -x '$(WORKER_DIR)/.venv/bin/uvicorn' ]; then \
	  echo "✗ bootstrap 후에도 uvicorn 없음"; exit 1; \
	fi
	@command -v pnpm >/dev/null 2>&1 || { echo "✗ pnpm 없음"; exit 1; }
	@command -v pm2 >/dev/null 2>&1 || { echo "✗ pm2 없음"; exit 1; }
	@if [ ! -d '$(FRONTEND_DIR)/node_modules' ]; then \
	  echo "⚠  $(FRONTEND_DIR)/node_modules 없음 — pnpm install"; \
	  cd '$(FRONTEND_DIR)' && (pnpm install --frozen-lockfile || pnpm install); \
	fi

# -----------------------------------------------------------------------------
# 핵심 3 모드 — via-host 기본
# -----------------------------------------------------------------------------
docker-local-via-host: dev-env-check host-deps-check ## local: Docker 없이 SQLite + 호스트 PM2 (가장 가벼움)
	@mkdir -p '$(HOST_LOG_DIR)'
	@echo "→ local 모드: SQLite (~/.wfp/wfp.db) + 호스트 PM2"
	@echo "  postgres/redis/minio/mailpit 미사용. SUPERVISOR_* 만 필요."
	@echo "→ $(GPU_MSG)"
	@echo "→ PM2 기동 (wfp-worker-local, wfp-web-local)"
	@$(PM2_ENV) $(PM2) start '$(PM2_ECO)' --only wfp-worker-local,wfp-web-local --update-env
	@$(PM2) save --force >/dev/null 2>&1 || true
	@sleep 2
	@$(MAKE) host-status
	@echo ""
	@echo "✓ local 기동 완료"
	@echo "  worker → http://localhost:8000 (DB: SQLite)"
	@echo "  web    → http://localhost:3000"
	@echo "  로그: make logs / 정지: make down"

docker-dev-via-host: docker-infra-start dev-env-check host-deps-check ## dev: 인프라(Docker) + worker/web (PM2, hot-reload)
	@mkdir -p '$(HOST_LOG_DIR)'
	@echo "→ $(GPU_MSG)"
	@echo "→ PM2 기동 (wfp-worker-dev, wfp-web-dev)"
	@$(PM2_ENV) $(PM2) start '$(PM2_ECO)' --only wfp-worker-dev,wfp-web-dev --update-env
	@$(PM2) save --force >/dev/null 2>&1 || true
	@sleep 2
	@$(MAKE) host-status
	@echo ""
	@echo "✓ dev 기동 완료"
	@echo "  worker → http://localhost:8000"
	@echo "  web    → http://localhost:3000"
	@echo "  postgres :5532  redis :6479  minio :9100/:9101  mailpit :1125/:8125"
	@echo "  로그: make logs / 정지: make down"

docker-prod-via-host: docker-infra-start env-check host-deps-check ## prod: 인프라(Docker) + worker/web (PM2, pnpm build 사전)
	@mkdir -p '$(HOST_LOG_DIR)'
	@echo "→ $(GPU_MSG)"
	@echo "→ web 프로덕션 빌드 ($(HOST_LOG_DIR)/web-build.log)"
	@cd '$(FRONTEND_DIR)' && pnpm build > '$(HOST_LOG_DIR)/web-build.log' 2>&1 || { \
	  echo "✗ pnpm build 실패. 최근 로그:"; tail -30 '$(HOST_LOG_DIR)/web-build.log'; exit 1; \
	}
	@echo "✓ web 빌드 성공"
	@echo "→ PM2 기동 (wfp-worker-prod, wfp-web-prod)"
	@$(PM2_ENV) $(PM2) start '$(PM2_ECO)' --only wfp-worker-prod,wfp-web-prod --update-env
	@$(PM2) save --force >/dev/null 2>&1 || true
	@sleep 2
	@$(MAKE) host-status
	@echo ""
	@echo "✓ prod 기동 완료"
	@echo "  worker → http://localhost:8000"
	@echo "  web    → http://localhost:3000"
	@echo "  로그: make logs / 정지: make down"

# -----------------------------------------------------------------------------
# 짧은 별칭 — via-host 기본이므로 dev/prod/local 만 입력
# -----------------------------------------------------------------------------
dev:   docker-dev-via-host    ## (별칭) docker-dev-via-host
prod:  docker-prod-via-host   ## (별칭) docker-prod-via-host
local: docker-local-via-host  ## (별칭) docker-local-via-host

# =============================================================================
# 운영 명령
# =============================================================================
host-down: ## PM2 daemon + 좀비 + 포트 8000/3000 강제 정지
	@'$(MAKEFILE_DIR)/scripts/host-down.sh'

host-restart: ## PM2 프로세스 재시작 (코드 + env 변경 반영)
	@if ! $(PM2) ping >/dev/null 2>&1; then \
	  echo "✗ PM2 daemon 미실행 — make dev / make prod / make local 먼저 실행"; \
	  exit 1; \
	fi
	@found=0; \
	for app in wfp-worker-dev wfp-worker-prod wfp-worker-local wfp-web-dev wfp-web-prod wfp-web-local; do \
	  if $(PM2) jlist 2>/dev/null | grep -q "\"name\":\"$$app\""; then \
	    $(PM2_ENV) $(PM2) restart $$app --update-env >/dev/null 2>&1 && \
	      echo "✓ $$app 재시작 (env reload)"; \
	    found=$$((found+1)); \
	  fi; \
	done; \
	if [ $$found -eq 0 ]; then echo "재시작할 PM2 앱 없음"; fi

host-logs: ## PM2 통합 로그 (worker + web)
	@bash -c '$(PM2) logs'

host-logs-worker: ## PM2 worker 로그
	@bash -c '$(PM2) logs wfp-worker-dev wfp-worker-prod wfp-worker-local'

host-logs-web: ## PM2 web 로그
	@bash -c '$(PM2) logs wfp-web-dev wfp-web-prod wfp-web-local'

host-status: ## PM2 프로세스 상태
	@bash -c '$(PM2) list'

host-monit: ## PM2 실시간 모니터
	@bash -c '$(PM2) monit'

# -----------------------------------------------------------------------------
# 짧은 별칭
# -----------------------------------------------------------------------------
down: ## (별칭) host-down + 인프라 정지
	@$(MAKE) -s host-down
	@cd docker && docker compose -f compose.infra.yaml down 2>/dev/null || true
	@echo "✓ 전체 정지 완료 (볼륨 보존)"

restart:     host-restart       ## (별칭) host-restart
logs:        host-logs           ## (별칭) host-logs
logs-worker: host-logs-worker    ## (별칭) host-logs-worker
logs-web:    host-logs-web       ## (별칭) host-logs-web
status:      host-status         ## (별칭) host-status
monit:       host-monit          ## (별칭) host-monit

# =============================================================================
# 진단 / 정리
# =============================================================================
info: ## 감지된 환경 출력 (경로 + GPU)
	@echo "MAKEFILE_DIR  = $(MAKEFILE_DIR)"
	@echo "WORKER_DIR    = $(WORKER_DIR)"
	@echo "FRONTEND_DIR  = $(FRONTEND_DIR)"
	@echo "HAS_GPU       = $(HAS_GPU)"
	@echo "$(GPU_MSG)"

clean: ## 빌드 산출물 정리
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find '$(FRONTEND_DIR)' -type d -name ".next" -prune -exec rm -rf {} + 2>/dev/null || true
	@echo "✓ clean 완료"

docker-clean: ## 인프라 정지 + 볼륨 삭제 (주의 — 데이터 손실)
	@echo "⚠  인프라 볼륨 삭제 — postgres/redis/minio 데이터 손실"
	@$(MAKE) -s host-down 2>/dev/null || true
	@cd docker && docker compose -f compose.infra.yaml down -v 2>/dev/null || true
	@echo "✓ 인프라 + 볼륨 삭제 완료"
