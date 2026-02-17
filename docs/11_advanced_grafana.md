# Step 11: Grafana 고급

## 📌 이 단계에서 배우는 것
- Template Variables (동적 변수)
- Chained Variables (연계 변수)
- Annotations (이벤트 마킹)
- 대시보드 프로비저닝 (코드로 관리)
- Grafana API 활용
- 플러그인 관리
- 조직/팀/권한 관리

---

## 1. Template Variables (동적 변수)

Template Variables를 사용하면 대시보드를 **동적으로 필터링**할 수 있습니다.

### 1.1 변수 생성

1. 대시보드 상단 ⚙️ (Settings) 클릭
2. `Variables` 탭 → `New variable` 클릭

### 1.2 Query 타입 변수

```
# Variable: instance
Label: Instance
Type: Query
Data Source: Prometheus
Query: label_values(up, instance)
```

**패널에서 사용:**
```promql
100 - (avg(rate(node_cpu_seconds_total{mode="idle",instance="$instance"}[5m])) * 100)
```

### 1.3 자주 사용하는 변수 쿼리

| 변수명 | Query | 설명 |
|--------|-------|------|
| `$job` | `label_values(up, job)` | 모든 job 목록 |
| `$instance` | `label_values(up{job="$job"}, instance)` | 선택된 job의 인스턴스 |
| `$device` | `label_values(node_network_receive_bytes_total, device)` | 네트워크 인터페이스 |
| `$mountpoint` | `label_values(node_filesystem_size_bytes, mountpoint)` | 마운트 포인트 |
| `$endpoint` | `label_values(app_requests_total, endpoint)` | API 엔드포인트 |

### 1.4 Interval 변수

시간 간격을 동적으로 변경할 수 있습니다:

```
Name: interval
Type: Interval
Values: 1m,5m,10m,30m,1h,6h,12h,1d
```

**사용:**
```promql
rate(node_cpu_seconds_total{mode="idle"}[$interval])
```

### 1.5 Multi-value 변수

여러 값을 동시에 선택할 수 있습니다:

1. Variable 설정에서 `Multi-value` 활성화
2. `Include All option` 활성화 (전체 선택 가능)

**패널에서 사용:**
```promql
# =~ 정규표현식 매쳐 사용 (Multi-value 지원)
node_cpu_seconds_total{mode=~"$mode"}
```

---

## 2. Chained Variables (연계 변수)

변수 간에 **의존 관계**를 설정하여, 상위 변수 선택에 따라 하위 변수 옵션이 변경됩니다.

```
# 1단계: Job 선택
Name: job
Query: label_values(up, job)

# 2단계: 선택된 job의 Instance 목록
Name: instance
Query: label_values(up{job="$job"}, instance)

# 3단계: 선택된 instance의 Device 목록
Name: device
Query: label_values(node_network_receive_bytes_total{instance="$instance"}, device)
```

**결과:** `Job` 드롭다운 변경 → `Instance` 옵션 자동 갱신 → `Device` 옵션 자동 갱신

---

## 3. Annotations (이벤트 마킹)

그래프 위에 **이벤트를 마킹**하여 배포, 장애 등의 시점을 표시합니다.

### Dashboard Annotations

1. Dashboard Settings → `Annotations` 탭
2. `New query` 클릭

```
Name: Alerts
Data Source: Prometheus
Query: ALERTS{alertstate="firing"}
```

### 수동 Annotation (API)

```bash
# Grafana API로 annotation 추가
curl -X POST http://admin:admin123@localhost:3000/api/annotations \
  -H "Content-Type: application/json" \
  -d '{
    "text": "v1.2.3 배포 완료",
    "tags": ["deploy", "v1.2.3"],
    "time": '$(date +%s000)'
  }'
```

---

## 4. 대시보드 프로비저닝

### 4.1 코드로 대시보드 관리 (GitOps)

학습 환경에서 이미 사용 중인 방식입니다:

```yaml
# grafana/provisioning/dashboards/dashboard.yml
apiVersion: 1
providers:
  - name: 'default'
    orgId: 1
    folder: 'Learning Lab'
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards/json
```

### 4.2 장점

| 항목 | GUI 관리 | 프로비저닝 (코드) |
|------|---------|----------------|
| 버전 관리 | ❌ | ✅ Git으로 추적 |
| 재현성 | 수동 | 자동 (환경 재생성 가능) |
| 팀 협업 | 어려움 | PR/리뷰 가능 |
| 백업 | 수동 | Git에 자동 |

---

## 5. Grafana HTTP API

### 5.1 주요 API 엔드포인트

```bash
BASE_URL="http://admin:admin123@localhost:3000"

# 현재 조직 정보
curl -s "${BASE_URL}/api/org" | python3 -m json.tool

# 모든 대시보드 목록
curl -s "${BASE_URL}/api/search?type=dash-db" | python3 -m json.tool

# 특정 대시보드 상세 (UID로 조회)
curl -s "${BASE_URL}/api/dashboards/uid/node-overview" | python3 -m json.tool

# 데이터 소스 목록
curl -s "${BASE_URL}/api/datasources" | python3 -m json.tool

# 헬스 체크
curl -s "${BASE_URL}/api/health" | python3 -m json.tool
```

### 5.2 대시보드 백업/복원

```bash
# 대시보드 JSON 백업
curl -s "${BASE_URL}/api/dashboards/uid/node-overview" \
  | python3 -m json.tool > backup-node-overview.json

# 대시보드 복원 (Import)
curl -X POST "${BASE_URL}/api/dashboards/db" \
  -H "Content-Type: application/json" \
  -d @backup-node-overview.json
```

### 5.3 스냅샷 생성

```bash
curl -X POST "${BASE_URL}/api/snapshots" \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": { ... },
    "name": "시스템 모니터링 스냅샷",
    "expires": 3600
  }'
```

---

## 6. 플러그인 관리

### CLI로 플러그인 설치

```bash
# 컨테이너 내부에서 실행
docker exec -it grafana grafana cli plugins install grafana-clock-panel
docker exec -it grafana grafana cli plugins install grafana-piechart-panel

# 설치 후 Grafana 재시작 필요
docker compose restart grafana
```

### 추천 플러그인

| 플러그인 | 설명 |
|---------|------|
| `grafana-piechart-panel` | 파이 차트 패널 |
| `grafana-clock-panel` | 시계 패널 |
| `grafana-worldmap-panel` | 세계 지도 패널 |
| `yesoreyeram-infinity-datasource` | CSV/JSON/XML 데이터 소스 |

---

## 7. 조직/팀/권한 관리

### 역할 (Role)

| 역할 | 권한 |
|------|------|
| Viewer | 대시보드 조회만 가능 |
| Editor | 대시보드 생성/수정 가능 |
| Admin | 모든 설정 관리 가능 |

### 폴더 기반 권한

대시보드를 폴더로 그룹화하고, 폴더별로 접근 권한을 설정할 수 있습니다:

1. `📊 Dashboards` → 폴더 생성
2. 폴더 설정 → `Permissions` 탭
3. 팀/사용자별 역할 할당

---

## 다음 단계

👉 [Step 12: 프로덕션 운영 Best Practices](./12_production_best_practices.md) — 전문가 수준의 운영 노하우를 학습합니다.
