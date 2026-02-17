# Step 09: Custom Exporter 개발

## 📌 이 단계에서 배우는 것
- Exporter 개발 원리
- Python `prometheus_client` 라이브러리 사용법
- Counter, Gauge, Histogram, Summary, Info 직접 구현
- Docker 컨테이너로 패키징
- Prometheus에 등록 및 확인

---

## 1. Exporter 개발 원리

Exporter는 단순히 **HTTP 엔드포인트에 Prometheus 텍스트 포맷으로 메트릭을 노출**하는 프로그램입니다.

```
┌──────────────────────────────┐
│     Custom Exporter          │
│                              │
│  1. 메트릭 정의              │
│  2. 비즈니스 로직 실행        │     GET /metrics
│  3. 메트릭 값 갱신            │ ◄───────────────── Prometheus
│  4. /metrics 에 노출          │ ──────────────────►
│                              │     텍스트 응답
└──────────────────────────────┘
```

**Prometheus 텍스트 포맷 예시:**
```
# HELP app_requests_total Total number of requests processed
# TYPE app_requests_total counter
app_requests_total{method="GET",endpoint="/api/users",status="200"} 1547
app_requests_total{method="POST",endpoint="/api/orders",status="500"} 23
```

---

## 2. Python prometheus_client 라이브러리

### 설치

```bash
pip install prometheus_client
```

### 메트릭 타입별 사용법

#### Counter — 단조 증가 메트릭

```python
from prometheus_client import Counter

# 정의
REQUEST_COUNT = Counter(
    'app_requests_total',              # 메트릭 이름
    'Total number of requests',        # 설명 (HELP)
    ['method', 'endpoint', 'status']   # 레이블
)

# 사용
REQUEST_COUNT.labels(method='GET', endpoint='/api/users', status='200').inc()     # 1 증가
REQUEST_COUNT.labels(method='POST', endpoint='/api/orders', status='201').inc(3)  # 3 증가
```

#### Gauge — 증감 가능 메트릭

```python
from prometheus_client import Gauge

ACTIVE_USERS = Gauge(
    'app_active_users',
    'Number of currently active users'
)

# 사용
ACTIVE_USERS.set(42)         # 값 직접 설정
ACTIVE_USERS.inc()           # 1 증가
ACTIVE_USERS.dec(5)          # 5 감소
```

#### Histogram — 분포 측정

```python
from prometheus_client import Histogram

REQUEST_DURATION = Histogram(
    'app_request_duration_seconds',
    'Request duration in seconds',
    ['method', 'endpoint'],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
)

# 사용
REQUEST_DURATION.labels(method='GET', endpoint='/api/users').observe(0.125)

# 데코레이터로 자동 측정
@REQUEST_DURATION.labels(method='GET', endpoint='/api/users').time()
def process_request():
    # 실제 로직
    pass
```

#### Summary — 분위수 계산

```python
from prometheus_client import Summary

RESPONSE_SIZE = Summary(
    'app_response_size_bytes',
    'Response size in bytes',
    ['endpoint']
)

RESPONSE_SIZE.labels(endpoint='/api/users').observe(1024)
```

#### Info — 정적 정보

```python
from prometheus_client import Info

APP_INFO = Info('app', 'Application information')
APP_INFO.info({
    'version': '1.2.3',
    'build': '2024-01-15',
    'environment': 'production'
})
```

---

## 3. 학습 환경 Custom Exporter 분석

`custom-exporter/app_exporter.py`의 핵심 구조:

```python
from prometheus_client import start_http_server, Counter, Gauge, Histogram

# 1. 메트릭 정의
REQUEST_COUNT = Counter('app_requests_total', '...', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('app_request_duration_seconds', '...', ['method', 'endpoint'])
ACTIVE_USERS = Gauge('app_active_users', '...')
ERROR_RATE = Gauge('app_error_rate', '...')

# 2. 시뮬레이션 로직
def simulate_request():
    endpoint = random.choice(ENDPOINTS)
    duration = random.gauss(endpoint['avg_duration'], ...)
    status = '200' if random.random() < 0.85 else '500'

    REQUEST_COUNT.labels(method=..., endpoint=..., status=status).inc()
    REQUEST_DURATION.labels(method=..., endpoint=...).observe(duration)

# 3. HTTP 서버 시작
if __name__ == '__main__':
    start_http_server(8000)      # /metrics 엔드포인트 노출
    simulation_loop()             # 무한 루프로 시뮬레이션
```

---

## 4. 직접 만들어 보기 (실습)

### 간단한 웹 요청 카운터

```python
"""simple_exporter.py - 최소 Custom Exporter"""
from prometheus_client import start_http_server, Counter, Gauge
import random
import time

# 메트릭 정의
HELLO_COUNT = Counter('hello_total', 'Number of hello messages')
TEMPERATURE = Gauge('room_temperature_celsius', 'Current room temperature')

if __name__ == '__main__':
    start_http_server(8001)  # :8001/metrics
    print("Exporter running on :8001")

    while True:
        HELLO_COUNT.inc()
        TEMPERATURE.set(20 + random.uniform(-3, 5))
        time.sleep(5)
```

```bash
# 실행
python simple_exporter.py

# 확인
curl http://localhost:8001/metrics
```

---

## 5. Docker로 패키징

### Dockerfile

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app_exporter.py .
EXPOSE 8000
CMD ["python", "app_exporter.py"]
```

### 빌드 및 실행

```bash
docker build -t my-exporter custom-exporter/
docker run -p 8000:8000 my-exporter
```

---

## 6. Prometheus에 등록

`prometheus.yml`에 새 job 추가:

```yaml
scrape_configs:
  - job_name: "custom-exporter"
    static_configs:
      - targets: ["custom-exporter:8000"]
    scrape_interval: 10s
```

설정 리로드:
```bash
curl -X POST http://localhost:9090/-/reload
```

확인:
1. `http://localhost:9090/targets` → `custom-exporter` UP 확인
2. Graph 탭에서 `app_requests_total` 쿼리 실행

---

## 핵심 정리

| 메트릭 타입 | Python 클래스 | 적합한 데이터 |
|------------|--------------|-------------|
| Counter | `Counter` | 누적 요청/에러 수 |
| Gauge | `Gauge` | 현재 사용자/온도/큐크기 |
| Histogram | `Histogram` | 응답시간/크기 분포 |
| Summary | `Summary` | 분위수 계산 |
| Info | `Info` | 버전/환경 정보 |

---

## 다음 단계

👉 [Step 10: Service Discovery](./10_service_discovery.md) — 동적으로 모니터링 타깃을 관리합니다.
