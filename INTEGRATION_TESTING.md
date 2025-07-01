# Integration Testing Documentation

## Overview

Integration testing for Claude Code Monitoring verifies that all components work together correctly across different platforms and container runtimes. These tests ensure the monitoring stack functions as a cohesive system.

## Integration Test Architecture

### Test Levels

1. **Component Integration** - Individual service interactions
2. **System Integration** - Full stack functionality
3. **Platform Integration** - Cross-platform compatibility
4. **End-to-End Testing** - Complete user workflows

### Test Environment Setup

Integration tests run in isolated environments to prevent interference:

```bash
# Docker Environment
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1

# Podman Environment
FORCE_PODMAN=true
PODMAN_USERNS=keep-id

# Test Isolation
TEST_PREFIX=ccm_test_
TEST_NETWORK=${TEST_PREFIX}network
TEST_VOLUMES=${TEST_PREFIX}data
```

## Integration Test Scenarios

### 1. Container Lifecycle Tests

#### Test: Full Stack Startup
```bash
@test "integration: full stack starts successfully" {
    run ./manage.sh up -d
    assert_success
    
    # Wait for services
    sleep 30
    
    # Verify all containers running
    run ./manage.sh ps
    assert_output --partial "prometheus"
    assert_output --partial "grafana"
    assert_output --partial "node-exporter"
    
    # Cleanup
    run ./manage.sh down
}
```

#### Test: Service Health Checks
```bash
@test "integration: all services are healthy" {
    ./manage.sh up -d
    sleep 30
    
    # Check Prometheus
    run curl -f http://localhost:9090/-/ready
    assert_success
    
    # Check Grafana
    run curl -f http://localhost:3000/api/health
    assert_success
    
    # Check metrics endpoint
    run curl -f http://localhost:9464/metrics
    assert_success
}
```

### 2. Configuration Management Tests

#### Test: Dynamic Configuration Updates
```bash
@test "integration: configuration updates propagate" {
    # Initial setup
    ./manage.sh configure
    ./manage.sh up -d
    
    # Modify configuration
    export CLAUDE_CODE_EXPORTER_HOST="10.0.0.100"
    ./manage.sh configure
    
    # Restart and verify
    ./manage.sh restart
    sleep 20
    
    # Check new configuration is active
    run docker exec ccm_prometheus cat /etc/prometheus/prometheus.yml
    assert_output --partial "10.0.0.100:9464"
}
```

### 3. Data Persistence Tests

#### Test: Metrics Data Persistence
```bash
@test "integration: metrics survive restart" {
    # Start and collect metrics
    ./manage.sh up -d
    sleep 60  # Collect data for 1 minute
    
    # Query current metric count
    METRICS_BEFORE=$(curl -s http://localhost:9090/api/v1/query?query=up | jq '.data.result | length')
    
    # Restart stack
    ./manage.sh restart
    sleep 30
    
    # Verify data persisted
    METRICS_AFTER=$(curl -s http://localhost:9090/api/v1/query?query=up | jq '.data.result | length')
    [ "$METRICS_AFTER" -ge "$METRICS_BEFORE" ]
}
```

### 4. Network Connectivity Tests

#### Test: Service Discovery
```bash
@test "integration: services can communicate" {
    ./manage.sh up -d
    sleep 30
    
    # Test Grafana can reach Prometheus
    run docker exec ccm_grafana curl -f http://prometheus:9090/api/v1/query?query=up
    assert_success
    
    # Test Prometheus can scrape targets
    run curl -s http://localhost:9090/api/v1/targets
    assert_output --partial '"health":"up"'
}
```

### 5. Platform-Specific Integration

#### WSL Integration Test
```bash
@test "integration: WSL IP detection and configuration" {
    [ -z "$WSL_DISTRO_NAME" ] && skip "Not running in WSL"
    
    # Get WSL IP
    WSL_IP=$(./update-wsl-ip.sh --dry-run | grep "WSL IP:" | cut -d' ' -f3)
    
    # Configure with WSL IP
    ./manage.sh configure
    
    # Verify configuration
    grep -q "$WSL_IP" prometheus.yml
    assert_success
}
```

#### macOS Integration Test
```bash
@test "integration: macOS host.docker.internal resolution" {
    [ "$(uname)" != "Darwin" ] && skip "Not running on macOS"
    
    ./manage.sh configure
    ./manage.sh up -d
    
    # Verify host resolution
    run docker exec ccm_prometheus nslookup host.docker.internal
    assert_success
}
```

