#!/usr/bin/env bash
# ============================================================================
# ORB-SLAM3 Environment Validation Script
# Run inside the Docker container as user tamirt.
# Usage: bash ~/workspace/ORB_SLAM3/docker/validate_env.sh
# ============================================================================

set -o pipefail

# --- Colour helpers (no-op when stdout is not a terminal) ---
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN='' RED='' YELLOW='' CYAN='' BOLD='' NC=''
fi

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
CRITICAL_FAIL=0

# Base directory of the ORB_SLAM3 checkout
ORBSLAM_DIR="${ORBSLAM_DIR:-$HOME/workspace/ORB_SLAM3}"
DATASETS_DIR="${DATASETS_DIR:-$HOME/workspace/datasets}"

# --- Helper functions -------------------------------------------------------

pass() {
    echo -e "  [${GREEN}PASS${NC}] $1"
    ((PASS_COUNT++))
}

fail() {
    echo -e "  [${RED}FAIL${NC}] $1"
    ((FAIL_COUNT++))
    ((CRITICAL_FAIL++))
}

warn() {
    echo -e "  [${YELLOW}WARN${NC}] $1"
    ((WARN_COUNT++))
}

section() {
    echo ""
    echo -e "${BOLD}${CYAN}=== $1 ===${NC}"
}

# check_cmd <description> <command...>
#   Runs the command; PASS if exit-code 0, FAIL otherwise.
check_cmd() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

# check_cmd_warn <description> <command...>
#   Like check_cmd but issues WARN instead of FAIL.
check_cmd_warn() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        pass "$desc"
    else
        warn "$desc"
    fi
}

# check_file <description> <path>
check_file() {
    local desc="$1"; local path="$2"
    if [ -f "$path" ]; then
        pass "$desc"
    else
        fail "$desc  (missing: $path)"
    fi
}

# check_dir <description> <path>
check_dir() {
    local desc="$1"; local path="$2"
    if [ -d "$path" ]; then
        pass "$desc"
    else
        fail "$desc  (missing: $path)"
    fi
}

# check_executable <description> <path>
check_executable() {
    local desc="$1"; local path="$2"
    if [ -x "$path" ]; then
        pass "$desc"
    else
        fail "$desc  (missing or not executable: $path)"
    fi
}

# ============================================================================
#  CHECKS BEGIN
# ============================================================================

echo -e "${BOLD}ORB-SLAM3 Environment Validation${NC}"
echo "ORBSLAM_DIR = $ORBSLAM_DIR"
echo "DATASETS_DIR = $DATASETS_DIR"
echo "Date         = $(date '+%Y-%m-%d %H:%M:%S')"

# ---------- System Dependencies ---------------------------------------------
section "System Dependencies"

# Eigen3
if pkg-config --modversion eigen3 >/dev/null 2>&1; then
    ver=$(pkg-config --modversion eigen3)
    pass "Eigen3 installed (version $ver)"
else
    fail "Eigen3 not found via pkg-config"
fi

# Boost serialization
check_cmd "Boost serialization dev package" dpkg -l libboost-serialization-dev

# OpenSSL / libcrypto
check_cmd "OpenSSL / libssl-dev" dpkg -l libssl-dev

# GLEW
check_cmd "GLEW (libglew-dev)" dpkg -l libglew-dev

# OpenCV
if pkg-config --modversion opencv4 >/dev/null 2>&1; then
    ver=$(pkg-config --modversion opencv4)
    pass "OpenCV4 available (version $ver)"
else
    fail "OpenCV4 not found via pkg-config"
fi

# EGL / Mesa
check_cmd "EGL / Mesa (libegl1-mesa-dev)" dpkg -l libegl1-mesa-dev

# Xvfb
if command -v xvfb-run >/dev/null 2>&1; then
    pass "Xvfb installed (xvfb-run found)"
else
    warn "Xvfb not installed (xvfb-run not found) -- headless rendering may not work"
    # Downgrade from critical: viewer can be disabled
    ((CRITICAL_FAIL--))
fi

# Python3 numpy
check_cmd "Python3 numpy" python3 -c "import numpy"

# Python3 matplotlib
check_cmd "Python3 matplotlib" python3 -c "import matplotlib"

# ---------- Build Artifacts -------------------------------------------------
section "Build Artifacts"

