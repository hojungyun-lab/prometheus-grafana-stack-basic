# 🔭 Prometheus + Grafana 학습 가이드

Prometheus와 Grafana를 처음부터 전문가 수준까지 학습할 수 있는 **실전 중심의 단계별 가이드**입니다.

Docker 기반 실습 환경이 포함되어 있어, 별도의 서버 설치 없이 **로컬에서 바로 실습**할 수 있습니다.

---

## 📋 학습 로드맵

| # | 주제 | 핵심 내용 |
|---|------|----------|
| [00](docs/00_overview.md) | **모니터링 개요** | 모니터링 정의, Observability, 아키텍처 |
| [01](docs/01_environment_setup.md) | **환경 구성** | Docker Compose 실행, 서비스 관리 |
| [02](docs/02_prometheus_basics.md) | **Prometheus 기초** | 데이터 모델, 메트릭 타입, Web UI |
| [03](docs/03_node_exporter.md) | **Node Exporter** | 시스템 메트릭 수집, 데이터 시뮬레이터 |
| [04](docs/04_promql_fundamentals.md) | **PromQL 기초** | Selector, rate(), sum(), 15개 실습 |
| [05](docs/05_grafana_basics.md) | **Grafana 기초** | UI 가이드, 패널 생성, Explore |
| [06](docs/06_grafana_dashboards.md) | **대시보드 구성** | 실전 대시보드, 커뮤니티 대시보드 |
| [07](docs/07_promql_advanced.md) | **PromQL 고급** | histogram_quantile, predict_linear, SLI/SLO |
| [08](docs/08_alerting.md) | **Alerting** | Alert Rule, Alertmanager, Silence |
| [09](docs/09_custom_exporter.md) | **Custom Exporter** | Python으로 비즈니스 메트릭 수집기 개발 |
| [10](docs/10_service_discovery.md) | **Service Discovery** | File/Docker SD, Relabeling |
| [11](docs/11_advanced_grafana.md) | **Grafana 고급** | 변수, 프로비저닝, API, 플러그인 |
| [12](docs/12_production_best_practices.md) | **프로덕션 운영** | 스토리지, 보안, 성능 튜닝, USE/RED |

---

## 🚀 빠른 시작

### 사전 요구 사항

- Docker Desktop 또는 Docker Engine + Docker Compose v2

### 실행

```bash
# 1. 프로젝트 클론
git clone <repository-url>
cd prometheus-grafana-stack-basic

# 2. 전체 스택 실행
cd docker
docker compose up -d --build

# 3. 접속 확인
open http://localhost:9090    # Prometheus
open http://localhost:3000    # Grafana (admin / admin123)
```

### 서비스 접속 정보

| 서비스 | URL | 인증 |
|--------|-----|------|
| Prometheus | http://localhost:9090 | 없음 |
| Grafana | http://localhost:3000 | admin / admin123 |
| Alertmanager | http://localhost:9093 | 없음 |
| Node Exporter | http://localhost:9100/metrics | 없음 |
| Custom Exporter | http://localhost:8000/metrics | 없음 |
| cAdvisor | http://localhost:8080 | 없음 |

---

## 🏗️ 프로젝트 구조

```
prometheus-grafana-stack-basic/
├── docs/                    # 📚 학습 문서 (Step 00~12)
├── docker/
│   ├── docker-compose.yml   # 🐳 전체 스택 정의 (6 서비스)
│   └── ubuntu/              # Ubuntu + Node Exporter + 시뮬레이터
├── prometheus/
│   ├── prometheus.yml       # Prometheus 메인 설정
│   ├── alert-rules.yml      # 알림 규칙
│   └── recording-rules.yml  # 사전 계산 규칙
├── grafana/
│   ├── grafana.ini          # Grafana 설정
│   └── provisioning/        # 데이터소스 + 대시보드 자동 설정
├── alertmanager/
│   └── alertmanager.yml     # 알림 라우팅
├── custom-exporter/
│   ├── app_exporter.py      # 🐍 Python 커스텀 메트릭 수집
│   ├── Dockerfile
│   └── requirements.txt
├── scripts/
│   ├── security-check.sh    # 🔒 로컬 보안 검사
│   └── pre-commit           # Git 훅
└── .github/
    ├── workflows/           # CI/CD (보안, 코드 품질, CodeQL)
    └── dependabot.yml       # 의존성 모니터링
```

---

## 📊 동적 데이터 시뮬레이터

Ubuntu Target 컨테이너에서 **유동적인 시스템 부하**를 자동 생성하여, 실제 운영 서버처럼 메트릭이 변화합니다.

| 모드 | 설명 |
|------|------|
| `normal` | 일반적인 서버 부하 (기본값) |
| `spike` | 주기적 급격한 부하 |
| `gradual` | 점진적 증가/감소 |
| `chaos` | 완전 랜덤 패턴 |

모드 변경: `docker-compose.yml`에서 `SIMULATOR_MODE` 환경 변수 수정

---

## 🔒 보안 및 코드 품질

### CI/CD (GitHub Actions)
- **Security Scan**: Gitleaks, Trivy, Hadolint
- **Code Quality**: yamllint, ShellCheck, promtool, Ruff
- **CodeQL**: Python 정적 분석
- **Dependabot**: 의존성 취약점 자동 모니터링

### 로컬 검사
```bash
# 전체 보안/품질 검사 실행
./scripts/security-check.sh

# Pre-commit 훅 설치
cp scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

---

## 🛠️ 사용 기술

| 기술 | 버전 | 용도 |
|------|------|------|
| Prometheus | v2.51.0 | 메트릭 수집 및 쿼리 |
| Grafana | v10.4.0 | 시각화 대시보드 |
| Alertmanager | v0.27.0 | 알림 관리 |
| Node Exporter | v1.7.0 | 시스템 메트릭 |
| cAdvisor | latest | 컨테이너 메트릭 |
| Python | 3.12 | Custom Exporter |

---

## 📄 라이선스

MIT License
