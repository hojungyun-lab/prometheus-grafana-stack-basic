#!/bin/bash
# =============================================================================
# 로컬 보안 및 코드 품질 검사 스크립트
# =============================================================================
# 사용법: ./scripts/security-check.sh
# push 전에 로컬에서 실행하여 문제를 사전에 발견합니다.
# =============================================================================

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
SKIP=0

# 결과 출력 함수
print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

check_pass() {
    echo -e "  ${GREEN}✅ PASS${NC}: $1"
    PASS=$((PASS + 1))
}

check_fail() {
    echo -e "  ${RED}❌ FAIL${NC}: $1"
    FAIL=$((FAIL + 1))
}

check_skip() {
    echo -e "  ${YELLOW}⏭️  SKIP${NC}: $1 (도구 미설치)"
    SKIP=$((SKIP + 1))
}

# 프로젝트 루트로 이동
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/..")"

echo ""
echo -e "${BLUE}🔒 Prometheus-Grafana Stack 보안 및 코드 품질 검사${NC}"
echo -e "${BLUE}   $(date '+%Y-%m-%d %H:%M:%S')${NC}"

# ─────────────────────────────────────────────────
# 1. YAML Lint
# ─────────────────────────────────────────────────
print_header "1/5 YAML Lint"
if command -v yamllint &> /dev/null; then
    if yamllint -c .yamllint.yml . 2>/dev/null; then
        check_pass "모든 YAML 파일 통과"
    else
        check_fail "YAML 파일에 문제 발견"
    fi
else
    check_skip "yamllint (pip install yamllint)"
fi

# ─────────────────────────────────────────────────
# 2. ShellCheck
# ─────────────────────────────────────────────────
print_header "2/5 ShellCheck"
if command -v shellcheck &> /dev/null; then
    SHELL_FILES=$(find . -name "*.sh" -not -path "./.git/*" 2>/dev/null)
    if [ -n "${SHELL_FILES}" ]; then
        SHELL_ERRORS=0
        for f in ${SHELL_FILES}; do
            if ! shellcheck "${f}" 2>/dev/null; then
                SHELL_ERRORS=$((SHELL_ERRORS + 1))
            fi
        done
        if [ ${SHELL_ERRORS} -eq 0 ]; then
            check_pass "모든 Shell 스크립트 통과"
        else
            check_fail "${SHELL_ERRORS}개 Shell 스크립트에 문제 발견"
        fi
    else
        echo "  Shell 스크립트 없음"
    fi
else
    check_skip "shellcheck (brew install shellcheck)"
fi

# ─────────────────────────────────────────────────
# 3. Hadolint (Dockerfile)
# ─────────────────────────────────────────────────
print_header "3/5 Hadolint (Dockerfile)"
if command -v hadolint &> /dev/null; then
    DOCKER_FILES=$(find . -name "Dockerfile" -not -path "./.git/*" 2>/dev/null)
    if [ -n "${DOCKER_FILES}" ]; then
        DOCKER_ERRORS=0
        for f in ${DOCKER_FILES}; do
            echo "  Checking: ${f}"
            if ! hadolint --config .hadolint.yaml "${f}" 2>/dev/null; then
                DOCKER_ERRORS=$((DOCKER_ERRORS + 1))
            fi
        done
        if [ ${DOCKER_ERRORS} -eq 0 ]; then
            check_pass "모든 Dockerfile 통과"
        else
            check_fail "${DOCKER_ERRORS}개 Dockerfile에 문제 발견"
        fi
    else
        echo "  Dockerfile 없음"
    fi
else
    check_skip "hadolint (brew install hadolint)"
fi

# ─────────────────────────────────────────────────
# 4. Gitleaks (시크릿 유출 탐지)
# ─────────────────────────────────────────────────
print_header "4/5 Gitleaks"
if command -v gitleaks &> /dev/null; then
    if gitleaks detect --source . --no-banner 2>/dev/null; then
        check_pass "시크릿 유출 없음"
    else
        check_fail "시크릿 유출 감지! 커밋 전에 수정하세요"
    fi
else
    check_skip "gitleaks (brew install gitleaks)"
fi

# ─────────────────────────────────────────────────
# 5. Python Lint (Ruff)
# ─────────────────────────────────────────────────
print_header "5/5 Python Lint (Ruff)"
if command -v ruff &> /dev/null; then
    if ruff check custom-exporter/ 2>/dev/null; then
        check_pass "Python 코드 통과"
    else
        check_fail "Python 코드에 문제 발견"
    fi
else
    check_skip "ruff (pip install ruff)"
fi

# ─────────────────────────────────────────────────
# 결과 요약
# ─────────────────────────────────────────────────
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  📋 결과 요약${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}✅ 통과${NC}: ${PASS}"
echo -e "  ${RED}❌ 실패${NC}: ${FAIL}"
echo -e "  ${YELLOW}⏭️  건너뜀${NC}: ${SKIP}"
echo ""

if [ ${FAIL} -gt 0 ]; then
    echo -e "  ${RED}⚠️  ${FAIL}개 검사가 실패했습니다. 수정 후 다시 실행하세요.${NC}"
    exit 1
else
    echo -e "  ${GREEN}🎉 모든 검사를 통과했습니다!${NC}"
    exit 0
fi
