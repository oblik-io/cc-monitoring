# Claude Code Monitoring - Makefile
# ================================

.PHONY: all test test-unit test-integration lint lint-shell lint-yaml coverage clean help install-deps ci docker-test podman-test

# Default shell
SHELL := /bin/bash

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Directories
COVERAGE_DIR := coverage
BUILD_DIR := build
REPORT_DIR := reports

# Tools
BATS := bats
SHELLCHECK := shellcheck
YAMLLINT := yamllint
DOCKER := docker
PODMAN := podman

# Default target
all: test

# Help target
help:
	@echo "Claude Code Monitoring - Makefile Targets"
	@echo "========================================"
	@echo ""
	@echo "Testing:"
	@echo "  make test           - Run all tests (unit + integration + lint)"
	@echo "  make test-unit      - Run unit tests only"
	@echo "  make test-integration - Run integration tests only"
	@echo "  make test-quick     - Run quick tests (unit + lint)"
	@echo ""
	@echo "Linting:"
	@echo "  make lint           - Run all linters (shell + yaml)"
	@echo "  make lint-shell     - Run ShellCheck on shell scripts"
	@echo "  make lint-yaml      - Run yamllint on YAML files"
	@echo ""
	@echo "Coverage:"
	@echo "  make coverage       - Generate test coverage report"
	@echo "  make coverage-html  - Generate HTML coverage report"
	@echo ""
	@echo "Container Testing:"
	@echo "  make docker-test    - Test with Docker"
	@echo "  make podman-test    - Test with Podman"
	@echo ""
	@echo "CI/CD:"
	@echo "  make ci             - Run CI checks locally"
	@echo "  make ci-deps        - Install CI dependencies"
	@echo ""
	@echo "Utilities:"
	@echo "  make install-deps   - Install all dependencies"
	@echo "  make clean          - Clean up generated files"
	@echo "  make verify-deps    - Verify all dependencies are installed"

# Install dependencies
install-deps:
	@echo -e "$(BLUE)Installing dependencies...$(NC)"
	@if [[ "$$(uname)" == "Darwin" ]]; then \
		echo "Installing dependencies for macOS..."; \
		command -v brew >/dev/null 2>&1 || { echo "Homebrew is required but not installed. Aborting." >&2; exit 1; }; \
		brew install bats-core shellcheck yamllint || true; \
		pip3 install bashcov || true; \
	elif [[ "$$(uname)" == "Linux" ]]; then \
		echo "Installing dependencies for Linux..."; \
		if command -v apt-get >/dev/null 2>&1; then \
			sudo apt-get update && sudo apt-get install -y bats shellcheck yamllint kcov; \
		elif command -v yum >/dev/null 2>&1; then \
			sudo yum install -y bats ShellCheck yamllint; \
		else \
			echo "Unsupported package manager"; \
			exit 1; \
		fi; \
		pip3 install bashcov || true; \
	else \
		echo "Unsupported OS"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)Dependencies installed!$(NC)"

# Verify dependencies
verify-deps:
	@echo -e "$(BLUE)Verifying dependencies...$(NC)"
	@command -v $(BATS) >/dev/null 2>&1 && echo -e "$(GREEN)✓ BATS is installed$(NC)" || echo -e "$(RED)✗ BATS is not installed$(NC)"
	@command -v $(SHELLCHECK) >/dev/null 2>&1 && echo -e "$(GREEN)✓ ShellCheck is installed$(NC)" || echo -e "$(RED)✗ ShellCheck is not installed$(NC)"
	@command -v $(YAMLLINT) >/dev/null 2>&1 && echo -e "$(GREEN)✓ yamllint is installed$(NC)" || echo -e "$(RED)✗ yamllint is not installed$(NC)"
	@command -v kcov >/dev/null 2>&1 && echo -e "$(GREEN)✓ kcov is installed$(NC)" || echo -e "$(YELLOW)⚠ kcov is not installed (optional)$(NC)"
	@command -v $(DOCKER) >/dev/null 2>&1 && echo -e "$(GREEN)✓ Docker is installed$(NC)" || echo -e "$(YELLOW)⚠ Docker is not installed$(NC)"
	@command -v $(PODMAN) >/dev/null 2>&1 && echo -e "$(GREEN)✓ Podman is installed$(NC)" || echo -e "$(YELLOW)⚠ Podman is not installed$(NC)"

