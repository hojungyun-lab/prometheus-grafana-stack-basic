# =============================================================================
# Ubuntu Target Server - Node Exporter 포함
# =============================================================================
# 이 이미지는 모니터링 대상 서버를 시뮬레이션합니다.
# Node Exporter가 설치되어 시스템 메트릭을 수집하고,
# data-simulator.sh가 유동적인 부하를 생성합니다.
# =============================================================================

FROM ubuntu:22.04

# 환경 변수 설정
ENV NODE_EXPORTER_VERSION=1.7.0
ENV SIMULATOR_MODE=normal
ENV SIMULATOR_INTERVAL=30
ENV DEBIAN_FRONTEND=noninteractive

# 시스템 패키지 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    bc \
    stress-ng \
    procps \
    sysstat \
    net-tools \
    iproute2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Node Exporter 다운로드 및 설치
RUN wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" \
    -O /tmp/node_exporter.tar.gz \
    && tar -xzf /tmp/node_exporter.tar.gz -C /tmp/ \
    && mv "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/ \
    && chmod +x /usr/local/bin/node_exporter \
    && rm -rf /tmp/node_exporter*

# 스크립트 복사
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/data-simulator.sh /usr/local/bin/data-simulator.sh

# 실행 권한 부여
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/data-simulator.sh

# Node Exporter 포트
EXPOSE 9100

# 헬스체크 설정
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -sf http://localhost:9100/metrics > /dev/null || exit 1

# 엔트리포인트
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