#### Podman Integration Test
```bash
@test "integration: Podman pod networking" {
    command -v podman >/dev/null || skip "Podman not available"
    
    FORCE_PODMAN=true ./manage.sh up -d
    sleep 30
    
    # Verify pod created
    run podman pod ps
    assert_output --partial "ccm"
    
    # Test inter-container communication
    run podman exec ccm-grafana curl -f http://localhost:9090/api/v1/query?query=up
    assert_success
}
```

## End-to-End Test Workflows

### Workflow 1: Complete Setup and Monitoring
```bash
#!/bin/bash
# End-to-end test for complete monitoring setup

test_e2e_complete_setup() {
    echo "=== E2E Test: Complete Setup ==="
    
    # 1. Clean environment
    ./manage.sh clean
    
    # 2. Configure monitoring
    export CLAUDE_CODE_ENABLE_TELEMETRY=1
    export OTEL_METRICS_EXPORTER=prometheus
    ./manage.sh configure
    
    # 3. Start monitoring stack
    ./manage.sh up -d
    
    # 4. Wait for services
    echo "Waiting for services to be ready..."
    for i in {1..30}; do
        if curl -s http://localhost:9090/-/ready >/dev/null && \
           curl -s http://localhost:3000/api/health >/dev/null; then
            break
        fi
        sleep 2
    done
    
    # 5. Simulate Claude Code metrics
    echo "Simulating metrics..."
    ./test/simulate-metrics.sh
    
    # 6. Verify metrics collection
    sleep 30
    METRICS=$(curl -s http://localhost:9090/api/v1/query?query=claude_code_sessions_total)
    
    if echo "$METRICS" | grep -q "value"; then
        echo "✅ Metrics collected successfully"
    else
        echo "❌ No metrics found"
        return 1
    fi
    
    # 7. Check Grafana dashboards
    DASHBOARDS=$(curl -s -u admin:admin http://localhost:3000/api/dashboards)
    if echo "$DASHBOARDS" | grep -q "Claude Code"; then
        echo "✅ Dashboards loaded successfully"
    else
        echo "❌ Dashboards not found"
        return 1
    fi
    
    # 8. Test data persistence
    ./manage.sh restart
    sleep 30
    
    METRICS_AFTER=$(curl -s http://localhost:9090/api/v1/query?query=claude_code_sessions_total)
    if echo "$METRICS_AFTER" | grep -q "value"; then
        echo "✅ Data persisted after restart"
    else
        echo "❌ Data lost after restart"
        return 1
    fi
    
    # 9. Cleanup
    ./manage.sh down
    
    echo "✅ E2E test completed successfully"
    return 0
}
```

### Workflow 2: Failure Recovery Test
```bash
#!/bin/bash
# Test system recovery from failures

test_e2e_failure_recovery() {
    echo "=== E2E Test: Failure Recovery ==="
    
    # Setup
    ./manage.sh up -d
    sleep 30
    
    # 1. Test container crash recovery
    echo "Testing container crash recovery..."
    docker kill ccm_prometheus
    sleep 5
    
    # Verify auto-restart
    if docker ps | grep -q ccm_prometheus; then
        echo "✅ Prometheus auto-restarted"
    else
        echo "❌ Prometheus did not restart"
        return 1
    fi
    
    # 2. Test configuration corruption recovery
    echo "Testing configuration recovery..."
    echo "corrupted" > prometheus.yml
    ./manage.sh restart
    
    # Should regenerate config
    if grep -q "global:" prometheus.yml; then
        echo "✅ Configuration regenerated"
    else
        echo "❌ Configuration not recovered"
        return 1
    fi
    
    # 3. Test network partition
    echo "Testing network partition handling..."
    docker network disconnect ccm_network ccm_grafana
    sleep 5
    docker network connect ccm_network ccm_grafana
    
    # Verify recovery
    sleep 10
    if curl -s http://localhost:3000/api/health | grep -q "ok"; then
        echo "✅ Network recovered"
    else
        echo "❌ Network recovery failed"
        return 1
    fi
    
    echo "✅ Failure recovery test completed"
    return 0
}
```

## Integration Test Utilities

