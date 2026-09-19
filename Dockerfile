FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PIP_NO_CACHE_DIR=1

# ============================================================
# SYSTEM PACKAGES
# ============================================================

RUN apt-get update && \
    apt-get install -y \
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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# APPLICATION
# ============================================================

WORKDIR /app

COPY . /app

# ============================================================
# SHOW FILES
# ============================================================

RUN echo "========================================" && \
    echo "UPLOADER-BOT-V4 BUILD" && \
    echo "========================================" && \
    echo "Repository files:" && \
    find /app -maxdepth 2 -type f \
        ! -path "/app/.git/*" \
        -print | sort && \
    echo "========================================"

# ============================================================
# REQUIREMENTS
# ============================================================

RUN test -f /app/requirements.txt

# ============================================================
# PYTHON VENV
# ============================================================

RUN python3 -m venv /app/.venv && \
    /app/.venv/bin/python -m pip install --upgrade pip setuptools wheel && \
    /app/.venv/bin/pip install -r /app/requirements.txt

# ============================================================
# START SCRIPT
# ============================================================

RUN cat > /app/start.sh <<'EOF'
#!/bin/bash

set -e

cd /app

echo "========================================"
echo "       UPLOADER-BOT-V4 STARTING"
echo "========================================"

echo "Python:"
python --version

echo "FFmpeg:"
ffmpeg -version 2>&1 | head -1

echo "Directory:"
pwd

echo "========================================"

if [ -f "/app/bot.py" ]; then
    echo "[START] bot.py detected"
    exec python /app/bot.py

elif [ -f "/app/main.py" ]; then
    echo "[START] main.py detected"
    exec python /app/main.py

elif [ -f "/app/app.py" ]; then
    echo "[START] app.py detected"
    exec python /app/app.py

else
    echo "[ERROR] No bot entry file found!"
    echo ""
    echo "Python files:"
    find /app -maxdepth 2 -name "*.py" \
        ! -path "/app/.venv/*" \
        -print | sort
    exit 1
fi
EOF

RUN chmod +x /app/start.sh

# ============================================================
# START
# ============================================================

CMD ["/app/start.sh"]