# Pangolin
if ls "$HOME/workspace/Pangolin/build/libpango"*.so >/dev/null 2>&1 || \
   ls "$HOME/workspace/Pangolin/build/src/libpango"*.so >/dev/null 2>&1 || \
   ls /usr/local/lib/libpango*.so >/dev/null 2>&1; then
    pass "Pangolin built (shared lib found)"
else
    fail "Pangolin shared library not found in ~/workspace/Pangolin/build/ or /usr/local/lib/"
fi

# DBoW2
check_file "DBoW2 library" "$ORBSLAM_DIR/Thirdparty/DBoW2/lib/libDBoW2.so"

# g2o
check_file "g2o library" "$ORBSLAM_DIR/Thirdparty/g2o/lib/libg2o.so"

# Sophus config
check_file "Sophus configured (SophusConfig.cmake)" "$ORBSLAM_DIR/Thirdparty/Sophus/build/SophusConfig.cmake"

# ORB vocabulary
check_file "ORB vocabulary extracted" "$ORBSLAM_DIR/Vocabulary/ORBvoc.txt"

# Main library
check_file "libORB_SLAM3.so" "$ORBSLAM_DIR/lib/libORB_SLAM3.so"

# Executables
check_executable "mono_euroc executable" "$ORBSLAM_DIR/Examples/Monocular/mono_euroc"
check_executable "stereo_euroc executable" "$ORBSLAM_DIR/Examples/Stereo/stereo_euroc"
check_executable "mono_inertial_euroc executable" "$ORBSLAM_DIR/Examples/Monocular-Inertial/mono_inertial_euroc"
check_executable "stereo_inertial_euroc executable" "$ORBSLAM_DIR/Examples/Stereo-Inertial/stereo_inertial_euroc"

# ---------- Data ------------------------------------------------------------
section "Data"

check_dir "EuRoC dataset directory" "$DATASETS_DIR/EuRoC"

# MH_01_easy with mav0
MH01="$DATASETS_DIR/EuRoC/MH_01_easy"
if [ -d "$MH01/mav0" ]; then
    pass "MH_01_easy sequence with mav0/ subdirectory"
elif [ -d "$MH01" ]; then
    warn "MH_01_easy exists but mav0/ subdirectory missing"
else
    fail "MH_01_easy sequence missing"
fi

# Ground truth
check_file "Ground truth MH01_GT.txt" "$ORBSLAM_DIR/evaluation/Ground_truth/EuRoC_left_cam/MH01_GT.txt"

# Timestamp files
check_file "Monocular timestamp MH01.txt" "$ORBSLAM_DIR/Examples/Monocular/EuRoC_TimeStamps/MH01.txt"

# ---------- Python Evaluation Scripts ---------------------------------------
section "Python Evaluation Scripts"

if python3 -m py_compile "$ORBSLAM_DIR/evaluation/evaluate_ate_scale.py" 2>/dev/null; then
    pass "evaluate_ate_scale.py syntax OK"
else
    fail "evaluate_ate_scale.py syntax error"
fi

if python3 -m py_compile "$ORBSLAM_DIR/evaluation/associate.py" 2>/dev/null; then
    pass "associate.py syntax OK"
else
    fail "associate.py syntax error"
fi

# ---------- GPU Access ------------------------------------------------------
section "GPU Access"

if [ -n "$CUDA_VISIBLE_DEVICES" ]; then
    pass "CUDA_VISIBLE_DEVICES is set ($CUDA_VISIBLE_DEVICES)"
else
    warn "CUDA_VISIBLE_DEVICES is not set"
fi

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    pass "nvidia-smi runs successfully"
else
    warn "nvidia-smi not available or failed -- GPU rendering may not work"
fi

# ============================================================================
#  SUMMARY
# ============================================================================
section "Summary"

TOTAL=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
echo ""
echo -e "  ${GREEN}PASS${NC}: $PASS_COUNT"
echo -e "  ${RED}FAIL${NC}: $FAIL_COUNT"
echo -e "  ${YELLOW}WARN${NC}: $WARN_COUNT"
echo -e "  TOTAL: $TOTAL"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All critical checks passed.${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}$FAIL_COUNT critical check(s) failed.${NC}"
    exit 1
fi
