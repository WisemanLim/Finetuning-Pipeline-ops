# =============================================================================
# Wise Fine-tuning Pipeline — 루트 Makefile
# 모든 컴포넌트를 단일 명령으로 관리.
# =============================================================================

SHELL := /bin/bash
.PHONY: help bootstrap dev test lint build clean docker-dev docker-prod docker-down docker-logs

# 프로젝트 루트 경로 (각 컴포넌트 독립 디렉토리)
WORKER_DIR   := /Users/wise/Developer/DA(Python,R,...)/Finetuning-Pipeline-worker
FRONTEND_DIR := /Users/wise/Developer/Web(Node,Script)/Finetuning-Pipeline-frontend

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
docker-dev: ## 개발 스택 기동 (백그라운드) — worker/web 포함
	cd docker && docker compose -f compose.dev.yaml up -d --build

docker-infra: ## 인프라만 기동 (postgres/redis/minio/mailhog) — worker/web은 호스트 직접 실행
	cd docker && docker compose -f compose.infra.yaml up -d
	@echo "→ 인프라 기동 완료. 별도 터미널에서:"
	@echo "  make dev-worker   (Apple Silicon MPS / 호스트 GPU 직접 사용)"
	@echo "  make dev-web"

docker-prod: ## 운영 스택 기동
	cd docker && docker compose -f compose.prod.yaml up -d --build

docker-down: ## 컨테이너 정지 (볼륨 유지)
	cd docker && docker compose -f compose.dev.yaml down

docker-infra-down: ## 인프라 컨테이너 정지
	cd docker && docker compose -f compose.infra.yaml down

docker-clean: ## 컨테이너 + 볼륨 삭제 (주의 — 데이터 손실)
	cd docker && docker compose -f compose.dev.yaml down -v

docker-logs: ## 워커 로그 추적
	cd docker && docker compose -f compose.dev.yaml logs -f worker

docker-ps: ## 컨테이너 상태
	cd docker && docker compose -f compose.dev.yaml ps

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
