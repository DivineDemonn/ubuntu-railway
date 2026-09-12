FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PATH="/app/.venv/bin:$PATH"

# ==========================================
# System packages
# ==========================================
RUN apt-get update && \
    apt-get install -y \
        wget \
        curl \
        python3 \
        python3-pip \
        python3-venv \
        python3-full \
        ffmpeg \
        neofetch \
        tmux \
        ca-certificates \
        procps \
        unzip \
        bash \
        git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ==========================================
# Node.js 20
# ==========================================
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get update && \
    apt-get install -y nodejs && \
    node --version && \
    npm --version && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ==========================================
# ttyd Web Console
# ==========================================
RUN wget -qO /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd && \
    /usr/local/bin/ttyd --version

# ==========================================
# VelouraMusic source
#
# IMPORTANT:
# Railway builds this Dockerfile from the
# VelouraMusic GitHub repository.
# Therefore COPY the repository files
# instead of git cloning it.
# ==========================================
WORKDIR /app

COPY . /app

# ==========================================
# Verify required files
# ==========================================
RUN test -f /app/requirements.txt && \
    test -f /app/start

# ==========================================
# Python virtual environment
# ==========================================
RUN python3 -m venv /app/.venv && \
    . /app/.venv/bin/activate && \
    python -m pip install --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r /app/requirements.txt && \
    pip install --no-cache-dir TgCrypto

# ==========================================
# VPS Supervisor
# ==========================================
RUN cat > /usr/local/bin/vps-supervisor.sh <<'EOF'
#!/bin/bash

set -u

BOT_DIR="/app"
LOG="/app/veloura.log"

echo "======================================"
echo "       Railway Ubuntu VPS"
echo "======================================"
echo "Node: $(node --version)"
echo "Python: $(python3 --version)"
echo "FFmpeg: $(ffmpeg -version 2>&1 | head -1)"
echo "======================================"

# ------------------------------------------
# Verify application
# ------------------------------------------
if [ ! -d "$BOT_DIR" ]; then
    echo "[ERROR] Application directory not found!"
    exit 1
fi

if [ ! -f "$BOT_DIR/start" ]; then
    echo "[ERROR] start file not found!"
    exit 1
fi

if [ ! -f "$BOT_DIR/requirements.txt" ]; then
    echo "[ERROR] requirements.txt not found!"
    exit 1
fi

echo "[VPS] VelouraMusic files found."

# ------------------------------------------
# Start ttyd
# ------------------------------------------
start_ttyd() {

    echo "[VPS] Starting ttyd on port ${PORT}..."

    # Kill old ttyd if present
    pkill -f "/usr/local/bin/ttyd" 2>/dev/null || true

    ttyd \
        --port "${PORT}" \
        --credential "${USERNAME}:${PASSWORD}" \
        --writable \
        /bin/bash &

    TTYD_PID=$!

    echo "[VPS] ttyd PID: ${TTYD_PID}"
}

start_ttyd

# ------------------------------------------
# VelouraMusic supervisor
# ------------------------------------------
while true; do

    echo ""
    echo "======================================"
    echo "[VPS] Starting VelouraMusic..."
    echo "======================================"

    cd "$BOT_DIR" || exit 1

    # Activate virtual environment
    if [ -f "$BOT_DIR/.venv/bin/activate" ]; then
        source "$BOT_DIR/.venv/bin/activate"
    fi

    echo "[VPS] Python: $(python --version)"
    echo "[VPS] Node: $(node --version)"
    echo "[VPS] FFmpeg: $(which ffmpeg)"

    # --------------------------------------
    # Prevent duplicate bot instances
    # --------------------------------------
    pkill -f "python.*MusicSp" 2>/dev/null || true

    sleep 2

    echo "[VPS] Starting ONE VelouraMusic instance..."

    bash "$BOT_DIR/start" >> "$LOG" 2>&1

    EXIT_CODE=$?

    echo ""
    echo "======================================"
    echo "[VPS] VelouraMusic stopped."
    echo "[VPS] Exit code: $EXIT_CODE"
    echo "[VPS] Restarting in 5 seconds..."
    echo "======================================"

    sleep 5
done
EOF

RUN chmod +x /usr/local/bin/vps-supervisor.sh

# ==========================================
# Root shell
# ==========================================
RUN echo 'neofetch' >> /root/.bashrc && \
    echo 'cd /app' >> /root/.bashrc

# ==========================================
# Railway port
# ==========================================
EXPOSE 8080

# ==========================================
# Start supervisor
# ==========================================
CMD ["/usr/local/bin/vps-supervisor.sh"]
