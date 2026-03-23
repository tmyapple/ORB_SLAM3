#!/bin/bash
set -e

# ============================================================
# ORB-SLAM3 Full Build Script
# Runs as user tamirt inside the container. Idempotent.
# ============================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[DONE]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[SKIP]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

WORKSPACE=~/workspace
ORBSLAM3_DIR="${WORKSPACE}/ORB_SLAM3"
PANGOLIN_DIR="${WORKSPACE}/Pangolin"

# Track whether Pangolin was installed system-wide
PANGOLIN_INSTALLED_SYSTEM=false
PANGOLIN_PREFIX_PATH=""

# ============================================================
# Step 1: Build Pangolin v0.8
# ============================================================
info "Step 1/6: Pangolin v0.8"

if ls "${PANGOLIN_DIR}/build"/libpango_*.so >/dev/null 2>&1; then
    warn "Pangolin already built, skipping"
else
    if [ ! -d "${PANGOLIN_DIR}" ]; then
        info "Cloning Pangolin v0.8..."
        git clone --depth 1 --branch v0.8 https://github.com/stevenlovegrove/Pangolin.git "${PANGOLIN_DIR}"
    else
        warn "Pangolin source already exists"
    fi

    mkdir -p "${PANGOLIN_DIR}/build"
    cd "${PANGOLIN_DIR}/build"
    info "Configuring Pangolin..."
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTS=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_TOOLS=OFF

    info "Building Pangolin (make -j4)..."
    make -j4
    ok "Pangolin built"
fi

# Always ensure Pangolin is installed in this container
# (/usr/local is per-container, not shared via volume mount)
if ldconfig -p 2>/dev/null | grep -q libpango_core; then
    warn "Pangolin already installed in this container"
    PANGOLIN_INSTALLED_SYSTEM=true
else
    info "Installing Pangolin to /usr/local (per-container)..."
    if sudo make -C "${PANGOLIN_DIR}/build" install 2>/dev/null; then
        sudo ldconfig 2>/dev/null || true
        PANGOLIN_INSTALLED_SYSTEM=true
        ok "Pangolin installed system-wide"
    else
        warn "sudo install failed; registering build dir with ldconfig"
        PANGOLIN_PREFIX_PATH="${PANGOLIN_DIR}/build"
        echo "${PANGOLIN_DIR}/build" | sudo tee /etc/ld.so.conf.d/pangolin.conf >/dev/null 2>&1 || true
        sudo ldconfig 2>/dev/null || true
        ok "Pangolin registered via ldconfig"
    fi
fi

# ============================================================
# Step 2: Build Thirdparty/DBoW2
# ============================================================
info "Step 2/6: Thirdparty/DBoW2"

DBOW2_DIR="${ORBSLAM3_DIR}/Thirdparty/DBoW2"
DBOW2_LIB="${DBOW2_DIR}/lib/libDBoW2.so"

if [ -f "${DBOW2_LIB}" ]; then
    warn "DBoW2 already built, skipping"
else
    mkdir -p "${DBOW2_DIR}/build"
    cd "${DBOW2_DIR}/build"
    info "Configuring DBoW2..."
    cmake .. -DCMAKE_BUILD_TYPE=Release
    info "Building DBoW2 (make -j4)..."
    make -j4
    ok "DBoW2 built"
fi

# ============================================================
# Step 3: Build Thirdparty/g2o
# ============================================================
info "Step 3/6: Thirdparty/g2o"

G2O_DIR="${ORBSLAM3_DIR}/Thirdparty/g2o"
G2O_LIB="${G2O_DIR}/lib/libg2o.so"

if [ -f "${G2O_LIB}" ]; then
    warn "g2o already built, skipping"
else
    mkdir -p "${G2O_DIR}/build"
    cd "${G2O_DIR}/build"
    info "Configuring g2o..."
    cmake .. -DCMAKE_BUILD_TYPE=Release
    info "Building g2o (make -j4)..."
    make -j4
    ok "g2o built"
