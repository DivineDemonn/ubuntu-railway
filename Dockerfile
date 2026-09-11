FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        wget \
        curl \
        git \
        python3 \
        python3-pip \
        neofetch \
        tmux && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN wget -qO /bin/ttyd \
    https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 && \
    chmod +x /bin/ttyd

RUN cat > /usr/local/bin/start-vps.sh <<'EOF'
#!/bin/bash

echo "======================================"
echo "        Railway Ubuntu VPS"
echo "======================================"

# Start VelouraMusic independently from ttyd
if [ -d "/root/VelouraMusic" ]; then

    echo "[VPS] VelouraMusic directory found."

    while true; do
        echo "[VPS] Starting VelouraMusic..."

        cd /root/VelouraMusic || exit 1

        if [ -f ".venv/bin/activate" ]; then
            source .venv/bin/activate
        fi

        bash start

        EXIT_CODE=$?

        echo "[VPS] VelouraMusic stopped with exit code: $EXIT_CODE"
        echo "[VPS] Restarting in 5 seconds..."

        sleep 5
    done &

else
    echo "[VPS] VelouraMusic directory not found."
    echo "[VPS] Console will still be available."
fi

# Start the web terminal independently
echo "[VPS] Starting ttyd..."

exec /bin/ttyd \
    -p "${PORT}" \
    -c "${USERNAME}:${PASSWORD}" \
    /bin/bash
EOF

RUN chmod +x /usr/local/bin/start-vps.sh

RUN echo 'neofetch' >> /root/.bashrc
RUN echo 'cd /root' >> /root/.bashrc

EXPOSE ${PORT}

CMD ["/usr/local/bin/start-vps.sh"]
