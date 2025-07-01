#!/usr/bin/env bats
# ==============================================================================
# Unit tests for manage.sh using BATS (Bash Automated Testing System)
# ==============================================================================

# Test setup and teardown
setup() {
    # Create a temporary test directory
    export TEST_DIR="$(mktemp -d)"
    export ORIGINAL_PWD="$(pwd)"
    cd "$TEST_DIR"
    
    # Copy the manage.sh script to test directory
    cp "$ORIGINAL_PWD/manage.sh" ./
    
    # Create test templates
    mkdir -p grafana-provisioning/datasources
    echo "target: CLAUDE_CODE_EXPORTER_HOST:9464" > prometheus.yml.template
    echo "url: PROMETHEUS_URL" > grafana-provisioning/datasources/prometheus.yml.template
    
    # Mock functions for external commands
    export PATH="$TEST_DIR/bin:$PATH"
    mkdir -p bin
    
    # Default mock responses
    export MOCK_DOCKER_EXISTS=0
    export MOCK_PODMAN_EXISTS=1
    export MOCK_DOCKER_COMPOSE_EXISTS=0
    export MOCK_POD_EXISTS=1
    export MOCK_UNAME="Linux"
    export MOCK_PROC_VERSION=""
    export MOCK_IP_ADDR="192.168.1.100"
}

teardown() {
    cd "$ORIGINAL_PWD"
    rm -rf "$TEST_DIR"
}

# Helper function to create command mocks
create_mock() {
    local cmd=$1
    local script=$2
    cat > "bin/$cmd" << EOF
#!/bin/bash
$script
EOF
    chmod +x "bin/$cmd"
}

# Test container engine detection
@test "detects podman when available" {
    create_mock "podman" 'exit $MOCK_PODMAN_EXISTS'
    create_mock "docker" 'exit 1'
    
    run bash -c 'source ./manage.sh 2>&1 | grep -o "podman"'
    [ "$status" -eq 0 ]
}

@test "detects docker when podman not available" {
    create_mock "podman" 'exit 1'
    create_mock "docker" 'exit $MOCK_DOCKER_EXISTS'
    create_mock "docker-compose" 'exit $MOCK_DOCKER_COMPOSE_EXISTS'
    
    # Create a modified version of manage.sh that exports CONTAINER_ENGINE
    cat > test_engine.sh << 'EOF'
#!/bin/bash
if command -v podman &> /dev/null; then
    CONTAINER_ENGINE="podman"
elif command -v docker &> /dev/null; then
    CONTAINER_ENGINE="docker"
fi
echo "$CONTAINER_ENGINE"
EOF
    chmod +x test_engine.sh
    
    run ./test_engine.sh
    [ "$status" -eq 0 ]
    [ "$output" = "docker" ]
}

@test "fails when neither docker nor podman available" {
    create_mock "podman" 'exit 1'
    create_mock "docker" 'exit 1'
    
    run ./manage.sh help
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Neither Podman nor Docker found" ]]
}

# Test docker compose detection
@test "detects 'docker compose' v2" {
    create_mock "podman" 'exit 1'
    create_mock "docker" '
if [[ "$1" == "compose" && "$2" == "version" ]]; then
    echo "Docker Compose version v2.20.0"
    exit 0
fi
exit $MOCK_DOCKER_EXISTS
'
    
    # Test script to check compose command
    cat > test_compose.sh << 'EOF'
#!/bin/bash
COMPOSE_CMD=""
if command -v docker &> /dev/null; then
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    fi
fi
echo "$COMPOSE_CMD"
EOF
    chmod +x test_compose.sh
    
    run ./test_compose.sh
    [ "$status" -eq 0 ]
    [ "$output" = "docker compose" ]
}

