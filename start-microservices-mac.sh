#!/bin/bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

CONFIG_DIR="$BASE_DIR/metaarch-config-server"
EUREKA_DIR="$BASE_DIR/metaarch-eureka-server"
SECURITY_DIR="$BASE_DIR/org-access"
GATEWAY_DIR="$BASE_DIR/metaarch-api-gateway"
BOOKING_DIR="$BASE_DIR/BokingSysem"
ALERTS_DIR="$BASE_DIR/Alerts"

CONFIG_PORT=8888
EUREKA_PORT=8761
SECURITY_PORT=8083
GATEWAY_PORT=8082
BOOKING_PORT=8086
ALERTS_PORT=8087

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    exit 1
  fi
}

check_directory() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo "Missing service directory: $dir"
    exit 1
  fi
}

is_port_open() {
  local port="$1"
  lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

wait_for_port() {
  local name="$1"
  local port="$2"
  local timeout="${3:-120}"
  local elapsed=0

  echo "Waiting for $name on port $port..."
  while ! is_port_open "$port"; do
    sleep 2
    elapsed=$((elapsed + 2))
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "$name did not start within $timeout seconds."
      exit 1
    fi
  done
  echo "$name is up on port $port."
}

open_terminal_tab() {
  local title="$1"
  local dir="$2"

  osascript <<EOF >/dev/null
tell application "Terminal"
  activate
  do script "cd '$dir' && printf '\\\\e]1;$title\\\\a' && mvn spring-boot:run"
end tell
EOF
}

start_service() {
  local name="$1"
  local dir="$2"
  local port="$3"

  if is_port_open "$port"; then
    echo "$name already appears to be running on port $port. Skipping startup."
    return
  fi

  echo "Starting $name..."
  open_terminal_tab "$name" "$dir"
  wait_for_port "$name" "$port"
}

require_command mvn
require_command lsof
require_command osascript

check_directory "$CONFIG_DIR"
check_directory "$EUREKA_DIR"
check_directory "$SECURITY_DIR"
check_directory "$GATEWAY_DIR"
check_directory "$BOOKING_DIR"
check_directory "$ALERTS_DIR"

start_service "Config Server" "$CONFIG_DIR" "$CONFIG_PORT"
start_service "Eureka Server" "$EUREKA_DIR" "$EUREKA_PORT"
start_service "Security Server" "$SECURITY_DIR" "$SECURITY_PORT"
start_service "API Gateway" "$GATEWAY_DIR" "$GATEWAY_PORT"
start_service "Booking System" "$BOOKING_DIR" "$BOOKING_PORT"
start_service "Alert System" "$ALERTS_DIR" "$ALERTS_PORT"
echo "All requested services have been started in order."
