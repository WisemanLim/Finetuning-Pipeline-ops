# =============================================================================
# Wise Fine-tuning Pipeline — 루트 Makefile
# 모든 컴포넌트를 단일 명령으로 관리.
# =============================================================================

SHELL := /bin/bash

# ~/.local/bin을 모든 recipe의 PATH에 추가 (uv/pnpm/pm2 user-local 설치 경로)
export PATH := $(HOME)/.local/bin:$(PATH)
.PHONY: help bootstrap dev test lint build clean env-check \
        dev-worker dev-web prod-worker prod-web \
        docker-dev docker-dev-cpu docker-dev-gpu \
        docker-prod docker-prod-cpu docker-prod-gpu \
        docker-prod-tls docker-prod-tls-gpu \
        docker-infra-start docker-dev-via-host docker-prod-via-host \
        host-deps-check host-down host-restart host-logs host-logs-worker host-logs-web host-status host-monit \
        docker-down docker-logs traefik-diag

# -----------------------------------------------------------------------------
# 컴포넌트 디렉토리 자동 감지
# 우선순위:
#   1) 환경 변수로 override   (export WORKER_DIR=...)
#   2) Makefile과 같은 부모의 시블링 (서버 배포: ops/worker/frontend 형제 구조)
#   3) macOS 워크스페이스 절대경로 (개발 환경 fallback)
# -----------------------------------------------------------------------------
MAKEFILE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

WORKER_DIR ?= $(abspath $(strip $(if $(wildcard $(MAKEFILE_DIR)/../Finetuning-Pipeline-worker),$(MAKEFILE_DIR)/../Finetuning-Pipeline-worker,/Users/wise/Developer/DA(Python,R,...)/Finetuning-Pipeline-worker)))

FRONTEND_DIR ?= $(abspath $(strip $(if $(wildcard $(MAKEFILE_DIR)/../Finetuning-Pipeline-frontend),$(MAKEFILE_DIR)/../Finetuning-Pipeline-frontend,/Users/wise/Developer/Web(Node,Script)/Finetuning-Pipeline-frontend)))

# -----------------------------------------------------------------------------
# GPU 자동 감지 — nvidia-smi 존재 + GPU 인식 시 GPU 모드
# -----------------------------------------------------------------------------
HAS_GPU := $(shell command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L 2>/dev/null | grep -q '^GPU' && echo 1 || echo 0)

ifeq ($(HAS_GPU),1)
DEV_FILES    := -f compose.dev.yaml -f compose.dev.gpu.yaml
PROD_FILES   := -f compose.prod.yaml -f compose.prod.gpu.yaml
GPU_MSG      := GPU 감지됨 → GPU 모드 (Dockerfile.gpu + nvidia 런타임)
else
DEV_FILES    := -f compose.dev.yaml
PROD_FILES   := -f compose.prod.yaml
GPU_MSG      := GPU 미감지 → CPU 모드 (Dockerfile)
endif

# docker compose에 빌드 컨텍스트 절대경로 주입 (workspace/server 경로 차이 흡수)
DC_ENV := WFP_WORKER_DIR='$(WORKER_DIR)' WFP_FRONTEND_DIR='$(FRONTEND_DIR)'

# 기본 — help
.DEFAULT_GOAL := help

help: ## 명령 목록
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------
bootstrap: ## 전체 의존성 설치 (uv + pnpm@10 + pm2, user-local — sudo 불필요)
	@# Node/npm 존재 확인 + Node 버전 감지
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
	@# 사용자 로컬 prefix 디렉토리 (sudo 회피)
	@mkdir -p "$$HOME/.local/bin"
	@# uv 설치 → ~/.local/bin/uv
	@if [ ! -x "$$HOME/.local/bin/uv" ]; then \
	  echo "→ uv 자동 설치 → ~/.local/bin/uv"; \
	  curl -LsSf https://astral.sh/uv/install.sh | sh; \
	fi
	@# Node 버전에 맞는 pnpm 결정 (>=22.13: v11, 그 이하: v10)
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
	@# pm2 → ~/.local
	@if [ ! -x "$$HOME/.local/bin/pm2" ]; then \
	  echo "→ pm2 설치 → ~/.local"; \
	  npm install -g --prefix="$$HOME/.local" pm2 || \
	    { echo "✗ pm2 설치 실패"; exit 1; }; \
	fi
	@# PATH 안내 (Makefile 내부는 PATH 자동 추가, 셸은 사용자가 설정 필요)
	@if ! echo "$$PATH" | grep -q "$$HOME/.local/bin"; then \
	  echo ""; \
	  echo "⚠  ~/.local/bin이 셸 PATH에 없음. 영구 추가 권장:"; \
	  echo "   echo 'export PATH=\"\$$HOME/.local/bin:\$$PATH\"' >> ~/.bashrc"; \
	  echo "   source ~/.bashrc"; \
	  echo ""; \
	fi
	@echo "→ Finetuning-Pipeline-worker (Python 3.12 + uv)"
	@cd '$(WORKER_DIR)' && "$$HOME/.local/bin/uv" venv .venv --python 3.12 && \
	  "$$HOME/.local/bin/uv" pip install -e ".[dev]" --python .venv/bin/python
	@echo "→ Finetuning-Pipeline-frontend (Node 20 + pnpm)"
	@cd '$(FRONTEND_DIR)' && "$$HOME/.local/bin/pnpm" install
	@echo "✓ bootstrap complete"
	@$(MAKE) env-status