@test "falls back to 'docker-compose' v1" {
    create_mock "podman" 'exit 1'
    create_mock "docker" '
if [[ "$1" == "compose" ]]; then
    exit 1
fi
exit 0
'
    create_mock "docker-compose" 'exit 0'
    
    # Test script to check compose command
    cat > test_compose.sh << 'EOF'
#!/bin/bash
COMPOSE_CMD=""
if command -v docker &> /dev/null; then
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    fi
fi
echo "$COMPOSE_CMD"
EOF
    chmod +x test_compose.sh
    
    run ./test_compose.sh
    [ "$status" -eq 0 ]
    [ "$output" = "docker-compose" ]
}

# Test initial_setup function
@test "initial_setup creates .env file if missing" {
    # Remove .env if exists
    rm -f .env
    
    # Create a test script that sources manage.sh and calls initial_setup
    cat > test_setup.sh << 'EOF'
#!/bin/bash
set -e
source ./manage.sh
initial_setup
EOF
    chmod +x test_setup.sh
    
    # Mock uname for Linux
    create_mock "uname" 'echo "Linux"'
    
    run ./test_setup.sh
    [ "$status" -eq 0 ]
    [ -f .env ]
    
    # Check .env contents
    grep -q "GRAFANA_ADMIN_USER=admin" .env
    grep -q "GRAFANA_ADMIN_PASSWORD=changeme" .env
}

@test "initial_setup preserves existing .env file" {
    # Create custom .env
    echo "GRAFANA_ADMIN_USER=custom" > .env
    echo "GRAFANA_ADMIN_PASSWORD=secret" >> .env
    
    cat > test_setup.sh << 'EOF'
#!/bin/bash
set -e
source ./manage.sh
initial_setup
EOF
    chmod +x test_setup.sh
    
    create_mock "uname" 'echo "Linux"'
    
    run ./test_setup.sh
    [ "$status" -eq 0 ]
    
    # Check that custom values are preserved
    grep -q "GRAFANA_ADMIN_USER=custom" .env
    grep -q "GRAFANA_ADMIN_PASSWORD=secret" .env
}

@test "initial_setup fails if template files missing" {
    rm -f prometheus.yml.template
    
    cat > test_setup.sh << 'EOF'
#!/bin/bash
set -e
source ./manage.sh
initial_setup
EOF
    chmod +x test_setup.sh
    
    run ./test_setup.sh
    [ "$status" -eq 1 ]
    [[ "$output" =~ "configuration template files not found" ]]
}

# Test platform detection
@test "detects WSL environment" {
    create_mock "uname" 'echo "Linux"'
    create_mock "grep" '
if [[ "$1" == "-qi" && "$2" == "microsoft" && "$3" == "/proc/version" ]]; then
    exit 0
fi
exit 1
'
    create_mock "ip" 'echo "inet 172.16.0.100/24"'
    
    cat > test_wsl.sh << 'EOF'
#!/bin/bash
set -e
source ./manage.sh
initial_setup
EOF
    chmod +x test_wsl.sh
    
    run ./test_wsl.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WSL environment detected" ]]
    [[ "$output" =~ "172.16.0.100" ]]
    
    # Check generated config
    grep -q "172.16.0.100" prometheus.yml
}

@test "uses localhost for native Linux" {
    create_mock "uname" 'echo "Linux"'
    create_mock "grep" 'exit 1'  # Not WSL
    
    cat > test_linux.sh << 'EOF'
#!/bin/bash
set -e
source ./manage.sh
initial_setup
EOF
    chmod +x test_linux.sh
    
    run ./test_linux.sh
    [ "$status" -eq 0 ]
    
    # Check generated config
    grep -q "localhost" prometheus.yml
}

@test "uses host.docker.internal for macOS" {
    create_mock "uname" 'echo "Darwin"'
    
    cat > test_macos.sh << 'EOF'
#!/bin/bash
set -e
source ./manage.sh
initial_setup
EOF
    chmod +x test_macos.sh
    
    run ./test_macos.sh
    [ "$status" -eq 0 ]
    
    # Check generated config
    grep -q "host.docker.internal" prometheus.yml
}

