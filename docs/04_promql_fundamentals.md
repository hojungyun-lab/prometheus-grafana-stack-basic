# Step 04: PromQL 기초

## 📌 이 단계에서 배우는 것
- PromQL 기본 문법 (Selector, Label Matcher)
- Instant Vector vs Range Vector
- 핵심 함수 (`rate()`, `increase()`, `sum()`, `avg()`)
- 집계 연산자 (`by`, `without`)
- 15개 실습 예제

---

## 1. PromQL이란?

**PromQL (Prometheus Query Language)**은 Prometheus에서 시계열 데이터를 조회하고 분석하기 위한 함수형 쿼리 언어입니다.

사용 위치:
- Prometheus Web UI (`Graph` 탭)
- Grafana 패널의 Data Source 쿼리
- Alert Rule 조건
- Recording Rule 정의
- HTTP API (`/api/v1/query`)

---

## 2. 기본 문법

### 2.1 Selector (메트릭 선택)

```promql
# 메트릭명만으로 선택 (모든 레이블 조합 반환)
node_cpu_seconds_total

# 레이블로 필터링
node_cpu_seconds_total{mode="idle"}

# 복수 레이블 필터링 (AND 조건)
node_cpu_seconds_total{mode="idle", cpu="0"}
```

### 2.2 Label Matcher (레이블 매칭)

| 매쳐 | 의미 | 예시 |
|------|------|------|
| `=` | 정확히 일치 | `{mode="idle"}` |
| `!=` | 일치하지 않음 | `{mode!="idle"}` |
| `=~` | 정규표현식 일치 | `{mode=~"idle\|user"}` |
| `!~` | 정규표현식 불일치 | `{device!~"lo\|veth.*"}` |

```promql
# idle 모드 제외
node_cpu_seconds_total{mode!="idle"}

# user 또는 system 모드만
node_cpu_seconds_total{mode=~"user|system"}

# lo(loopback), veth(가상) 인터페이스 제외
node_network_receive_bytes_total{device!~"lo|veth.*"}
```

---

## 3. Vector 타입

### 3.1 Instant Vector (즉시 벡터)

현재 시점의 단일 값을 반환합니다.

```promql
# 현재 메모리 사용 가능량
node_memory_MemAvailable_bytes

# 결과: 하나의 값
# node_memory_MemAvailable_bytes{instance="..."} 2147483648
```

### 3.2 Range Vector (범위 벡터)

지정된 시간 범위의 값 목록을 반환합니다. `[시간]` 형태로 지정합니다.

```promql
# 최근 5분간의 CPU 사용 데이터 (그래프에서 직접 사용 불가)
node_cpu_seconds_total{mode="idle"}[5m]
```

**시간 단위:**
| 단위 | 의미 |
|------|------|
| `s` | 초 |
| `m` | 분 |
| `h` | 시간 |
| `d` | 일 |
| `w` | 주 |
| `y` | 년 |

> ⚠️ Range Vector는 `rate()`, `increase()` 등의 함수와 함께 사용해야 합니다.

---

## 4. 핵심 함수

### 4.1 rate() — 초당 증가율 (Counter 전용)

Counter 메트릭의 **초당 평균 증가율**을 계산합니다.

```promql
# CPU 초당 사용률 (5분 평균)
rate(node_cpu_seconds_total{mode="idle"}[5m])

# 네트워크 수신 속도 (bytes/s)
rate(node_network_receive_bytes_total{device!="lo"}[5m])

# 디스크 쓰기 속도 (bytes/s)
rate(node_disk_written_bytes_total[5m])
```

> 💡 **rate()는 Counter 메트릭에 가장 많이 사용하는 함수입니다!**
> Counter의 절대값보다 변화율이 훨씬 유용합니다.

### 4.2 increase() — 지정 시간 동안 증가량

```promql
# 최근 1시간 동안 증가한 요청 수
increase(app_requests_total[1h])

# 최근 5분 동안 네트워크 수신 바이트
increase(node_network_receive_bytes_total{device!="lo"}[5m])
```

### 4.3 sum() — 합계

```promql
# 모든 CPU 코어의 idle 시간 합계
sum(rate(node_cpu_seconds_total{mode="idle"}[5m]))

# 모든 인터페이스의 네트워크 수신 속도 합계
sum(rate(node_network_receive_bytes_total{device!="lo"}[5m]))
```