env-status: ## 호스트 환경 진단 (OS·GPU 자동 감지 + 누락 패키지 표시)
	cd '$(WORKER_DIR)' && .venv/bin/python -m wfp_worker.env_check

install-deps: ## 호스트 환경 자동 감지 후 학습 패키지 자동 설치
	cd '$(WORKER_DIR)' && WFP_PROJECT_DIR=$$(pwd) .venv/bin/python -m wfp_worker.env_check --install

# -----------------------------------------------------------------------------
# 로컬 호스트 실행 (Docker 없이) — dev/prod 공통 변수로 단일화
# -----------------------------------------------------------------------------
# 워커 uvicorn 옵션 — dev=핫리로드, prod=worker 2개
WORKER_UVICORN_DEV  := .venv/bin/uvicorn wfp_worker.server:app --host 0.0.0.0 --port 8000 --reload
WORKER_UVICORN_PROD := .venv/bin/uvicorn wfp_worker.server:app --host 0.0.0.0 --port 8000 --workers 2

dev-worker: ## Finetuning-Pipeline-worker dev 서버 (uvicorn --reload, .env 자동 로드, foreground)
	cd '$(WORKER_DIR)' && bash -c 'set -a; [ -f .env ] && source .env; set +a; exec $(WORKER_UVICORN_DEV)'

prod-worker: ## Finetuning-Pipeline-worker prod 서버 (uvicorn workers=2, .env 자동 로드, foreground)
	cd '$(WORKER_DIR)' && bash -c 'set -a; [ -f .env ] && source .env; set +a; exec $(WORKER_UVICORN_PROD)'

dev-web: ## Finetuning-Pipeline-frontend dev 서버 (pnpm dev, foreground)
	cd '$(FRONTEND_DIR)' && pnpm dev

prod-web: ## Finetuning-Pipeline-frontend prod 서버 (pnpm build → pnpm start, foreground)
	cd '$(FRONTEND_DIR)' && pnpm build && exec pnpm start

# -----------------------------------------------------------------------------
# 테스트 / lint
# -----------------------------------------------------------------------------
test: ## Finetuning-Pipeline-worker pytest 전체
	cd '$(WORKER_DIR)' && .venv/bin/python -m pytest tests/ -v

env-status-json: ## 환경 진단 JSON 출력 (CI/스크립트용)
	@cd '$(WORKER_DIR)' && .venv/bin/python -m wfp_worker.env_check --json

test-cov: ## 커버리지 포함 테스트
	cd '$(WORKER_DIR)' && .venv/bin/python -m pytest tests/ --cov=wfp_worker --cov-report=term-missing

lint: ## ruff + eslint
	cd '$(WORKER_DIR)' && .venv/bin/ruff check src/ tests/
	cd '$(FRONTEND_DIR)' && pnpm lint

typecheck: ## mypy + tsc
	cd '$(WORKER_DIR)' && .venv/bin/mypy src/
	cd '$(FRONTEND_DIR)' && pnpm typecheck

# -----------------------------------------------------------------------------
# 빌드
# -----------------------------------------------------------------------------
build-worker: ## Finetuning-Pipeline-worker Docker 이미지 (CPU)
	docker build -t wfp-worker:latest '$(WORKER_DIR)'

build-worker-gpu: ## Finetuning-Pipeline-worker Docker 이미지 (GPU)
	docker build -f '$(WORKER_DIR)/Dockerfile.gpu' -t wfp-worker:gpu '$(WORKER_DIR)'