### Test Helper Functions
```bash
# Wait for service to be ready
wait_for_service() {
    local url=$1
    local timeout=${2:-60}
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if curl -sf "$url" >/dev/null; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    return 1
}

# Verify metric exists
check_metric() {
    local metric=$1
    local prometheus_url="http://localhost:9090"
    
    curl -s "$prometheus_url/api/v1/query?query=$metric" | \
        jq -r '.data.result[0].value[1]' 2>/dev/null
}

# Clean test environment
cleanup_test_env() {
    ./manage.sh down 2>/dev/null || true
    docker network rm ${TEST_NETWORK} 2>/dev/null || true
    docker volume rm ${TEST_VOLUMES} 2>/dev/null || true
}
```

### Mock Claude Code Metrics Generator
```bash
#!/bin/bash
# simulate-metrics.sh - Generate test metrics

generate_test_metrics() {
    cat << EOF
# HELP claude_code_sessions_total Total number of sessions
# TYPE claude_code_sessions_total counter
claude_code_sessions_total{version="1.0.25"} 42

# HELP claude_code_operations_total Total operations performed
# TYPE claude_code_operations_total counter
claude_code_operations_total{operation="read_file"} 156
claude_code_operations_total{operation="write_file"} 89
claude_code_operations_total{operation="execute_command"} 234

# HELP claude_code_active_sessions Current active sessions
# TYPE claude_code_active_sessions gauge
claude_code_active_sessions 3

# HELP claude_code_operation_duration_seconds Operation duration
# TYPE claude_code_operation_duration_seconds histogram
claude_code_operation_duration_seconds_bucket{operation="read_file",le="0.1"} 120
claude_code_operation_duration_seconds_bucket{operation="read_file",le="0.5"} 145
claude_code_operation_duration_seconds_bucket{operation="read_file",le="1"} 155
claude_code_operation_duration_seconds_bucket{operation="read_file",le="+Inf"} 156
EOF
}

# Start mock metrics server
python3 -m http.server 9464 &
SERVER_PID=$!
echo "$$" > /tmp/mock_metrics.pid

# Serve metrics
while true; do
    generate_test_metrics > metrics
    sleep 10
done
```

## Running Integration Tests

### Local Development
```bash
# Run all integration tests
./test-runner.sh --integration

# Run specific platform tests
FORCE_DOCKER=true ./test-runner.sh --integration
FORCE_PODMAN=true ./test-runner.sh --integration

# Run with debug output
DEBUG=1 ./test-runner.sh --integration --verbose
```

### CI Environment
```bash
# GitHub Actions
- name: Run integration tests
  run: |
    ./test-runner.sh --integration
    
# With coverage
- name: Integration tests with coverage
  run: |
    ./test-runner.sh --integration --coverage
```

### Docker-in-Docker Testing
```bash
# For testing container operations
docker run --rm -it \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v $(pwd):/workspace \
    -w /workspace \
    docker:dind \
    ./test-runner.sh --integration
```

## Troubleshooting Integration Tests

### Common Issues

#### Services Not Starting
```bash
# Check logs
./manage.sh logs

# Verify ports available
lsof -i :9090
lsof -i :3000
lsof -i :9464

# Check resource limits
docker system df
```

#### Network Connectivity Issues
```bash
# Test container networking
docker network inspect ccm_network

# Verify DNS resolution
docker exec ccm_prometheus nslookup grafana

# Check firewall rules
sudo iptables -L -n | grep -E "9090|3000|9464"
```

#### Timing Issues
```bash
# Increase wait times in tests
export INTEGRATION_TEST_TIMEOUT=120

# Add retry logic
for i in {1..5}; do
    if run_test; then
        break
    fi
    sleep 10
done
```

## Best Practices

1. **Test Isolation**
   - Use unique prefixes for test resources
   - Clean up after each test
   - Don't depend on external services

2. **Reliability**
   - Add proper wait conditions
   - Use health checks, not fixed delays
   - Implement retry mechanisms

3. **Performance**
   - Run integration tests in parallel where possible
   - Cache container images
   - Use lightweight test data

4. **Debugging**
   - Capture logs on failure
   - Save test artifacts
   - Use verbose output in CI

5. **Platform Testing**
   - Test on all supported platforms
   - Use platform-specific assertions
   - Document platform limitations

## Future Enhancements

- [ ] Chaos engineering tests
- [ ] Performance benchmarking
- [ ] Multi-node testing
- [ ] Upgrade/migration testing
- [ ] Security integration tests
- [ ] API contract testing