# Testing Documentation for Claude Code Monitoring

## Overview

Claude Code Monitoring employs a comprehensive testing strategy to ensure reliability across different platforms and container runtimes. Our test suite includes unit tests, integration tests, static analysis, and continuous integration checks.

## Test Suite Architecture

### Test Categories

1. **Unit Tests** - Test individual functions and scripts in isolation
2. **Integration Tests** - Test component interactions and system behavior
3. **Static Analysis** - Code quality and syntax validation
4. **Platform Tests** - Platform-specific functionality testing
5. **Security Scans** - Vulnerability detection and security validation

### Test Files Structure

```
cc-monitoring/
├── test-runner.sh              # Main test orchestrator
├── test-system-validation.sh   # System requirements validator
├── test_manage.bats           # Unit tests for manage.sh
├── test_check_claude_metrics.bats  # Unit tests for metrics checking
├── test_update_wsl_ip.bats    # Unit tests for WSL IP updates
├── run_tests.sh               # Legacy test runner
├── run_update_wsl_ip_tests.sh # WSL-specific test runner
└── .github/workflows/test.yml # CI/CD pipeline configuration
```

## Quick Start Guide

### Prerequisites

Install test dependencies based on your platform:

#### macOS
```bash
brew install bats-core shellcheck yamllint
# Optional: brew install kcov (for coverage)
```

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y bats shellcheck yamllint
# Optional: sudo apt-get install -y kcov
```

#### Python Tools
```bash
pip install yamllint
# Optional: pip install bashcov
```

### Running Tests

#### Run All Tests
```bash
./test-runner.sh
```

#### Run with Verbose Output
```bash
./test-runner.sh --verbose
```

#### Run Only Unit Tests
```bash
./test-runner.sh --unit-only
```

#### Run Only Linting
```bash
./test-runner.sh --lint-only
```

#### Generate Coverage Reports
```bash
./test-runner.sh --coverage
```

#### Using Make
```bash
make test          # Run all tests
make test-unit     # Run unit tests only
make test-lint     # Run linting only
make test-coverage # Run tests with coverage
```

## Test Suite Components

### 1. BATS Unit Tests

BATS (Bash Automated Testing System) is used for unit testing shell scripts.

**Test Files:**
- `test_manage.bats` - Tests for the main management script
- `test_check_claude_metrics.bats` - Tests for metrics verification
- `test_update_wsl_ip.bats` - Tests for WSL IP update functionality

**Example Test:**
```bash
@test "detect_runtime correctly identifies Docker" {
    MOCK_DOCKER_EXISTS=0
    MOCK_PODMAN_EXISTS=1
    create_runtime_mocks
    
    source ./manage.sh
    detect_runtime
    
    [ "$RUNTIME" = "docker" ]
}
```

### 2. ShellCheck Static Analysis

ShellCheck validates shell script syntax and identifies common issues.

**Checked Files:**
- `manage.sh`
- `check-claude-metrics.sh`
- `update-wsl-ip.sh`
- `test-runner.sh`
- All test scripts

**Configuration:**
- Exclusion: SC1091 (not following sourced files)
- Style: Error on all severity levels

### 3. YAML Validation

yamllint ensures all YAML configuration files are valid.

**Validated Files:**
- `docker-compose.yaml`
- `prometheus.yml` (generated)
- Grafana provisioning files
- GitHub Actions workflows

**Configuration:**
- Profile: relaxed
- Line length: disabled
- Indentation: 2 spaces

### 4. Integration Tests

Integration tests verify the complete system functionality.

**Test Scenarios:**
- Container startup and health checks
- Service connectivity
- Metrics collection pipeline
- Dashboard provisioning
- Cross-platform compatibility

### 5. Platform-Specific Tests

Tests tailored for different environments:

**WSL (Windows Subsystem for Linux):**
- IP address detection
- Network connectivity
- File path handling

**macOS:**
- Docker Desktop integration
- host.docker.internal resolution
- Podman machine handling

**Linux:**
- Native Docker/Podman support
- Direct localhost connectivity
- SystemD integration (where applicable)

## Coverage Requirements

### Current Coverage Goals

- **Critical Path Coverage:** 100%
  - Container management functions
  - Configuration generation
  - Platform detection
  
- **Overall Coverage Target:** 80%
  - All user-facing commands
  - Error handling paths
  - Configuration validation

### Measuring Coverage

Generate coverage reports using kcov:

```bash
./test-runner.sh --coverage --keep-coverage
```

Coverage reports are generated in the `coverage/` directory.

## Contributing Guidelines

### Writing New Tests

1. **Unit Tests (BATS)**
   ```bash
   @test "description of what is being tested" {
       # Setup test conditions
       
       # Execute function/command
       run command_to_test
       
       # Assert results
       [ "$status" -eq 0 ]
       [ "$output" = "expected output" ]
   }
   ```

2. **Integration Tests**
   - Add to `test-runner.sh` in the `run_integration_tests()` function
   - Use Docker/Podman commands to verify system state
   - Include cleanup in test teardown

3. **Test Naming Conventions**
   - Unit test files: `test_<script_name>.bats`
   - Integration test functions: `test_<feature>_integration()`
   - Use descriptive test names that explain the scenario

### Test Development Workflow

1. **Before Writing Code**
   - Write tests for new functionality first (TDD)
   - Ensure tests fail initially

2. **During Development**
   - Run tests frequently: `./test-runner.sh --unit-only`
   - Fix failing tests immediately

3. **Before Committing**
   - Run full test suite: `./test-runner.sh`
   - Ensure all tests pass
   - Check coverage if adding new functions

4. **CI Integration**
   - All PRs must pass CI checks
   - New features require corresponding tests
   - Coverage should not decrease

## Troubleshooting

### Common Issues

#### 1. BATS Not Found
```bash
# macOS
brew install bats-core