build-web: ## Finetuning-Pipeline-frontend Docker 이미지
	docker build -t wfp-frontend:latest '$(FRONTEND_DIR)'

build: build-worker build-web ## 전체 이미지 빌드

# -----------------------------------------------------------------------------
# Docker Compose
# -----------------------------------------------------------------------------
env-check: ## docker/.env 존재 + 필수 키 검증
	@if [ ! -f docker/.env ]; then \
	  if [ -f docker/.env.example ]; then \
	    echo "⚠  docker/.env 없음 → docker/.env.example 복사"; \
	    cp docker/.env.example docker/.env; \
	    echo "✗ 빌드 중단. docker/.env 열어 placeholder 값을 실제 값으로 교체 후 재실행."; \
	    echo "  주요 키: SUPERVISOR_*, POSTGRES_PASSWORD, REDIS_PASSWORD, MINIO_ROOT_*, NEXTAUTH_SECRET, HF_TOKEN"; \
	    exit 1; \
	  else \
	    echo "✗ docker/.env 와 docker/.env.example 모두 없음"; exit 1; \
	  fi; \
	fi
	@missing=""; \
	for k in SUPERVISOR_ID SUPERVISOR_PASSWORD POSTGRES_PASSWORD REDIS_PASSWORD MINIO_ROOT_USER MINIO_ROOT_PASSWORD NEXTAUTH_SECRET HF_TOKEN; do \
	  if ! grep -q "^$$k=" docker/.env || grep -qE "^$$k=$$" docker/.env; then \
	    missing="$$missing $$k"; \
	  fi; \
	done; \
	if [ -n "$$missing" ]; then \
	  echo "✗ docker/.env 누락/빈 키:$$missing"; exit 1; \
	fi
	@echo "✓ docker/.env 검증 통과"

docker-dev: env-check ## 개발 스택 기동 (GPU 자동 감지)
	@echo "→ $(GPU_MSG)"
	cd docker && $(DC_ENV) docker compose $(DEV_FILES) up -d --build

docker-dev-cpu: env-check ## 개발 스택 기동 (CPU 강제)
	cd docker && $(DC_ENV) docker compose -f compose.dev.yaml up -d --build

docker-dev-gpu: env-check ## 개발 스택 기동 (GPU 강제 — nvidia 런타임 필요)
	cd docker && $(DC_ENV) docker compose -f compose.dev.yaml -f compose.dev.gpu.yaml up -d --build

docker-infra-start:
	@cd docker && docker compose -f compose.infra.yaml up -d

docker-infra: docker-infra-start ## 인프라만 기동 (postgres/redis/minio/mailhog) — worker/web은 호스트 직접 실행
	@echo "→ 인프라 기동 완료. 별도 터미널에서:"
	@echo "  make dev-worker   (Apple Silicon MPS / 호스트 GPU 직접 사용)"
	@echo "  make dev-web"

docker-prod: env-check ## 운영 스택 기동 (GPU 자동 감지)
	@echo "→ $(GPU_MSG)"
	cd docker && $(DC_ENV) docker compose $(PROD_FILES) up -d --build

docker-prod-cpu: env-check ## 운영 스택 기동 (CPU 강제)
	cd docker && $(DC_ENV) docker compose -f compose.prod.yaml up -d --build

docker-prod-gpu: env-check ## 운영 스택 기동 (GPU 강제 — nvidia 런타임 필요)
	cd docker && $(DC_ENV) docker compose -f compose.prod.yaml -f compose.prod.gpu.yaml up -d --build

docker-prod-tls: env-check ## 운영 스택 기동 + TLS (DOMAIN/ACME_EMAIL 필요)
	cd docker && $(DC_ENV) docker compose -f compose.prod.yaml -f compose.prod.tls.yaml up -d --build

docker-prod-tls-gpu: env-check ## 운영 스택 기동 + TLS + GPU
	cd docker && $(DC_ENV) docker compose -f compose.prod.yaml -f compose.prod.gpu.yaml -f compose.prod.tls.yaml up -d --build

# -----------------------------------------------------------------------------
# 하이브리드 모드 — 인프라(Docker) + worker/web(호스트 PM2 관리)
# PM2가 nohup 대체 — 자동 재시작, 중앙 로그, 상태 모니터링 제공
# -----------------------------------------------------------------------------
HOST_LOG_DIR := $(MAKEFILE_DIR)/.host-logs
PM2_ECO      := $(MAKEFILE_DIR)/scripts/ecosystem.config.cjs
PM2_ENV      := WORKER_DIR='$(WORKER_DIR)' FRONTEND_DIR='$(FRONTEND_DIR)' HOST_LOG_DIR='$(HOST_LOG_DIR)'

