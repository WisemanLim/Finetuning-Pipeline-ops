/**
 * PM2 ecosystem — worker / web (dev/prod 변형).
 *
 * Makefile이 환경변수로 경로 주입:
 *   WORKER_DIR        — Finetuning-Pipeline-worker 절대경로
 *   FRONTEND_DIR      — Finetuning-Pipeline-frontend 절대경로
 *   HOST_LOG_DIR      — PM2 로그 출력 디렉토리
 *
 * 사용:
 *   pm2 start scripts/ecosystem.config.cjs --only wfp-worker-dev,wfp-web-dev
 *   pm2 start scripts/ecosystem.config.cjs --only wfp-worker-prod,wfp-web-prod
 *   pm2 list
 *   pm2 logs wfp-worker-dev
 *   pm2 delete all
 */

const path = require("path");

const workerDir = process.env.WORKER_DIR;
const frontendDir = process.env.FRONTEND_DIR;
const logDir = process.env.HOST_LOG_DIR || "./.host-logs";
// ops/docker/.env — Makefile env-check가 검증한 SUPERVISOR_ID/PASSWORD 등 위치
const opsDockerEnv = path.join(__dirname, "..", "docker", ".env");

if (!workerDir || !frontendDir) {
  console.error("WORKER_DIR / FRONTEND_DIR 환경 변수 미설정");
}

// worker: docker/.env (운영 비밀) + WORKER_DIR/.env (로컬 override) 순으로 로드
// PATH에 시스템 bin 보장 — nvidia-smi (/usr/bin), pynvml 등 외부 명령 접근
const workerScript = (uvicornArgs) =>
  `export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/cuda/bin:$PATH"; ` +
  `set -a; ` +
  `[ -f "${opsDockerEnv}" ] && source "${opsDockerEnv}"; ` +
  `[ -f .env ] && source .env; ` +
  `set +a; ` +
  `exec .venv/bin/uvicorn wfp_worker.server:app --host 0.0.0.0 --port 8000 ${uvicornArgs}`;

// web: docker/.env (NEXTAUTH_*, NEXT_PUBLIC_*) + FRONTEND_DIR/.env.local 순
const webScript = (cmd) =>
  `set -a; ` +
  `[ -f "${opsDockerEnv}" ] && source "${opsDockerEnv}"; ` +
  `[ -f .env.local ] && source .env.local; ` +
  `set +a; ` +
  `exec ${cmd}`;

module.exports = {
  apps: [
    // -------------------------------------------------------------------------
    // Worker (FastAPI) — dev: --reload, prod: --workers 1
    // workers=2 사용 시 in-memory _jobs dict가 프로세스마다 분리 → 잡 목록 flicker.
    // -------------------------------------------------------------------------
    {
      name: "wfp-worker-dev",
      cwd: workerDir,
      script: "/bin/bash",
      args: ["-c", workerScript("--reload")],
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s",
      out_file: `${logDir}/worker.log`,
      error_file: `${logDir}/worker.error.log`,
      merge_logs: true,
      time: true,
    },
    {
      name: "wfp-worker-prod",
      cwd: workerDir,
      script: "/bin/bash",
      args: ["-c", workerScript("--workers 1")],
      autorestart: true,
      max_restarts: 10,
      min_uptime: "30s",
      out_file: `${logDir}/worker.log`,
      error_file: `${logDir}/worker.error.log`,
      merge_logs: true,
      time: true,
    },

    // -------------------------------------------------------------------------
    // Web (Next.js) — dev: pnpm dev, prod: pnpm start (build는 Makefile에서 사전)
    // -------------------------------------------------------------------------
    {
      name: "wfp-web-dev",
      cwd: frontendDir,
      script: "/bin/bash",
      args: ["-c", webScript("pnpm dev")],
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s",
      out_file: `${logDir}/web.log`,
      error_file: `${logDir}/web.error.log`,
      merge_logs: true,
      time: true,
    },
    {
      name: "wfp-web-prod",
      cwd: frontendDir,
      script: "/bin/bash",
      args: ["-c", webScript("pnpm start")],
      autorestart: true,
      max_restarts: 10,
      min_uptime: "30s",
      out_file: `${logDir}/web.log`,
      error_file: `${logDir}/web.error.log`,
      merge_logs: true,
      time: true,
    },
  ],
};
