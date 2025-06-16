#!/bin/bash
# Claude Code Metrics Checker

echo "🔍 Checking Claude Code metrics availability..."
echo "============================================="

# Check if Claude Code is exposing metrics
echo -n "📡 Checking metrics endpoint (localhost:9464)... "
if curl -s http://localhost:9464/metrics > /dev/null 2>&1; then
    echo "✅ Accessible"
    echo ""
    echo "📊 Sample Claude Code metrics:"
    echo "------------------------------"
    curl -s http://localhost:9464/metrics | grep "^claude_code_" | head -10
else
    echo "❌ Not accessible"
    echo ""
    echo "💡 Troubleshooting steps:"
    echo "   1. Ensure Claude Code is running"
    echo "   2. Check environment variables:"
    echo "      export CLAUDE_CODE_ENABLE_TELEMETRY=1"
    echo "      export OTEL_METRICS_EXPORTER=prometheus"
    echo "   3. Optionally set:"
    echo "      export OTEL_EXPORTER_PROMETHEUS_HOST=0.0.0.0"
fi

# Check Prometheus targets
echo ""
echo "🎯 Checking Prometheus targets..."
echo "================================="
if curl -s http://localhost:9090/api/v1/targets > /dev/null 2>&1; then
    echo "Prometheus Claude Code target status:"
    curl -s http://localhost:9090/api/v1/targets | \
    jq -r '.data.activeTargets[] | select(.labels.job=="claude-code") | "Health: \(.health), Last Error: \(.lastError // "none"), Last Scrape: \(.lastScrape)"'
else
    echo "❌ Prometheus not accessible on localhost:9090"
fi

# Check if metrics are being collected
echo ""
echo "📈 Checking if metrics are being collected..."
echo "==========================================="
if curl -s http://localhost:9090/api/v1/query?query=claude_code_session_count_total > /dev/null 2>&1; then
    SESSION_COUNT=$(curl -s http://localhost:9090/api/v1/query?query=claude_code_session_count_total | jq -r '.data.result[0].value[1] // "0"')
    echo "✅ Total sessions recorded: $SESSION_COUNT"
else
    echo "❌ Cannot query Prometheus metrics"
fi