# Run all tests
test: verify-deps lint test-unit test-integration
	@echo -e "$(GREEN)All tests completed!$(NC)"

# Run unit tests only
test-unit:
	@echo -e "$(BLUE)Running unit tests...$(NC)"
	@./test-runner.sh --unit-only

# Run integration tests only
test-integration:
	@echo -e "$(BLUE)Running integration tests...$(NC)"
	@if command -v $(DOCKER) >/dev/null 2>&1 || command -v $(PODMAN) >/dev/null 2>&1; then \
		echo "Container runtime available, running integration tests..."; \
		./manage.sh configure && ./manage.sh ps; \
	else \
		echo -e "$(YELLOW)No container runtime available, skipping integration tests$(NC)"; \
	fi

# Quick tests (unit + lint)
test-quick: lint test-unit
	@echo -e "$(GREEN)Quick tests completed!$(NC)"

# Run all linters
lint: lint-shell lint-yaml
	@echo -e "$(GREEN)All linting completed!$(NC)"

# Run ShellCheck
lint-shell:
	@echo -e "$(BLUE)Running ShellCheck...$(NC)"
	@if command -v $(SHELLCHECK) >/dev/null 2>&1; then \
		find . -name "*.sh" -not -path "./coverage/*" -not -path "./.git/*" -exec $(SHELLCHECK) -e SC1091 {} + && \
		echo -e "$(GREEN)✓ ShellCheck passed$(NC)" || \
		{ echo -e "$(RED)✗ ShellCheck failed$(NC)"; exit 1; }; \
	else \
		echo -e "$(YELLOW)ShellCheck not installed, skipping$(NC)"; \
	fi

# Run yamllint
lint-yaml:
	@echo -e "$(BLUE)Running yamllint...$(NC)"
	@if command -v $(YAMLLINT) >/dev/null 2>&1; then \
		find . -name "*.yml" -o -name "*.yaml" -not -path "./coverage/*" -not -path "./.git/*" | \
		xargs $(YAMLLINT) -d relaxed && \
		echo -e "$(GREEN)✓ yamllint passed$(NC)" || \
		{ echo -e "$(RED)✗ yamllint failed$(NC)"; exit 1; }; \
	else \
		echo -e "$(YELLOW)yamllint not installed, skipping$(NC)"; \
	fi

# Generate coverage report
coverage:
	@echo -e "$(BLUE)Generating coverage report...$(NC)"
	@mkdir -p $(COVERAGE_DIR)
	@./test-runner.sh --coverage --keep-coverage
	@echo -e "$(GREEN)Coverage report generated in $(COVERAGE_DIR)/$(NC)"

# Generate HTML coverage report
coverage-html: coverage
	@if [ -d "$(COVERAGE_DIR)" ]; then \
		echo -e "$(BLUE)Generating HTML coverage report...$(NC)"; \
		if command -v kcov >/dev/null 2>&1; then \
			echo "HTML reports available in $(COVERAGE_DIR)/*/index.html"; \
		else \
			echo -e "$(YELLOW)kcov not available, cannot generate HTML reports$(NC)"; \
		fi; \
	else \
		echo -e "$(RED)No coverage data found. Run 'make coverage' first.$(NC)"; \
	fi

