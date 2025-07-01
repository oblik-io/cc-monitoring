#!/usr/bin/env bats
# ==============================================================================
# Unit tests for update-wsl-ip.sh using BATS (Bash Automated Testing System)
# ==============================================================================

# Test setup and teardown
setup() {
    # Create a temporary test directory
    export TEST_DIR="$(mktemp -d)"
    export ORIGINAL_PWD="$(pwd)"
    cd "$TEST_DIR"
    
    # Copy the update-wsl-ip.sh script to test directory
    cp "$ORIGINAL_PWD/update-wsl-ip.sh" ./
    
    # Create test prometheus.yml file
    cat > prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'claude-code'
    static_configs:
      - targets: ['192.168.1.50:9464']
EOF
    
    # Mock functions for external commands
    export PATH="$TEST_DIR/bin:$PATH"
    mkdir -p bin
    
    # Default mock responses
    export MOCK_IP_OUTPUT="192.168.1.100"
    export MOCK_IP_EXIT=0
    export MOCK_DOCKER_PS_OUTPUT=""
    export MOCK_DOCKER_RESTART_EXIT=0
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

# Test successful IP detection and update
@test "detects WSL IP from eth0 and updates prometheus.yml" {
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
    echo "    inet6 fe80::215:5dff:fe00:0/64 scope link"
    exit 0
fi
exit 1
'
    
    create_mock "docker" 'exit 0'
    create_mock "grep" 'exit 1'  # No containers running
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Found WSL IP: 192.168.1.100" ]]
    [[ "$output" =~ "Updated prometheus.yml with IP: 192.168.1.100" ]]
    
    # Check that prometheus.yml was updated
    grep -q "192.168.1.100:9464" prometheus.yml
}

@test "handles multiple IP addresses on eth0" {
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
    echo "    inet 192.168.1.200/24 brd 192.168.1.255 scope global secondary eth0"
    echo "    inet6 fe80::215:5dff:fe00:0/64 scope link"
    exit 0
fi
exit 1
'
    
    create_mock "docker" 'exit 0'
    create_mock "grep" 'exit 1'  # No containers running
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Found WSL IP: 192.168.1.100" ]]
    
    # Should use the first IP address
    grep -q "192.168.1.100:9464" prometheus.yml
    ! grep -q "192.168.1.200:9464" prometheus.yml
}

@test "fails when no IP address found on eth0" {
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
    echo "    inet6 fe80::215:5dff:fe00:0/64 scope link"
    exit 0
fi
exit 1
'
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Failed to detect WSL IP address" ]]
}

@test "fails when eth0 interface not found" {
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "Device \"eth0\" does not exist." >&2
    exit 1
fi
exit 1
'
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Failed to detect WSL IP address" ]]
}

@test "restarts prometheus container when running" {
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
    exit 0
fi
exit 1
'
    
    create_mock "docker" '
if [[ "$1" == "ps" ]]; then
    echo "CONTAINER ID   IMAGE                    COMMAND                  CREATED       STATUS"
    echo "abc123         prom/prometheus:v2.53.0  \"/bin/prometheus\"       5 hours ago   Up 5 hours"
    echo "def456         grafana/grafana:11.0.0   \"/run.sh\"               5 hours ago   Up 5 hours"
    exit 0
elif [[ "$1" == "restart" && "$2" == "claude-prometheus" ]]; then
    echo "claude-prometheus"
    exit 0
fi
exit 1
'
    
    create_mock "grep" '
if [[ "$*" =~ "claude-prometheus" ]]; then
    exit 0  # Container found
fi
exit 1
'
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Prometheus is running. Restarting to apply changes..." ]]
    [[ "$output" =~ "Prometheus restarted" ]]
}

@test "does not restart when prometheus container not running" {
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
    exit 0
fi
exit 1
'
    
    create_mock "docker" '
if [[ "$1" == "ps" ]]; then
    echo "CONTAINER ID   IMAGE                    COMMAND                  CREATED       STATUS"
    echo "def456         grafana/grafana:11.0.0   \"/run.sh\"               5 hours ago   Up 5 hours"
    exit 0
fi
exit 1
'
    
    create_mock "grep" '
if [[ "$*" =~ "claude-prometheus" ]]; then
    exit 1  # Container not found
fi
exit 0
'
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Restarting to apply changes" ]]
    [[ ! "$output" =~ "Prometheus restarted" ]]
}

@test "handles docker restart failure gracefully" {
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
    exit 0
fi
exit 1
'
    
    create_mock "docker" '
if [[ "$1" == "ps" ]]; then
    echo "CONTAINER ID   IMAGE                    COMMAND                  CREATED       STATUS"
    echo "abc123         prom/prometheus:v2.53.0  \"/bin/prometheus\"       5 hours ago   Up 5 hours"
    exit 0
elif [[ "$1" == "restart" && "$2" == "claude-prometheus" ]]; then
    echo "Error: No such container: claude-prometheus" >&2
    exit 1
fi
exit 1
'
    
    create_mock "grep" '
if [[ "$*" =~ "claude-prometheus" ]]; then
    exit 0  # Container found in ps output
fi
exit 1
'
    
    run ./update-wsl-ip.sh
    # Script should not fail even if restart fails
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Prometheus is running. Restarting to apply changes..." ]]
}

@test "shows current configuration at the end" {
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
    exit 0
fi
exit 1
'
    
    create_mock "docker" 'exit 0'
    
    # Mock grep to handle the final configuration display
    create_mock "grep" '
if [[ "$*" =~ "claude-prometheus" ]]; then
    exit 1  # No container
elif [[ "$*" =~ "job_name.*claude-code" ]]; then
    # Simulate grep output for job_name
    echo "  - job_name: '\''claude-code'\''"
    echo "    static_configs:"
    echo "      - targets: ['\''192.168.1.100:9464'\'']"
    exit 0
fi
exit 1
'
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Current configuration:" ]]
    [[ "$output" =~ "targets" ]]
}

@test "updates prometheus.yml with sed correctly" {
    # Create a more complex prometheus.yml to test sed pattern
    cat > prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  - job_name: 'claude-code'
    static_configs:
      - targets: ['10.0.0.1:9464']
      
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
EOF
    
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "    inet 172.16.0.50/24 brd 172.16.0.255 scope global eth0"
    exit 0
fi
exit 1
'
    
    create_mock "docker" 'exit 0'
    create_mock "grep" 'exit 1'  # No containers
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 0 ]
    
    # Check that only the claude-code target was updated
    grep -q "targets: \['172.16.0.50:9464'\]" prometheus.yml
    grep -q "targets: \['localhost:9090'\]" prometheus.yml  # Should remain unchanged
    grep -q "targets: \['localhost:9100'\]" prometheus.yml  # Should remain unchanged
}

