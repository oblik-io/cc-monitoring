#!/bin/bash
# ==============================================================================
# Comprehensive Test Runner for Claude Code Monitoring
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Test statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Configuration
COVERAGE_DIR="coverage"
REPORT_FILE="test-report.txt"
SHELLCHECK_OPTS="-e SC1091"  # Exclude 'not following' warnings

# Print banner
print_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       Claude Code Monitoring - Test Verification System      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Print section header
print_section() {
    echo ""
    echo -e "${BLUE}${BOLD}▶ $1${NC}"
    echo -e "${BLUE}$(printf '═%.0s' {1..60})${NC}"
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Install missing dependencies
check_dependencies() {
    print_section "Checking Dependencies"
    
    local missing_deps=()
    
    # Check for BATS
    if ! command_exists bats; then
        missing_deps+=("bats")
        echo -e "${YELLOW}⚠ BATS is not installed${NC}"
    else
        echo -e "${GREEN}✓ BATS is installed$(bats --version | head -1)${NC}"
    fi
    
    # Check for shellcheck
    if ! command_exists shellcheck; then
        missing_deps+=("shellcheck")
        echo -e "${YELLOW}⚠ ShellCheck is not installed${NC}"
    else
        echo -e "${GREEN}✓ ShellCheck is installed ($(shellcheck --version | grep version: | cut -d' ' -f2))${NC}"
    fi
    
    # Check for yamllint
    if ! command_exists yamllint; then
        missing_deps+=("yamllint")
        echo -e "${YELLOW}⚠ yamllint is not installed${NC}"
    else
        echo -e "${GREEN}✓ yamllint is installed ($(yamllint --version | cut -d' ' -f2))${NC}"
    fi
    
    # Check for coverage tools
    if ! command_exists kcov && ! command_exists bashcov; then
        echo -e "${YELLOW}⚠ No coverage tool found (kcov or bashcov)${NC}"
    else
        if command_exists kcov; then
            echo -e "${GREEN}✓ kcov is installed${NC}"
        fi
        if command_exists bashcov; then
            echo -e "${GREEN}✓ bashcov is installed${NC}"
        fi
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Missing dependencies: ${missing_deps[*]}${NC}"
        echo ""
        echo "Installation instructions:"
        echo "  macOS:"
        echo "    brew install bats-core shellcheck yamllint kcov"
        echo "  Ubuntu/Debian:"
        echo "    sudo apt-get install bats shellcheck yamllint kcov"
        echo "  Python tools:"
        echo "    pip install yamllint bashcov"
        echo ""
        
        if [ "$CI" != "true" ]; then
            read -p "Continue without missing dependencies? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
}

# Run BATS tests
run_bats_tests() {
    print_section "Running BATS Unit Tests"
    
    if ! command_exists bats; then
        echo -e "${YELLOW}Skipping: BATS not installed${NC}"
        ((SKIPPED_TESTS++))
        return
    fi
    
    local test_files=(
        "test_manage.bats"
        "test_check_claude_metrics.bats"
        "test_update_wsl_ip.bats"
    )
    
    for test_file in "${test_files[@]}"; do
        if [ -f "$test_file" ]; then
            echo -e "\n${CYAN}Running $test_file...${NC}"
            
            if [ "$VERBOSE" == "true" ]; then
                bats -v "$test_file"
            else
                bats "$test_file"
            fi
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ $test_file passed${NC}"
                ((PASSED_TESTS++))
            else
                echo -e "${RED}✗ $test_file failed${NC}"
                ((FAILED_TESTS++))
            fi
            ((TOTAL_TESTS++))
        else
            echo -e "${YELLOW}⚠ $test_file not found${NC}"
            ((SKIPPED_TESTS++))
        fi
    done
}

# Run ShellCheck on all shell scripts
run_shellcheck() {
    print_section "Running ShellCheck Static Analysis"
    
    if ! command_exists shellcheck; then
        echo -e "${YELLOW}Skipping: ShellCheck not installed${NC}"
        ((SKIPPED_TESTS++))
        return
    fi
    
    local shell_scripts=(
        "manage.sh"
        "check-claude-metrics.sh"
        "update-wsl-ip.sh"
        "run_tests.sh"
        "run_update_wsl_ip_tests.sh"
        "test-runner.sh"
    )
    
    local shellcheck_failed=0
    
    for script in "${shell_scripts[@]}"; do
        if [ -f "$script" ]; then
            echo -n "Checking $script... "
            
            if shellcheck $SHELLCHECK_OPTS "$script" > /dev/null 2>&1; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC}"
                if [ "$VERBOSE" == "true" ]; then
                    shellcheck $SHELLCHECK_OPTS "$script"
                fi
                ((shellcheck_failed++))
            fi
        fi
    done
    
    ((TOTAL_TESTS++))
    if [ $shellcheck_failed -eq 0 ]; then
        echo -e "\n${GREEN}✓ All shell scripts passed ShellCheck${NC}"
        ((PASSED_TESTS++))
    else
        echo -e "\n${RED}✗ $shellcheck_failed scripts failed ShellCheck${NC}"
        ((FAILED_TESTS++))
    fi
}

