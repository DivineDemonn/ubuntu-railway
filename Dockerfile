FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PIP_NO_CACHE_DIR=1
ENV PATH="/app/.venv/bin:$PATH"

# ============================================================
# SYSTEM PACKAGES
# ============================================================

RUN apt-get update && \
    apt-get install -y \
        ca-certificates \
        curl \
        wget \
        git \
        bash \
        python3 \
        python3-pip \
        python3-venv \
        python3-full \
        ffmpeg \
        procps \
        tmux \
        unzip \
        neofetch \
        build-essential \
        libffi-dev \
        libssl-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# NODE.JS 20
# ============================================================

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get update && \
    apt-get install -y nodejs && \
    node --version && \
    npm --version && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ============================================================
# TTYD WEB TERMINAL
# ============================================================

RUN wget -qO /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd && \
    /usr/local/bin/ttyd --version

# ============================================================
# APPLICATION
# ============================================================

WORKDIR /app

COPY . /app

# ============================================================
# SHOW REPOSITORY
# ============================================================

RUN echo "" && \
    echo "============================================" && \
    echo "        UPLOADER-BOT-V4 REPOSITORY" && \
    echo "============================================" && \
    echo "" && \
    find /app -maxdepth 2 -type f \
        ! -path "/app/.git/*" \
        -printf "%p\n" | sort | head -200 && \
    echo "" && \
    echo "============================================"

# ============================================================
# CHECK REQUIREMENTS
# ============================================================

RUN if [ -f "/app/requirements.txt" ]; then \
        echo "[OK] requirements.txt found"; \
    elif [ -f "/app/requirements/requirements.txt" ]; then \
        echo "[OK] requirements/requirements.txt found"; \
    else \
        echo "[ERROR] No requirements.txt found!"; \
        echo ""; \
        echo "Python dependency file was not found."; \
        echo "Repository contents:"; \
        find /app -maxdepth 2 -type f -print | sort; \
        exit 1; \
    fi

# ============================================================
# PYTHON VIRTUAL ENVIRONMENT
# ============================================================

RUN python3 -m venv /app/.venv && \
    /app/.venv/bin/python -m pip install --upgrade \
        pip \
        setuptools \
        wheel

# ============================================================
# INSTALL PYTHON DEPENDENCIES
# ============================================================

RUN if [ -f "/app/requirements.txt" ]; then \
        /app/.venv/bin/pip install -r /app/requirements.txt; \
    elif [ -f "/app/requirements/requirements.txt" ]; then \
        /app/.venv/bin/pip install -r /app/requirements/requirements.txt; \
    fi

# ============================================================
# TGCRYPTO
#
# Safe to install if the bot uses Pyrogram.
# ============================================================

RUN /app/.venv/bin/pip install TgCrypto

# ============================================================
# OPTIONAL YOUTUBE / MEDIA SUPPORT
# ============================================================

RUN /app/.venv/bin/pip install yt-dlp

# ============================================================
# CREATE UNIVERSAL START SCRIPT
# ============================================================

RUN cat > /app/start <<'EOF'
#!/bin/bash

set -u

cd /app

echo ""
echo "============================================"
echo "          UPLOADER-BOT-V4"
echo "============================================"
echo "Python : $(python --version)"
echo "FFmpeg : $(ffmpeg -version 2>&1 | head -1)"
echo "PWD    : $(pwd)"
echo "============================================"
echo ""

# ============================================================
# ENTRY POINT DETECTION
# ============================================================

if [ -f "/app/bot.py" ]; then

    echo "[START] Detected bot.py"
    exec python /app/bot.py

elif [ -f "/app/main.py" ]; then

    echo "[START] Detected main.py"
    exec python /app/main.py

elif [ -f "/app/app.py" ]; then

    echo "[START] Detected app.py"
    exec python /app/app.py

elif [ -f "/app/run.py" ]; then

    echo "[START] Detected run.py"
    exec python /app/run.py

elif [ -f "/app/start.py" ]; then

    echo "[START] Detected start.py"
    exec python /app/start.py

else

    echo ""
    echo "[ERROR] Could not automatically detect bot entry file!"
    echo ""
    echo "Python files found:"
    find /app -maxdepth 2 -type f \
        \( -name "*.py" -o -name "*.sh" \) \
        ! -path "/app/.venv/*" \
        -print | sort
    echo ""

    exit 1

fi
EOF

