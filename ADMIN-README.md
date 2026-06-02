# WFP 관리자 기능 — 확인 가이드

**한국어** | [English](./ADMIN-README.en.md)

PRD §10 관리자 기능이 구현된 백엔드 엔드포인트 + 일부 프론트엔드 UI를 활용해 관리자 권한을 검증하는 절차.

> WFP 는 via-host 만 지원 — worker/web 은 호스트 PM2 실행. 로그/재시작은 `make logs-worker` / `make restart`.
> 운영 가이드는 [상위 README](README.md) ([EN](README.en.md)).

---

## 1. 관리자 계정

### 1.1 계정 생성 정책

| 가입 경로 | 권한 |
|---|---|
| `/auth/signup` (웹 회원가입) | **항상 USER** (강제) |
| `SUPERVISOR_ID` / `SUPERVISOR_PASSWORD` env | **자동 ADMIN** (서버 시작 시 생성/보장) |

회원가입한 일반 사용자는 절대 ADMIN이 될 수 없다. ADMIN은 오직 env 기반 supervisor 계정 한 개만 보장된다.
추가 ADMIN이 필요하면 supervisor 계정으로 로그인 후 `PATCH /admin/users/{id}` 로 다른 사용자 권한을 승격.

### 1.2 Supervisor 계정 설정

워커 `.env` (또는 `docker/.env`):

```bash
SUPERVISOR_ID=admin@your-domain.com
SUPERVISOR_PASSWORD=replace-with-strong-password
```

서버 재시작 시:
- 해당 이메일 계정이 없으면 자동 생성 (ADMIN 권한)
- 이미 있으면 비밀번호 갱신 + ADMIN 권한 강제 부여

확인:

```bash
make logs-worker | grep supervisor_created
# → {"msg":"supervisor_created","extra":{"email":"admin@..."}}
```

---

## 2. 관리자 로그인

### 2.1 웹 UI

```
http://<서버-IP-또는-도메인>/login
```

`SUPERVISOR_ID` / `SUPERVISOR_PASSWORD` 입력 → 로그인 성공 시 사이드바에 **관리자 메뉴** 영역 노출 (`/admin/...`).

### 2.2 CLI / curl

JWT 토큰 발급:

```bash
TOKEN=$(curl -s -X POST http://<서버>/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@your-domain.com","password":"<password>"}' \
  | jq -r .access_token)

echo $TOKEN   # eyJhbG...
```

이후 모든 admin API 호출:

```bash
curl -H "Authorization: Bearer $TOKEN" http://<서버>/admin/stats
```

### 2.3 Swagger UI

```
http://<서버>:8000/docs       # 운영에선 BFF 경유: http://<서버>/api/proxy/docs
```

우상단 **Authorize** 버튼 → `bearerAuth` → 토큰 입력 → 모든 `/admin/*` 엔드포인트 시도 가능.

---

## 3. PRD §10 기능별 확인 절차

### 10.1 대시보드 (`/admin/stats`, `/admin/resources`)

**프론트엔드:** `/admin/resources` (리소스 카드)
**백엔드 — 통계 카드 (확장된 응답):**

```bash
curl -H "Authorization: Bearer $TOKEN" http://<서버>/admin/stats | jq
```

응답 필드:

| 필드 | 의미 |
|---|---|
| `users_total` / `users_active` | 전체/활성 사용자 |
| `jobs_pending` / `running` / `done` / `failed` / `cancelled` | 잡 상태별 개수 |
| `queue_depth` | 큐 길이 (= PENDING 잡 개수) |
| `avg_wait_seconds` | 생성 → 실행 시작까지 평균 대기 시간 |
| `avg_train_seconds` | 실행 시작 → 완료까지 평균 학습 시간 |
| `disk_free_gb` / `gpu_count` | 디스크 / GPU 개수 |
| `gpu_breakdown[]` | GPU별 VRAM 사용/총량, 점유율 |

**검증 시나리오:**

1. 일반 사용자 계정으로 `POST /jobs` → 잡 1건 생성
2. 어드민으로 `GET /admin/stats` 호출 → `jobs_pending` 또는 `jobs_running` 증가 확인
3. 잡 완료 후 다시 호출 → `jobs_done` 증가 + `avg_train_seconds` 값 채워짐

