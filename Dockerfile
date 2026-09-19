
# ============================================================
# UPLOADER-BOT-V4
# Production Dockerfile
# Railway / VPS
# ============================================================

FROM ubuntu:22.04

# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH="/app/.venv/bin:$PATH"

# ------------------------------------------------------------
# System dependencies
# ------------------------------------------------------------

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        python3-full \
        ffmpeg \
        git \
        curl \
        wget \
        ca-certificates \
        bash \
        procps \
        tini \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Working directory
# ------------------------------------------------------------

WORKDIR /app

# ------------------------------------------------------------
# Copy dependency file first
#
# This allows Docker/Railway to cache Python dependencies
# when only application source code changes.
# ------------------------------------------------------------

COPY requirements.txt /app/requirements.txt

# ------------------------------------------------------------
# Python virtual environment
# ------------------------------------------------------------

RUN python3 -m venv /app/.venv && \
    /app/.venv/bin/python -m pip install --upgrade \
        pip \
        setuptools \
        wheel && \
    /app/.venv/bin/pip install \
        --no-cache-dir \
        -r /app/requirements.txt

# ------------------------------------------------------------
# Copy application source
# ------------------------------------------------------------

COPY . /app

# ------------------------------------------------------------
# Runtime directories
# ------------------------------------------------------------

RUN mkdir -p \
        /app/logs \
        /app/downloads \
        /app/temp \
        /app/cache

# ------------------------------------------------------------
# Basic application validation
# ------------------------------------------------------------

RUN echo "========== UPLOADER-BOT-V4 BUILD CHECK ==========" && \
    python --version && \
    pip --version && \
    ffmpeg -version 2>&1 | head -1 && \
    echo "Application directory:" && \
    ls -la /app && \
    echo "=================================================="

# ------------------------------------------------------------
# Production supervisor
#
# Keeps the bot alive if the main process crashes.
# Railway will still be able to restart the container itself
# if the supervisor/container completely fails.
# ------------------------------------------------------------

RUN cat > /usr/local/bin/uploader-supervisor.sh <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

APP_DIR="/app"
LOG_DIR="/app/logs"
LOG_FILE="${LOG_DIR}/uploader.log"

mkdir -p "$LOG_DIR"

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Send output to both Railway logs and application log.
exec > >(tee -a "$LOG_FILE") 2>&1

# ------------------------------------------------------------
# Startup information
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo "              UPLOADER-BOT-V4"
echo "              Production Runtime"
echo "============================================================"

log "Container started"
log "Working directory: ${APP_DIR}"
log "Python: $(python --version 2>&1)"
log "Pip: $(pip --version 2>&1 | head -1)"
log "FFmpeg: $(ffmpeg -version 2>&1 | head -1)"
log "Hostname: $(hostname)"

echo "============================================================"

# ------------------------------------------------------------
# Validate application
# ------------------------------------------------------------

if [[ ! -d "$APP_DIR" ]]; then
    log "[ERROR] Application directory does not exist."
    exit 1
fi

if [[ ! -f "$APP_DIR/requirements.txt" ]]; then
    log "[ERROR] requirements.txt not found."
    exit 1
fi

cd "$APP_DIR"

log "[OK] Application files detected."

# ------------------------------------------------------------
# Detect startup command
#
# Priority:
#   1. executable ./start
#   2. executable ./start.sh
#   3. bot.py
#   4. main.py
#   5. app.py
# ------------------------------------------------------------

if [[ -x "$APP_DIR/start" ]]; then

    START_COMMAND=("$APP_DIR/start")

elif [[ -f "$APP_DIR/start" ]]; then

    START_COMMAND=("bash" "$APP_DIR/start")

elif [[ -x "$APP_DIR/start.sh" ]]; then

    START_COMMAND=("$APP_DIR/start.sh")

elif [[ -f "$APP_DIR/start.sh" ]]; then

    START_COMMAND=("bash" "$APP_DIR/start.sh")

elif [[ -f "$APP_DIR/bot.py" ]]; then

    START_COMMAND=("python" "$APP_DIR/bot.py")

elif [[ -f "$APP_DIR/main.py" ]]; then

    START_COMMAND=("python" "$APP_DIR/main.py")

elif [[ -f "$APP_DIR/app.py" ]]; then

    START_COMMAND=("python" "$APP_DIR/app.py")

else

    log "[ERROR] No supported startup file found."
    log "Expected one of:"
    log "  start"
    log "  start.sh"
    log "  bot.py"
    log "  main.py"
    log "  app.py"
    exit 1

fi

log "[OK] Startup command detected:"
printf ' '
printf '%q ' "${START_COMMAND[@]}"
echo ""

# ------------------------------------------------------------
# Graceful shutdown
# ------------------------------------------------------------

BOT_PID=""

shutdown() {

    log "[SYSTEM] Shutdown signal received."

    if [[ -n "${BOT_PID}" ]] && kill -0 "$BOT_PID" 2>/dev/null; then

        log "[SYSTEM] Stopping bot PID ${BOT_PID}..."

        kill -TERM "$BOT_PID" 2>/dev/null || true

        for _ in {1..15}; do

            if ! kill -0 "$BOT_PID" 2>/dev/null; then
                break
            fi

            sleep 1

        done

        if kill -0 "$BOT_PID" 2>/dev/null; then
            log "[SYSTEM] Bot did not stop gracefully. Sending SIGKILL."
            kill -KILL "$BOT_PID" 2>/dev/null || true
        fi

    fi

    log "[SYSTEM] Shutdown complete."

    exit 0
}

trap shutdown SIGTERM SIGINT

# ------------------------------------------------------------
# Main restart loop
# ------------------------------------------------------------

RESTART_DELAY=5
RESTART_COUNT=0

while true; do

    RESTART_COUNT=$((RESTART_COUNT + 1))

    echo ""
    echo "============================================================"
    log "Starting UPLOADER-BOT-V4"
    log "Start attempt: ${RESTART_COUNT}"
    echo "============================================================"

    cd "$APP_DIR"

    # --------------------------------------------------------
    # Start bot
    # --------------------------------------------------------

    set +e

    "${START_COMMAND[@]}" &
    BOT_PID=$!

    log "[BOT] Running with PID ${BOT_PID}"

    wait "$BOT_PID"

    EXIT_CODE=$?

    set -e

    BOT_PID=""

    echo ""
    echo "============================================================"
    log "[BOT] Process stopped."
    log "[BOT] Exit code: ${EXIT_CODE}"
    echo "============================================================"

    # --------------------------------------------------------
    # Normal exit
    #
    # Still restart because this container is intended to keep
    # the uploader service alive.
    # --------------------------------------------------------

    log "[SYSTEM] Restarting in ${RESTART_DELAY} seconds..."

    sleep "$RESTART_DELAY"

done
EOF

RUN chmod +x /usr/local/bin/uploader-supervisor.sh

# ------------------------------------------------------------
# Optional root shell configuration
# ------------------------------------------------------------

RUN echo 'cd /app' >> /root/.bashrc

# ------------------------------------------------------------
# Railway port
#
# Only relevant if the application or ttyd exposes HTTP.
# Railway may provide its own PORT environment variable.
# ------------------------------------------------------------

EXPOSE 8080

# ------------------------------------------------------------
# tini = proper PID 1 / signal handling
# ------------------------------------------------------------

ENTRYPOINT ["/usr/bin/tini", "--"]

# ------------------------------------------------------------
# Start production supervisor
# ------------------------------------------------------------

CMD ["/usr/local/bin/uploader-supervisor.sh"]