RUN chmod +x /app/start

# ============================================================
# SUPERVISOR
# ============================================================

RUN cat > /usr/local/bin/uploader-supervisor.sh <<'EOF'
#!/bin/bash

set -u

APP_DIR="/app"
LOG_FILE="/app/uploader.log"

# Railway gives the service a PORT.
PORT="${PORT:-8080}"

echo ""
echo "================================================"
echo "              UPLOADER-BOT-V4"
echo "              RAILWAY CONTAINER"
echo "================================================"
echo "Python : $(python3 --version)"
echo "Node   : $(node --version)"
echo "FFmpeg : $(ffmpeg -version 2>&1 | head -1)"
echo "Port   : ${PORT}"
echo "App    : ${APP_DIR}"
echo "================================================"
echo ""

# ============================================================
# BASIC VALIDATION
# ============================================================

if [ ! -d "$APP_DIR" ]; then
    echo "[ERROR] /app does not exist!"
    exit 1
fi

if [ ! -f "$APP_DIR/start" ]; then
    echo "[ERROR] /app/start does not exist!"
    exit 1
fi

if [ ! -f "$APP_DIR/.venv/bin/python" ]; then
    echo "[ERROR] Python virtual environment not found!"
    exit 1
fi

echo "[OK] Application directory"
echo "[OK] Start script"
echo "[OK] Python virtual environment"

# ============================================================
# START TTYD
# ============================================================

start_ttyd() {

    echo ""
    echo "[VPS] Starting ttyd..."

    # IMPORTANT:
    # ttyd uses a separate internal port.
    # Railway's public PORT is used for the service.
    # We bind ttyd to 8080 by default.

    TTYD_PORT="${TTYD_PORT:-8080}"

    pkill -f "/usr/local/bin/ttyd" 2>/dev/null || true

    sleep 1

    if [ -n "${USERNAME:-}" ] && [ -n "${PASSWORD:-}" ]; then

        echo "[VPS] ttyd authentication enabled"
        echo "[VPS] ttyd port: ${TTYD_PORT}"

        /usr/local/bin/ttyd \
            --port "${TTYD_PORT}" \
            --credential "${USERNAME}:${PASSWORD}" \
            --writable \
            /bin/bash &

    else

        echo "[VPS] USERNAME/PASSWORD not configured"
        echo "[VPS] Starting ttyd without authentication"
        echo "[VPS] ttyd port: ${TTYD_PORT}"

        /usr/local/bin/ttyd \
            --port "${TTYD_PORT}" \
            --writable \
            /bin/bash &

    fi

    TTYD_PID=$!

    echo "[VPS] ttyd PID: ${TTYD_PID}"
}

# ============================================================
# START WEB TERMINAL
# ============================================================

start_ttyd

sleep 2

# ============================================================
# BOT SUPERVISOR LOOP
# ============================================================

while true; do

    echo ""
    echo "================================================"
    echo "          STARTING UPLOADER-BOT-V4"
    echo "================================================"
    echo "Time: $(date)"
    echo ""

    cd "$APP_DIR" || exit 1

    # Activate virtual environment
    source "$APP_DIR/.venv/bin/activate"

    echo "[VPS] Python: $(python --version)"
    echo "[VPS] FFmpeg: $(which ffmpeg)"
    echo "[VPS] Working directory: $(pwd)"
    echo ""

    # ========================================================
    # START BOT
    # ========================================================

    echo "[VPS] Starting bot..."
    echo ""

    bash "$APP_DIR/start" 2>&1 | tee -a "$LOG_FILE"

    EXIT_CODE=${PIPESTATUS[0]}

    echo ""
    echo "================================================"
    echo "          BOT PROCESS STOPPED"
    echo "================================================"
    echo "Exit code: ${EXIT_CODE}"
    echo "Time: $(date)"
    echo "Restarting in 5 seconds..."
    echo "================================================"
    echo ""

    sleep 5

done
EOF

RUN chmod +x /usr/local/bin/uploader-supervisor.sh

# ============================================================
# ROOT SHELL
# ============================================================

RUN echo 'cd /app' >> /root/.bashrc && \
    echo 'neofetch' >> /root/.bashrc

# ============================================================
# RAILWAY PORT
# ============================================================

EXPOSE 8080

# ============================================================
# START CONTAINER
# ============================================================

CMD ["/usr/local/bin/uploader-supervisor.sh"]
