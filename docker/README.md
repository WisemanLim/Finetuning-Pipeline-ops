# WFP Docker 인프라 가이드

**한국어** | [English](./README.en.md)

이 디렉토리는 **인프라 컨테이너 전용**. worker/web 은 호스트에서 PM2 로 직접 실행한다 (호스트 GPU/MPS 그대로 사용).

> WFP 는 Worktro Finetuning Pipeline 의 단순화 분기. via-host 만 지원 —
> 구 `compose.dev/prod*.yaml`, `compose.*.gpu.yaml`, `compose.prod.tls.yaml`, worker/frontend `Dockerfile`, Traefik 경로는 모두 제거됨.
> 전체 운영 가이드는 [상위 README](../README.md) ([EN](../README.en.md)) 참조.

---

## 파일 목록

| 파일 | 용도 |
|------|------|
| [`compose.infra.yaml`](./compose.infra.yaml) | 인프라 컨테이너 — postgres / redis / minio / mailpit |
| [`.env.example`](./.env.example) | 환경 변수 템플릿 (모든 비밀의 source of truth) |
| `.env` | 실제 비밀 (직접 생성, `.gitignore`) |

worker/web 실행은 docker 가 아니라 상위 Makefile 의 via-host 모드:

```bash
cd ..
make local              # SQLite + 호스트 PM2, Docker 인프라 없음
make dev                # 인프라 컨테이너 + 호스트 PM2 (hot-reload)
make prod               # 인프라 컨테이너 + 호스트 PM2 (pnpm build 사전)
```

---

## 인프라 서비스

`compose.infra.yaml` 의 4 개 서비스. 모두 `wfp` bridge 네트워크 + `restart: unless-stopped` + healthcheck.

| 서비스    | 컨테이너명     | 이미지 | 외부 포트 | 내부 포트 | 용도 |
|-----------|----------------|--------|-----------|-----------|------|
| postgres  | `wfp-postgres` | `postgres:16-alpine` | 5532 | 5432 | 메인 DB (다른 PG 와 충돌 회피) |
| redis     | `wfp-redis`    | `redis:7-alpine` (AOF) | 6479 | 6379 | 큐 / 캐시 |
| minio     | `wfp-minio`    | `minio/minio:latest` | 9100 (S3), 9101 (콘솔) | 9000, 9001 | S3 호환 객체 저장 |
| mailpit   | `wfp-mailhog`  | `axllent/mailpit:latest` | 1125 (SMTP), 8125 (UI) | 1025, 8025 | 회원가입 이메일 인증 트랩 |

> 호스트 포트는 5xxx/6xxx/8xxx/9xxx 대역으로 재매핑 — 다른 로컬 서비스와 충돌 회피.
> 컨테이너 간 통신은 표준 포트 유지 (`postgres:5432`, `redis:6379`, `minio:9000`).

> `mailhog/mailhog:latest` 는 유지보수 중단 + 멀티아키 푸시 깨짐(`exec format error`) → drop-in 호환 `mailpit` 으로 교체. SMTP/UI 포트 동일. (컨테이너명만 `wfp-mailhog` 유지)

볼륨: `pg_data` / `redis_data` / `minio_data` — `make docker-clean` 으로만 삭제 (**데이터 손실**).

---

## 빠른 시작

```bash
cd ..                               # ops 루트
cp docker/.env.example docker/.env  # 비밀 채우기
$EDITOR docker/.env

make dev                            # 인프라 + 호스트 PM2
```

인프라만 단독 기동/정지:

```bash
make docker-infra-start
make docker-infra-down
```

직접 docker compose:

```bash
cd docker
docker compose -f compose.infra.yaml up -d        # 기동
docker compose -f compose.infra.yaml ps           # 상태
docker compose -f compose.infra.yaml logs -f postgres
docker compose -f compose.infra.yaml restart redis
docker compose -f compose.infra.yaml down         # 정지 (볼륨 보존)
docker compose -f compose.infra.yaml down -v      # 정지 + 볼륨 삭제 (데이터 손실)
```

---

## 접속

| 서비스 | URL | 인증 |
|--------|-----|------|
| MinIO 콘솔 | http://localhost:9101 | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` |
| MinIO S3 API | http://localhost:9100 | 컨테이너 내부는 `minio:9000` |
| Mailpit UI | http://localhost:8125 | 없음 (회원가입 메일 확인) |
| PostgreSQL | localhost:5532 | `wfp` / `POSTGRES_PASSWORD` / DB `wfp` |
| Redis | localhost:6479 | dev 비번 없음 |