# Docker-specific tests
docker-test:
	@echo -e "$(BLUE)Running Docker tests...$(NC)"
	@if command -v $(DOCKER) >/dev/null 2>&1; then \
		./manage.sh configure && \
		./manage.sh up -d && \
		sleep 10 && \
		./manage.sh ps && \
		curl -f http://localhost:9090/-/ready && \
		curl -f http://localhost:3000/api/health && \
		./manage.sh down && \
		echo -e "$(GREEN)✓ Docker tests passed$(NC)"; \
	else \
		echo -e "$(RED)Docker not available$(NC)"; \
		exit 1; \
	fi

# Podman-specific tests
podman-test:
	@echo -e "$(BLUE)Running Podman tests...$(NC)"
	@if command -v $(PODMAN) >/dev/null 2>&1; then \
		FORCE_PODMAN=true ./manage.sh configure && \
		FORCE_PODMAN=true ./manage.sh up -d && \
		sleep 10 && \
		FORCE_PODMAN=true ./manage.sh ps && \
		FORCE_PODMAN=true ./manage.sh down && \
		echo -e "$(GREEN)✓ Podman tests passed$(NC)"; \
	else \
		echo -e "$(RED)Podman not available$(NC)"; \
		exit 1; \
	fi

# Run CI checks locally
ci: ci-deps
	@echo -e "$(BLUE)Running CI checks locally...$(NC)"
	@$(MAKE) lint
	@$(MAKE) test-unit
	@$(MAKE) test-integration
	@echo -e "$(GREEN)CI checks passed!$(NC)"

# Install CI-specific dependencies
ci-deps:
	@echo -e "$(BLUE)Checking CI dependencies...$(NC)"
	@command -v $(BATS) >/dev/null 2>&1 || { echo "Installing BATS..."; $(MAKE) install-deps; }
	@command -v $(SHELLCHECK) >/dev/null 2>&1 || { echo "Installing ShellCheck..."; $(MAKE) install-deps; }
	@command -v $(YAMLLINT) >/dev/null 2>&1 || { echo "Installing yamllint..."; $(MAKE) install-deps; }

# Clean up generated files
clean:
	@echo -e "$(BLUE)Cleaning up...$(NC)"
	@rm -rf $(COVERAGE_DIR) $(BUILD_DIR) $(REPORT_DIR)
	@rm -f test-report.txt
	@rm -f prometheus.yml grafana-provisioning/datasources/prometheus.yml
	@echo -e "$(GREEN)Cleanup completed!$(NC)"

# Watch for changes and run tests
watch:
	@echo -e "$(BLUE)Watching for changes...$(NC)"
	@while true; do \
		inotifywait -e modify,create,delete -r . --exclude '(coverage|.git|.env)' 2>/dev/null && \
		clear && \
		$(MAKE) test-quick; \
	done

# Generate test report
report:
	@echo -e "$(BLUE)Generating detailed test report...$(NC)"
	@mkdir -p $(REPORT_DIR)
	@./test-runner.sh --verbose > $(REPORT_DIR)/test-output.log 2>&1
	@if [ -f test-report.txt ]; then \
		cp test-report.txt $(REPORT_DIR)/; \
		echo -e "$(GREEN)Test report saved to $(REPORT_DIR)/test-report.txt$(NC)"; \
	fi

# Check code quality
quality: lint
	@echo -e "$(BLUE)Checking code quality...$(NC)"
	@# Add additional quality checks here
	@echo -e "$(GREEN)Code quality checks passed!$(NC)"

# Run performance tests
perf-test:
	@echo -e "$(BLUE)Running performance tests...$(NC)"
	@# Add performance testing logic here
	@echo -e "$(YELLOW)Performance tests not yet implemented$(NC)"

# Validate all configurations
validate-config:
	@echo -e "$(BLUE)Validating configurations...$(NC)"
	@$(MAKE) lint-yaml
	@if [ -f docker-compose.yaml ]; then \
		$(DOCKER) compose config >/dev/null 2>&1 && \
		echo -e "$(GREEN)✓ docker-compose.yaml is valid$(NC)" || \
		echo -e "$(RED)✗ docker-compose.yaml is invalid$(NC)"; \
	fi

.SILENT: help verify-deps