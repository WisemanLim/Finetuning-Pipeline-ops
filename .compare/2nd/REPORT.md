# ops 비교/QA 리포트 — 2nd pass

- 작성일: 2026-06-09
- 방향: **Eden-FP-ops = 기준(정답·최신), 워크스페이스 Finetuning-Pipeline-ops = 수정 대상**
- 기준(REF): `/Users/wise/Developer/Web(Node,Script)/Eden-FP-ops`
- 대상(TGT): `/Users/wise/Developer/Web(Node,Script)/Finetuning-Pipeline-ops`
- 1st 리포트: `.compare/1st/REPORT.md`
- 네이밍 규칙: Eden-FP-worker→Finetuning-Pipeline-worker, fp_worker→wfp_worker, PM2 `fp-worker-*`→`wfp-worker-*`, Worktro→Wise (리브랜딩 차이는 버그 아님)

## 1. 비교 개요 (2nd)

1st에서 via-host-only 재설계(compose 단일화 + 호스트 PM2)를 이식·커밋함. 2nd는 현재 상태를 Eden과 재diff하여 잔여 격차 점검. **모델 변환 도구 설치 타깃 + 통합 배포 타깃 격차 발견 → 이식.**

## 2. 1st 대비 잔여 차이 (2nd에서 발견)

Eden에 있고 워크스페이스에 미반영이던 운영 편의/변환 지원:
- `install-convert-tools` 타깃(변환 도구 + llama.cpp clone) 및 bootstrap 연동
- `deploy`/`pull`/`redeploy` 타깃(worker+web 동시 배포, prod 자동 빌드 감지)
- 변환 관련 env 문서화

## 3. 추가 이식/수정 내역 (이번 pass)

| 파일 | 변경 | 내용 |
|------|------|------|
| `Makefile` | +71 | `install-convert-tools`(uv `.[convert]` 설치 + llama.cpp clone/pull + requirements), bootstrap에 연동, `pull`(두 레포 git pull, 로컬변경 시 skip), `deploy`(worker editable 재설치 + web 의존성 + prod web 감지 시 `pnpm build` + PM2 재시작, `GIT_PULL=0` 지원), `redeploy` 별칭, `.PHONY`/help 갱신 |
| `docker/.env.example` | +7 | 변환 관련 옵션 문서화: `WFP_LLAMA_CPP_DIR`(llama.cpp 위치), `WFP_CONVERT_TIMEOUT`(기본 1800s) |
| `README.md` | +8 | 변환/배포 명령 안내 갱신 |
| `ADMIN-README.md` | +55 | 운영자용 변환 도구 설치·배포 절차 |

경로/모듈/PM2명 모두 `Finetuning-Pipeline-*`/`wfp_worker`/`wfp-*`로 역매핑. Eden 브랜딩 유출 없음(`make help`도 "Wise Fine-tuning Pipeline" 유지).

## 4. 스킵한 리브랜딩 항목

- `Eden-FP-*` 경로, `fp_worker`/`fp-worker-*` → 워크스페이스 네이밍으로 역매핑. Eden 제품명·repo URL 미이식.

## 5. 발견·수정 버그 / 댕글링 참조

- 댕글링 참조 **0**. `make install-convert-tools`가 설치하는 worker `.[convert]` extra는 동일 pass에서 worker `pyproject.toml`에 추가됨 → 정합.
- 삭제된 구 compose(dev/prod/gpu/tls) 참조 잔존 **0** (`grep compose.(dev|prod)` empty).

## 6. 시크릿 처리

- `docker/.env.example`은 placeholder만 추가(실 시크릿 없음). Eden의 라이브 `HF_TOKEN`/JWT 미복사. `docker/.env`(gitignore)는 미변경.

## 7. 테스트 결과 (검증)

| 검증 | 결과 |
|------|------|
| `bash -n scripts/host-down.sh` | OK |
| `node --check scripts/ecosystem.config.cjs` | OK |
| `docker compose -f docker/compose.infra.yaml config` | OK (파싱 정상) |
| `make -n` (deploy, pull, down, host-down, status, logs) | 6/6 RESOLVE OK |
| 댕글링 compose 참조 | 0 |

## 8. 미해결 / 주의 항목

- `install-convert-tools`는 네트워크(GitHub clone) + 빌드 도구 필요. GGUF 양자화(`llama-quantize`)까지 쓰려면 cmake 빌드 별도 필요(타깃 출력에 안내됨). Apple Silicon 외 환경은 mlx-lm 설치 실패가 정상(graceful skip).
- 프로덕션 배포 전 `docker/.env` placeholder를 실값으로 교체 필요(`env-check` 타깃이 placeholder 잔존 시 차단).
- `deploy`의 prod web 빌드 감지는 PM2 프로세스명 `wfp-web-prod` 기준 — 네이밍 변경 시 동기화 필요.
