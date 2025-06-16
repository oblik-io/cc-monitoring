#!/bin/bash
# ==============================================================================
# Universal monitoring stack management script v5.2 (Dynamic Grafana)
# Author: CC-Monitoring Contributors
# Description: Added dynamic URL configuration for Grafana Datasource.
# ==============================================================================

# --- Variables and configuration ---
set -e # Stop script on first error
CONTAINER_ENGINE=""
COMPOSE_CMD=""
DOCKER_COMPOSE_FILE="docker-compose.yml"
POD_NAME="claude-monitoring-pod"
PROMETHEUS_CONFIG_TEMPLATE="prometheus.yml.template"
PROMETHEUS_CONFIG="prometheus.yml"
GRAFANA_DATASOURCE_TEMPLATE="grafana-provisioning/datasources/prometheus.yml.template"
GRAFANA_DATASOURCE_CONFIG="grafana-provisioning/datasources/prometheus.yml"

# --- Automatic environment detection block ---
if command -v podman &> /dev/null; then
    CONTAINER_ENGINE="podman"
elif command -v docker &> /dev/null; then
    CONTAINER_ENGINE="docker"
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    fi
else
    echo "❌ Error: Neither Podman nor Docker found. Please install one of them."
    exit 1
fi

# --- Functions ---

show_help() {
    echo "Usage: ./manage.sh [command]"
    echo "Auto-detected engine: $CONTAINER_ENGINE"
    echo ""
    echo "Commands:"
    echo "  up      Start the monitoring stack."
    echo "  down    Stop and remove containers/pod."
    echo "  clean   Completely clean the stack (removes containers/pod and data volumes)."
    echo "  restart Restart the stack (runs 'down' then 'up')."
    echo "  reset   Restart the Podman virtual machine (macOS/Windows only)."
    echo "  logs    View logs of all services."
    echo "  ps      Show status of containers/pod."
    echo "  help    Show this help."
}

initial_setup() {
    echo "🔎 Checking initial configuration..."

    if [ ! -f .env ]; then
        echo "⚠️ .env file not found. Creating default one (password: changeme)..."
        echo "GRAFANA_ADMIN_USER=admin" > .env
        echo "GRAFANA_ADMIN_PASSWORD=changeme" >> .env
        echo "❗ IMPORTANT: Change the default password in the .env file!"
    fi

    if [ ! -f "$PROMETHEUS_CONFIG_TEMPLATE" ] || [ ! -f "$GRAFANA_DATASOURCE_TEMPLATE" ]; then
        echo "❌ Error: One of the configuration template files not found."
        exit 1
    fi

    local target_ip="host.docker.internal"
    local prom_url_for_grafana="http://prometheus:9090" # For Docker

    if [[ "$(uname -s)" == "Linux" ]]; then
        if grep -qi "microsoft" /proc/version; then
            echo "🐧 WSL environment detected. Determining IP..."
            target_ip=$(ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
            if [ -z "$target_ip" ]; then
                echo "❌ Failed to determine IP for WSL."
                exit 1
            fi
            echo "✅ Found WSL IP: $target_ip"
        else
            target_ip="localhost"
        fi
    fi

    if [ "$CONTAINER_ENGINE" == "podman" ]; then
        prom_url_for_grafana="http://localhost:9090" # For Podman
    fi

    echo "📝 Generating '$PROMETHEUS_CONFIG' with target IP: $target_ip..."
    sed "s/CLAUDE_CODE_EXPORTER_HOST/$target_ip/" "$PROMETHEUS_CONFIG_TEMPLATE" > "$PROMETHEUS_CONFIG"

    echo "📝 Generating '$GRAFANA_DATASOURCE_CONFIG' with Prometheus URL: $prom_url_for_grafana..."
    sed "s|PROMETHEUS_URL|$prom_url_for_grafana|g" "$GRAFANA_DATASOURCE_TEMPLATE" > "$GRAFANA_DATASOURCE_CONFIG"
}

start_stack_podman() {
    if podman pod exists "$POD_NAME"; then
        echo "⚠️ Existing pod '$POD_NAME' found. Removing before restart..."
        podman pod rm -f "$POD_NAME"
    fi

    set -o allexport
    # shellcheck source=.env
    source .env
    set +o allexport

    echo "Creating pod '$POD_NAME'..."
    podman pod create --name "$POD_NAME" -p 3000:3000 -p 9090:9090

    echo "Starting containers..."
    podman run -d --pod "$POD_NAME" --name claude-prometheus \
      -v "$(pwd)/$PROMETHEUS_CONFIG:/etc/prometheus/prometheus.yml:ro,Z" \
      -v "prometheus-data:/prometheus:Z" \
      docker.io/prom/prometheus:v2.53.0 \
      --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus \
      --web.console.libraries=/usr/share/prometheus/console_libraries \
      --web.console.templates=/usr/share/prometheus/consoles

    podman run -d --pod "$POD_NAME" --name claude-node-exporter --privileged \
      -v "/proc:/host/proc:ro" -v "/sys:/host/sys:ro" -v "/:/rootfs:ro" \
      docker.io/prom/node-exporter:v1.8.1 \
      --path.procfs=/host/proc --path.sysfs=/host/sys --path.rootfs=/rootfs \
      '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'

    podman run -d --pod "$POD_NAME" --name claude-grafana \
      -v "grafana-data:/var/lib/grafana:Z" \
      -v "$(pwd)/grafana-provisioning:/etc/grafana/provisioning:ro,Z" \
      -e GF_SECURITY_ADMIN_USER="${GRAFANA_ADMIN_USER}" \
      -e GF_SECURITY_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD}" \
      -e GF_USERS_ALLOW_SIGN_UP=false \
      docker.io/grafana/grafana-oss:12.0.1-security-01
}