### 10.2 작업 모니터링 (`/admin/jobs`, 강제 취소, 우선순위)

**프론트엔드:** `/admin/jobs` (필터링된 전체 잡 리스트)

**필터 쿼리:**

```bash
# 특정 사용자의 RUNNING 잡
curl -H "Authorization: Bearer $TOKEN" \
  "http://<서버>/admin/jobs?state=RUNNING&user_id=<uuid>" | jq

# KSIC J(정보통신업) 분야 + 날짜 범위
curl -H "Authorization: Bearer $TOKEN" \
  "http://<서버>/admin/jobs?ksic_section=J&date_from=2026-05-01&date_to=2026-05-31" | jq
```

**잡 상세 + 이벤트 로그:**

```bash
curl -H "Authorization: Bearer $TOKEN" http://<서버>/admin/jobs/<job_id> | jq
```

응답에 `events` 배열 (실시간 진행 이벤트 누적 기록).

**강제 취소:**

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" \
  http://<서버>/admin/jobs/<job_id>/cancel
# {"job_id":"...","state":"CANCELLED"}
```

**우선순위 변경 (1~9, 낮을수록 먼저):**

```bash
curl -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"priority": 2}' \
  http://<서버>/admin/jobs/<job_id>/priority
```

---

### 10.3 자원 회수 (`/admin/reaper/run`)

PRD §10.3 정책:
- heartbeat 끊김 N분 이상 → 잡 FAILED 처리
- 디스크 사용량 임계치 초과 시 오래된 체크포인트부터 회수
- 일정 기간 미접속 사용자 아티팩트 → soft-delete

**자동:** 호스트 cron 으로 `scripts/reaper.py` 주기 실행 (compose 사이드카 제거 — via-host).

**수동 트리거 (관리자):**

```bash
curl -X POST -H "Authorization: Bearer $TOKEN" http://<서버>/admin/reaper/run | jq
```

응답:

```json
{
  "jobs_failed": 0,
  "artifacts_deleted": 0,
  "checkpoints_purged": 1,
  "disk_freed_mb": 234.5,
  "detail": ["checkpoint <id> purged (234.5MB)"]
}
```

**검증 시나리오:**

1. 잡 1건 PENDING 상태로 stuck (worker 죽이기 등으로 heartbeat 끊김 재현)
2. `WFP_HEARTBEAT_TIMEOUT_MIN` 환경변수 기본 30분 → 짧게 (예: 1분)으로 변경 후 reaper 트리거
3. 응답에 `jobs_failed: 1` 확인

환경변수:

| 변수 | 기본 | 설명 |
|---|---|---|
| `WFP_HEARTBEAT_TIMEOUT_MIN` | 30 | 이 시간 이상 멈춘 RUNNING 잡 → FAILED |
| `WFP_DISK_THRESHOLD_PCT` | 80 | 디스크 사용률 초과 시 체크포인트 회수 |

---

### 10.4 카탈로그 관리

세 가지 CRUD 카테고리:

#### A. 모델 카탈로그 (`/admin/catalog/models`)

**프론트엔드:** `/admin/catalog`

**CRUD:**

```bash
# 목록
curl -H "Authorization: Bearer $TOKEN" http://<서버>/admin/catalog/models | jq

# 추가
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "hf_repo": "meta-llama/Llama-3.2-3B",
    "params_b": 3.2,
    "license": "llama3.2",
    "hw_min_vram_gb": 8,
    "language": "ko,en",
    "tags": "general,chat",
    "priority": 5
  }' \
  http://<서버>/admin/catalog/models

# 수정
curl -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"priority": 1}' \
  http://<서버>/admin/catalog/models/<id>

# 비활성화 (soft delete)
curl -X DELETE -H "Authorization: Bearer $TOKEN" \
  http://<서버>/admin/catalog/models/<id>
```

#### B. 데이터 소스 화이트리스트 (`/admin/data-sources`) — UI 미구현

```bash
# 목록 (활성만)
curl -H "Authorization: Bearer $TOKEN" \
  "http://<서버>/admin/data-sources?active_only=true" | jq

