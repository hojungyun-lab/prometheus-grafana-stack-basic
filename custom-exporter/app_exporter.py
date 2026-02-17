"""
=============================================================================
Custom Prometheus Exporter - 비즈니스 메트릭 수집기
=============================================================================
이 스크립트는 Python prometheus_client 라이브러리를 사용하여
가상의 애플리케이션 메트릭을 생성합니다.

메트릭:
  - app_requests_total      (Counter)   - 총 요청 수
  - app_request_duration_seconds (Histogram) - 요청 처리 시간
  - app_active_users        (Gauge)     - 현재 활성 사용자 수
  - app_error_rate           (Gauge)     - 현재 에러율
  - app_items_in_queue       (Gauge)     - 큐에 대기 중인 작업 수
  - app_info                 (Info)      - 애플리케이션 정보

접속: http://localhost:8000/metrics
=============================================================================
"""

import random
import time
import threading
import math
from datetime import datetime

from prometheus_client import (
    start_http_server,
    Counter,
    Gauge,
    Histogram,
    Info,
    Summary,
)

# =============================================================================
# 메트릭 정의
# =============================================================================

# Counter: 단조 증가하는 값 (절대로 감소하지 않음)
# → 총 요청 수, 총 에러 수 등에 사용
REQUEST_COUNT = Counter(
    "app_requests_total",
    "Total number of requests processed",
    ["method", "endpoint", "status"],
)

# Histogram: 값의 분포를 측정 (버킷별 카운트)
# → 응답 시간, 요청 크기 등에 사용
REQUEST_DURATION = Histogram(
    "app_request_duration_seconds",
    "Request duration in seconds",
    ["method", "endpoint"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0],
)

# Gauge: 증가하거나 감소할 수 있는 값
# → 현재 온도, 활성 사용자 수, 큐 크기 등에 사용
ACTIVE_USERS = Gauge(
    "app_active_users",
    "Number of currently active users",
)

ERROR_RATE = Gauge(
    "app_error_rate",
    "Current error rate (0.0 to 1.0)",
)

ITEMS_IN_QUEUE = Gauge(
    "app_items_in_queue",
    "Number of items waiting in the processing queue",
)

# Summary: Histogram과 유사하지만 quantile을 직접 계산
RESPONSE_SIZE = Summary(
    "app_response_size_bytes",
    "Response size in bytes",
    ["endpoint"],
)

# Info: 정적 정보용 (버전, 빌드 등)
APP_INFO = Info(
    "app",
    "Application information",
)

# =============================================================================
# 시뮬레이션 로직
# =============================================================================

# 가상 엔드포인트 정의
ENDPOINTS = [
    {"path": "/api/users", "methods": ["GET", "POST"], "avg_duration": 0.1},
    {"path": "/api/products", "methods": ["GET"], "avg_duration": 0.15},
    {"path": "/api/orders", "methods": ["GET", "POST", "PUT"], "avg_duration": 0.3},
    {"path": "/api/search", "methods": ["GET"], "avg_duration": 0.5},
    {"path": "/api/upload", "methods": ["POST"], "avg_duration": 1.5},
    {"path": "/health", "methods": ["GET"], "avg_duration": 0.005},
]


def simulate_request():
    """가상 API 요청을 시뮬레이션합니다."""
    endpoint = random.choice(ENDPOINTS)
    method = random.choice(endpoint["methods"])
    path = endpoint["path"]

    # 응답 시간 시뮬레이션 (정규분포 + 가끔 스파이크)
    base_duration = endpoint["avg_duration"]
    if random.random() < 0.05:  # 5% 확률로 느린 응답
        duration = base_duration * random.uniform(5, 20)
    else:
        duration = max(0.001, random.gauss(base_duration, base_duration * 0.3))

    # 상태 코드 결정
    rand_val = random.random()
    if rand_val < 0.85:
        status = "200"
    elif rand_val < 0.92:
        status = "201"
    elif rand_val < 0.96:
        status = "400"
    elif rand_val < 0.98:
        status = "404"
    elif rand_val < 0.995:
        status = "500"
    else:
        status = "503"

    # 메트릭 기록
    REQUEST_COUNT.labels(method=method, endpoint=path, status=status).inc()
    REQUEST_DURATION.labels(method=method, endpoint=path).observe(duration)

    # 응답 크기 기록
    response_size = random.randint(128, 65536)
    RESPONSE_SIZE.labels(endpoint=path).observe(response_size)


def simulate_active_users():
    """활성 사용자 수를 시간대별로 시뮬레이션합니다."""
    hour = datetime.now().hour

    # 시간대별 기본 사용자 수 (사인파 패턴 + 랜덤)
    base_users = 30 + 25 * math.sin(math.pi * hour / 12)
    noise = random.gauss(0, 5)
    users = max(1, int(base_users + noise))

    ACTIVE_USERS.set(users)


def simulate_error_rate():
    """에러율을 시뮬레이션합니다."""
    # 기본 에러율 1~3%
    base_rate = random.uniform(0.01, 0.03)

    # 가끔 에러 스파이크 (10% 확률)
    if random.random() < 0.1:
        base_rate += random.uniform(0.05, 0.15)

    ERROR_RATE.set(min(1.0, base_rate))


def simulate_queue():
    """큐 대기 항목을 시뮬레이션합니다."""
    # 랜덤 워크 패턴
    current = ITEMS_IN_QUEUE._value.get() if hasattr(ITEMS_IN_QUEUE, "_value") else 10
    change = random.randint(-5, 7)
    new_val = max(0, int(current + change))

    ITEMS_IN_QUEUE.set(new_val)


def simulation_loop():
    """메인 시뮬레이션 루프"""
    # 초기 앱 정보 설정
    APP_INFO.info({
        "version": "1.2.3",
        "build": "2024-01-15",
        "environment": "learning-lab",
        "language": "python",
    })

    ITEMS_IN_QUEUE.set(10)

    print("[Exporter] Simulation loop started")

    while True:
        # 1초당 5~20개의 요청 시뮬레이션
        requests_this_second = random.randint(5, 20)
        for _ in range(requests_this_second):
            simulate_request()

        # 10초마다 게이지 메트릭 업데이트
        simulate_active_users()
        simulate_error_rate()
        simulate_queue()

        time.sleep(1)


# =============================================================================
# 메인 엔트리포인트
# =============================================================================

if __name__ == "__main__":
    port = 8000
    print(f"[Exporter] Starting Custom Prometheus Exporter on :{port}")
    print(f"[Exporter] Metrics available at http://localhost:{port}/metrics")

    # Prometheus HTTP 서버 시작 (메트릭 엔드포인트 제공)
    start_http_server(port)

    # 시뮬레이션 루프 실행
    simulation_loop()
