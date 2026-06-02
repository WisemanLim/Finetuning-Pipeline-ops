# Ops 재설계 이식 리포트 — Eden → 워크스페이스

## 1. 비교 개요 (방향)

- **기준(REFERENCE, 정답·최신):** `/Users/wise/Developer/Web(Node,Script)/Eden-FP-ops`
- **대상(TARGET, 수정 대상·구버전):** `/Users/wise/Developer/Web(Node,Script)/Finetuning-Pipeline-ops`
- **이식 내용:** Eden 이 단행한 **via-host-only 아키텍처 재설계** 를 워크스페이스로 이식.
  - 인프라(postgres/redis/minio/mailpit)는 Docker 단일 `docker/compose.infra.yaml` 로만 구동.
  - worker / web 은 호스트에서 **PM2** 로 직접 실행 (Apple Silicon MPS / 호스트 NVIDIA GPU 직접 사용).
  - 구 멀티-compose 모델(`compose.dev/prod/*.yaml` + Traefik + GPU 오버라이드)은 폐기.
- **브랜딩 원칙:** 워크스페이스 고유 네이밍 유지. Eden 토큰은 전부 역매핑.

## 2. 반영한 변경 (추가 / 삭제 / 재작성)

### 재작성 (Git 추적, 4개)
| 파일 | 내용 |
|---|---|
| `Makefile` | Eden 의 via-host-only Makefile 을 역매핑 이식. 구 멀티-compose 타깃(`docker-dev[-cpu/-gpu]`, `docker-prod[-cpu/-gpu]`, `docker-prod-tls[-gpu]`, `docker-down`, `docker-logs`, `docker-ps`, `traefik-diag`, `build*`) 제거. 3 모드(`dev`/`prod`/`local` = via-host) + `down`/`logs`/`status`/`restart`/`monit` 별칭 + `docker-infra-start/down`, `docker-clean` 로 단순화. |
| `README.md` | Eden README(498줄, via-host-only) 역매핑 이식. |
| `docker/README.md` | Eden docker README(167줄) 역매핑 이식. |
| `ADMIN-README.md` | Eden ADMIN README(420줄) 역매핑 이식. |

### 삭제 (Git 추적, 5개) — `git rm`
- `docker/compose.dev.yaml`
- `docker/compose.dev.gpu.yaml`
- `docker/compose.prod.yaml`
- `docker/compose.prod.gpu.yaml`
- `docker/compose.prod.tls.yaml`

신규 Makefile/스크립트가 위 파일을 참조하지 않음을 확인 후 삭제 (3절 참고).

### 비추적 변경 (gitignore 대상, 1개)
- `docker/.env` — 시크릿 세정 후 재작성 (6절). `git check-ignore` 로 gitignore 확인됨 → 커밋 이력에 실 시크릿 유입 없음.

### 이미 일치(변경 불필요) — 사전 분석 확인
- `docker/compose.infra.yaml` : Eden 과 **바이트 동일**. 서비스 네임 `wfp-*` 로 이미 중립.
- `scripts/ecosystem.config.cjs` : 이미 워크스페이스 네이밍(`wfp-worker-*`, `wfp_worker`, `Finetuning-Pipeline-*`)으로 역매핑 완료 상태.
- `scripts/host-down.sh` : 이미 `uvicorn wfp_worker.server` 로 역매핑 완료 상태.
- `scripts/reaper.py` : Eden 과 동일.
- `docker/.env.example` : Eden 과 **동일**(placeholder 규약 일치).

## 3. 발견·수정한 버그 / 댕글링 참조

- **댕글링 참조 0건** (Makefile + scripts + compose 범위). 신규 Makefile/`host-down.sh`/`ecosystem.config.cjs` 전수 grep 결과 삭제된 compose 파일을 참조하는 실행 경로 없음. `make -n down` 은 `compose.infra.yaml` + `scripts/host-down.sh`(둘 다 존재)만 참조.
- 구 Makefile 의 멀티-compose 타깃이 가리키던 `compose.dev/prod*.yaml` 은 타깃 자체를 제거하여 해소.
- 남아있는 `compose.dev/prod` 문자열은 모두 **"삭제됨" 안내 주석**(`README.md:469`, `docker/README.md:8`)으로 정확함 → 의도적 유지.

## 4. 역매핑한 네이밍 (Eden → 워크스페이스)

| Eden 토큰 | 워크스페이스 토큰 |
|---|---|
| `Eden-FP-worker` | `Finetuning-Pipeline-worker` |
| `Eden-FP-frontend` | `Finetuning-Pipeline-frontend` |
| `Eden-FP-ops` | `Finetuning-Pipeline-ops` |
| `Eden Finetuning Pipeline` | `Wise Fine-tuning Pipeline` |
| `Eden-FP` | `WFP` |
| `fp_worker` (python 모듈) | `wfp_worker` |
| `fp-worker` (uv 패키지 / PM2 프로세스) | `wfp-worker` |

