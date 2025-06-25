# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code Monitoring is a local monitoring solution for tracking Claude Code usage metrics using Prometheus and Grafana. The project provides automatic environment detection (Docker/Podman), pre-configured dashboards, and privacy-first local data storage.

## Architecture

The monitoring stack consists of three main services:

1. **Prometheus** (v2.53.0) - Metrics collection and storage
   - Scrapes metrics from Claude Code at port 9464
   - Stores time-series data in persistent volume
   - Configured via `prometheus.yml` (generated from template)

2. **Grafana** (v11.0.0) - Visualization and dashboards
   - Pre-configured with two dashboards (basic and comprehensive)
   - Auto-provisions datasources and dashboards
   - Accessible at http://localhost:3000

3. **Node Exporter** (v1.8.1) - Optional host metrics collection
   - Collects system-level metrics from the host

## Common Commands

All operations are managed through the `./manage.sh` script:

```bash
# Start the monitoring stack
./manage.sh up

# Stop and remove containers/pod
./manage.sh down

# Restart the stack
./manage.sh restart

# View logs of all services
./manage.sh logs

# Show status of containers/pod
./manage.sh ps

# Completely clean the stack (removes containers and data)
./manage.sh clean

# Restart Podman VM (macOS/Windows only)
./manage.sh reset
```

## Development Workflow

### Before Starting Claude Code

Set these environment variables:

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=prometheus
export OTEL_EXPORTER_PROMETHEUS_HOST=0.0.0.0  # Optional
export OTEL_EXPORTER_PROMETHEUS_PORT=9464     # Optional
export OTEL_METRIC_EXPORT_INTERVAL=10000      # Optional (ms)
```

### Verify Metrics Collection

```bash
# Check if metrics are exposed
./check-claude-metrics.sh

# Or manually check
curl http://localhost:9464/metrics | grep claude_code
```

### Configuration Files

- **prometheus.yml** - Generated from `prometheus.yml.template` with appropriate host IP
- **grafana-provisioning/datasources/prometheus.yml** - Generated from template with correct Prometheus URL
- **.env** - Contains Grafana credentials (created automatically if missing)

### Platform-Specific Configurations

The `manage.sh` script automatically detects and configures for:
- **WSL**: Uses WSL IP address for metric scraping
- **macOS**: Uses `host.docker.internal`
- **Linux**: Uses `localhost`
- **Podman**: Uses pod networking (services communicate via localhost)
- **Docker**: Uses docker-compose networking

### Dashboard Files

Located in `grafana-provisioning/dashboards/`:
- `claude-code-basic.json` - Essential metrics dashboard
- `claude-code-comprehensive.json` - Detailed analytics dashboard

Both dashboards are automatically loaded when Grafana starts.

## Development Workflow Reminders

- ALWAYS update CHANGELOG.md before committing changes
- Document all significant changes in CHANGELOG.md following Keep a Changelog format
- Use descriptive commit messages in English
- Maintain ability to rollback to any commit by keeping clear change history