# 사전 검증 — 누락 감지 시 bootstrap 자동 호출 (idempotent)
host-deps-check:
	@need_bootstrap=0; \
	[ ! -x '$(WORKER_DIR)/.venv/bin/uvicorn' ] && need_bootstrap=1; \
	command -v pnpm >/dev/null 2>&1 || need_bootstrap=1; \
	command -v pm2 >/dev/null 2>&1 || need_bootstrap=1; \
	if [ $$need_bootstrap -eq 1 ]; then \
	  echo "⚠  의존성 누락 감지 → make bootstrap 자동 실행"; \
	  $(MAKE) -s -C '$(MAKEFILE_DIR)' bootstrap || { \
	    echo ""; \
	    echo "✗ bootstrap 실패. 수동 확인 필요:"; \
	    echo "  - uv:   ~/.local/bin/uv 또는 PATH에 uv (curl -LsSf https://astral.sh/uv/install.sh | sh)"; \
	    echo "  - pnpm: corepack enable && corepack prepare pnpm@11 --activate"; \
	    echo "  - pm2:  npm i -g pm2"; \
	    exit 1; \
	  }; \
	fi
	@# 재검증 (bootstrap 후에도 누락이면 명시적 실패)
	@if [ ! -x '$(WORKER_DIR)/.venv/bin/uvicorn' ]; then \
	  echo "✗ bootstrap 후에도 $(WORKER_DIR)/.venv/bin/uvicorn 없음"; \
	  echo "  uv 설치 후 새 셸 열거나 'source ~/.bashrc'/'source ~/.zshrc' 후 재시도"; \
	  exit 1; \
	fi
	@command -v pnpm >/dev/null 2>&1 || { echo "✗ bootstrap 후에도 pnpm 없음"; exit 1; }
	@command -v pm2 >/dev/null 2>&1 || { echo "✗ bootstrap 후에도 pm2 없음"; exit 1; }
	@if [ ! -d '$(FRONTEND_DIR)/node_modules' ]; then \
	  echo "⚠  $(FRONTEND_DIR)/node_modules 없음 — pnpm install 자동 실행"; \
	  cd '$(FRONTEND_DIR)' && (pnpm install --frozen-lockfile || pnpm install); \
	fi

docker-dev-via-host: docker-infra-start host-deps-check ## 인프라(Docker) + dev-worker/dev-web (PM2 관리)
	@mkdir -p $(HOST_LOG_DIR)
	@echo "→ PM2로 worker/web 기동 (ecosystem: scripts/ecosystem.config.cjs)"
	@$(PM2_ENV) pm2 start '$(PM2_ECO)' --only wfp-worker-dev,wfp-web-dev --update-env
	@pm2 save --force >/dev/null 2>&1 || true
	@sleep 2
	@$(MAKE) host-status
	@echo ""
	@echo "✓ 하이브리드 dev 기동 완료"
	@echo "  worker → http://localhost:8000"
	@echo "  web    → http://localhost:3000"
	@echo "  로그: make host-logs / 정지: make host-down"

docker-prod-via-host: docker-infra-start env-check host-deps-check ## 인프라(Docker) + prod-worker/prod-web (PM2 관리, pnpm build 사전)
	@mkdir -p $(HOST_LOG_DIR)
	@echo "→ web 프로덕션 빌드 (pnpm build, 로그: $(HOST_LOG_DIR)/web-build.log)"
	@cd '$(FRONTEND_DIR)' && pnpm build > $(HOST_LOG_DIR)/web-build.log 2>&1 || { \
	  echo "✗ pnpm build 실패. 최근 로그:"; tail -30 $(HOST_LOG_DIR)/web-build.log; exit 1; \
	}
	@echo "✓ web 빌드 성공"
	@echo "→ PM2로 worker/web 기동 (ecosystem: scripts/ecosystem.config.cjs)"
	@$(PM2_ENV) pm2 start '$(PM2_ECO)' --only wfp-worker-prod,wfp-web-prod --update-env
	@pm2 save --force >/dev/null 2>&1 || true
	@sleep 2
	@$(MAKE) host-status
	@echo ""
	@echo "✓ 하이브리드 prod 기동 완료"
	@echo "  worker → http://localhost:8000"
	@echo "  web    → http://localhost:3000"
	@echo "  로그: make host-logs / 정지: make host-down"

