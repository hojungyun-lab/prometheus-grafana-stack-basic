# Step 08: Alerting (Alertmanager)

## 📌 이 단계에서 배우는 것
- Alertmanager 아키텍처
- Alert Rule 작성 (Prometheus side)
- Alertmanager 설정 (라우팅, 수신채널, 억제)
- 실습: CPU 80% 초과 알림 발생 확인
- Grafana Alerting과의 비교

---

## 1. 알림 아키텍처

```
┌──────────────┐    Alert Rules 평가    ┌──────────────────┐
│  Prometheus  │ ───────────────────►  │   Alertmanager    │
│              │   (조건 충족 시 발송)    │                  │
│  alert-rules │                       │  라우팅/그룹화      │
│  .yml        │                       │  중복 제거         │
└──────────────┘                       │  알림 전송         │
                                       └────────┬─────────┘
                                                │
                              ┌────────────────┼─────────────┐
                              ▼                ▼             ▼
                         📧 Email        💬 Slack      🔗 Webhook
```

### 알림 흐름

1. **Prometheus**가 `alert-rules.yml`의 조건을 주기적으로 평가
2. 조건 충족 시 **Alert 상태**: `Inactive` → `Pending` → `Firing`
3. `Firing` 상태의 알림을 **Alertmanager**로 전송
4. Alertmanager가 **그룹화, 중복 제거, 라우팅** 후 수신 채널로 전달

### Alert 상태

| 상태 | 설명 |
|------|------|
| **Inactive** | 조건 미충족 (정상) |
| **Pending** | 조건 충족, `for` 기간 대기 중 |
| **Firing** | `for` 기간 경과, 알림 발생! |

> 💡 `for` 기간을 설정하면 순간적인 스파이크로 인한 오알림(false positive)을 방지합니다.

---

## 2. Alert Rule 작성

### 기본 구조

```yaml
groups:
  - name: 그룹_이름
    rules:
      - alert: 알림_이름
        expr: PromQL_조건_식
        for: 대기_시간
        labels:
          severity: critical|warning|info
        annotations:
          summary: "요약 메시지"
          description: "상세 설명 ({{ $value }} 사용 가능)"
```

### 학습 환경의 Alert Rule 분석

`prometheus/alert-rules.yml`에 정의된 주요 알림:

#### CPU 사용률 경고 (80%)

```yaml
- alert: HighCpuUsage
  expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
  for: 2m                  # 2분간 지속될 때만 발생
  labels:
    severity: warning       # 심각도: 경고
  annotations:
    summary: "CPU 사용률이 높습니다"
    description: "{{ $labels.instance }}의 CPU 사용률이 {{ $value | printf \"%.1f\" }}%"
```

#### Node Exporter 다운 감지

```yaml
- alert: NodeExporterDown
  expr: up{job="node-exporter"} == 0
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "Node Exporter가 다운되었습니다"
```

#### 디스크 공간 예측

```yaml
- alert: DiskSpacePrediction
  expr: predict_linear(node_filesystem_avail_bytes[6h], 24*3600) < 0
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "디스크 공간이 24시간 내 부족할 수 있습니다"
```

---

## 3. Alertmanager 설정

### 3.1 라우팅 설정 (Route)

```yaml
route:
  # 그룹화 기준
  group_by: ['alertname', 'severity']

  # 그룹 내 첫 알림까지 대기 시간
  group_wait: 30s

  # 같은 그룹의 새 알림 전송 간격
  group_interval: 5m

  # 동일 알림 반복 전송 간격
  repeat_interval: 4h

  # 기본 수신 채널
  receiver: 'webhook-receiver'

  # 하위 라우팅 (severity별 분기)
  routes:
    - match:
        severity: critical
      receiver: 'webhook-receiver'
      group_wait: 10s           # Critical은 빠르게 전송
      repeat_interval: 1h
```

### 3.2 수신 채널 (Receiver) 예시

