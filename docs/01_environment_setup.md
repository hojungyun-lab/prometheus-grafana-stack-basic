# Step 01: Docker 환경 구성

## 📌 이 단계에서 배우는 것
- Docker 및 Docker Compose 사전 요구 사항
- 학습 환경 구성 요소 이해
- 환경 시작, 중지, 리셋 방법
- 각 서비스 접속 및 확인

---

## 1. 사전 요구 사항

### 필수 설치
- **Docker Desktop** (macOS/Windows) 또는 **Docker Engine** (Linux)
- **Docker Compose** v2 이상 (Docker Desktop에 포함)

### 설치 확인

```bash
# Docker 버전 확인
docker --version
# Docker version 24.x.x 이상 권장

# Docker Compose 버전 확인
docker compose version
# Docker Compose version v2.x.x 이상 필요

# Docker 데몬 실행 확인
docker info
```

---

## 2. 프로젝트 구조 이해

```
prometheus-grafana-stack-basic/
├── docker/
│   ├── docker-compose.yml       ← 전체 스택 정의
│   └── ubuntu/
│       ├── Dockerfile           ← Ubuntu + Node Exporter 이미지
│       └── scripts/
│           ├── entrypoint.sh    ← 컨테이너 시작 스크립트
│           └── data-simulator.sh ← 유동적 부하 생성기
├── prometheus/
│   ├── prometheus.yml           ← 메트릭 수집 설정
│   ├── alert-rules.yml          ← 알림 규칙
│   └── recording-rules.yml      ← 사전 계산 규칙
├── grafana/
│   ├── grafana.ini              ← Grafana 설정
│   └── provisioning/            ← 자동 설정 (데이터소스, 대시보드)
├── alertmanager/
│   └── alertmanager.yml         ← 알림 라우팅
└── custom-exporter/
    ├── app_exporter.py          ← Python 커스텀 메트릭
    ├── Dockerfile
    └── requirements.txt
```

---

## 3. 서비스 구성 (docker-compose.yml)

학습 환경은 **6개의 Docker 컨테이너**로 구성됩니다:

| # | 서비스 | 이미지 | 포트 | 역할 |
|---|--------|--------|------|------|
| 1 | **prometheus** | prom/prometheus:v2.51.0 | 9090 | 메트릭 수집/저장/쿼리 |
| 2 | **grafana** | grafana/grafana:10.4.0 | 3000 | 시각화 대시보드 |
| 3 | **alertmanager** | prom/alertmanager:v0.27.0 | 9093 | 알림 관리 |
| 4 | **ubuntu-target** | 커스텀 빌드 | 9100 | 모니터링 대상 서버 |
| 5 | **custom-exporter** | 커스텀 빌드 | 8000 | Python 비즈니스 메트릭 |
| 6 | **cadvisor** | gcr.io/cadvisor/cadvisor | 8080 | 컨테이너 자체 모니터링 |

### 네트워크

모든 서비스는 `prom-grafana-net` 브리지 네트워크에서 서로 통신합니다.

### 볼륨

| 볼륨 | 용도 |
|------|------|
| `prometheus_data` | Prometheus 시계열 데이터 영속화 |
| `grafana_data` | Grafana 대시보드/설정 영속화 |

---

## 4. 환경 실행

### 4.1 초기 실행

```bash
# 프로젝트 디렉토리로 이동
cd prometheus-grafana-stack-basic/docker

# 이미지 빌드 및 전체 스택 시작
docker compose up -d --build
```

> 💡 첫 실행 시 이미지를 빌드하므로 2~3분 소요될 수 있습니다.

### 4.2 서비스 상태 확인

```bash
# 전체 서비스 상태 확인
docker compose ps

# 예상 출력:
# NAME              STATUS        PORTS
# alertmanager      Up            0.0.0.0:9093->9093/tcp
# cadvisor          Up            0.0.0.0:8080->8080/tcp
# custom-exporter   Up (healthy)  0.0.0.0:8000->8000/tcp
# grafana           Up            0.0.0.0:3000->3000/tcp
# prometheus        Up            0.0.0.0:9090->9090/tcp
# ubuntu-target     Up (healthy)  0.0.0.0:9100->9100/tcp
```

### 4.3 각 서비스 접속 확인

```bash
# Prometheus UI 확인
curl -s http://localhost:9090/-/healthy
# → Prometheus Server is Healthy.

# Node Exporter 메트릭 확인
curl -s http://localhost:9100/metrics | head -5
# → 시스템 메트릭 출력 확인

# Custom Exporter 확인
curl -s http://localhost:8000/metrics | head -5
# → 비즈니스 메트릭 출력 확인

# Grafana 확인
curl -s http://localhost:3000/api/health
# → {"commit":"...","database":"ok","version":"10.4.0"}
```

---

## 5. 환경 관리 명령어

### 서비스 중지 (데이터 유지)
```bash
docker compose stop
```

### 서비스 재시작
```bash
docker compose start
```

### 서비스 완전 종료 (컨테이너 삭제, 데이터 유지)
```bash
docker compose down
```

### 완전 초기화 (데이터도 삭제)
```bash
docker compose down -v    # 볼륨 포함 삭제
docker compose up -d --build
```

### 로그 확인
```bash
# 전체 서비스 로그
docker compose logs -f

# 특정 서비스 로그
docker compose logs -f prometheus
docker compose logs -f ubuntu-target
docker compose logs -f custom-exporter
```

### 특정 서비스만 재시작
```bash
docker compose restart prometheus
docker compose restart ubuntu-target
```

---

## 6. 데이터 시뮬레이터

Ubuntu Target 컨테이너 내의 `data-simulator.sh`가 자동으로 실행되어 **유동적인 시스템 부하**를 생성합니다.

### 시뮬레이션 모드

| 모드 | 설명 | 사용 시나리오 |
|------|------|-------------|
| `normal` | 낮은~중간 부하 (기본값) | 일반적인 서버 상태 학습 |
| `spike` | 주기적 급격한 부하 발생 | 스파이크 감지 및 알림 테스트 |
| `gradual` | 점진적 증가/감소 | 트렌드 분석 학습 |
| `chaos` | 완전 랜덤 부하 | 예측 불가능한 상황 대응 |

### 모드 변경 방법

`docker-compose.yml`에서 환경 변수를 수정합니다:

```yaml
ubuntu-target:
  environment:
    - SIMULATOR_MODE=spike      # normal → spike로 변경
    - SIMULATOR_INTERVAL=15     # 30초 → 15초로 변경
```

변경 후 재시작:

```bash
docker compose up -d ubuntu-target
```

---

## 7. 트러블슈팅

### 컨테이너가 시작되지 않을 때

```bash
# 상세 로그 확인
docker compose logs [서비스명]

# 컨테이너 상태 확인
docker compose ps -a

# 이미지 재빌드
docker compose build --no-cache ubuntu-target
docker compose up -d
```

### 포트 충돌

기존에 9090, 3000 등의 포트를 사용하는 서비스가 있다면:

```bash
# 사용 중인 포트 확인
lsof -i :9090
lsof -i :3000

# docker-compose.yml에서 포트 변경
# 예: "9091:9090" (호스트 9091 → 컨테이너 9090)
```

### Docker 디스크 공간 부족

```bash
# 사용하지 않는 리소스 정리
docker system prune -f
docker volume prune -f
```

---

## 다음 단계

👉 [Step 02: Prometheus 기초 및 UI](./02_prometheus_basics.md) — Prometheus의 핵심 개념과 웹 UI를 탐색합니다.
