# =============================================================================
# Wise Fine-tuning Pipeline — 루트 Makefile
# 모든 컴포넌트를 단일 명령으로 관리.
# =============================================================================

SHELL := /bin/bash
.PHONY: help bootstrap dev test lint build clean env-check \
        docker-dev docker-dev-cpu docker-dev-gpu \
        docker-prod docker-prod-cpu docker-prod-gpu \
        docker-prod-tls docker-prod-tls-gpu \
        docker-dev-via-host docker-prod-via-host \
        host-down host-logs host-logs-worker host-logs-web host-status \
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
bootstrap: ## 전체 의존성 설치 (uv + pnpm)
	@echo "→ Finetuning-Pipeline-worker (Python 3.12 + uv)"
	cd '$(WORKER_DIR)' && uv venv .venv --python 3.12 && \
	  uv pip install -e ".[dev]" --python .venv/bin/python
	@echo "→ Finetuning-Pipeline-frontend (Node 20 + pnpm)"
	cd '$(FRONTEND_DIR)' && pnpm install
	@echo "✓ bootstrap complete"
	@$(MAKE) env-status

env-status: ## 호스트 환경 진단 (OS·GPU 자동 감지 + 누락 패키지 표시)
	cd '$(WORKER_DIR)' && .venv/bin/python -m wfp_worker.env_check

install-deps: ## 호스트 환경 자동 감지 후 학습 패키지 자동 설치
	cd '$(WORKER_DIR)' && WFP_PROJECT_DIR=$$(pwd) .venv/bin/python -m wfp_worker.env_check --install

# -----------------------------------------------------------------------------
# 로컬 개발 (Docker 없이)
# -----------------------------------------------------------------------------
dev-worker: ## Finetuning-Pipeline-worker dev 서버 (.env 자동 로드)
	cd '$(WORKER_DIR)' && bash -c 'set -a; [ -f .env ] && source .env; set +a; .venv/bin/uvicorn wfp_worker.server:app --port 8000 --reload'

dev-web: ## Finetuning-Pipeline-frontend dev 서버
	cd '$(FRONTEND_DIR)' && pnpm dev

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

docker-infra: ## 인프라만 기동 (postgres/redis/minio/mailhog) — worker/web은 호스트 직접 실행
	cd docker && docker compose -f compose.infra.yaml up -d
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
# 하이브리드 모드 — 인프라(Docker) + worker/web(호스트 직접)
# Apple Silicon MPS, 호스트 GPU 직접 접근, 빠른 재시작 등 활용
# -----------------------------------------------------------------------------
HOST_PID_DIR := $(MAKEFILE_DIR)/.host-pids
HOST_LOG_DIR := $(MAKEFILE_DIR)/.host-logs

docker-dev-via-host: docker-infra ## 인프라(Docker) + worker/web(호스트 dev 모드) 백그라운드 기동
	@mkdir -p $(HOST_PID_DIR) $(HOST_LOG_DIR)
	@echo "→ 호스트 워커 기동 (uvicorn --reload, 로그: $(HOST_LOG_DIR)/worker.log)"
	@cd '$(WORKER_DIR)' && bash -c 'set -a; [ -f .env ] && source .env; set +a; \
	  nohup .venv/bin/uvicorn wfp_worker.server:app --host 0.0.0.0 --port 8000 --reload \
	  > $(HOST_LOG_DIR)/worker.log 2>&1 & echo $$! > $(HOST_PID_DIR)/worker.pid'
	@echo "→ 호스트 웹 기동 (pnpm dev, 로그: $(HOST_LOG_DIR)/web.log)"
	@cd '$(FRONTEND_DIR)' && bash -c 'nohup pnpm dev \
	  > $(HOST_LOG_DIR)/web.log 2>&1 & echo $$! > $(HOST_PID_DIR)/web.pid'
	@sleep 1
	@echo ""
	@echo "✓ 하이브리드 dev 기동 완료"
	@echo "  worker PID: $$(cat $(HOST_PID_DIR)/worker.pid) — http://localhost:8000"
	@echo "  web    PID: $$(cat $(HOST_PID_DIR)/web.pid)    — http://localhost:3000"
	@echo "  로그: make host-logs"
	@echo "  정지: make host-down"