- PM2 프로세스명: `fp-worker-{dev,prod,local}` → `wfp-worker-{dev,prod,local}`. `wfp-web-*` 는 Eden·워크스페이스 공통이라 변경 없음.
- 경로 fallback: Eden 의 `/Users/.../Eden-FP-{worker,frontend}` → 워크스페이스 `/Users/.../Finetuning-Pipeline-{worker,frontend}`.
- 이식 후 전수 검증: `Eden` / bare `fp_worker` / bare `fp-worker` 잔존 토큰 **0건** (Makefile + 3 README).

## 5. 스킵한 리브랜딩 / 범위 제외 항목

- `docker/.env` · `docker/.env.example` 의 `compose.prod.tls.yaml` / `Traefik` **주석** : Eden 기준 파일에도 동일하게 남아있는 주석(삭제된 파일을 가리키는 설명문). 기준과 1:1 일치 우선 원칙에 따라 **그대로 유지**. 동작에 영향 없음(주석). → 주의 항목으로 플래그.
- `need-to-debug.md` : 워크스페이스 고유 분석 산출물(Eden 미존재). `compose.dev` 삭제로 결함이 해소됨을 기록한 디버그 로그라 현재 기술적으로 정확 → 미변경.
- `.doc/PRD.md` : 제품 요구사항 설계 문서. ops 명령 문서가 아니며 기존 자산 → 범위 제외(주의 항목으로 플래그).
- `README.en.md` / `docker/README.en.md` : Eden 에는 영문판 존재하나 워크스페이스에는 없음. 신규 영문 문서 생성은 요청 범위 밖이라 **생성 안 함**.

## 6. 시크릿 처리 (placeholder)

- 기존 워크스페이스 `docker/.env` 에 **실 시크릿** 존재했음 (`POSTGRES/REDIS/MINIO_PASSWORD=dlems1234!`, 실 `JWT_SECRET`, `SUPERVISOR_ID=admin@edentns.com`).
- Eden `docker/.env` 의 실 시크릿(가동 가능성 있는 `HF_TOKEN`, JWT/NEXTAUTH)은 **복사하지 않음**.
- 세정 방식: 워크스페이스 `docker/.env.example`(이미 placeholder 규약, Eden 과 구조 동일)을 `docker/.env` 로 복사.
  - `*_PASSWORD=replace-with-strong-password`, `JWT_SECRET/NEXTAUTH_SECRET=replace-with-...`, `HF_TOKEN=hf_xxxxx`, `SUPERVISOR_ID=admin@example.com`.
- 검증: `docker/.env`·`.env.example` 에서 `dlems1234` / `hf_LamY...` / 실 JWT / `edentns` 패턴 **0건**.
- `docker/.env` 는 gitignore 대상 → 커밋되지 않음.

> 경고 플래그: 운영 배포 전 `docker/.env` 의 placeholder 를 실제 강한 랜덤값으로 교체 필요(`env-check` 타깃이 placeholder 잔존 시 빌드 차단).

## 7. 테스트 결과

| 검증 | 결과 |
|---|---|
| `bash -n scripts/host-down.sh` | PASS |
| `node --check scripts/ecosystem.config.cjs` | PASS |
| `docker compose -f docker/compose.infra.yaml config` | PASS (valid) |
| `make -n` × 20 타깃 (help, info, dev, prod, local, down, docker-dev/prod/local-via-host, docker-infra-start/down, docker-clean, host-down/restart/logs/status, logs, status, restart, monit) | 전부 PASS — 모든 참조 파일 존재 |
| 구 타깃 제거 확인 (docker-dev, docker-prod, docker-prod-tls, docker-down, docker-logs, traefik-diag, build) | 전부 제거됨 |
| 시크릿 누출 스캔 | 누출 0건 |

## 8. 미해결 / 주의 항목

1. `docker/.env`·`.env.example` 의 Traefik/`compose.prod.tls.yaml` 주석은 삭제된 파일을 언급함(Eden 기준과 동일하게 유지). 향후 정리 시 제거 가능하나 동작 무관.
2. `.doc/PRD.md` 는 여전히 구 멀티-compose 구조를 설계 문서로 기술함. ops 명령 문서가 아니라 미변경 — 필요 시 별도 갱신.
3. 워크스페이스에 영문 README 변형 없음. Eden 의 `README.en.md` 동등물이 필요하면 별도 작업 필요.
4. `docker/.env` 는 운영 전 실제 시크릿 주입 필수 (6절 플래그).
