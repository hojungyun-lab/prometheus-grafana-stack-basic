#!/bin/bash
# =============================================================================
# 데이터 시뮬레이터 - 유동적 시스템 부하 생성
# =============================================================================
# 이 스크립트는 CPU, 메모리, 디스크 I/O 부하를 유동적으로 생성하여
# Node Exporter가 수집하는 메트릭이 실시간으로 변화하도록 합니다.
#
# 지원 모드:
#   normal  - 일반적인 서버 부하 시뮬레이션 (낮은~중간 부하)
#   spike   - 주기적으로 급격한 부하 스파이크 발생
#   gradual - 점진적으로 부하가 증가했다가 감소 (물결 패턴)
#   chaos   - 예측 불가능한 랜덤 부하 (카오스 엔지니어링)
#
# 환경 변수:
#   SIMULATOR_MODE     - 시뮬레이션 모드 (기본값: normal)
#   SIMULATOR_INTERVAL - 부하 변경 간격/초 (기본값: 30)
# =============================================================================

MODE="${SIMULATOR_MODE:-normal}"
INTERVAL="${SIMULATOR_INTERVAL:-30}"
CYCLE=0

echo "[SIMULATOR] Mode: ${MODE}, Interval: ${INTERVAL}s"

# -----------------------------------------------------------------------------
# 유틸리티 함수
# -----------------------------------------------------------------------------

# 범위 내 랜덤 정수 생성
random_between() {
    local min=$1 max=$2
    echo $(( RANDOM % (max - min + 1) + min ))
}

# 이전 부하 프로세스 정리
cleanup_load() {
    pkill -f "stress-ng" 2>/dev/null || true
    # 임시 파일 정리
    rm -f /tmp/simulator_*.tmp 2>/dev/null || true
}

# CPU 부하 생성
generate_cpu_load() {
    local cores=$1
    local duration=$2
    local load_percent=$3

    echo "[SIMULATOR] CPU: ${cores} cores, ${load_percent}% load for ${duration}s"
    stress-ng --cpu "${cores}" --cpu-load "${load_percent}" \
              --timeout "${duration}s" --quiet &
}

# 메모리 부하 생성
generate_memory_load() {
    local mb=$1
    local duration=$2

    echo "[SIMULATOR] Memory: allocating ${mb}MB for ${duration}s"
    stress-ng --vm 1 --vm-bytes "${mb}M" --vm-hang "${duration}" \
              --timeout "${duration}s" --quiet &
}

# 디스크 I/O 부하 생성
generate_disk_load() {
    local size_mb=$1
    local duration=$2

    echo "[SIMULATOR] Disk I/O: ${size_mb}MB write for ${duration}s"
    stress-ng --hdd 1 --hdd-bytes "${size_mb}M" \
              --timeout "${duration}s" --quiet &
}

# -----------------------------------------------------------------------------
# 시뮬레이션 패턴
# -----------------------------------------------------------------------------

# Normal 모드: 일반적인 서버 워크로드
simulate_normal() {
    local cpu_cores
    local cpu_load
    local mem_mb
    local duration

    cpu_cores=$(random_between 1 2)
    cpu_load=$(random_between 10 40)
    mem_mb=$(random_between 32 128)
    duration=$(random_between 15 45)

    generate_cpu_load "${cpu_cores}" "${duration}" "${cpu_load}"
    generate_memory_load "${mem_mb}" "${duration}"

    # 30% 확률로 디스크 I/O 추가
    if [ $(random_between 1 10) -le 3 ]; then
        generate_disk_load "$(random_between 5 20)" "${duration}"
    fi
}

# Spike 모드: 갑작스러운 부하 스파이크
simulate_spike() {
    local phase
    phase=$(( CYCLE % 4 ))

    case ${phase} in
        0|1)
            # 평상시 (낮은 부하)
            echo "[SIMULATOR] Spike phase: idle"
            generate_cpu_load 1 "${INTERVAL}" "$(random_between 5 15)"
            generate_memory_load "$(random_between 16 48)" "${INTERVAL}"
            ;;
        2)
            # 스파이크! (높은 부하)
            echo "[SIMULATOR] 🔥 SPIKE! High load burst!"
            generate_cpu_load "$(random_between 2 4)" "${INTERVAL}" "$(random_between 70 95)"
            generate_memory_load "$(random_between 128 256)" "${INTERVAL}"
            generate_disk_load "$(random_between 20 50)" "${INTERVAL}"
            ;;
        3)
            # 회복 (중간 부하)
            echo "[SIMULATOR] Spike phase: recovering"
            generate_cpu_load 1 "${INTERVAL}" "$(random_between 20 40)"
            generate_memory_load "$(random_between 48 96)" "${INTERVAL}"
            ;;
    esac
}

# Gradual 모드: 점진적 증가/감소 (사인파 패턴)
simulate_gradual() {
    local steps=10
    local phase
    phase=$(( CYCLE % steps ))

    # 0→5: 증가, 5→10: 감소 (삼각형 패턴)
    local level
    if [ "${phase}" -lt 5 ]; then
        level=$(( phase * 18 + 10 ))      # 10, 28, 46, 64, 82
    else
        level=$(( (steps - phase) * 18 + 10 ))  # 82, 64, 46, 28, 10
    fi

    local mem_level=$(( level * 2 + 16 ))

    echo "[SIMULATOR] Gradual: level=${level}%, cycle=${CYCLE}"
    generate_cpu_load "$(random_between 1 3)" "${INTERVAL}" "${level}"
    generate_memory_load "${mem_level}" "${INTERVAL}"

    # 상위 레벨에서 디스크 I/O 추가
    if [ "${level}" -gt 50 ]; then
        generate_disk_load "$(random_between 10 30)" "${INTERVAL}"
    fi
}

# Chaos 모드: 완전 랜덤
simulate_chaos() {
    echo "[SIMULATOR] 🎲 Chaos mode: unpredictable load!"

    local cpu_cores
    local cpu_load
    local mem_mb
    local duration

    cpu_cores=$(random_between 1 4)
    cpu_load=$(random_between 5 95)
    mem_mb=$(random_between 16 256)
    duration=$(random_between 5 60)

    generate_cpu_load "${cpu_cores}" "${duration}" "${cpu_load}"

    # 70% 확률로 메모리 부하
    if [ $(random_between 1 10) -le 7 ]; then
        generate_memory_load "${mem_mb}" "${duration}"
    fi

    # 40% 확률로 디스크 I/O
    if [ $(random_between 1 10) -le 4 ]; then
        generate_disk_load "$(random_between 5 50)" "${duration}"
    fi
}

# -----------------------------------------------------------------------------
# 메인 루프
# -----------------------------------------------------------------------------

trap "cleanup_load; echo '[SIMULATOR] Stopped.'; exit 0" SIGTERM SIGINT

echo "[SIMULATOR] Starting simulation loop..."

while true; do
    # 이전 부하 정리
    cleanup_load
    sleep 1

    echo ""
    echo "[SIMULATOR] ──────────────── Cycle #${CYCLE} ────────────────"

    case "${MODE}" in
        normal)  simulate_normal   ;;
        spike)   simulate_spike    ;;
        gradual) simulate_gradual  ;;
        chaos)   simulate_chaos    ;;
        *)
            echo "[SIMULATOR] Unknown mode: ${MODE}, falling back to normal"
            simulate_normal
            ;;
    esac

    CYCLE=$(( CYCLE + 1 ))

    # 대기
    sleep "${INTERVAL}"
done
