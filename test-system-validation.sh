#!/bin/bash
# ==============================================================================
# System Validation Tests for Claude Code Monitoring
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

echo -e "${BLUE}Claude Code Monitoring - System Validation${NC}"
echo "=========================================="
echo ""

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -n "Testing $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Function to check file exists
check_file() {
    local file="$1"
    run_test "File exists: $file" "test -f '$file'"
}

# Function to check directory exists
check_dir() {
    local dir="$1"
    run_test "Directory exists: $dir" "test -d '$dir'"
}

# Function to check command exists
check_command() {
    local cmd="$1"
    run_test "Command available: $cmd" "command -v '$cmd'"
}

# Function to validate YAML file
check_yaml() {
    local file="$1"
    if command -v yamllint >/dev/null 2>&1; then
        run_test "YAML valid: $file" "yamllint -d relaxed '$file'"
    else
        echo -e "${YELLOW}⚠ yamllint not installed, skipping YAML validation${NC}"
    fi
}

# Function to validate shell script
check_shell() {
    local file="$1"
    if command -v shellcheck >/dev/null 2>&1; then
        run_test "Shell script valid: $file" "shellcheck -e SC1091 '$file'"
    else
        echo -e "${YELLOW}⚠ ShellCheck not installed, skipping shell validation${NC}"
    fi
}

echo -e "${BLUE}1. Checking core files...${NC}"
check_file "manage.sh"
check_file "check-claude-metrics.sh"
check_file "update-wsl-ip.sh"
check_file "docker-compose.yaml"
check_file "prometheus.yml.template"
check_file "README.md"
check_file "CHANGELOG.md"

echo -e "\n${BLUE}2. Checking test files...${NC}"
check_file "test_manage.bats"
check_file "test_check_claude_metrics.bats"
check_file "test_update_wsl_ip.bats"
check_file "run_tests.sh"
check_file "run_update_wsl_ip_tests.sh"
check_file "test-runner.sh"
check_file "Makefile"

echo -e "\n${BLUE}3. Checking directories...${NC}"
check_dir "grafana-provisioning"
check_dir "grafana-provisioning/dashboards"
check_dir "grafana-provisioning/datasources"
check_dir ".github/workflows"

echo -e "\n${BLUE}4. Checking Grafana configuration...${NC}"
check_file "grafana-provisioning/dashboards/dashboard.yml"
check_file "grafana-provisioning/dashboards/claude-code-basic.json"
check_file "grafana-provisioning/dashboards/claude-code-comprehensive.json"
check_file "grafana-provisioning/datasources/prometheus.yml.template"

echo -e "\n${BLUE}5. Checking CI/CD configuration...${NC}"
check_file ".github/workflows/test.yml"
check_yaml ".github/workflows/test.yml"

echo -e "\n${BLUE}6. Validating shell scripts...${NC}"
check_shell "manage.sh"
check_shell "check-claude-metrics.sh"
check_shell "update-wsl-ip.sh"
check_shell "test-runner.sh"

echo -e "\n${BLUE}7. Validating YAML files...${NC}"
check_yaml "docker-compose.yaml"
check_yaml "grafana-provisioning/dashboards/dashboard.yml"
if [ -f ".yamllint" ]; then
    check_yaml ".yamllint"
fi

echo -e "\n${BLUE}8. Checking executable permissions...${NC}"
run_test "manage.sh is executable" "test -x manage.sh"
run_test "check-claude-metrics.sh is executable" "test -x check-claude-metrics.sh"
run_test "update-wsl-ip.sh is executable" "test -x update-wsl-ip.sh"
run_test "test-runner.sh is executable" "test -x test-runner.sh"

echo -e "\n${BLUE}9. Checking dependencies...${NC}"
check_command "bash"
check_command "curl"
check_command "sed"
check_command "awk"

echo -e "\n${BLUE}10. Checking optional dependencies...${NC}"
if command -v docker >/dev/null 2>&1; then
    check_command "docker"
    run_test "Docker daemon running" "docker ps"
elif command -v podman >/dev/null 2>&1; then
    check_command "podman"
    run_test "Podman accessible" "podman version"
else
    echo -e "${YELLOW}⚠ Neither Docker nor Podman found${NC}"
fi

check_command "bats" || echo -e "${YELLOW}⚠ BATS not installed (required for tests)${NC}"
check_command "shellcheck" || echo -e "${YELLOW}⚠ ShellCheck not installed (required for linting)${NC}"
check_command "yamllint" || echo -e "${YELLOW}⚠ yamllint not installed (required for YAML validation)${NC}"
check_command "make" || echo -e "${YELLOW}⚠ make not installed (optional)${NC}"

echo -e "\n${BLUE}11. Checking environment...${NC}"
run_test "Git repository exists" "test -d .git"
run_test "Can create test file" "touch .test-write-permission && rm .test-write-permission"

# Summary
echo ""
echo "=========================================="
echo -e "${BLUE}Validation Summary:${NC}"
echo -e "  Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "  Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All validation tests passed!${NC}"
    echo ""
    echo "You can now run:"
    echo "  - ./test-runner.sh         # Run all tests"
    echo "  - make test                # Run tests via Makefile"
    echo "  - ./manage.sh up           # Start monitoring stack"
    exit 0
else
    echo -e "${RED}✗ Some validation tests failed!${NC}"
    echo ""
    echo "Please fix the issues above before proceeding."
    exit 1
fi