worker API (`:8000`) / 웹 UI (`:3000`) 는 호스트 PM2 가 노출 — docker 아님.

---

## 환경 변수

`.env.example` → `.env` 복사 후 채움. 상위 `ecosystem.config.cjs` 가 worker/web 양쪽에 주입.

| 키 | 필수 | 비고 |
|----|------|------|
| `SUPERVISOR_ID` / `SUPERVISOR_PASSWORD` | ✓ | 부팅 시 admin 계정 자동 생성/보장 |
| `POSTGRES_PASSWORD` | prod | postgres 인증 (기본 `wfp-dev`) |
| `REDIS_PASSWORD` | prod | redis 인증 |
| `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` | prod | S3 인증 (기본 `wfp-minio` / `wfp-minio-secret`) |
| `NEXTAUTH_SECRET` | prod | `openssl rand -base64 32` |
| `HF_TOKEN` | | 비공개 HF 모델 다운로드 |
| `JWT_SECRET` | | 미지정 시 `NEXTAUTH_SECRET` 사용 |
| `DATABASE_URL` | | Postgres 강제. 미지정 시 SQLite |
| `NEXTAUTH_URL` | | IP 접속 = 서버 IP, TLS = `https://도메인` |
| `NEXT_PUBLIC_WS_BASE` / `NEXT_PUBLIC_WORKER_WS_PORT` | | WS 베이스 (빌드 타임 inline — 변경 후 `make prod` 재빌드) |
| `NEXT_PUBLIC_AUTH_DISABLED` | | dev 전용. **운영 절대 `true` 금지** |
| `GRADIO_BASE_URL` | | Stage 9 추론 시연 (선택) |
| `GOOGLE_/GITHUB_/KAKAO_CLIENT_*` | | OAuth (선택) |
| `WFP_RULES_PATH` | | `rules/hw_to_plan.yaml` override (선택) |

검증:

```bash
cd ..
make dev-env-check      # SUPERVISOR_* 만 (dev — 나머지 compose default)
make env-check          # 모든 운영 비밀 (prod)
```

---

## 백업 / 복구

### PostgreSQL dump

```bash
docker exec wfp-postgres pg_dump -U wfp wfp | gzip > wfp-$(date +%F).sql.gz
```

### MinIO 데이터

```bash
docker run --rm -v wfp-infra_minio_data:/data alpine \
  tar czf - /data > minio-$(date +%F).tar.gz
```

잡 상태 파일은 컨테이너 아닌 호스트 `~/.wfp/jobs_state.json` (via-host).

---

## 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| 컨테이너 healthcheck 실패 | 기동 직후 / 포트 충돌 | `docker logs wfp-postgres` → `docker compose -f compose.infra.yaml restart postgres` |
| 포트 충돌 (5532/6479/9100/9101/8125) | 다른 로컬 서비스 점유 | `lsof -i :5532` 확인 후 충돌 서비스 정지 또는 compose 포트 변경 |
| Login `HMAC key must not be empty` | `NEXTAUTH_SECRET` / `JWT_SECRET` 빈 값 | `.env` 에 `NEXTAUTH_SECRET=$(openssl rand -base64 32)` + `make restart` |
| HF 다운로드 401 | `HF_TOKEN` 미설정 | `.env` 토큰 추가 + `make restart` |
| Mailpit `exec format error` | 옛 mailhog 멀티아키 깨짐 | `compose.infra.yaml` 이미 `axllent/mailpit` 사용 — 옛 이미지면 `docker rmi mailhog/mailhog` |
| 외부 IP 에서 3000/8000 안 됨 | ufw/iptables 차단 (docker 우회와 별개, 호스트 PM2 라 방화벽 적용) | `sudo ufw allow from <LAN>/24 to any port 3000 proto tcp` |

---

## 보안 권장

- 운영 비밀은 모두 랜덤 (`openssl rand -base64 32`)
- `.env` 절대 커밋 금지 (`.gitignore` 적용)
- `SUPERVISOR_*` 강한 값 필수 — 미설정 시 admin 계정 없음
- 운영에서 `NEXT_PUBLIC_AUTH_DISABLED=true` 절대 금지
- MinIO 는 운영에서 외부 S3(AWS / Cloudflare R2) 로 교체 권장
- TLS/도메인은 호스트 리버스 프록시(nginx/Caddy/Traefik)로 별도 구성 — compose 책임 아님