# Linux
sudo apt-get install bats
```

#### 2. ShellCheck Warnings
```bash
# View specific warnings
shellcheck -e SC1091 manage.sh

# Fix automatically where possible
shellcheck -f diff manage.sh | patch -p1
```

#### 3. Coverage Not Generated
```bash
# Install kcov
# Ubuntu/Debian
sudo apt-get install kcov

# Build from source for other platforms
git clone https://github.com/SimonKagstrom/kcov.git
cd kcov && mkdir build && cd build
cmake .. && make && sudo make install
```

#### 4. Tests Hanging
- Check for infinite loops in tested scripts
- Verify mock commands exit properly
- Use timeout in integration tests

#### 5. Platform-Specific Failures
- Use `FORCE_DOCKER=true` or `FORCE_PODMAN=true` to test specific runtimes
- Check platform detection in `detect_platform()` function
- Verify network connectivity for WSL tests

### Debug Mode

Enable debug output for troubleshooting:

```bash
# Debug test runner
DEBUG=1 ./test-runner.sh --verbose

# Debug specific test
DEBUG=1 bats -v test_manage.bats

# Debug manage.sh
DEBUG=1 ./manage.sh status
```

## Continuous Integration

### GitHub Actions Workflow

The CI pipeline runs on every push and pull request:

1. **Test Matrix**
   - OS: Ubuntu Latest, macOS Latest
   - Container Runtime: Docker, Podman

2. **Job Stages**
   - Dependency installation
   - Linting (ShellCheck, yamllint)
   - Unit tests (BATS)
   - Integration tests
   - Security scanning (Trivy)

3. **Artifacts**
   - Test reports
   - Coverage data
   - Security scan results

### Running CI Locally

Simulate CI environment locally:

```bash
# Run with CI environment variable
CI=true ./test-runner.sh

# Test specific OS behavior
# WSL
WSL_DISTRO_NAME=Ubuntu ./test-runner.sh

# macOS
FORCE_MACOS=true ./test-runner.sh
```

## Best Practices

1. **Test Isolation**
   - Each test should be independent
   - Use setup/teardown for clean state
   - Don't rely on test execution order

2. **Mock External Dependencies**
   - Mock Docker/Podman commands in unit tests
   - Use test containers for integration tests
   - Simulate network conditions

3. **Error Testing**
   - Test error conditions explicitly
   - Verify error messages
   - Check exit codes

4. **Performance**
   - Keep unit tests fast (<100ms each)
   - Use `--unit-only` during development
   - Reserve slow tests for integration suite

5. **Documentation**
   - Document complex test scenarios
   - Explain mock behaviors
   - Include examples in test names

## Future Enhancements

- [ ] Add performance benchmarks
- [ ] Implement chaos testing for reliability
- [ ] Add visual regression tests for dashboards
- [ ] Create test data generators
- [ ] Implement contract testing for APIs
- [ ] Add mutation testing for coverage quality