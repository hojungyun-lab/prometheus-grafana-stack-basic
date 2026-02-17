# Step 10: Service Discovery

## 📌 이 단계에서 배우는 것
- Static Config vs Service Discovery
- File-based Service Discovery
- Docker Service Discovery
- Relabeling 개념 및 활용
- 실습: 동적 타깃 추가/제거

---

## 1. 왜 Service Discovery가 필요한가?

### Static Config의 한계

```yaml
# 타깃이 추가/삭제될 때마다 파일을 수정하고 재시작해야 함
static_configs:
  - targets: ["server1:9100", "server2:9100", "server3:9100"]
```

- 서버 추가 시 수동으로 설정 파일 수정 필요
- 설정 변경 후 Prometheus 재시작/리로드 필요
- 오토스케일링 환경에서 불가능

### Service Discovery 방식

Prometheus가 **자동으로 모니터링 대상을 발견**합니다:

| 방식 | 설명 | 사용 환경 |
|------|------|----------|
| `static_configs` | 수동 목록 | 소규모, 고정 환경 |
| `file_sd_configs` | JSON/YAML 파일 감시 | 범용, 외부 연동 |
| `docker_sd_configs` | Docker API 조회 | Docker 환경 |
| `kubernetes_sd_configs` | K8s API 조회 | Kubernetes |
| `consul_sd_configs` | Consul 서비스 레지스트리 | 마이크로서비스 |
| `ec2_sd_configs` | AWS EC2 API | AWS 클라우드 |
| `dns_sd_configs` | DNS SRV 레코드 | DNS 기반 환경 |

---

## 2. File-based Service Discovery

### 개념

Prometheus가 **JSON 또는 YAML 파일을 감시**하여 타깃 목록을 동적으로 로드합니다. 파일이 변경되면 자동으로 반영됩니다.

### 설정

```yaml
# prometheus.yml
scrape_configs:
  - job_name: "file-discovery"
    file_sd_configs:
      - files:
          - '/etc/prometheus/targets/*.json'    # JSON 파일 감시
          - '/etc/prometheus/targets/*.yml'     # YAML 파일 감시
        refresh_interval: 30s                   # 파일 변경 감시 간격
```

### 타깃 파일 형식

**JSON 형식:**
```json
[
  {
    "targets": ["server1:9100", "server2:9100"],
    "labels": {
      "env": "production",
      "team": "backend"
    }
  },
  {
    "targets": ["server3:9100"],
    "labels": {
      "env": "staging",
      "team": "frontend"
    }
  }
]
```

**YAML 형식:**
```yaml
- targets:
    - "server1:9100"
    - "server2:9100"
  labels:
    env: production
    team: backend
```

### 실습: 동적 타깃 추가

```bash
# 1. 타깃 파일 생성
mkdir -p prometheus/targets

cat > prometheus/targets/webservers.json << 'EOF'
[
  {
    "targets": ["ubuntu-target:9100"],
    "labels": {
      "group": "webservers",
      "env": "lab"
    }
  }
]
EOF

# 2. prometheus.yml에 file_sd_configs 추가 (또는 기존 job에 추가)

# 3. Prometheus 리로드
curl -X POST http://localhost:9090/-/reload

# 4. Status > Targets에서 확인

# 5. 타깃 추가 (파일만 수정하면 자동 반영!)
# webservers.json을 수정하여 새 타깃 추가
```

---

## 3. Docker Service Discovery

### 개념

Prometheus가 Docker API를 통해 **실행 중인 컨테이너를 자동으로 발견**합니다.

### 설정

```yaml
# prometheus.yml
scrape_configs:
  - job_name: "docker-containers"
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 15s
    relabel_configs:
      # Prometheus 메트릭 포트가 있는 컨테이너만 스크랩
      - source_labels: [__meta_docker_container_label_prometheus_scrape]
        regex: 'true'
        action: keep
      # 컨테이너 이름을 instance 레이블에 매핑
      - source_labels: [__meta_docker_container_name]
        target_label: container_name
        regex: '/(.*)'
        replacement: '$1'
```

### Docker Label 기반 자동 발견

```yaml
# docker-compose.yml
services:
  my-app:
    image: my-app:latest
    labels:
      prometheus.scrape: "true"        # 이 라벨이 있으면 자동 스크랩
      prometheus.port: "8080"          # 메트릭 포트
      prometheus.path: "/metrics"      # 메트릭 경로
```

---

## 4. Relabeling

### 개념

Relabeling은 **메트릭 수집 전후에 레이블을 변환/필터링**하는 강력한 기능입니다.

### relabel_configs vs metric_relabel_configs

| 설정 | 실행 시점 | 용도 |
|------|----------|------|
| `relabel_configs` | **스크랩 전** | 타깃 선택/변환 |
| `metric_relabel_configs` | **스크랩 후** | 메트릭 필터링/변환 |

### 주요 Action

| Action | 설명 |
|--------|------|
| `keep` | 매칭되는 타깃만 유지 |
| `drop` | 매칭되는 타깃 제거 |
| `replace` | 레이블 값 교체 |
| `labelmap` | 레이블 이름 매핑 |
| `labeldrop` | 특정 레이블 삭제 |
| `hashmod` | 해시 기반 분산 |

### 예시

```yaml
relabel_configs:
  # 1. 특정 레이블이 있는 타깃만 수집
  - source_labels: [__meta_docker_container_label_monitor]
    regex: 'true'
    action: keep

  # 2. 메타 레이블을 커스텀 레이블로 변환
  - source_labels: [__meta_docker_container_name]
    target_label: container
    regex: '/(.*)'
    replacement: '$1'

  # 3. 메트릭 포트 동적 설정
  - source_labels: [__meta_docker_container_label_prometheus_port]
    target_label: __address__
    regex: '(.+)'
    replacement: '${1}'

metric_relabel_configs:
  # 4. 불필요한 메트릭 제거 (카디널리티 관리)
  - source_labels: [__name__]
    regex: 'go_.*'
    action: drop

  # 5. 특정 메트릭만 유지
  - source_labels: [__name__]
    regex: 'node_cpu.*|node_memory.*|node_disk.*'
    action: keep
```

---

## 5. 핵심 정리

| 방식 | 복잡도 | 실시간성 | 추천 환경 |
|------|--------|---------|----------|
| `static_configs` | 낮음 | 수동 | 소규모 고정 |
| `file_sd_configs` | 낮음 | 파일 변경 즉시 | 범용 |
| `docker_sd_configs` | 중간 | 15s 간격 | Docker |
| `kubernetes_sd_configs` | 높음 | 즉시 | K8s |

---

## 다음 단계

👉 [Step 11: Grafana 고급](./11_advanced_grafana.md) — 변수, 템플릿, 프로비저닝 등 전문가 수준의 Grafana를 학습합니다.