# 추가
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "HF datasets official",
    "source_type": "hf_datasets",
    "url_pattern": "huggingface.co/datasets/.*",
    "description": "공식 HF 데이터셋 허용"
  }' \
  http://<서버>/admin/data-sources

# 수정
curl -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"is_active": false}' \
  http://<서버>/admin/data-sources/<id>

# 비활성화
curl -X DELETE -H "Authorization: Bearer $TOKEN" \
  http://<서버>/admin/data-sources/<id>
```

`source_type` 허용 값: `hf_datasets` / `url` / `api` / `upload`

#### C. 카테고리/프리셋 (`/admin/presets`) — UI 미구현

KSIC 분야 + 태스크 조합별 추천 모델 + 기본 학습 설정.

```bash
# 추가
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "J-chat-default",
    "ksic_section": "J",
    "task_type": "chat",
    "recommended_models": ["meta-llama/Llama-3.2-3B", "Qwen/Qwen2.5-3B"],
    "default_config": {"learning_rate": 2e-4, "num_epochs": 3, "batch_size": 4},
    "description": "정보통신업 챗봇 기본값"
  }' \
  http://<서버>/admin/presets

# 필터링 조회 (KSIC J + chat 태스크)
curl -H "Authorization: Bearer $TOKEN" \
  "http://<서버>/admin/presets?ksic_section=J&task_type=chat" | jq
```

---

### 10.5 감사 로그 (`/admin/audit`)

**프론트엔드:** `/admin/audit`

모든 관리자 액션이 자동 적재:

| Action | 트리거 |
|---|---|
| `user_role_patch` | 사용자 권한 변경 |
| `job_cancel` | 잡 강제 취소 |
| `job_priority` | 우선순위 변경 |
| `catalog_create/patch/delete` | 모델 카탈로그 |
| `datasource_create/patch/delete` | 데이터 소스 |
| `preset_create/patch/delete` | 프리셋 |
| `reaper_run` | Reaper 트리거 |
| `env_install` | 학습 패키지 설치 |

**필터:**

```bash
# 특정 액션
curl -H "Authorization: Bearer $TOKEN" \
  "http://<서버>/admin/audit?action=job_cancel" | jq

# 액터 이메일 + 날짜
curl -H "Authorization: Bearer $TOKEN" \
  "http://<서버>/admin/audit?actor_email=admin@your-domain.com&date_from=2026-05-22" | jq
```

**검증:** 위 §10.2~10.4 명령들을 차례로 실행 후 `/admin/audit` 조회 → 액션이 시간순으로 누적되어야 함.

---

## 4. 프론트엔드 UI 매핑

| PRD §10 항목 | 프론트엔드 경로 | 상태 |
|---|---|---|
| 10.1 대시보드 (리소스 카드) | `/admin/resources` | ✓ UI 존재 |
| 10.1 대시보드 (통계 카드 확장) | — | 백엔드만 (`/admin/stats`) |
| 10.2 잡 목록 + 필터 | `/admin/jobs` | ✓ UI 존재 |
| 10.2 잡 상세 / 강제 취소 | `/admin/jobs/<id>` | (페이지 미구현, API ✓) |
| 10.2 우선순위 변경 | — | 백엔드만 (`PATCH /admin/jobs/<id>/priority`) |
| 10.3 Reaper 수동 트리거 | — | 백엔드만 (`POST /admin/reaper/run`) |
| 10.4 모델 카탈로그 CRUD | `/admin/catalog` | ✓ UI 존재 |
| 10.4 데이터 소스 화이트리스트 | — | 백엔드만 (`/admin/data-sources`) |
| 10.4 카테고리/프리셋 | — | 백엔드만 (`/admin/presets`) |
| 10.5 감사 로그 | `/admin/audit` | ✓ UI 존재 |
| 부가: 사용자 관리 | `/admin/users` | ✓ UI 존재 |

**UI 미구현 항목**은 curl 또는 Swagger UI로 검증 가능. 향후 별도 페이지 추가 예정.

---

## 5. 전체 검증 시나리오 (1회 통합 테스트)

다음을 순서대로 실행해 모든 §10 기능을 종단 확인:

```bash
SERVER=http://<서버-IP-또는-도메인>
ADMIN_EMAIL=admin@your-domain.com
ADMIN_PW=<password>