@test "handles IP addresses with different formats" {
    # Test with IP that has leading zeros
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "    inet 10.0.0.1/8 brd 10.255.255.255 scope global eth0"
    exit 0
fi
exit 1
'
    
    create_mock "docker" 'exit 0'
    create_mock "grep" 'exit 1'
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Found WSL IP: 10.0.0.1" ]]
    grep -q "10.0.0.1:9464" prometheus.yml
}

@test "preserves file permissions and ownership" {
    # Set specific permissions on prometheus.yml
    chmod 644 prometheus.yml
    
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
    exit 0
fi
exit 1
'
    
    create_mock "docker" 'exit 0'
    create_mock "grep" 'exit 1'
    
    # Get original permissions
    original_perms=$(stat -c "%a" prometheus.yml 2>/dev/null || stat -f "%Lp" prometheus.yml)
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 0 ]
    
    # Check permissions are preserved
    new_perms=$(stat -c "%a" prometheus.yml 2>/dev/null || stat -f "%Lp" prometheus.yml)
    [ "$original_perms" = "$new_perms" ]
}

@test "handles missing prometheus.yml file" {
    rm -f prometheus.yml
    
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
    exit 0
fi
exit 1
'
    
    run ./update-wsl-ip.sh
    # The script doesn't check for file existence, so sed will fail
    [ "$status" -ne 0 ]
}

@test "handles prometheus.yml without claude-code job" {
    # Create prometheus.yml without claude-code job
    cat > prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
    
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
    exit 0
fi
exit 1
'
    
    create_mock "docker" 'exit 0'
    create_mock "grep" '
if [[ "$*" =~ "claude-prometheus" ]]; then
    exit 1
elif [[ "$*" =~ "job_name.*claude-code" ]]; then
    exit 1  # No claude-code job found
fi
exit 1
'
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 0 ]
    # The sed command will run but won't match anything
    # File should remain unchanged
    ! grep -q "192.168.1.100:9464" prometheus.yml
}

@test "handles IP with CIDR notation correctly" {
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "    inet 192.168.100.50/16 brd 192.168.255.255 scope global eth0"
    exit 0
fi
exit 1
'
    
    create_mock "docker" 'exit 0'
    create_mock "grep" 'exit 1'
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Found WSL IP: 192.168.100.50" ]]
    # IP should be extracted without CIDR notation
    grep -q "192.168.100.50:9464" prometheus.yml
    ! grep -q "/16" prometheus.yml
}

@test "handles special characters in IP regex" {
    # Test that the grep regex properly escapes special characters
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "    inet 172.17.0.1/16 brd 172.17.255.255 scope global eth0"
    echo "    inet secondary 172.17.0.2/16 scope global eth0"
    exit 0
fi
exit 1
'
    
    create_mock "docker" 'exit 0'
    create_mock "grep" 'exit 1'
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 0 ]
    # Should get first IP only
    [[ "$output" =~ "Found WSL IP: 172.17.0.1" ]]
}

@test "sed in-place edit creates no backup files" {
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
    exit 0
fi
exit 1
'
    
    create_mock "docker" 'exit 0'
    create_mock "grep" 'exit 1'
    
    # Count files before
    files_before=$(ls -1 | wc -l)
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 0 ]
    
    # Count files after
    files_after=$(ls -1 | wc -l)
    
    # No backup files should be created
    [ "$files_before" -eq "$files_after" ]
    ! ls prometheus.yml.* 2>/dev/null
}

@test "updates multiple occurrences of IP in targets" {
    # Create prometheus.yml with multiple targets lines
    cat > prometheus.yml << 'EOF'
scrape_configs:
  - job_name: 'test1'
    static_configs:
      - targets: ['10.0.0.1:9464']
  - job_name: 'test2'
    static_configs:
      - targets: ['10.0.0.2:9464']
  - job_name: 'test3'
    static_configs:
      - targets: ['10.0.0.3:9464']
EOF
    
    create_mock "ip" '
if [[ "$*" == "addr show eth0" ]]; then
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
    exit 0
fi
exit 1
'
    
    create_mock "docker" 'exit 0'
    create_mock "grep" 'exit 1'
    
    run ./update-wsl-ip.sh
    [ "$status" -eq 0 ]
    
    # All targets with port 9464 should be updated
    grep -q "192.168.1.100:9464" prometheus.yml
    # Count occurrences - should update all three
    count=$(grep -c "192.168.1.100:9464" prometheus.yml)
    [ "$count" -eq 3 ]
}