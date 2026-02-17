#!/bin/bash
# =============================================================================
# Ubuntu Target 컨테이너 엔트리포인트
# =============================================================================
# 1. Node Exporter 시작 (백그라운드)
# 2. Data Simulator 시작 (백그라운드)
# 3. 프로세스 유지
# =============================================================================

set -e

echo "=============================================="
echo " Ubuntu Target Server Starting..."
echo "=============================================="

# Node Exporter 시작 (백그라운드)
echo "[INFO] Starting Node Exporter on :9100..."
/usr/local/bin/node_exporter \
    --web.listen-address=":9100" \
    --collector.filesystem.mount-points-exclude="^/(sys|proc|dev|host|etc)($$|/)" \
    &
NODE_EXPORTER_PID=$!
echo "[INFO] Node Exporter started (PID: ${NODE_EXPORTER_PID})"

# Node Exporter가 준비될 때까지 대기
sleep 2

# Data Simulator 시작 (백그라운드)
echo "[INFO] Starting Data Simulator (mode: ${SIMULATOR_MODE}, interval: ${SIMULATOR_INTERVAL}s)..."
/usr/local/bin/data-simulator.sh &
SIMULATOR_PID=$!
echo "[INFO] Data Simulator started (PID: ${SIMULATOR_PID})"

echo "=============================================="
echo " All services started successfully!"
echo " Node Exporter: http://localhost:9100/metrics"
echo " Simulator Mode: ${SIMULATOR_MODE}"
echo "=============================================="

# 시그널 핸들링
trap "echo '[INFO] Shutting down...'; kill ${NODE_EXPORTER_PID} ${SIMULATOR_PID} 2>/dev/null; exit 0" SIGTERM SIGINT

# 프로세스 유지 (Node Exporter가 종료되면 컨테이너도 종료)
wait ${NODE_EXPORTER_PID}