### 4.4 avg() — 평균

```promql
# 모든 CPU 코어의 평균 idle 비율
avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))

# CPU 사용률 (%)
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

### 4.5 min() / max()

```promql
# 가장 사용률이 높은 파일시스템
max(node_filesystem_avail_bytes)

# 가용 메모리 최솟값
min(node_memory_MemAvailable_bytes)
```

### 4.6 count()

```promql
# 수집 중인 타깃 수
count(up)

# 정상(UP) 타깃 수
count(up == 1)
```

---

## 5. 집계 연산자

### 5.1 by — 기준별 집계

```promql
# CPU 모드별 사용률
sum by(mode) (rate(node_cpu_seconds_total[5m]))

# job별 타깃 수
count by(job) (up)

# 인스턴스별 네트워크 수신 속도
sum by(instance) (rate(node_network_receive_bytes_total[5m]))
```

### 5.2 without — 특정 레이블 제외하고 집계

```promql
# cpu 레이블을 제외하고 합계 (= 전체 CPU 합산)
sum without(cpu) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
```

---

## 6. 산술 연산

```promql
# 메모리 사용률 (%)
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100

# 디스크 사용률 (%)
(1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100

# 바이트를 GiB로 변환
node_memory_MemTotal_bytes / 1073741824

# 바이트를 MiB로 변환
node_filesystem_avail_bytes / 1048576
```

---

## 7. 비교 연산

```promql
# CPU 사용률이 80%를 초과하는지 확인
(100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80

# 다운된 타깃 필터링
up == 0

# 디스크 여유 공간이 10GB 미만인 파일시스템
node_filesystem_avail_bytes < 10 * 1024 * 1024 * 1024
```

---

## 8. 실습 예제 (15개)

### 기초 (1~5)

```promql
# 1. 모든 타깃 상태 확인
up

# 2. CPU 사용률 (%)
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# 3. 메모리 사용률 (%)
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# 4. 디스크 사용률 (%)
(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100

# 5. 네트워크 수신 속도 (bytes/s)
rate(node_network_receive_bytes_total{device!="lo"}[5m])
```

### 중급 (6~10)

```promql
# 6. CPU 모드별 비율 (스택 그래프용)
avg by(mode) (rate(node_cpu_seconds_total{mode!="idle"}[5m])) * 100

# 7. 메모리 구성 (Used + Buffers + Cached + Free = Total)
node_memory_MemTotal_bytes - node_memory_MemFree_bytes - node_memory_Buffers_bytes - node_memory_Cached_bytes

# 8. 1시간 동안의 네트워크 총 트래픽 (MB)
increase(node_network_receive_bytes_total{device!="lo"}[1h]) / 1048576

# 9. Custom Exporter 요청 속도 (req/s)
rate(app_requests_total[5m])

# 10. Custom Exporter 엔드포인트별 요청 속도
sum by(endpoint) (rate(app_requests_total[5m]))
```

### 응용 (11~15)

```promql
# 11. 에러 요청만 필터링 (상태 코드 5xx)
sum(rate(app_requests_total{status=~"5.."}[5m]))

# 12. 에러율 계산 (에러요청 / 전체요청)
sum(rate(app_requests_total{status=~"5.."}[5m])) / sum(rate(app_requests_total[5m]))

# 13. Prometheus 자체 스크랩 소요 시간
scrape_duration_seconds{job="node-exporter"}

# 14. 수집 중인 메트릭 수 (job별)
count by(job) ({__name__!=""})

# 15. 시스템 부팅 후 경과 시간 (초)
time() - node_boot_time_seconds
```

---

## 9. 핵심 정리

| 개념 | 설명 |
|------|------|
| **Instant Vector** | 현재 시점의 값 반환 |
| **Range Vector** | 시간 범위의 값 목록 반환, `[5m]` 등 |
| **rate()** | Counter의 초당 변화율 (가장 중요!) |
| **increase()** | 지정 기간 동안 증가량 |
| **sum/avg/min/max** | 집계 함수 |
| **by/without** | 집계 기준 레이블 지정 |

---

## 다음 단계

👉 [Step 05: Grafana 기초 및 UI](./05_grafana_basics.md) — Grafana로 시각화를 시작합니다.
