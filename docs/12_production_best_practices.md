# Step 12: 프로덕션 운영 Best Practices

## 📌 이 단계에서 배우는 것
- 스토리지 관리 (retention, WAL, 압축)
- Federation (다중 Prometheus)
- Remote Write/Read
- 장기 저장 솔루션 (Thanos, Mimir)
- 보안 (TLS, 인증, RBAC)
- 성능 튜닝
- 실무 모니터링 설계 패턴
- 다음 학습 로드맵

---

## 1. 스토리지 관리

### TSDB 구조

```
prometheus_data/
├── wal/                  # Write-Ahead Log (최근 데이터, 메모리)
├── chunks_head/          # 아직 압축되지 않은 최근 블록
├── 01ABCDEF.../          # 압축된 블록 (2시간 단위)
│   ├── chunks/
│   ├── index
│   ├── meta.json
│   └── tombstones
└── lock
```

### Retention (데이터 보존)

```yaml
# docker-compose.yml의 Prometheus 설정
command:
  - '--storage.tsdb.retention.time=15d'     # 시간 기반 보존 (15일)
  - '--storage.tsdb.retention.size=5GB'     # 크기 기반 보존 (5GB)
```

| 설정 | 기본값 | 설명 |
|------|--------|------|
| `retention.time` | 15d | 데이터 보존 기간 |
| `retention.size` | 0 (무제한) | 최대 디스크 사용량 |

### 디스크 사용량 확인

```promql
# Prometheus TSDB 상태 (Status > TSDB Status)
prometheus_tsdb_storage_blocks_bytes        # 블록 크기
prometheus_tsdb_head_series                 # 현재 시계열 수
prometheus_tsdb_head_chunks                 # 현재 청크 수
prometheus_tsdb_compactions_total           # 압축 횟수
```

### 디스크 용량 계산

```
필요 디스크 = ingested_samples_per_second × bytes_per_sample × retention_seconds

예시:
- 수집: 100,000 samples/s
- 평균 크기: 1.5 bytes/sample (압축 후)
- 보존: 15일

100,000 × 1.5 × 15 × 86400 = ~194 GB
```

---

## 2. Federation (다중 Prometheus)

### 계층적 Federation

```
┌─────────────────────────────────┐
│    Global Prometheus            │    장기 저장, 집계 뷰
│    (Federation)                 │
└────────────────┬────────────────┘
                 │ /federate
      ┌──────────┼──────────┐
      ▼          ▼          ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│ Regional │ │ Regional │ │ Regional │
│ Prom #1  │ │ Prom #2  │ │ Prom #3  │
│ (Asia)   │ │ (US)     │ │ (EU)     │
└──────────┘ └──────────┘ └──────────┘
```

### Federation 설정

```yaml
# Global Prometheus
scrape_configs:
  - job_name: 'federate'
    scrape_interval: 30s
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job="node-exporter"}'
        - '{__name__=~"job:.*"}'
    static_configs:
      - targets:
          - 'regional-prom-1:9090'
          - 'regional-prom-2:9090'
```

---

## 3. Remote Write / Read

### Remote Write

Prometheus가 수집한 데이터를 **외부 저장소로 실시간 전송**합니다.

```yaml
# prometheus.yml
remote_write:
  - url: "http://thanos-receive:19291/api/v1/receive"
    queue_config:
      max_samples_per_send: 5000
      max_shards: 200
```

### Remote Read

외부 저장소의 데이터를 Prometheus를 통해 **쿼리**할 수 있습니다.

```yaml
remote_read:
  - url: "http://thanos-store:10901/api/v1/read"
    read_recent: false    # 최근 데이터는 로컬 TSDB 사용
```

---

## 4. 장기 저장 솔루션

### 비교

| 솔루션 | 저장소 | 특장점 | 복잡도 |
|--------|--------|--------|--------|
| **Thanos** | Object Storage (S3, GCS) | HA, 장기 저장, 글로벌 뷰 | 높음 |
| **Cortex** | Object Storage + NoSQL | 멀티테넌트, 수평 확장 | 매우 높음 |
| **Mimir** | Object Storage | Cortex 후속, 성능 개선 | 높음 |
| **VictoriaMetrics** | 자체 스토리지 | 고성능, 쉬운 설정 | 낮음 |

### Thanos 아키텍처

```
┌────────────┐     ┌──────────────┐     ┌────────────────┐
│ Prometheus │────►│  Thanos      │────►│ Object Storage │
│ + Sidecar  │     │  Store GW    │     │ (S3/GCS/MinIO) │
└────────────┘     └──────────────┘     └────────────────┘
                          │
                   ┌──────┴──────┐
                   │ Thanos Query │ ◄──── Grafana
                   │ (PromQL)     │
                   └─────────────┘
```

---

## 5. 보안

### TLS 설정