# Run yamllint on YAML files
run_yamllint() {
    print_section "Running YAML Validation"
    
    if ! command_exists yamllint; then
        echo -e "${YELLOW}Skipping: yamllint not installed${NC}"
        ((SKIPPED_TESTS++))
        return
    fi
    
    local yaml_files=(
        "docker-compose.yaml"
        "prometheus.yml"
        "grafana-provisioning/datasources/prometheus.yml"
        "grafana-provisioning/dashboards/dashboard.yml"
        ".github/workflows/test.yml"
    )
    
    local yaml_failed=0
    
    for yaml_file in "${yaml_files[@]}"; do
        if [ -f "$yaml_file" ]; then
            echo -n "Validating $yaml_file... "
            
            if yamllint -d relaxed "$yaml_file" > /dev/null 2>&1; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC}"
                if [ "$VERBOSE" == "true" ]; then
                    yamllint -d relaxed "$yaml_file"
                fi
                ((yaml_failed++))
            fi
        fi
    done
    
    ((TOTAL_TESTS++))
    if [ $yaml_failed -eq 0 ]; then
        echo -e "\n${GREEN}✓ All YAML files are valid${NC}"
        ((PASSED_TESTS++))
    else
        echo -e "\n${RED}✗ $yaml_failed YAML files failed validation${NC}"
        ((FAILED_TESTS++))
    fi
}

# Run integration tests
run_integration_tests() {
    print_section "Running Integration Tests"
    
    echo "Checking Docker/Podman availability..."
    if command_exists docker; then
        echo -e "${GREEN}✓ Docker is available${NC}"
    elif command_exists podman; then
        echo -e "${GREEN}✓ Podman is available${NC}"
    else
        echo -e "${YELLOW}⚠ Neither Docker nor Podman found - skipping integration tests${NC}"
        ((SKIPPED_TESTS++))
        return
    fi
    
    # Add integration tests here
    echo -e "${YELLOW}Integration tests not yet implemented${NC}"
    ((SKIPPED_TESTS++))
}

# Generate coverage report
generate_coverage() {
    print_section "Generating Coverage Report"
    
    if command_exists kcov; then
        echo "Using kcov for coverage analysis..."
        mkdir -p "$COVERAGE_DIR"
        
        # Run coverage for main scripts
        for script in manage.sh check-claude-metrics.sh update-wsl-ip.sh; do
            if [ -f "$script" ]; then
                echo "Analyzing coverage for $script..."
                kcov --exclude-pattern=/usr,/tmp "$COVERAGE_DIR/$script" "./$script" --help || true
            fi
        done
        
        echo -e "${GREEN}✓ Coverage reports generated in $COVERAGE_DIR/${NC}"
    elif command_exists bashcov; then
        echo "Using bashcov for coverage analysis..."
        # bashcov implementation
        echo -e "${YELLOW}bashcov coverage not yet implemented${NC}"
    else
        echo -e "${YELLOW}No coverage tool available${NC}"
    fi
}

# Generate test report
generate_report() {
    print_section "Test Summary"
    
    local total=$((PASSED_TESTS + FAILED_TESTS + SKIPPED_TESTS))
    local pass_rate=0
    if [ $total -gt 0 ]; then
        pass_rate=$((PASSED_TESTS * 100 / total))
    fi
    
    {
        echo "Claude Code Monitoring - Test Report"
        echo "===================================="
        echo "Generated: $(date)"
        echo ""
        echo "Test Results:"
        echo "  Total Tests:    $total"
        echo "  Passed:         $PASSED_TESTS"
        echo "  Failed:         $FAILED_TESTS"
        echo "  Skipped:        $SKIPPED_TESTS"
        echo "  Pass Rate:      $pass_rate%"
        echo ""
        
        if [ $FAILED_TESTS -gt 0 ]; then
            echo "Status: FAILED"
        elif [ $SKIPPED_TESTS -eq $total ]; then
            echo "Status: NO TESTS RUN"
        else
            echo "Status: PASSED"
        fi
    } | tee "$REPORT_FILE"
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    if [ $FAILED_TESTS -gt 0 ]; then
        echo -e "${CYAN}║ ${RED}${BOLD}                    ✗ TESTS FAILED                          ${CYAN}║${NC}"
    elif [ $SKIPPED_TESTS -eq $total ]; then
        echo -e "${CYAN}║ ${YELLOW}${BOLD}                   NO TESTS WERE RUN                        ${CYAN}║${NC}"
    else
        echo -e "${CYAN}║ ${GREEN}${BOLD}                    ✓ ALL TESTS PASSED                      ${CYAN}║${NC}"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
}

# Clean up temporary files
cleanup() {
    if [ -d "$COVERAGE_DIR" ] && [ "$KEEP_COVERAGE" != "true" ]; then
        rm -rf "$COVERAGE_DIR"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -c|--coverage)
                RUN_COVERAGE=true
                shift
                ;;
            -k|--keep-coverage)
                KEEP_COVERAGE=true
                shift
                ;;
            -u|--unit-only)
                UNIT_ONLY=true
                shift
                ;;
            -l|--lint-only)
                LINT_ONLY=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -v, --verbose         Show verbose output
    -c, --coverage        Generate coverage reports
    -k, --keep-coverage   Keep coverage reports after tests
    -u, --unit-only       Run only unit tests
    -l, --lint-only       Run only linting checks
    -h, --help            Show this help message

Examples:
    $0                    Run all tests
    $0 -v                 Run all tests with verbose output
    $0 -c                 Run tests and generate coverage
    $0 -u                 Run only unit tests
    $0 -l                 Run only linting checks
EOF
}

# Main execution
main() {
    print_banner
    parse_args "$@"
    
    # Set up trap for cleanup
    trap cleanup EXIT
    
    # Check dependencies first
    check_dependencies
    
    # Run tests based on options
    if [ "$LINT_ONLY" == "true" ]; then
        run_shellcheck
        run_yamllint
    elif [ "$UNIT_ONLY" == "true" ]; then
        run_bats_tests
    else
        run_bats_tests
        run_shellcheck
        run_yamllint
        run_integration_tests
    fi
    
    # Generate coverage if requested
    if [ "$RUN_COVERAGE" == "true" ]; then
        generate_coverage
    fi
    
    # Generate final report
    generate_report
    
    # Exit with appropriate code
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"