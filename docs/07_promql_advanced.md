# Step 07: PromQL 고급 쿼리

## 📌 이 단계에서 배우는 것
- 고급 함수 (`histogram_quantile()`, `predict_linear()`, `label_replace()`)
- 서브쿼리와 오프셋
- Binary 연산자 (`and`, `or`, `unless`)
- Recording Rules 작성
- 실전 시나리오 10개

---

## 1. 고급 함수

### 1.1 histogram_quantile() — 분위수 계산

Histogram 메트릭에서 **percentile**을 계산합니다.

```promql
# p50 (중앙값) 응답 시간
histogram_quantile(0.50, rate(app_request_duration_seconds_bucket[5m]))

# p90 응답 시간
histogram_quantile(0.90, rate(app_request_duration_seconds_bucket[5m]))

# p99 응답 시간
histogram_quantile(0.99, rate(app_request_duration_seconds_bucket[5m]))

# 엔드포인트별 p95 응답 시간
histogram_quantile(0.95, sum by(le, endpoint) (rate(app_request_duration_seconds_bucket[5m])))
```

> 💡 `le` 레이블은 반드시 보존해야 합니다. `sum by(le, ...)` 형태로 사용합니다.

### 1.2 predict_linear() — 선형 예측

현재 추세를 기반으로 **미래 값을 예측**합니다.

```promql
# 6시간 추세로 24시간 후 디스크 여유 공간 예측
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 24*3600)

# 1시간 추세로 4시간 후 메모리 여유 공간 예측
predict_linear(node_memory_MemAvailable_bytes[1h], 4*3600)
```

**Alert Rule 활용:**
```promql
# 디스크가 24시간 내에 가득 찰 것으로 예측
predict_linear(node_filesystem_avail_bytes[6h], 24*3600) < 0
```

### 1.3 label_replace() — 레이블 변환

레이블 값을 정규표현식으로 변환합니다.

```promql
# instance 레이블에서 포트 번호 제거
label_replace(up, "clean_instance", "$1", "instance", "(.*):.*")

# job 이름에 접두사 추가
label_replace(up, "service", "svc-$1", "job", "(.*)")
```

### 1.4 absent() — 메트릭 부재 감지

메트릭이 존재하지 않을 때 1을 반환합니다.

```promql
# node_exporter가 메트릭을 보내지 않을 때 감지
absent(up{job="node-exporter"})

# 특정 메트릭이 사라졌는지 확인
absent(node_cpu_seconds_total{job="node-exporter"})
```

### 1.5 changes() — 값 변경 횟수

```promql
# 최근 1시간 동안 에러율이 변경된 횟수
changes(app_error_rate[1h])
```

### 1.6 delta() / idelta() — 값의 변화량 (Gauge 전용)

```promql
# 최근 5분 동안 활성 사용자 수 변화량
delta(app_active_users[5m])

# 최근 메모리 사용량 변화
delta(node_memory_MemAvailable_bytes[10m])
```

### 1.7 deriv() — 미분 (변화 속도)

```promql
# 메모리 사용량의 변화 속도 (bytes/s)
deriv(node_memory_MemAvailable_bytes[15m])
```

---

## 2. 서브쿼리

서브쿼리는 Instant 함수에 Range Vector를 전달할 때 사용합니다.

```promql
# 최근 30분 동안 5분 간격으로 계산된 CPU 사용률의 최댓값
max_over_time(
  (100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)[30m:5m]
)

# 최근 1시간 동안 에러율의 최댓값
max_over_time(app_error_rate[1h:1m])

# 최근 6시간 동안 활성 사용자의 평균
avg_over_time(app_active_users[6h:5m])
```

**구문:** `metric[전체범위:해상도]`

---

## 3. 오프셋 (Offset)

과거 시점의 데이터와 비교할 때 사용합니다.

```promql
# 1시간 전 CPU 사용률
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m] offset 1h)) * 100)

# 현재 vs 1시간 전 요청 수 비교
rate(app_requests_total[5m]) / rate(app_requests_total[5m] offset 1h)

# 24시간 전 대비 메모리 사용량 변화
node_memory_MemAvailable_bytes - node_memory_MemAvailable_bytes offset 24h
```

---

## 4. Binary 연산자

### 집합 연산

| 연산자 | 설명 |
|--------|------|
| `and` | 양쪽 모두 존재하는 시계열만 반환 |
| `or` | 합집합 |
| `unless` | 왼쪽에만 존재하는 시계열 반환 (차집합) |