host-down: ## PM2 daemon + 좀비 프로세스 + 포트 점유 모두 강제 정지
	@echo "→ PM2 앱 삭제 + daemon kill (자동 재시작 차단)"
	@pm2 delete all 2>/dev/null || true
	@pm2 save --force >/dev/null 2>&1 || true
	@pm2 kill 2>/dev/null || true
	@echo "→ 잔여 프로세스 정리 (uvicorn / next-server / pnpm)"
	@pkill -TERM -f "uvicorn wfp_worker.server" 2>/dev/null || true
	@pkill -TERM -f "next-server" 2>/dev/null || true
	@pkill -TERM -f "pnpm.*\(dev\|start\)" 2>/dev/null || true
	@pkill -TERM -f "node.*next/dist/bin/next" 2>/dev/null || true
	@pkill -TERM -f "PM2" 2>/dev/null || true
	@sleep 1
	@# 8000 (worker) / 3000 (web) 포트 점유 프로세스 강제 종료
	@for port in 8000 3000; do \
	  pids=$$(lsof -ti :$$port 2>/dev/null); \
	  if [ -n "$$pids" ]; then \
	    echo "  포트 $$port 점유 PID $$pids → SIGTERM"; \
	    kill $$pids 2>/dev/null || true; \
	    sleep 1; \
	    pids2=$$(lsof -ti :$$port 2>/dev/null); \
	    if [ -n "$$pids2" ]; then \
	      echo "  포트 $$port 잔여 PID $$pids2 → SIGKILL"; \
	      kill -9 $$pids2 2>/dev/null || true; \
	    fi; \
	  fi; \
	done
	@# 잔여 multiprocessing 자식 (uvicorn workers=2가 fork한 spawn_main 등)
	@pkill -9 -f "multiprocessing.spawn" 2>/dev/null || true
	@pkill -9 -f "multiprocessing.resource_tracker" 2>/dev/null || true
	@echo "✓ 호스트 프로세스 + PM2 daemon 정리 완료"

host-restart: ## PM2 프로세스 재시작 (코드 변경 반영)
	@pm2 restart wfp-worker-dev wfp-worker-prod wfp-web-dev wfp-web-prod 2>/dev/null || \
	  echo "재시작할 프로세스 없음"

host-logs: ## PM2 통합 로그 (worker + web)
	pm2 logs

host-logs-worker: ## PM2 worker 로그만
	pm2 logs wfp-worker-dev wfp-worker-prod

host-logs-web: ## PM2 web 로그만
	pm2 logs wfp-web-dev wfp-web-prod

host-status: ## PM2 프로세스 상태 (테이블 형식)
	@pm2 list

host-monit: ## PM2 실시간 모니터 (CPU/메모리/로그)
	pm2 monit

docker-down: ## 모든 모드 정지 — PM2 + 좀비 프로세스 + dev/prod/infra compose (볼륨 유지)
	@$(MAKE) -s host-down
	@echo "→ docker compose dev/prod/infra 정지"
	@cd docker && $(DC_ENV) docker compose -f compose.dev.yaml -f compose.dev.gpu.yaml down 2>/dev/null || true
	@cd docker && $(DC_ENV) docker compose -f compose.dev.yaml down 2>/dev/null || true
	@cd docker && $(DC_ENV) docker compose -f compose.prod.yaml -f compose.prod.gpu.yaml -f compose.prod.tls.yaml down 2>/dev/null || true
	@cd docker && $(DC_ENV) docker compose -f compose.prod.yaml -f compose.prod.gpu.yaml down 2>/dev/null || true
	@cd docker && $(DC_ENV) docker compose -f compose.prod.yaml -f compose.prod.tls.yaml down 2>/dev/null || true
	@cd docker && $(DC_ENV) docker compose -f compose.prod.yaml down 2>/dev/null || true
	@cd docker && docker compose -f compose.infra.yaml down 2>/dev/null || true
	@echo "✓ 전체 정지 완료 (볼륨/이미지 보존)"

docker-infra-down: ## 인프라 컨테이너만 정지
	cd docker && docker compose -f compose.infra.yaml down

