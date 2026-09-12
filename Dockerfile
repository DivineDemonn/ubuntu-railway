FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PATH="/root/VelouraMusic/.venv/bin:$PATH"

# ==========================================
# System packages
# ==========================================
RUN apt-get update && \
    apt-get install -y \
        wget \
        curl \
        git \
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
# ttyd Web VPS Console
# ==========================================
RUN wget -qO /usr/local/bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 && \
    chmod +x /usr/local/bin/ttyd && \
    /usr/local/bin/ttyd --version

# ==========================================
# Clone VelouraMusic
# ==========================================
RUN rm -rf /root/VelouraMusic && \
    git clone --depth 1 \
    https://github.com/DivineDemonn/VelouraMusic.git \
    /root/VelouraMusic

# ==========================================
# Python virtual environment
# ==========================================
RUN cd /root/VelouraMusic && \
    test -f requirements.txt && \
    test -f start && \
    python3 -m venv .venv && \
    . .venv/bin/activate && \
    python -m pip install --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir TgCrypto

# ==========================================
# VPS Supervisor
# ==========================================
RUN cat > /usr/local/bin/vps-supervisor.sh <<'EOF'
#!/bin/bash

set -u

BOT_DIR="/root/VelouraMusic"
LOG="/root/veloura.log"

echo "======================================"
echo "       Railway Ubuntu VPS"
echo "======================================"
echo "Node: $(node --version)"
echo "Python: $(python3 --version)"
echo "======================================"

# ------------------------------------------
# Check VelouraMusic
# ------------------------------------------
if [ ! -d "$BOT_DIR" ]; then
    echo "[ERROR] VelouraMusic directory not found!"
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

echo "[VPS] VelouraMusic directory found."
echo "[VPS] Starting web console..."

# ------------------------------------------
# Start ttyd
# ------------------------------------------
start_ttyd() {
    echo "[VPS] Starting ttyd on port ${PORT}..."

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
# Restart ttyd if it dies
# ------------------------------------------
(
    while true; do
        sleep 5

        if ! kill -0 "$TTYD_PID" 2>/dev/null; then
            echo "[VPS] ttyd stopped. Restarting..."

            ttyd \
                --port "${PORT}" \
                --credential "${USERNAME}:${PASSWORD}" \
                --writable \
                /bin/bash &

            TTYD_PID=$!

            echo "[VPS] New ttyd PID: ${TTYD_PID}"
        fi
    done
) &

TTyd_WATCHDOG_PID=$!

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
    echo "[VPS] Starting bot..."

    # Run bot independently from browser/ttyd
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
# Bash configuration
# ==========================================
RUN echo 'neofetch' >> /root/.bashrc && \
    echo 'cd /root' >> /root/.bashrc

# Railway supplies PORT at runtime
EXPOSE 8080

# ==========================================
# Start VPS
# ==========================================
CMD ["/usr/local/bin/vps-supervisor.sh"]
