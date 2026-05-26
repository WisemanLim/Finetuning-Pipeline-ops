#!/usr/bin/env bash
# Host process cleanup — separate script to avoid pkill matching bash command line.
# bash -c with inline pkill 패턴 사용 시 pkill -f가 자기 부모 bash argv를 매칭 → make Terminated.
# 이 스크립트는 argv에 패턴 문자열 없음 → 안전.

set -u

echo "→ PM2 앱 삭제 + daemon kill (자동 재시작 차단)"
pm2 delete all 2>/dev/null || true
pm2 save --force >/dev/null 2>&1 || true
pm2 kill 2>/dev/null || true

echo "→ 잔여 프로세스 정리 (uvicorn / next-server / next)"
for pat in \
  "uvicorn wfp_worker.server" \
  "next-server" \
  "node.*next/dist/bin/next"; do
  pkill -TERM -f "$pat" 2>/dev/null || true
done

sleep 1

echo "→ 포트 점유 정리 (8000, 3000)"
for port in 8000 3000; do
  pids=$(lsof -ti ":$port" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "  포트 $port 점유 PID $pids → SIGTERM"
    kill $pids 2>/dev/null || true
    sleep 1
    pids2=$(lsof -ti ":$port" 2>/dev/null || true)
    if [ -n "$pids2" ]; then
      echo "  포트 $port 잔여 PID $pids2 → SIGKILL"
      kill -9 $pids2 2>/dev/null || true
    fi
  fi
done

# multiprocessing 자식 (uvicorn workers=2가 fork)
pkill -9 -f "multiprocessing.spawn" 2>/dev/null || true
pkill -9 -f "multiprocessing.resource_tracker" 2>/dev/null || true

echo "✓ 호스트 프로세스 + PM2 daemon 정리 완료"
exit 0
