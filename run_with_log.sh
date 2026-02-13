#!/bin/bash

APP_CMD="gleam run"
LOG_FILE="app.log"

echo "[$(date)] Running guardian..." | tee -a "$LOG_FILE"
while true; do
    echo "[$(date)] Starting app..." | tee -a "$LOG_FILE"
    $APP_CMD 2>&1 | tee -a "$LOG_FILE"
    EXIT_CODE=${PIPESTATUS[0]}
    echo "[$(date)] Process exited with code: $EXIT_CODE. Restart in 5 sec" | tee -a "$LOG_FILE"
    sleep 5
done