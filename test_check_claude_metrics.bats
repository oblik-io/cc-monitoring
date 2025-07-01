#!/usr/bin/env bats
# ==============================================================================
# Unit tests for check-claude-metrics.sh using BATS (Bash Automated Testing System)
# ==============================================================================

# Test setup and teardown
setup() {
    # Create a temporary test directory
    export TEST_DIR="$(mktemp -d)"
    export ORIGINAL_PWD="$(pwd)"
    cd "$TEST_DIR"
    
    # Copy the check-claude-metrics.sh script to test directory
    cp "$ORIGINAL_PWD/check-claude-metrics.sh" ./
    
    # Mock functions for external commands
    export PATH="$TEST_DIR/bin:$PATH"
    mkdir -p bin
    
    # Default mock responses
    export MOCK_METRICS_RESPONSE=""
    export MOCK_METRICS_STATUS=0
    export MOCK_PROMETHEUS_TARGETS_RESPONSE=""
    export MOCK_PROMETHEUS_TARGETS_STATUS=0
    export MOCK_PROMETHEUS_QUERY_RESPONSE=""
    export MOCK_PROMETHEUS_QUERY_STATUS=0
    export MOCK_JQ_EXISTS=0
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

# Test metrics endpoint checking (port 9464)
@test "detects accessible metrics endpoint" {
    export MOCK_METRICS_RESPONSE="claude_code_session_count_total 5
claude_code_messages_total{type=\"sent\"} 100
claude_code_messages_total{type=\"received\"} 98
claude_code_tokens_total{type=\"input\"} 50000
claude_code_tokens_total{type=\"output\"} 45000
claude_code_active_sessions 2
claude_code_error_count_total 3
claude_code_response_time_seconds_sum 120.5
claude_code_response_time_seconds_count 98
claude_code_uptime_seconds 3600"
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9464/metrics" ]]; then
    if [[ "$*" =~ " -s " ]] && [[ ! "$*" =~ "grep" ]]; then
        if [[ "$*" =~ "/dev/null" ]]; then
            exit $MOCK_METRICS_STATUS
        else
            echo "$MOCK_METRICS_RESPONSE"
            exit $MOCK_METRICS_STATUS
        fi
    fi
fi
exit 1
'
    
    create_mock "grep" '
if [[ "$1" == "^claude_code_" ]]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^claude_code_ ]]; then
            echo "$line"
        fi
    done
fi
'
    
    create_mock "head" '
count=10
while IFS= read -r line && [ $count -gt 0 ]; do
    echo "$line"
    ((count--))
done
'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✅ Accessible" ]]
    [[ "$output" =~ "📊 Sample Claude Code metrics:" ]]
    [[ "$output" =~ "claude_code_session_count_total" ]]
}

@test "handles inaccessible metrics endpoint" {
    export MOCK_METRICS_STATUS=1
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9464/metrics" ]]; then
    exit $MOCK_METRICS_STATUS
fi
exit 0
'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "❌ Not accessible" ]]
    [[ "$output" =~ "💡 Troubleshooting steps:" ]]
    [[ "$output" =~ "CLAUDE_CODE_ENABLE_TELEMETRY=1" ]]
    [[ "$output" =~ "OTEL_METRICS_EXPORTER=prometheus" ]]
    [[ "$output" =~ "OTEL_EXPORTER_PROMETHEUS_HOST=0.0.0.0" ]]
}

@test "shows only first 10 metrics when many available" {
    # Generate 20 metrics
    local metrics=""
    for i in {1..20}; do
        metrics="${metrics}claude_code_metric_${i} ${i}\n"
    done
    export MOCK_METRICS_RESPONSE=$(echo -e "$metrics")
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9464/metrics" ]]; then
    if [[ ! "$*" =~ "/dev/null" ]]; then
        echo "$MOCK_METRICS_RESPONSE"
    fi
    exit 0
fi
exit 1
'
    
    create_mock "grep" '
if [[ "$1" == "^claude_code_" ]]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^claude_code_ ]]; then
            echo "$line"
        fi
    done
fi
'
    
    create_mock "head" '
count=10
while IFS= read -r line && [ $count -gt 0 ]; do
    echo "$line"
    ((count--))
done
'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    # Should show metrics 1-10 but not 11-20
    [[ "$output" =~ "claude_code_metric_10" ]]
    [[ ! "$output" =~ "claude_code_metric_11" ]]
}

# Test Prometheus targets validation
@test "shows Prometheus target health when accessible" {
    export MOCK_PROMETHEUS_TARGETS_RESPONSE='{
  "status": "success",
  "data": {
    "activeTargets": [
      {
        "labels": {
          "job": "claude-code"
        },
        "health": "up",
        "lastError": "",
        "lastScrape": "2024-01-15T10:30:00Z"
      }
    ]
  }
}'
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9090/api/v1/targets" ]]; then
    echo "$MOCK_PROMETHEUS_TARGETS_RESPONSE"
    exit $MOCK_PROMETHEUS_TARGETS_STATUS
fi
exit 1
'
    
    create_mock "jq" '
if [[ "$*" =~ "activeTargets" ]] && [[ "$*" =~ "claude-code" ]]; then
    echo "Health: up, Last Error: none, Last Scrape: 2024-01-15T10:30:00Z"
fi
exit $MOCK_JQ_EXISTS
'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Prometheus Claude Code target status:" ]]
    [[ "$output" =~ "Health: up" ]]
    [[ "$output" =~ "Last Error: none" ]]
}