docker-clean: ## 전체 정지 + 볼륨 삭제 (주의 — 데이터 손실)
	@echo "⚠  볼륨 삭제 진행 — 데이터 손실 발생"
	@$(MAKE) host-down 2>/dev/null || true
	@cd docker && $(DC_ENV) docker compose -f compose.dev.yaml -f compose.dev.gpu.yaml down -v 2>/dev/null || true
	@cd docker && $(DC_ENV) docker compose -f compose.dev.yaml down -v 2>/dev/null || true
	@cd docker && $(DC_ENV) docker compose -f compose.prod.yaml -f compose.prod.gpu.yaml -f compose.prod.tls.yaml down -v 2>/dev/null || true
	@cd docker && $(DC_ENV) docker compose -f compose.prod.yaml down -v 2>/dev/null || true
	@cd docker && docker compose -f compose.infra.yaml down -v 2>/dev/null || true
	@echo "✓ 전체 정지 + 볼륨 삭제 완료"

docker-logs: ## 워커 로그 추적
	cd docker && $(DC_ENV) docker compose $(DEV_FILES) logs -f worker

docker-ps: ## 컨테이너 상태
	cd docker && $(DC_ENV) docker compose $(DEV_FILES) ps

traefik-diag: ## Traefik 라우터/서비스 진단 (404 / 라우팅 문제 디버그)
	@echo "── Traefik 컨테이너 ──"; \
	docker ps --filter name=wfp-traefik --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
	@echo ""
	@echo "── Traefik 로그 (최근 50줄) ──"; \
	docker logs --tail 50 wfp-traefik 2>&1 || echo "(traefik 컨테이너 미기동)"
	@echo ""
	@echo "── web 컨테이너 라벨 ──"; \
	docker inspect wfp-prod-web-1 --format '{{range $$k, $$v := .Config.Labels}}{{if (or (eq (slice $$k 0 7) "traefik") false)}}{{$$k}}={{$$v}}\n{{end}}{{end}}' 2>/dev/null || \
	docker inspect wfp-dev-web-1 --format '{{range $$k, $$v := .Config.Labels}}{{if (or (eq (slice $$k 0 7) "traefik") false)}}{{$$k}}={{$$v}}\n{{end}}{{end}}' 2>/dev/null || \
	echo "(web 컨테이너 미발견)"
	@echo ""
	@echo "── Traefik 네트워크 검증 ──"; \
	docker inspect wfp-traefik --format 'Networks: {{range $$k, $$v := .NetworkSettings.Networks}}{{$$k}} {{end}}' 2>/dev/null
	@echo ""
	@echo "── API 활성화 시 라우터 목록 (TRAEFIK_API=true 재기동 필요) ──"; \
	curl -sf http://127.0.0.1:8090/api/http/routers 2>/dev/null | head -100 || \
	echo "API 비활성. 재기동: TRAEFIK_API=true make docker-prod"
	@echo ""
	@echo "── HTTP 80 응답 테스트 ──"; \
	curl -sI http://localhost/ 2>&1 | head -5

docker-info: ## 현재 감지된 환경 확인 (경로 + GPU)
	@echo "MAKEFILE_DIR  = $(MAKEFILE_DIR)"
	@echo "WORKER_DIR    = $(WORKER_DIR)"
	@echo "FRONTEND_DIR  = $(FRONTEND_DIR)"
	@echo "HAS_GPU       = $(HAS_GPU)"
	@echo "$(GPU_MSG)"
	@echo "DEV_FILES     = $(DEV_FILES)"
	@echo "PROD_FILES    = $(PROD_FILES)"

# -----------------------------------------------------------------------------
# 문서 / 정리
# -----------------------------------------------------------------------------
pdf: ## PRD를 PDF로 변환
	cd .doc && pandoc PRD.md -o PRD.pdf \
	  --pdf-engine=xelatex \
	  -V mainfont="Noto Sans CJK KR" \
	  -V monofont="Noto Sans Mono CJK KR" \
	  -V geometry:margin=20mm

architecture: ## architecture.mmd → png + svg
	cd .doc && mmdc -i architecture.mmd -o architecture.png -b transparent -w 2400 -H 1800
	cd .doc && mmdc -i architecture.mmd -o architecture.svg -b transparent

clean: ## 빌드 산출물 정리
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".next" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "node_modules" -prune -exec rm -rf {} + 2>/dev/null || true

# -----------------------------------------------------------------------------
# 통합
# -----------------------------------------------------------------------------
ci: lint typecheck test ## CI 파이프라인 (lint + typecheck + test)
