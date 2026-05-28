# need-to-debug — Worktro Finetuning Pipeline 결함 + Eden-FP 수정 가이드

원본 Worktro Finetuning Pipeline 코드(`Finetuning-Pipeline-worker` / `-frontend` / `-ops`) 점검 중 발견한
결함과 Eden-FP 분기에서 적용한 / 권장하는 수정 가이드.

각 항목 구성:
- **위치** — 원본 파일 경로 + 라인
- **증상**
- **원인**
- **Eden-FP 수정** — 실제 코드에 반영한 변경 (또는 권장)
- **검증 방법**

---

## 1. `runtime._emit_ws` 가 매 WS 이벤트마다 동기 디스크 쓰기 (HIGH)

### 위치
`Finetuning-Pipeline-worker/src/wfp_worker/runtime.py` — `_emit_ws()` (Worktro 178행 부근).

### 증상
학습(Stage 7)의 tqdm 진행 로그가 초당 수십~수백 이벤트로 흐를 때
`save_state()` 가 매 호출마다 `jobs_state.json` 회전 백업 + atomic write 수행 → 디스크 I/O 폭주, SSD 수명/지연 악화. 동기 호출이라 이벤트 루프도 미세하게 정체.

### 원인
```python
async def _emit_ws(job_id, msg, extra=None):
    ...
    buf.append(payload)
    save_state()           # ← 매 호출마다 disk write
```
backfill 보존 목적이지만 호출 빈도가 비합리적.

### Eden-FP 수정 (적용 완료)
`save_state()` 에 throttle 추가. 마지막 디스크 쓰기로부터 `_SAVE_MIN_INTERVAL = 2.0` 초 이내 호출은 skip. `force=True` 인자로 우회 가능.

```python
# Eden-FP-worker/src/wfp_worker/runtime.py
_SAVE_MIN_INTERVAL = 2.0
_last_save_at: float = 0.0

def save_state(force: bool = False) -> None:
    global _last_save_at
    import time
    now = time.monotonic()
    if not force and (now - _last_save_at) < _SAVE_MIN_INTERVAL:
        return
    _last_save_at = now
    try:
        _PERSIST_DIR.mkdir(parents=True, exist_ok=True)
        _rotate_backup()
        ...
```

명시적으로 강제 쓰기가 필요한 호출부 갱신:
- `runtime.finalize_job` → `save_state(force=True)`
- `server._lifespan` shutdown → `save_state(force=True)`

`_emit_ws` 의 호출은 throttle 그대로 적용 (force 없음) → 학습 중 2초 간격으로만 디스크 hit.

### 검증
- `make local` 또는 `make dev` 기동
- 잡 실행 (Stage 7 진입) 중 `~/.wfp/jobs_state.json` mtime 관찰
- throttle 적용 전: 초당 갱신 → 적용 후: 2초 이상 간격

---

## 2. `env_check._check_imports` 가 실제 import 로 side-effect 유발 (MED)

### 위치
`Finetuning-Pipeline-worker/src/wfp_worker/env_check.py` — `_check_imports()` (Worktro 121행).

### 증상
- non-CUDA 호스트에서 `bitsandbytes` 가 설치되어 있으면 import 시 CUDA 초기화 시도 → `RuntimeError` / `AttributeError` 발생 → ImportError 가 아니라 미잡힘 → 진단 명령(`make env-status`) 자체가 크래시
- 그 외 라이브러리도 import 시 GPU detect / dataset 다운로드 등 side-effect 가능

### 원인
```python
try:
    __import__(import_name.replace("-", "_"))
    installed.append(pip_name)
except ImportError:
    missing.append(pip_name)
```
`__import__` 는 실제 import — 모든 module-level 코드 실행.

### Eden-FP 수정 (적용 완료)
`importlib.util.find_spec` 으로 변경 — 실제 import 없이 설치 여부만 확인:

```python
def _check_imports(packages):
    import importlib.util
    installed, missing = [], []
    for import_name, pip_name in packages.items():
        mod_name = import_name.replace("-", "_")
        try:
            spec = importlib.util.find_spec(mod_name)
        except (ImportError, ValueError):
            spec = None
        if spec is not None:
            installed.append(pip_name)
        else:
            missing.append(pip_name)
    return installed, missing
```