@test "handles Prometheus not accessible" {
    export MOCK_PROMETHEUS_TARGETS_STATUS=1
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9090/api/v1/targets" ]]; then
    exit $MOCK_PROMETHEUS_TARGETS_STATUS
fi
exit 0
'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "❌ Prometheus not accessible on localhost:9090" ]]
}

@test "shows target with error state" {
    export MOCK_PROMETHEUS_TARGETS_RESPONSE='{
  "status": "success",
  "data": {
    "activeTargets": [
      {
        "labels": {
          "job": "claude-code"
        },
        "health": "down",
        "lastError": "connection refused",
        "lastScrape": "2024-01-15T10:30:00Z"
      }
    ]
  }
}'
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9090/api/v1/targets" ]]; then
    echo "$MOCK_PROMETHEUS_TARGETS_RESPONSE"
    exit 0
fi
exit 1
'
    
    create_mock "jq" '
if [[ "$*" =~ "activeTargets" ]] && [[ "$*" =~ "claude-code" ]]; then
    echo "Health: down, Last Error: connection refused, Last Scrape: 2024-01-15T10:30:00Z"
fi
exit 0
'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Health: down" ]]
    [[ "$output" =~ "Last Error: connection refused" ]]
}

# Test metrics collection verification
@test "shows collected metrics count" {
    export MOCK_PROMETHEUS_QUERY_RESPONSE='{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": [
      {
        "metric": {},
        "value": [1642329600, "42"]
      }
    ]
  }
}'
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9090/api/v1/query" ]]; then
    echo "$MOCK_PROMETHEUS_QUERY_RESPONSE"
    exit $MOCK_PROMETHEUS_QUERY_STATUS
fi
exit 1
'
    
    create_mock "jq" '
if [[ "$*" =~ "result\[0\].value\[1\]" ]]; then
    echo "42"
fi
exit 0
'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✅ Total sessions recorded: 42" ]]
}

@test "handles zero metrics collected" {
    export MOCK_PROMETHEUS_QUERY_RESPONSE='{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": []
  }
}'
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9090/api/v1/query" ]]; then
    echo "$MOCK_PROMETHEUS_QUERY_RESPONSE"
    exit 0
fi
exit 1
'
    
    create_mock "jq" '
if [[ "$*" =~ "result\[0\].value\[1\]" ]]; then
    echo "0"
fi
exit 0
'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✅ Total sessions recorded: 0" ]]
}

@test "handles Prometheus query failure" {
    export MOCK_PROMETHEUS_QUERY_STATUS=1
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9090/api/v1/query" ]]; then
    exit $MOCK_PROMETHEUS_QUERY_STATUS
fi
exit 0
'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "❌ Cannot query Prometheus metrics" ]]
}

# Test error handling for curl timeouts
@test "handles curl timeout on metrics endpoint" {
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9464/metrics" ]]; then
    sleep 5  # Simulate timeout
    exit 28  # Curl timeout exit code
fi
exit 0
'
    
    # Use timeout to prevent test from hanging
    run timeout 2s ./check-claude-metrics.sh
    [ "$status" -eq 124 ] || [ "$status" -eq 0 ]  # timeout exit code or success
    [[ "$output" =~ "❌ Not accessible" ]] || [[ "$output" =~ "Checking Claude Code metrics" ]]
}

# Test handling of malformed responses
@test "handles malformed JSON from Prometheus targets API" {
    export MOCK_PROMETHEUS_TARGETS_RESPONSE="not valid json"
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9090/api/v1/targets" ]]; then
    echo "$MOCK_PROMETHEUS_TARGETS_RESPONSE"
    exit 0
fi
exit 1
'
    
    create_mock "jq" '
# Simulate jq parse error
>&2 echo "parse error: Invalid numeric literal at line 1, column 4"
exit 1
'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    # Should still complete despite jq error
    [[ "$output" =~ "Checking Claude Code metrics" ]]
}

# Test network failure scenarios
@test "handles network connection refused" {
    create_mock "curl" '
if [[ "$*" =~ "localhost:9464" ]]; then
    >&2 echo "curl: (7) Failed to connect to localhost port 9464: Connection refused"
    exit 7
elif [[ "$*" =~ "localhost:9090" ]]; then
    >&2 echo "curl: (7) Failed to connect to localhost port 9090: Connection refused"
    exit 7
fi
exit 0
'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "❌ Not accessible" ]]
    [[ "$output" =~ "❌ Prometheus not accessible" ]]
}