```yaml
receivers:
  # Webhook (학습용)
  - name: 'webhook-receiver'
    webhook_configs:
      - url: 'http://localhost:5001/webhook'
        send_resolved: true

  # Email (실전)
  # - name: 'email-receiver'
  #   email_configs:
  #     - to: 'admin@example.com'
  #       from: 'alertmanager@example.com'
  #       smarthost: 'smtp.gmail.com:587'
  #       auth_username: 'user@gmail.com'
  #       auth_password: 'app-password'

  # Slack (실전)
  # - name: 'slack-receiver'
  #   slack_configs:
  #     - api_url: 'https://hooks.slack.com/services/...'
  #       channel: '#alerts'
  #       title: '{{ .GroupLabels.alertname }}'
  #       text: '{{ .CommonAnnotations.description }}'
```

### 3.3 Inhibition Rules (알림 억제)

상위 알림이 발생하면 하위 알림을 억제합니다:

```yaml
inhibit_rules:
  - source_match:
      severity: 'critical'     # Critical이 발생하면
    target_match:
      severity: 'warning'      # Warning은 억제
    equal: ['instance']        # 같은 인스턴스에 대해서만
```

**시나리오:** `NodeExporterDown` (critical)이 발생하면, 그 노드의 `HighCpuUsage` (warning)은 억제

---

## 4. 실습: 알림 발생 시키기

### 4.1 Prometheus에서 알림 상태 확인

**http://localhost:9090/alerts** 접속:
- 현재 정의된 모든 Alert Rule 확인
- 각 Rule의 상태 (Inactive/Pending/Firing)

### 4.2 Alertmanager UI 확인

**http://localhost:9093** 접속:
- 현재 발생 중인 알림 목록
- Silence (일시 중지) 설정 가능
- 알림 그룹화 상태 확인

### 4.3 강제 알림 발생 (spike 모드)

```bash
# docker-compose.yml에서 SIMULATOR_MODE=spike로 변경
cd docker
# docker-compose.yml 편집 후:
docker compose up -d ubuntu-target

# 로그에서 SPIKE 확인
docker compose logs -f ubuntu-target
```

2~3분 후 Prometheus Alerts 탭에서 `HighCpuUsage`가 `Pending` → `Firing`으로 변하는 것을 확인합니다.

### 4.4 Alertmanager에서 Silence 설정

1. **http://localhost:9093** → `Silences` 탭
2. `New Silence` 클릭
3. Matcher: `alertname = HighCpuUsage`
4. Duration: `1h`
5. Creator: 본인 이름
6. Comment: `학습 테스트`
7. `Create` 클릭

> Silence 설정 후 해당 알림이 더 이상 전송되지 않습니다.

---

## 5. Grafana Alerting (비교)

Grafana도 자체 Alerting 기능을 제공합니다:

| 구분 | Prometheus + Alertmanager | Grafana Alerting |
|------|--------------------------|------------------|
| **설정** | YAML 파일 | GUI 기반 |
| **평가** | Prometheus가 평가 | Grafana가 평가 |
| **라우팅** | Alertmanager 라우팅 규칙 | Grafana Contact Points |
| **장점** | 컨테이너 친화적, GitOps 가능 | 시각적 설정, 대시보드 통합 |
| **권장** | 프로덕션 환경 | 소규모/PoC 환경 |

---

## 핵심 정리

```
Alerting 핵심 포인트:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Alert Rule은 Prometheus에서 정의 (alert-rules.yml)
✅ 조건 충족 → Pending → for 시간 경과 → Firing
✅ Alertmanager가 그룹화, 중복 제거, 라우팅 처리
✅ Inhibition으로 상위 알림 발생 시 하위 알림 억제
✅ Silence로 특정 알림 일시 중지 가능
```

---

## 다음 단계

👉 [Step 09: Custom Exporter 개발](./09_custom_exporter.md) — Python으로 자신만의 메트릭 수집기를 만듭니다.