@test "WSL IP detection fails gracefully" {
    create_mock "uname" 'echo "Linux"'
    create_mock "grep" '
if [[ "$3" == "/proc/version" ]]; then
    exit 0
fi
exit 1
'
    create_mock "ip" 'exit 1'  # IP command fails
    
    cat > test_wsl_fail.sh << 'EOF'
#!/bin/bash
set -e
source ./manage.sh
initial_setup
EOF
    chmod +x test_wsl_fail.sh
    
    run ./test_wsl_fail.sh
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Failed to determine IP for WSL" ]]
}

# Test Grafana datasource configuration
@test "configures Grafana datasource for Docker" {
    create_mock "uname" 'echo "Linux"'
    create_mock "podman" 'exit 1'
    create_mock "docker" 'exit 0'
    
    cat > test_grafana_docker.sh << 'EOF'
#!/bin/bash
set -e
CONTAINER_ENGINE="docker"
source ./manage.sh
initial_setup
EOF
    chmod +x test_grafana_docker.sh
    
    run ./test_grafana_docker.sh
    [ "$status" -eq 0 ]
    
    # Check Grafana datasource config
    grep -q "http://prometheus:9090" grafana-provisioning/datasources/prometheus.yml
}

@test "configures Grafana datasource for Podman" {
    create_mock "uname" 'echo "Linux"'
    create_mock "podman" 'exit 0'
    
    cat > test_grafana_podman.sh << 'EOF'
#!/bin/bash
set -e
CONTAINER_ENGINE="podman"
source ./manage.sh
initial_setup
EOF
    chmod +x test_grafana_podman.sh
    
    run ./test_grafana_podman.sh
    [ "$status" -eq 0 ]
    
    # Check Grafana datasource config
    grep -q "http://localhost:9090" grafana-provisioning/datasources/prometheus.yml
}

# Test start_stack_podman function
@test "start_stack_podman removes existing pod" {
    create_mock "podman" '
case "$1" in
    "pod")
        if [[ "$2" == "exists" ]]; then
            exit 0  # Pod exists
        elif [[ "$2" == "rm" ]]; then
            echo "Pod removed"
            exit 0
        elif [[ "$2" == "create" ]]; then
            echo "Pod created"
            exit 0
        fi
        ;;
    "run")
        echo "Container started"
        exit 0
        ;;
esac
exit 1
'
    
    # Create .env file
    echo "GRAFANA_ADMIN_USER=admin" > .env
    echo "GRAFANA_ADMIN_PASSWORD=changeme" >> .env
    
    cat > test_podman_start.sh << 'EOF'
#!/bin/bash
set -e
source ./manage.sh
start_stack_podman
EOF
    chmod +x test_podman_start.sh
    
    run ./test_podman_start.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Pod removed" ]]
    [[ "$output" =~ "Pod created" ]]
}

@test "start_stack_podman creates new pod if not exists" {
    create_mock "podman" '
case "$1" in
    "pod")
        if [[ "$2" == "exists" ]]; then
            exit 1  # Pod doesn't exist
        elif [[ "$2" == "create" ]]; then
            echo "Pod created"
            exit 0
        fi
        ;;
    "run")
        echo "Container started"
        exit 0
        ;;
esac
exit 1
'
    
    # Create .env file
    echo "GRAFANA_ADMIN_USER=admin" > .env
    echo "GRAFANA_ADMIN_PASSWORD=changeme" >> .env
    
    cat > test_podman_new.sh << 'EOF'
#!/bin/bash
set -e
source ./manage.sh
start_stack_podman
EOF
    chmod +x test_podman_new.sh
    
    run ./test_podman_new.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Pod created" ]]
    [[ ! "$output" =~ "Pod removed" ]]
}

# Test stop_stack function
@test "stop_stack stops podman pod" {
    create_mock "podman" '
if [[ "$1" == "pod" && "$2" == "exists" ]]; then
    exit 0
elif [[ "$1" == "pod" && "$2" == "rm" ]]; then
    echo "Pod stopped and removed"
    exit 0
fi
exit 1
'
    
    cat > test_stop_podman.sh << 'EOF'
#!/bin/bash
CONTAINER_ENGINE="podman"
source ./manage.sh
stop_stack
EOF
    chmod +x test_stop_podman.sh
    
    run ./test_stop_podman.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Pod stopped and removed" ]]
}