docker-prod-via-host: docker-infra env-check ## 인프라(Docker) + worker/web(호스트 prod 모드) 백그라운드 기동
	@mkdir -p $(HOST_PID_DIR) $(HOST_LOG_DIR)
	@echo "→ 호스트 워커 기동 (uvicorn workers=2, 로그: $(HOST_LOG_DIR)/worker.log)"
	@cd '$(WORKER_DIR)' && bash -c 'set -a; [ -f .env ] && source .env; set +a; \
	  nohup .venv/bin/uvicorn wfp_worker.server:app --host 0.0.0.0 --port 8000 --workers 2 \
	  > $(HOST_LOG_DIR)/worker.log 2>&1 & echo $$! > $(HOST_PID_DIR)/worker.pid'
	@echo "→ 호스트 웹 빌드 + 기동 (pnpm build → pnpm start, 로그: $(HOST_LOG_DIR)/web.log)"
	@cd '$(FRONTEND_DIR)' && pnpm build > $(HOST_LOG_DIR)/web-build.log 2>&1
	@cd '$(FRONTEND_DIR)' && bash -c 'nohup pnpm start \
	  > $(HOST_LOG_DIR)/web.log 2>&1 & echo $$! > $(HOST_PID_DIR)/web.pid'
	@sleep 2
	@echo ""
	@echo "✓ 하이브리드 prod 기동 완료"
	@echo "  worker PID: $$(cat $(HOST_PID_DIR)/worker.pid) — http://localhost:8000"
	@echo "  web    PID: $$(cat $(HOST_PID_DIR)/web.pid)    — http://localhost:3000"
	@echo "  로그: make host-logs"
	@echo "  정지: make host-down"

host-down: ## 호스트에서 띄운 worker/web 정지 (PID 파일 기반)
	@if [ -d $(HOST_PID_DIR) ]; then \
	  for f in $(HOST_PID_DIR)/*.pid; do \
	    if [ -f "$$f" ]; then \
	      name=$$(basename $$f .pid); pid=$$(cat $$f); \
	      if kill -0 $$pid 2>/dev/null; then \
	        kill $$pid && echo "✓ $$name 종료 (PID $$pid)"; \
	      else \
	        echo "- $$name PID $$pid 이미 종료됨"; \
	      fi; \
	      rm $$f; \
	    fi; \
	  done; \
	else \
	  echo "PID 디렉토리 없음 (호스트 프로세스 미기동)"; \
	fi

host-logs: ## 호스트 worker + web 로그 동시 추적
	@if [ ! -d $(HOST_LOG_DIR) ]; then echo "로그 디렉토리 없음"; exit 1; fi
	tail -f $(HOST_LOG_DIR)/worker.log $(HOST_LOG_DIR)/web.log

host-logs-worker: ## 호스트 worker 로그만
	tail -f $(HOST_LOG_DIR)/worker.log

host-logs-web: ## 호스트 web 로그만
	tail -f $(HOST_LOG_DIR)/web.log

host-status: ## 호스트 worker/web 프로세스 상태
	@if [ ! -d $(HOST_PID_DIR) ]; then echo "PID 디렉토리 없음"; exit 0; fi
	@for f in $(HOST_PID_DIR)/*.pid; do \
	  if [ -f "$$f" ]; then \
	    name=$$(basename $$f .pid); pid=$$(cat $$f); \
	    if kill -0 $$pid 2>/dev/null; then \
	      echo "✓ $$name PID $$pid (running)"; \
	    else \
	      echo "✗ $$name PID $$pid (dead)"; \
	    fi; \
	  fi; \
	done

docker-down: ## 컨테이너 정지 (볼륨 유지) — dev/prod 모두 정지
	cd docker && $(DC_ENV) docker compose $(DEV_FILES) down 2>/dev/null || true
	cd docker && $(DC_ENV) docker compose $(PROD_FILES) down 2>/dev/null || true

docker-infra-down: ## 인프라 컨테이너 정지
	cd docker && docker compose -f compose.infra.yaml down

docker-clean: ## 컨테이너 + 볼륨 삭제 (주의 — 데이터 손실)
	cd docker && $(DC_ENV) docker compose $(DEV_FILES) down -v

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
