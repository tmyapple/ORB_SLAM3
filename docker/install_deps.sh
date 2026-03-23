#!/usr/bin/env bash
# install_deps.sh - Install system dependencies for ORB-SLAM3 inside the Docker container.
# Uses sudo if not root. Run as tamirt inside container.
# Idempotent: safe to re-run.

set -euo pipefail

# ------------------------------------------------------------------
# Use sudo if not already root
# ------------------------------------------------------------------
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

# ------------------------------------------------------------------
# Install packages
# ------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive

$SUDO apt-get update

$SUDO apt-get install -y \
    libeigen3-dev \
    libboost-serialization-dev \
    libssl-dev \
    libglew-dev \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libegl1-mesa-dev \
    libopencv-dev \
    xvfb \
    git \
    wget \
    unzip \
    python3-numpy \
    python3-matplotlib \
    bc \
    ffmpeg

# ------------------------------------------------------------------
# Fix numpy version conflict: system matplotlib needs numpy<2,
# but user's ~/.local may have numpy>=2 from pip
# ------------------------------------------------------------------
if python3 -c "import numpy; exit(0 if int(numpy.__version__.split('.')[0]) >= 2 else 1)" 2>/dev/null; then
    echo "Downgrading user-local numpy to <2 for matplotlib compatibility..."
    pip3 install --user --break-system-packages 'numpy<2' 2>/dev/null || true
fi

echo ""
echo "All ORB-SLAM3 system dependencies installed successfully."