```promql
# CPU 사용률이 80% 이상이면서 (AND) 메모리도 고사용인 인스턴스
(instance:node_cpu_utilization:avg_rate5m > 80)
and
(instance:node_memory_utilization:ratio > 80)

# 정상 타깃 OR 다운 타깃 (전체)
up == 1 or up == 0

# Node Exporter 메트릭 중 Custom Exporter에 없는 것
{job="node-exporter"} unless {job="custom-exporter"}
```

### Vector Matching

```promql
# on() — 특정 레이블 기준으로 매칭
sum by(instance) (rate(node_cpu_seconds_total[5m]))
  / on(instance)
count by(instance) (node_cpu_seconds_total{mode="idle"})

# ignoring() — 특정 레이블 무시하고 매칭
sum by(instance, mode) (rate(node_cpu_seconds_total[5m]))
```

---

## 5. Recording Rules

Recording Rules는 **복잡한 쿼리를 사전 계산**하여 새로운 시계열로 저장합니다.

### 목적
- 대시보드 로딩 속도 향상
- 쿼리 중복 제거
- Alert Rule에서의 사용 최적화

### 작성 예시 (prometheus/recording-rules.yml)

```yaml
groups:
  - name: cpu_recording_rules
    interval: 15s
    rules:
      # 이 쿼리 결과가 새로운 메트릭으로 저장됨
      - record: instance:node_cpu_utilization:avg_rate5m
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

      # 이후 대시보드/Alert에서 이렇게 사용:
      # instance:node_cpu_utilization:avg_rate5m
```

### 이름 규칙 (Convention)

```
level:metric_name:operations
```

| 부분 | 설명 | 예시 |
|------|------|------|
| level | 집계 수준 | `instance`, `job`, `cluster` |
| metric_name | 원본 메트릭 출처 | `node_cpu`, `node_memory` |
| operations | 적용된 연산 | `avg_rate5m`, `ratio` |

---

## 6. 실전 시나리오 10개

### 시나리오 1: SLI — 가용성

```promql
# 서비스 가용률 (성공 요청 / 전체 요청)
sum(rate(app_requests_total{status=~"2.."}[1h])) /
sum(rate(app_requests_total[1h]))
```

### 시나리오 2: SLI — 지연 시간 SLO

```promql
# p99 응답 시간이 500ms 이내인지 (SLO: p99 < 500ms)
histogram_quantile(0.99, rate(app_request_duration_seconds_bucket[5m])) < 0.5
```

### 시나리오 3: Error Budget 소모율

```promql
# SLO 99.9% 기준 에러 예산 소모율
(1 - (sum(rate(app_requests_total{status=~"2.."}[1h])) / sum(rate(app_requests_total[1h])))) / 0.001
```

### 시나리오 4: TOP 5 느린 엔드포인트

```promql
topk(5, histogram_quantile(0.95,
  sum by(le, endpoint) (rate(app_request_duration_seconds_bucket[5m]))
))
```

### 시나리오 5: 24시간 전 대비 트래픽 증감률

```promql
(sum(rate(app_requests_total[5m])) - sum(rate(app_requests_total[5m] offset 24h))) /
sum(rate(app_requests_total[5m] offset 24h)) * 100
```

### 시나리오 6: CPU Saturation 감지

```promql
# Load Average가 CPU 코어 수를 초과하면 포화
node_load1 > count without(cpu, mode) (node_cpu_seconds_total{mode="idle"})
```

### 시나리오 7: 메모리 누수 감지

```promql
# 6시간 동안 메모리가 지속적으로 증가 추세인지
deriv(node_memory_MemAvailable_bytes[6h]) < 0
and
delta(node_memory_MemAvailable_bytes[6h]) < -100*1024*1024
```

### 시나리오 8: 디스크 IOPS

```promql
# 초당 디스크 읽기/쓰기 작업 수
rate(node_disk_reads_completed_total[5m])
rate(node_disk_writes_completed_total[5m])
```

### 시나리오 9: 네트워크 대역폭 사용률 (Mbps)

```promql
# 수신 Mbps
rate(node_network_receive_bytes_total{device!="lo"}[5m]) * 8 / 1000000

# 송신 Mbps
rate(node_network_transmit_bytes_total{device!="lo"}[5m]) * 8 / 1000000
```

### 시나리오 10: USE Method (Utilization, Saturation, Errors)

```promql
# CPU Utilization
instance:node_cpu_utilization:avg_rate5m

# CPU Saturation
node_load1 / count without(cpu, mode) (node_cpu_seconds_total{mode="idle"})

# Memory Utilization
instance:node_memory_utilization:ratio

# Disk Errors
rate(node_disk_io_time_weighted_seconds_total[5m])
```

---

## 다음 단계

👉 [Step 08: Alerting (Alertmanager)](./08_alerting.md) — 임계값 초과 시 자동 알림을 설정합니다.