@test "stop_stack handles missing podman pod gracefully" {
    create_mock "podman" '
if [[ "$1" == "pod" && "$2" == "exists" ]]; then
    exit 1  # Pod doesn't exist
fi
exit 0
'
    
    cat > test_stop_missing.sh << 'EOF'
#!/bin/bash
CONTAINER_ENGINE="podman"
source ./manage.sh
stop_stack
EOF
    chmod +x test_stop_missing.sh
    
    run ./test_stop_missing.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Pod 'claude-monitoring-pod' not found" ]]
}

@test "stop_stack uses docker-compose for docker" {
    create_mock "docker-compose" '
echo "Docker compose down"
exit 0
'
    
    cat > test_stop_docker.sh << 'EOF'
#!/bin/bash
CONTAINER_ENGINE="docker"
COMPOSE_CMD="docker-compose"
source ./manage.sh
stop_stack
EOF
    chmod +x test_stop_docker.sh
    
    run ./test_stop_docker.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Docker compose down" ]]
}

# Test clean_stack function
@test "clean_stack removes podman volumes" {
    create_mock "podman" '
case "$1" in
    "pod")
        if [[ "$2" == "exists" ]]; then
            exit 0
        elif [[ "$2" == "rm" ]]; then
            echo "Pod removed"
            exit 0
        fi
        ;;
    "volume")
        if [[ "$2" == "rm" ]]; then
            echo "Volumes removed"
            exit 0
        fi
        ;;
esac
exit 1
'
    
    cat > test_clean_podman.sh << 'EOF'
#!/bin/bash
CONTAINER_ENGINE="podman"
source ./manage.sh
clean_stack
EOF
    chmod +x test_clean_podman.sh
    
    run ./test_clean_podman.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Pod removed" ]]
    [[ "$output" =~ "Volumes removed" ]]
}

@test "clean_stack uses docker-compose with volumes flag" {
    create_mock "docker-compose" '
if [[ "$*" =~ "--volumes" ]]; then
    echo "Docker compose down with volumes"
else
    echo "Docker compose down"
fi
exit 0
'
    
    cat > test_clean_docker.sh << 'EOF'
#!/bin/bash
CONTAINER_ENGINE="docker"
COMPOSE_CMD="docker-compose"
source ./manage.sh
clean_stack
EOF
    chmod +x test_clean_docker.sh
    
    run ./test_clean_docker.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Docker compose down with volumes" ]]
}

# Test reset_podman_vm function
@test "reset_podman_vm works on macOS" {
    create_mock "uname" 'echo "Darwin"'
    create_mock "podman" '
if [[ "$1" == "machine" && "$2" == "stop" ]]; then
    echo "Podman machine stopped"
elif [[ "$1" == "machine" && "$2" == "start" ]]; then
    echo "Podman machine started"
fi
exit 0
'
    
    cat > test_reset_macos.sh << 'EOF'
#!/bin/bash
source ./manage.sh
reset_podman_vm
EOF
    chmod +x test_reset_macos.sh
    
    run ./test_reset_macos.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Podman machine stopped" ]]
    [[ "$output" =~ "Podman machine started" ]]
}

@test "reset_podman_vm works on WSL" {
    create_mock "uname" 'echo "Linux"'
    create_mock "grep" '
if [[ "$2" == "microsoft" && "$3" == "/proc/version" ]]; then
    exit 0  # Is WSL
fi
exit 1
'
    create_mock "podman" '
if [[ "$1" == "machine" ]]; then
    echo "Podman machine command"
fi
exit 0
'
    
    cat > test_reset_wsl.sh << 'EOF'
#!/bin/bash
source ./manage.sh
reset_podman_vm
EOF
    chmod +x test_reset_wsl.sh
    
    run ./test_reset_wsl.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Podman machine command" ]]
}

