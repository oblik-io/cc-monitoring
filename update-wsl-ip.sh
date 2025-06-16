#!/bin/bash

# Update Prometheus configuration with current WSL IP address

echo "🔍 Detecting WSL IP address..."

# Get the current WSL IP address from eth0
WSL_IP=$(ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

if [ -z "$WSL_IP" ]; then
    echo "❌ Failed to detect WSL IP address"
    exit 1
fi

echo "✅ Found WSL IP: $WSL_IP"

# Update prometheus.yml with the new IP
sed -i "s/- targets: \['[0-9.]*:9464'\]/- targets: \['$WSL_IP:9464'\]/" prometheus.yml

echo "📝 Updated prometheus.yml with IP: $WSL_IP"

# Check if containers are running and offer to restart
if docker ps | grep -q claude-prometheus; then
    echo ""
    echo "🔄 Prometheus is running. Restarting to apply changes..."
    docker restart claude-prometheus
    echo "✅ Prometheus restarted"
fi

echo ""
echo "💡 Current configuration:"
grep -A2 "job_name: 'claude-code'" prometheus.yml | grep targets