start_stack() {
    initial_setup
    echo "🚀 Starting monitoring stack using '$CONTAINER_ENGINE'..."

    if [ "$CONTAINER_ENGINE" == "podman" ]; then
        start_stack_podman
    else
        $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" up -d
    fi

    echo "✅ Monitoring stack successfully started!"
    echo "📊 Grafana: http://localhost:3000 | Prometheus: http://localhost:9090"
}

stop_stack() {
    echo "🛑 Stopping monitoring stack..."
    if [ "$CONTAINER_ENGINE" == "podman" ]; then
        if podman pod exists "$POD_NAME"; then
            podman pod rm -f "$POD_NAME"
        else
            echo "Pod '$POD_NAME' not found."
        fi
    else
        $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" down
    fi
    echo "✅ Stack stopped."
}

clean_stack() {
    echo "🧹 Complete stack cleanup (including data volumes)..."
    stop_stack
    if [ "$CONTAINER_ENGINE" == "podman" ]; then
        echo "Removing Podman volumes..."
        podman volume rm grafana-data prometheus-data &>/dev/null || true
    else
        $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" down --volumes
    fi
    echo "✅ Stack and its data removed."
}

reset_podman_vm() {
    if [[ "$(uname -s)" == "Linux" ]] && ! grep -qi "microsoft" /proc/version; then
        echo "ℹ️ This command is for Podman on macOS or Windows (WSL)."
        exit 0
    fi
    echo "🚨 Restarting Podman virtual machine..."
    podman machine stop
    podman machine start
    echo "✅ Podman virtual machine restarted."
}

show_logs() {
    echo "📜 Displaying logs... (Press Ctrl+C to exit)"
    if [ "$CONTAINER_ENGINE" == "podman" ]; then
        podman pod logs -f "$POD_NAME"
    else
        $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" logs -f
    fi
}

show_status() {
    echo "ℹ️ Stack status:"
    if [ "$CONTAINER_ENGINE" == "podman" ]; then
        podman pod ps -f "name=$POD_NAME"
    else
        $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" ps
    fi
}

case "$1" in
    up) start_stack ;;
    down) stop_stack ;;
    clean) clean_stack ;;
    restart)
        stop_stack
        start_stack
        ;;
    reset)
        if [ "$CONTAINER_ENGINE" != "podman" ]; then
            echo "❌ 'reset' command is only available for Podman."
            exit 1
        fi
        reset_podman_vm
        ;;
    logs) show_logs ;;
    ps) show_status ;;
    help|""|*) show_help ;;
esac

exit 0