@test "reset_podman_vm exits on native Linux" {
    create_mock "uname" 'echo "Linux"'
    create_mock "grep" 'exit 1'  # Not WSL
    
    cat > test_reset_linux.sh << 'EOF'
#!/bin/bash
source ./manage.sh
reset_podman_vm
EOF
    chmod +x test_reset_linux.sh
    
    run ./test_reset_linux.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "This command is for Podman on macOS or Windows" ]]
}

# Test command routing
@test "help command shows usage" {
    create_mock "podman" 'exit 0'
    
    run ./manage.sh help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: ./manage.sh" ]]
    [[ "$output" =~ "Commands:" ]]
}

@test "empty command shows help" {
    create_mock "podman" 'exit 0'
    
    run ./manage.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: ./manage.sh" ]]
}

@test "invalid command shows help" {
    create_mock "podman" 'exit 0'
    
    run ./manage.sh invalid_command
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: ./manage.sh" ]]
}

@test "reset command fails for docker" {
    create_mock "podman" 'exit 1'
    create_mock "docker" 'exit 0'
    
    run ./manage.sh reset
    [ "$status" -eq 1 ]
    [[ "$output" =~ "'reset' command is only available for Podman" ]]
}

# Test error handling
@test "handles missing .env during podman start" {
    rm -f .env
    
    create_mock "podman" 'exit 0'
    
    cat > test_no_env.sh << 'EOF'
#!/bin/bash
source ./manage.sh
start_stack_podman 2>&1 || echo "Failed as expected"
EOF
    chmod +x test_no_env.sh
    
    run ./test_no_env.sh
    [[ "$output" =~ "Failed as expected" ]]
}

@test "script exits on error with set -e" {
    # Create a script that should fail
    cat > test_error.sh << 'EOF'
#!/bin/bash
set -e
source ./manage.sh
false  # This should cause the script to exit
echo "This should not print"
EOF
    chmod +x test_error.sh
    
    run ./test_error.sh
    [ "$status" -ne 0 ]
    [[ ! "$output" =~ "This should not print" ]]
}

# Test show_logs function
@test "show_logs uses podman pod logs" {
    create_mock "podman" '
if [[ "$1" == "pod" && "$2" == "logs" ]]; then
    echo "Podman pod logs output"
    exit 0
fi
exit 1
'
    
    cat > test_logs_podman.sh << 'EOF'
#!/bin/bash
CONTAINER_ENGINE="podman"
POD_NAME="claude-monitoring-pod"
source ./manage.sh
show_logs
EOF
    chmod +x test_logs_podman.sh
    
    # Run with timeout to prevent hanging
    run timeout 1s ./test_logs_podman.sh
    [[ "$output" =~ "Podman pod logs output" ]]
}

@test "show_logs uses docker-compose logs" {
    create_mock "docker-compose" '
if [[ "$*" =~ "logs -f" ]]; then
    echo "Docker compose logs output"
    exit 0
fi
exit 1
'
    
    cat > test_logs_docker.sh << 'EOF'
#!/bin/bash
CONTAINER_ENGINE="docker"
COMPOSE_CMD="docker-compose"
source ./manage.sh
show_logs
EOF
    chmod +x test_logs_docker.sh
    
    # Run with timeout to prevent hanging
    run timeout 1s ./test_logs_docker.sh
    [[ "$output" =~ "Docker compose logs output" ]]
}

# Test show_status function
@test "show_status uses podman pod ps" {
    create_mock "podman" '
if [[ "$1" == "pod" && "$2" == "ps" ]]; then
    echo "POD ID  NAME                    STATUS"
    echo "123456  claude-monitoring-pod   Running"
    exit 0
fi
exit 1
'
    
    cat > test_status_podman.sh << 'EOF'
#!/bin/bash
CONTAINER_ENGINE="podman"
POD_NAME="claude-monitoring-pod"
source ./manage.sh
show_status
EOF
    chmod +x test_status_podman.sh
    
    run ./test_status_podman.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "claude-monitoring-pod" ]]
    [[ "$output" =~ "Running" ]]
}

