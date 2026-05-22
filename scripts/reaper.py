#!/usr/bin/env python3
"""
WFP Reaper — 자원 회수 스탠드얼론 스크립트.

Docker Compose cron 사이드카 또는 직접 실행.

동작:
  1. jobs_state.json 읽기 — heartbeat 타임아웃된 RUNNING 잡 FAILED 처리
  2. 디스크 80% 초과 시 오래된 체크포인트 삭제
  3. 결과를 stdout + /data/reaper.log에 기록

환경 변수:
  WFP_HEARTBEAT_TIMEOUT_MIN  기본 30 (분)
  WFP_DISK_THRESHOLD_PCT     기본 80 (%)
  WFP_DATA_DIR               기본 /data (없으면 ~/.wfp)
"""
from __future__ import annotations

import json
import logging
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path

logging.basicConfig(
    format="%(asctime)s [reaper] %(levelname)s %(message)s",
    level=logging.INFO,
)
log = logging.getLogger("reaper")

HEARTBEAT_TIMEOUT_MIN = int(os.environ.get("WFP_HEARTBEAT_TIMEOUT_MIN", "30"))
DISK_THRESHOLD_PCT = float(os.environ.get("WFP_DISK_THRESHOLD_PCT", "80"))
DATA_DIR = Path(os.environ.get("WFP_DATA_DIR", "/data" if Path("/data").exists() else str(Path.home() / ".wfp")))
STATE_PATH = DATA_DIR / "jobs_state.json"
LOG_PATH = DATA_DIR / "reaper.log"

TERMINAL_STATES = {"DONE", "FAILED", "CANCELLED"}


def load_state() -> dict:
    if not STATE_PATH.exists():
        log.info("jobs_state.json 없음 — 종료")
        return {}
    return json.loads(STATE_PATH.read_text(encoding="utf-8"))


def save_state(data: dict) -> None:
    tmp = STATE_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, default=str), encoding="utf-8")
    tmp.replace(STATE_PATH)


def reap_timed_out_jobs(jobs: dict) -> list[str]:
    """heartbeat_timeout_min 이상 RUNNING/EVAL 상태인 잡 → FAILED."""
    now = datetime.now(timezone.utc)
    changed = []
    for jid, spec in jobs.items():
        state = spec.get("state", "")
        if state not in ("RUNNING", "EVAL"):
            continue
        created_raw = spec.get("created_at")
        if not created_raw:
            continue
        try:
            created = datetime.fromisoformat(str(created_raw))
            if created.tzinfo is None:
                created = created.replace(tzinfo=timezone.utc)
        except ValueError:
            continue
        elapsed_min = (now - created).total_seconds() / 60
        if elapsed_min > HEARTBEAT_TIMEOUT_MIN:
            spec["state"] = "FAILED"
            spec["error_message"] = f"Reaper: heartbeat timeout ({HEARTBEAT_TIMEOUT_MIN}min, elapsed {elapsed_min:.1f}min)"
            changed.append(jid)
            log.info(f"job {jid} FAILED (timeout {elapsed_min:.1f}min)")
    return changed


def reap_checkpoints(jobs: dict) -> tuple[int, float]:
    """디스크 임계치 초과 시 완료된 잡의 오래된 체크포인트 삭제."""
    ckpt_dir = DATA_DIR / "checkpoints"
    if not ckpt_dir.exists():
        return 0, 0.0

    total, used, _ = shutil.disk_usage(DATA_DIR)
    used_pct = used / total * 100 if total else 0
    if used_pct <= DISK_THRESHOLD_PCT:
        log.info(f"디스크 {used_pct:.1f}% — 임계치 미달, 회수 불필요")
        return 0, 0.0

    log.info(f"디스크 {used_pct:.1f}% > {DISK_THRESHOLD_PCT}% — 체크포인트 회수 시작")
    active_states = {"RUNNING", "EVAL", "PENDING"}
    active_jobs = {jid for jid, s in jobs.items() if s.get("state") in active_states}

    entries = sorted(ckpt_dir.iterdir(), key=lambda p: p.stat().st_mtime)
    purged, freed_mb = 0, 0.0
    half = max(1, len(entries) // 2)
    for ckpt in entries[:half]:
        if ckpt.name in active_jobs:
            continue
        size_mb = sum(f.stat().st_size for f in ckpt.rglob("*") if f.is_file()) / 1024 / 1024
        shutil.rmtree(ckpt, ignore_errors=True)
        purged += 1
        freed_mb += size_mb
        log.info(f"체크포인트 {ckpt.name} 삭제 ({size_mb:.1f}MB)")

    return purged, freed_mb


def main() -> None:
    log.info(f"=== Reaper 시작 | timeout={HEARTBEAT_TIMEOUT_MIN}min | disk_threshold={DISK_THRESHOLD_PCT}% ===")

    data = load_state()
    jobs = data.get("jobs", {})

    timed_out = reap_timed_out_jobs(jobs)
    purged, freed_mb = reap_checkpoints(jobs)

    if timed_out or purged:
        data["jobs"] = jobs
        save_state(data)

    summary = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "jobs_failed": len(timed_out),
        "checkpoints_purged": purged,
        "disk_freed_mb": round(freed_mb, 2),
        "timed_out_jobs": timed_out,
    }
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(summary, ensure_ascii=False) + "\n")

    log.info(f"=== Reaper 완료 | {summary} ===")


if __name__ == "__main__":
    main()
