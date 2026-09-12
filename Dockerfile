FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# System packages
RUN apt-get update && \
    apt-get upgrade -y && \
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
        procps && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    node --version && \
    npm --version

# ttyd
RUN wget -qO /bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 && \
    chmod +x /bin/ttyd

# Clone VelouraMusic
RUN git clone --depth 1 \
    https://github.com/DivineDemonn/VelouraMusic.git \
    /root/VelouraMusic

# Python environment
RUN cd /root/VelouraMusic && \
    python3 -m venv .venv && \
    . .venv/bin/activate && \
    python -m pip install --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir TgCrypto

# VPS supervisor
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

# Start ttyd independently
echo "[VPS] Starting ttyd..."

ttyd \
    -p "${PORT}" \
    -c "${USERNAME}:${PASSWORD}" \
    /bin/bash &

TTYD_PID=$!

echo "[VPS] ttyd PID: ${TTYD_PID}"

# Give the terminal a moment to start
sleep 2

# Start and supervise VelouraMusic
while true; do

    if ! kill -0 "${TTYD_PID}" 2>/dev/null; then
        echo "[VPS] ttyd stopped. Restarting..."
        
        ttyd \
            -p "${PORT}" \
            -c "${USERNAME}:${PASSWORD}" \
            /bin/bash &

        TTYD_PID=$!
    fi

    echo "[VPS] Starting VelouraMusic..."

    cd "${BOT_DIR}" || exit 1

    if [ -f "${BOT_DIR}/.venv/bin/activate" ]; then
        source "${BOT_DIR}/.venv/bin/activate"
    fi

    bash "${BOT_DIR}/start" >> "${LOG}" 2>&1 &
    BOT_PID=$!

    echo "[VPS] VelouraMusic PID: ${BOT_PID}"

    # Wait while bot is running.
    wait "${BOT_PID}"
    EXIT_CODE=$?

    echo "[VPS] VelouraMusic stopped."
    echo "[VPS] Exit code: ${EXIT_CODE}"
    echo "[VPS] Restarting in 5 seconds..."

    sleep 5
done
EOF

RUN chmod +x /usr/local/bin/vps-supervisor.sh

RUN echo 'neofetch' >> /root/.bashrc
RUN echo 'cd /root' >> /root/.bashrc

EXPOSE ${PORT}

CMD ["/usr/local/bin/vps-supervisor.sh"]