fi

# ============================================================
# Step 4: Build Thirdparty/Sophus
# ============================================================
info "Step 4/6: Thirdparty/Sophus"

SOPHUS_DIR="${ORBSLAM3_DIR}/Thirdparty/Sophus"
SOPHUS_BUILD="${SOPHUS_DIR}/build"
# Sophus is header-only but has a cmake build for config files
SOPHUS_ARTIFACT="${SOPHUS_BUILD}/SophusConfig.cmake"

if [ -f "${SOPHUS_ARTIFACT}" ]; then
    warn "Sophus already built, skipping"
else
    # Primary fix: strip -Werror via sed (persistent, safe for re-runs)
    if grep -q '\-Werror' "${SOPHUS_DIR}/CMakeLists.txt" 2>/dev/null; then
        info "Removing -Werror from Sophus CMakeLists.txt (GCC 13 compatibility)..."
        sed -i 's/-Werror//g' "${SOPHUS_DIR}/CMakeLists.txt"
    fi

    mkdir -p "${SOPHUS_BUILD}"
    cd "${SOPHUS_BUILD}"
    info "Configuring Sophus..."
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-Wno-error"
    info "Building Sophus (make -j4)..."
    make -j4
    ok "Sophus built"
fi

# ============================================================
# Step 5: Extract vocabulary
# ============================================================
info "Step 5/6: Extract ORB vocabulary"

VOCAB_DIR="${ORBSLAM3_DIR}/Vocabulary"

if [ -f "${VOCAB_DIR}/ORBvoc.txt" ]; then
    warn "ORBvoc.txt already extracted, skipping"
else
    if [ -f "${VOCAB_DIR}/ORBvoc.txt.tar.gz" ]; then
        info "Extracting ORBvoc.txt.tar.gz..."
        cd "${VOCAB_DIR}"
        tar -xf ORBvoc.txt.tar.gz
        ok "Vocabulary extracted"
    else
        fail "ORBvoc.txt.tar.gz not found in ${VOCAB_DIR}"
    fi
fi

# ============================================================
# Step 6: Build ORB-SLAM3
# ============================================================
info "Step 6/6: Build ORB-SLAM3"

ORBSLAM3_LIB="${ORBSLAM3_DIR}/lib/libORB_SLAM3.so"

# Fix C++14 requirement: Pangolin v0.8 signal.hpp needs C++14, ORB-SLAM3 defaults to C++11
if grep -q 'std=c++11' "${ORBSLAM3_DIR}/CMakeLists.txt" 2>/dev/null; then
    info "Upgrading C++ standard from C++11 to C++14 (required by Pangolin v0.8)..."
    sed -i 's/-std=c++11/-std=c++14/g' "${ORBSLAM3_DIR}/CMakeLists.txt"
fi

if [ -f "${ORBSLAM3_LIB}" ]; then
    warn "ORB-SLAM3 already built, skipping"
else
    mkdir -p "${ORBSLAM3_DIR}/build"
    cd "${ORBSLAM3_DIR}/build"

    CMAKE_ARGS="-DCMAKE_BUILD_TYPE=Release"
    if [ -n "${PANGOLIN_PREFIX_PATH}" ]; then
        CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_PREFIX_PATH=${PANGOLIN_PREFIX_PATH}"
        info "Using Pangolin from local build: ${PANGOLIN_PREFIX_PATH}"
    fi

    info "Configuring ORB-SLAM3..."
    cmake .. ${CMAKE_ARGS}
    info "Building ORB-SLAM3 (make -j4)..."
    make -j4
    ok "ORB-SLAM3 built"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ORB-SLAM3 build complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
if [ -f "${ORBSLAM3_LIB}" ]; then
    echo -e "  Library: ${ORBSLAM3_LIB}"
fi
echo -e "  Examples: ${ORBSLAM3_DIR}/Examples/"
echo ""
