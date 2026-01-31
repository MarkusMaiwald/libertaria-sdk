#!/bin/bash
set -e

BIN="./zig-out/bin/capsule"

echo "Killing any existing capsule..."
pkill -f "$BIN" || true

echo "Starting daemon..."
$BIN start &
DAEMON_PID=$!

sleep 2

echo "Checking status..."
$BIN status

echo "Checking peers..."
$BIN peers

echo "Stopping daemon..."
$BIN stop

wait $DAEMON_PID
echo "Done."