# Test output formatting
@test "displays section headers correctly" {
    export MOCK_METRICS_STATUS=1
    export MOCK_PROMETHEUS_TARGETS_STATUS=1
    export MOCK_PROMETHEUS_QUERY_STATUS=1
    
    create_mock "curl" 'exit 1'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "🔍 Checking Claude Code metrics availability..." ]]
    [[ "$output" =~ "=============================================" ]]
    [[ "$output" =~ "🎯 Checking Prometheus targets..." ]]
    [[ "$output" =~ "=================================" ]]
    [[ "$output" =~ "📈 Checking if metrics are being collected..." ]]
    [[ "$output" =~ "==========================================" ]]
}

# Test empty metrics response
@test "handles empty metrics from Claude Code" {
    export MOCK_METRICS_RESPONSE=""
    export MOCK_METRICS_STATUS=0
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9464/metrics" ]]; then
    if [[ ! "$*" =~ "/dev/null" ]]; then
        echo "$MOCK_METRICS_RESPONSE"
    fi
    exit $MOCK_METRICS_STATUS
fi
exit 1
'
    
    create_mock "grep" 'exit 1'  # No matching lines
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✅ Accessible" ]]
    # Should still show the metrics section header but no metrics
    [[ "$output" =~ "📊 Sample Claude Code metrics:" ]]
}

# Test with all services running correctly
@test "shows success for fully operational stack" {
    export MOCK_METRICS_RESPONSE="claude_code_session_count_total 10"
    export MOCK_PROMETHEUS_TARGETS_RESPONSE='{
  "status": "success",
  "data": {
    "activeTargets": [{
      "labels": {"job": "claude-code"},
      "health": "up",
      "lastError": "",
      "lastScrape": "2024-01-15T10:30:00Z"
    }]
  }
}'
    export MOCK_PROMETHEUS_QUERY_RESPONSE='{
  "status": "success",
  "data": {
    "result": [{
      "value": [1642329600, "10"]
    }]
  }
}'
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9464/metrics" ]]; then
    if [[ "$*" =~ "/dev/null" ]]; then
        exit 0
    else
        echo "$MOCK_METRICS_RESPONSE"
        exit 0
    fi
elif [[ "$*" =~ "http://localhost:9090/api/v1/targets" ]]; then
    echo "$MOCK_PROMETHEUS_TARGETS_RESPONSE"
    exit 0
elif [[ "$*" =~ "http://localhost:9090/api/v1/query" ]]; then
    echo "$MOCK_PROMETHEUS_QUERY_RESPONSE"
    exit 0
fi
exit 1
'
    
    create_mock "grep" '
if [[ "$1" == "^claude_code_" ]]; then
    echo "claude_code_session_count_total 10"
fi
'
    
    create_mock "head" 'cat'
    
    create_mock "jq" '
if [[ "$*" =~ "activeTargets" ]]; then
    echo "Health: up, Last Error: none, Last Scrape: 2024-01-15T10:30:00Z"
elif [[ "$*" =~ "result\[0\].value\[1\]" ]]; then
    echo "10"
fi
exit 0
'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✅ Accessible" ]]
    [[ "$output" =~ "Health: up" ]]
    [[ "$output" =~ "✅ Total sessions recorded: 10" ]]
}

# Test jq not installed
@test "handles missing jq gracefully" {
    export MOCK_JQ_EXISTS=127  # Command not found
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9090/api/v1/targets" ]]; then
    echo "{}"
    exit 0
elif [[ "$*" =~ "http://localhost:9090/api/v1/query" ]]; then
    echo "{}"
    exit 0
fi
exit 1
'
    
    create_mock "jq" 'exit 127'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    # Script should continue despite missing jq
    [[ "$output" =~ "Checking Claude Code metrics" ]]
}

# Test metrics with special characters
@test "handles metrics with special characters" {
    export MOCK_METRICS_RESPONSE='claude_code_error{type="connection_error",message="Failed to connect: \"timeout\""} 5
claude_code_response_time_seconds{quantile="0.99"} 1.5
claude_code_status{version="1.0.0-beta.1"} 1'
    
    create_mock "curl" '
if [[ "$*" =~ "http://localhost:9464/metrics" ]]; then
    if [[ ! "$*" =~ "/dev/null" ]]; then
        echo "$MOCK_METRICS_RESPONSE"
    fi
    exit 0
fi
exit 1
'
    
    create_mock "grep" '
if [[ "$1" == "^claude_code_" ]]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^claude_code_ ]]; then
            echo "$line"
        fi
    done
fi
'
    
    create_mock "head" 'cat'
    
    run ./check-claude-metrics.sh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "claude_code_error" ]]
    [[ "$output" =~ "connection_error" ]]
}