# 1) 로그인
TOKEN=$(curl -s -X POST $SERVER/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PW\"}" \
  | jq -r .access_token)

H="Authorization: Bearer $TOKEN"

# 2) 대시보드 (10.1)
curl -s -H "$H" $SERVER/admin/stats | jq '.queue_depth, .gpu_count'

# 3) 잡 목록 (10.2)
curl -s -H "$H" $SERVER/admin/jobs | jq 'length'

# 4) Reaper (10.3)
curl -s -X POST -H "$H" $SERVER/admin/reaper/run | jq '.jobs_failed, .checkpoints_purged'

# 5) 모델 카탈로그 (10.4-A)
MODEL_ID=$(curl -s -X POST -H "$H" -H "Content-Type: application/json" \
  -d '{"hf_repo":"test/admin-check","params_b":1,"license":"mit","hw_min_vram_gb":4}' \
  $SERVER/admin/catalog/models | jq -r .id)
curl -s -X DELETE -H "$H" $SERVER/admin/catalog/models/$MODEL_ID

# 6) 데이터 소스 (10.4-B)
DS_ID=$(curl -s -X POST -H "$H" -H "Content-Type: application/json" \
  -d '{"name":"check-ds","source_type":"url","url_pattern":"https://.*"}' \
  $SERVER/admin/data-sources | jq -r .id)
curl -s -X DELETE -H "$H" $SERVER/admin/data-sources/$DS_ID

# 7) 프리셋 (10.4-C)
PRESET_ID=$(curl -s -X POST -H "$H" -H "Content-Type: application/json" \
  -d '{"name":"check-preset","ksic_section":"J","task_type":"chat"}' \
  $SERVER/admin/presets | jq -r .id)
curl -s -X DELETE -H "$H" $SERVER/admin/presets/$PRESET_ID

# 8) 감사 로그 (10.5) — 위 액션들이 모두 기록되어 있어야 함
curl -s -H "$H" "$SERVER/admin/audit?actor_email=$ADMIN_EMAIL" \
  | jq '.[] | .action' | head -10
```

기대 결과:
- 모든 명령이 200/201/204 응답
- 마지막 audit 조회에서 `catalog_create`, `catalog_delete`, `datasource_create`, `datasource_delete`, `preset_create`, `preset_delete`, `reaper_run` 액션 확인

---

## 6. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| 로그인 401 | `SUPERVISOR_PASSWORD` 미설정 또는 오타 | `docker/.env` 확인 후 `make restart` |
| `/admin/*` 403 | 일반 USER 토큰으로 호출 | supervisor 계정으로 다시 로그인 |
| 사이드바에 관리자 메뉴 없음 | 프론트엔드 빌드 캐시 또는 권한 미반영 | 재로그인 → 토큰 클레임의 `role: "ADMIN"` 확인 |
| 새 admin 계정 만들고 싶음 | `signup`은 항상 USER | supervisor로 로그인 → `PATCH /admin/users/<id>` `{"role":"ADMIN"}` |
| `priority` 변경했는데 안 적용 | 잡은 in-memory + 단일 worker. 우선순위 큐 미구현 — 필드만 변경 (PRD §10.2 UI 표시용) | 다중 worker 큐로 확장 시 적용 예정 |
| Swagger /docs 접속 안 됨 | 운영 환경에서 worker 외부 노출 안 됨 (BFF 경유) | `http://<서버>/api/proxy/docs` 또는 SSH 터널 |

---

## 7. 참조

- 백엔드 구현: [`../Finetuning-Pipeline-worker/src/wfp_worker/api/admin.py`](../Finetuning-Pipeline-worker/src/wfp_worker/api/admin.py)
- 프론트엔드 페이지: [`../Finetuning-Pipeline-frontend/app/(admin)/`](../Finetuning-Pipeline-frontend/app/\(admin\)/)
- PRD §10 명세: [.doc/PRD.md](.doc/PRD.md) (§10 관리자 기능)
- worker API / admin 엔드포인트 요약: [../Finetuning-Pipeline-worker/README.md](../Finetuning-Pipeline-worker/README.md)