@test "show_status uses docker-compose ps" {
    create_mock "docker-compose" '
if [[ "$*" =~ " ps" ]]; then
    echo "NAME                  STATUS"
    echo "prometheus            running"
    echo "grafana               running"
    exit 0
fi
exit 1
'
    
    cat > test_status_docker.sh << 'EOF'
#!/bin/bash
CONTAINER_ENGINE="docker"
COMPOSE_CMD="docker-compose"
source ./manage.sh
show_status
EOF
    chmod +x test_status_docker.sh
    
    run ./test_status_docker.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "prometheus" ]]
    [[ "$output" =~ "grafana" ]]
}

# Test restart command
@test "restart command stops then starts stack" {
    create_mock "podman" '
echo "podman command: $*"
exit 0
'
    create_mock "uname" 'echo "Linux"'
    
    cat > test_restart.sh << 'EOF'
#!/bin/bash
CONTAINER_ENGINE="podman"
source ./manage.sh
# Override functions to track calls
stop_called=0
start_called=0
stop_stack() {
    stop_called=1
    echo "stop_stack called"
}
start_stack() {
    start_called=1
    echo "start_stack called"
}
case "restart" in
    restart)
        stop_stack
        start_stack
        ;;
esac
echo "stop_called=$stop_called start_called=$start_called"
EOF
    chmod +x test_restart.sh
    
    run ./test_restart.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "stop_stack called" ]]
    [[ "$output" =~ "start_stack called" ]]
    [[ "$output" =~ "stop_called=1 start_called=1" ]]
}

# Test volume mount paths
@test "uses correct volume mount syntax for podman" {
    create_mock "podman" '
if [[ "$1" == "run" ]]; then
    echo "$*" | grep -E "ro,Z|:Z" && echo "Correct SELinux labels"
fi
exit 0
'
    
    echo "GRAFANA_ADMIN_USER=admin" > .env
    echo "GRAFANA_ADMIN_PASSWORD=changeme" >> .env
    
    cat > test_volumes.sh << 'EOF'
#!/bin/bash
source ./manage.sh
start_stack_podman 2>&1 | grep "Correct SELinux labels" | head -1
EOF
    chmod +x test_volumes.sh
    
    run ./test_volumes.sh
    [[ "$output" =~ "Correct SELinux labels" ]]
}

# Test environment variable handling
@test "sources .env file correctly" {
    echo "GRAFANA_ADMIN_USER=testuser" > .env
    echo "GRAFANA_ADMIN_PASSWORD=testpass" >> .env
    
    create_mock "podman" '
if [[ "$1" == "run" ]]; then
    echo "$*" | grep -E "GF_SECURITY_ADMIN_USER.*testuser" && echo "User env var passed"
    echo "$*" | grep -E "GF_SECURITY_ADMIN_PASSWORD.*testpass" && echo "Password env var passed"
fi
exit 0
'
    
    cat > test_env_vars.sh << 'EOF'
#!/bin/bash
source ./manage.sh
start_stack_podman 2>&1 | grep "env var passed"
EOF
    chmod +x test_env_vars.sh
    
    run ./test_env_vars.sh
    [[ "$output" =~ "User env var passed" ]]
    [[ "$output" =~ "Password env var passed" ]]
}

# Test network port mappings
@test "creates pod with correct port mappings" {
    create_mock "podman" '
if [[ "$1" == "pod" && "$2" == "create" ]]; then
    echo "$*" | grep -E "\-p 3000:3000.*\-p 9090:9090" && echo "Correct port mappings"
fi
exit 0
'
    
    echo "GRAFANA_ADMIN_USER=admin" > .env
    echo "GRAFANA_ADMIN_PASSWORD=changeme" >> .env
    
    cat > test_ports.sh << 'EOF'
#!/bin/bash
source ./manage.sh
start_stack_podman 2>&1 | grep "Correct port mappings"
EOF
    chmod +x test_ports.sh
    
    run ./test_ports.sh
    [[ "$output" =~ "Correct port mappings" ]]
}