```yaml
# prometheus.yml - TLS가 활성화된 타깃 스크랩
scrape_configs:
  - job_name: 'secure-target'
    scheme: https
    tls_config:
      ca_file: /etc/prometheus/certs/ca.pem
      cert_file: /etc/prometheus/certs/client.pem
      key_file: /etc/prometheus/certs/client-key.pem
```

### 인증

```yaml
# Prometheus Web UI에 Basic Auth 추가 (web.yml)
basic_auth_users:
  admin: $2y$12$...  # bcrypt 해시
```

### Grafana RBAC

| 수준 | 설정 |
|------|------|
| 조직 | 조직별 독립된 데이터/대시보드 |
| 팀 | 팀별 대시보드 폴더 접근 제어 |
| 사용자 | Viewer/Editor/Admin 역할 |
| 데이터소스 | 데이터소스별 접근 제한 |

---

## 6. 성능 튜닝

### 스크랩 간격 최적화

| 상황 | 권장 간격 |
|------|----------|
| 시스템 메트릭 (Node) | 15s ~ 30s |
| 애플리케이션 메트릭 | 10s ~ 15s |
| 배치 작업 메트릭 | 30s ~ 60s |
| 장기 추이 분석 | 60s ~ 120s |

### 카디널리티 관리

**카디널리티** = 고유한 레이블 조합의 수

```promql
# 카디널리티가 높은 메트릭 확인 (TSDB Status 페이지)
# Status > TSDB Status > Top 10 series count by metric name

# 카디널리티 확인 쿼리
count by(__name__) ({__name__!=""})
```

**카디널리티 폭발 방지:**
- ❌ 사용자 ID를 레이블에 포함하지 않기
- ❌ 요청 URL 전체를 레이블에 넣지 않기
- ✅ 카테고리/그룹으로 집계하여 사용
- ✅ `metric_relabel_configs`로 불필요한 메트릭 제거

### 메모리 최적화

```yaml
# Prometheus 시작 옵션
command:
  - '--storage.tsdb.min-block-duration=2h'
  - '--storage.tsdb.max-block-duration=36h'
  # GOMAXPROCS 설정 (컨테이너 CPU 제한에 맞춤)
```

---

## 7. 실무 모니터링 설계 패턴

### USE Method (시스템 리소스용)

| 항목 | 의미 | 예시 메트릭 |
|------|------|-----------|
| **U**tilization | 사용률 | CPU 사용률, 메모리 사용률 |
| **S**aturation | 포화도 | Load Average, 큐 길이 |
| **E**rrors | 에러 | 디스크 에러, 네트워크 드롭 |

### RED Method (서비스용)

| 항목 | 의미 | 예시 메트릭 |
|------|------|-----------|
| **R**ate | 요청률 | 초당 요청 수 (req/s) |
| **E**rrors | 에러율 | 5xx 응답 비율 |
| **D**uration | 소요시간 | p50, p90, p99 응답 시간 |

### Four Golden Signals (Google SRE)

| 시그널 | PromQL 예시 |
|--------|------------|
| **Latency** | `histogram_quantile(0.99, rate(request_duration_seconds_bucket[5m]))` |
| **Traffic** | `sum(rate(http_requests_total[5m]))` |
| **Errors** | `sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))` |
| **Saturation** | `node_load1 / count(node_cpu_seconds_total{mode="idle"})` |

---

## 8. 다음 학습 로드맵

이 가이드를 완료했다면, 다음 기술을 학습할 수 있습니다:

| 기술 | 설명 | 학습 이유 |
|------|------|----------|
| **Loki** | 로그 집계 시스템 | Grafana + Prometheus + Loki = 관측 가능성 완성 |
| **Tempo** | 분산 추적 시스템 | 마이크로서비스 요청 경로 추적 |
| **OpenTelemetry** | 통합 관측 프레임워크 | Metrics + Logs + Traces 통합 수집 |
| **Kubernetes** | 컨테이너 오케스트레이션 | Prometheus Operator로 자동 관리 |
| **Thanos/Mimir** | 장기 저장 + HA | 프로덕션 규모 확장 |

---

## 🎉 축하합니다!

이 가이드의 모든 단계를 완료했습니다. 이제 여러분은:

- ✅ Prometheus + Grafana 아키텍처를 이해합니다
- ✅ Docker 환경에서 전체 모니터링 스택을 구성할 수 있습니다
- ✅ Node Exporter로 시스템 메트릭을 수집할 수 있습니다
- ✅ PromQL로 복잡한 쿼리를 작성할 수 있습니다
- ✅ Grafana로 전문적인 대시보드를 구성할 수 있습니다
- ✅ Alert Rule과 Alertmanager를 설정할 수 있습니다
- ✅ Python으로 Custom Exporter를 개발할 수 있습니다
- ✅ Service Discovery로 동적 환경을 관리할 수 있습니다
- ✅ 프로덕션 운영 Best Practice를 알고 있습니다

**Prometheus + Grafana 전문가로서의 첫걸음을 내딛었습니다!** 🚀
