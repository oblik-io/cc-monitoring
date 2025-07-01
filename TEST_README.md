# Unit Tests for manage.sh

This directory contains comprehensive unit tests for the `manage.sh` script using the BATS (Bash Automated Testing System) framework.

## Prerequisites

Install BATS before running the tests:

### macOS
```bash
brew install bats-core
```

### Ubuntu/Debian
```bash
sudo apt-get install bats
```

### Other Systems
See the [BATS installation guide](https://github.com/bats-core/bats-core#installation)

## Running the Tests

### Quick Start
```bash
./run_tests.sh
```

### Verbose Mode
```bash
./run_tests.sh --verbose
# or
./run_tests.sh -v
```

### Run Specific Tests
```bash
# Run a single test by name pattern
bats test_manage.bats --filter "detects podman"

# Run tests matching a pattern
bats test_manage.bats --filter "platform"
```

### Run with TAP Output
```bash
bats test_manage.bats --tap
```

## Test Coverage

The test suite covers:

### Container Engine Detection
- Podman detection when available
- Docker detection as fallback
- Docker Compose v2 vs v1 detection
- Failure when no container engine is found

### Platform Detection
- WSL environment detection and IP resolution
- Native Linux (uses localhost)
- macOS (uses host.docker.internal)
- WSL IP detection failure handling

### Core Functions
- `initial_setup()` - Environment configuration
- `start_stack()` and `start_stack_podman()` - Stack initialization
- `stop_stack()` - Graceful shutdown
- `clean_stack()` - Complete cleanup including volumes
- `reset_podman_vm()` - VM restart for Podman
- `show_logs()` and `show_status()` - Monitoring commands

### Configuration Management
- .env file creation and preservation
- Prometheus configuration generation
- Grafana datasource configuration
- Template file validation

### Error Handling
- Missing template files
- Failed IP detection in WSL
- Missing pods/containers
- Invalid commands
- Script error propagation (set -e)

### Platform-Specific Behavior
- SELinux labels for Podman volumes (`:Z` suffix)
- Different networking for Docker vs Podman
- Platform-specific reset command restrictions

## Test Structure

Each test follows this pattern:

```bash
@test "description of what is being tested" {
    # Setup test environment
    create_mock "command" 'mock behavior'
    
    # Run the test
    run ./test_script.sh
    
    # Assert results
    [ "$status" -eq 0 ]
    [[ "$output" =~ "expected output" ]]
}
```

## Mocking Strategy

The tests use command mocking to simulate external dependencies:

1. **Path Injection**: Test-specific `bin/` directory is prepended to PATH
2. **Mock Scripts**: Executable scripts that simulate command behavior
3. **Conditional Responses**: Mocks can respond differently based on arguments

Example mock:
```bash
create_mock "docker" '
if [[ "$1" == "compose" && "$2" == "version" ]]; then
    echo "Docker Compose version v2.20.0"
    exit 0
fi
exit $MOCK_DOCKER_EXISTS
'
```

## Adding New Tests

1. Add test functions to `test_manage.bats`
2. Follow the naming convention: `@test "component: specific behavior"`
3. Use descriptive test names that explain what is being tested
4. Include both positive and negative test cases
5. Clean up any created files in teardown

## Debugging Tests

### Run in Debug Mode
```bash
# Shows each command as it executes
bats test_manage.bats --trace
```

### Inspect Test Output
```bash
# Keep test artifacts for inspection
bats test_manage.bats --no-tempdir-cleanup
```

### Print Debug Information
Add debug output in tests:
```bash
@test "debugging example" {
    echo "Debug: variable=$variable" >&3
    run ./script.sh
    echo "Debug: output=$output" >&3
    echo "Debug: status=$status" >&3
}
```

## CI/CD Integration

The tests can be integrated into CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Install BATS
  run: |
    sudo npm install -g bats
    
- name: Run Tests
  run: ./run_tests.sh
```

## Known Limitations

1. **Network Operations**: External network calls are not mocked
2. **Time-based Tests**: No tests for timeouts or delays
3. **Interactive Commands**: Cannot test interactive prompts
4. **Real Container Operations**: Tests don't actually start containers

## Contributing

When adding new features to `manage.sh`:

1. Write tests first (TDD approach)
2. Ensure all existing tests pass
3. Add tests for edge cases
4. Document any new mocking requirements
5. Update this README if adding new test categories