### 검증
```bash
make env-status            # bitsandbytes 설치된 mac 에서도 크래시 없이 진단
make env-status-json | jq .missing_packages
```

---

## 3. `compose.dev.yaml` reaper 사이드카의 빈 `pip install` (LOW — Eden-FP 에서 compose.dev 삭제로 자동 해소)

### 위치
원본 `Finetuning-Pipeline-ops/docker/compose.dev.yaml` (155–160행) — `reaper` 서비스.

### 증상
컨테이너 부팅 시 `pip install --quiet --no-cache-dir &&` 가 인자 없이 실행 → `ERROR: You must give at least one requirement to install` → 컨테이너 영구 재시작 루프 (`restart: unless-stopped`).

### 원인
```yaml
command: >
  sh -c "pip install --quiet --no-cache-dir && \
         while true; do python /scripts/reaper.py; sleep 1800; done"
```
설치할 패키지 명 누락. 작성자가 의존성 정리 중 인자를 빼먹고 커밋한 것으로 보임.

### Eden-FP 처리
via-host 모드만 지원 — `compose.dev.yaml` 자체 삭제 → 결함 자동 해소.
reaper 가 필요하면 호스트 cron 또는 PM2 cron 으로 별도 운영:

```bash
# crontab -e
*/30 * * * * cd /path/to/Eden-FP-ops && python scripts/reaper.py
```

또는 PM2 cron:
```js
// scripts/ecosystem.config.cjs 에 추가 가능
{
  name: "wfp-reaper",
  script: "python",
  args: [path.join(__dirname, "reaper.py")],
  cron_restart: "*/30 * * * *",
  autorestart: false,
}
```

### 검증
`make dev` 후 `make logs` — reaper 관련 컨테이너 오류 없음.

---

## 4. `middleware.ts` 보호 경로 비활성 — 인증 미들웨어 무동작 (KNOWN / LOW)

### 위치
`Finetuning-Pipeline-frontend/middleware.ts` 15행.

### 증상
```typescript
const PROTECTED_PREFIXES: string[] = [];   // 빈 배열
```
모든 경로가 미들웨어를 통과. `/admin/*` / `/jobs/*` 보호 없음.

### 원인 (문서화됨)
현재 인증은 client-side JWT(localStorage) 기반. 미들웨어는 NextAuth 쿠키 기반이라 토큰 위치 불일치 → 미들웨어가 항상 미인증으로 판정 → 로그인 무한 리다이렉트 회피 위해 의도적으로 비활성.

### Eden-FP 처리
**현 상태 유지.** JWT 를 httpOnly 쿠키로 마이그레이션할 때 함께 활성화. 단기 대응:
- `NEXT_PUBLIC_AUTH_DISABLED=false` (운영 기본) + 클라이언트 가드(`components/auth-guard.tsx`)로 보호
- 운영 reverse proxy(nginx/Caddy) 레벨에서 `/admin/*` IP allowlist 권장

### 권장 작업
1. NextAuth 세션을 httpOnly cookie 로 전환 (`session.strategy = "jwt"` + `cookies.sessionToken.options.httpOnly = true`)
2. `lib/api.ts` fetch 에 `credentials: "include"` 적용
3. middleware 의 `PROTECTED_PREFIXES` 에 `/admin`, `/(app)`, `/(admin)` 추가

---

## 5. `runtime._PERSIST_DIR` 가 모듈 로드 시점에 고정 (LOW)

### 위치
`Finetuning-Pipeline-worker/src/wfp_worker/runtime.py` 69행.

### 증상
```python
_PERSIST_DIR = Path("/data") if Path("/data").exists() else Path.home() / ".wfp"
```
서버 부팅 시 `/data` 가 없으면 영원히 `~/.wfp` 사용. 이후 `/data` 가 마운트되어도 무시.

### 원인
모듈 import 타임 평가.

### Eden-FP 처리
via-host 모드는 worker 가 호스트에서 직접 실행 → `/data` 마운트 없음. 항상 `~/.wfp` 사용 정상. 향후 컨테이너 모드 부활 시 수정 필요:

```python
def _resolve_persist_dir() -> Path:
    return Path("/data") if Path("/data").exists() else Path.home() / ".wfp"

# 사용 시점에 호출
_PERSIST_PATH = _resolve_persist_dir() / "jobs_state.json"
```

---

## 6. `runtime._make_progress_cb` 가 잡 당 여러 번 호출되어 tqdm bridge 누적 (LOW)

### 위치
`Finetuning-Pipeline-worker/src/wfp_worker/runtime.py` — `_run_pipeline` + Stage 7/8 직접 호출.

### 증상
`_make_progress_cb` 가 `tqdm_bridge.configure(cb)` 를 호출. `_run_pipeline` 초기 + `_stage_7_train` + `_stage_8_eval` 에서 각각 호출 → 같은 잡에서 3회 configure.

`tqdm_bridge.configure` 가 idempotent 라고 코멘트되어 있으면 무해. 그렇지 않으면 콜백 누적 → WS 이벤트 중복.

### Eden-FP 처리
`tqdm_bridge.configure` 의 실제 구현 확인 후 idempotent 보장 필요. 현재 코멘트 신뢰. 후속 검증 항목:

```bash
grep -n "def configure" ../Eden-FP-worker/src/wfp_worker/common/tqdm_bridge.py
```

idempotent 가 아니면 `wfp_worker/common/tqdm_bridge.py` 에 콜백 dedup 추가.

---

## 7. `host-down.sh` 가 `next-server` / `node next` 만 매칭 — pnpm 으로 부팅된 next 누락 가능 (LOW)

### 위치
`Finetuning-Pipeline-ops/scripts/host-down.sh` 17–22행.

### 증상
```bash
for pat in \
  "uvicorn wfp_worker.server" \
  "next-server" \
  "node.*next/dist/bin/next"; do
  pkill -TERM -f "$pat" 2>/dev/null || true
done
```
이후 `lsof -ti :3000` 으로 잔여 정리되므로 결과적으로는 정리되지만, 일부 환경에서 pnpm wrapper 가 자식 SIGTERM 전파 실패 시 좀비 가능.

### Eden-FP 처리
포트 기반 정리(`lsof -ti :3000 :8000`) 가 backstop 으로 동작하므로 현 상태 유지. 더 엄격한 정리가 필요하면 `pkill -f "pnpm.*(dev|start)"` 추가.

---

## 8. Makefile 의 `docker-down` 이 삭제된 compose 파일 참조 (CLEANED — Eden-FP 에서 단순화)

### 위치
원본 `Finetuning-Pipeline-ops/Makefile` 428–438행.

### 증상
`docker-down` 이 `compose.dev.yaml` / `compose.prod*.yaml` 모두 `docker compose down` 시도. Eden-FP 는 이들 삭제 → `|| true` 로 무시되지만 로그 노이즈.

### Eden-FP 수정 (적용 완료)
`make down` 을 인프라 compose 1개 + host-down 으로 단순화. `traefik-diag` / `docker-prod-tls` 등 관련 타깃도 모두 제거.

---

## 우선순위 요약

| #  | 항목                                | 등급 | Eden-FP 적용 |
|----|-------------------------------------|------|--------------|
| 1  | save_state throttle                 | HIGH | ✅ 적용     |
| 2  | env_check find_spec                 | MED  | ✅ 적용     |
| 3  | reaper pip install 빈 인자          | LOW  | ✅ 우회 (compose.dev 삭제) |
| 4  | middleware 보호 경로 비활성         | LOW  | 📋 문서화 (JWT 쿠키 마이그레이션 후) |
| 5  | _PERSIST_DIR 로드타임 고정          | LOW  | 📋 권장 (현재 영향 없음) |
| 6  | tqdm_bridge.configure 다중 호출     | LOW  | 📋 후속 검증 |
| 7  | host-down.sh pkill 패턴             | LOW  | ➖ 현 상태 |
| 8  | Makefile docker-down 노이즈         | LOW  | ✅ 적용 (단순화) |

`✅` = Eden-FP 코드에 실제 반영 / `📋` = 권장 작업으로 명시 / `➖` = 현 상태 유지.
