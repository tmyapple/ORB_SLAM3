#!/usr/bin/env bash
# setup_all.sh — One-script full environment setup for ORB-SLAM3.
# Run from the HOST machine. Creates container, installs deps, builds, validates.
#
# Usage:
#   bash ~/workspace/ORB_SLAM3/docker/setup_all.sh                                    # full setup (defaults)
#   bash ~/workspace/ORB_SLAM3/docker/setup_all.sh --name my_container --gpus 0,1     # custom name + GPUs
#   bash ~/workspace/ORB_SLAM3/docker/setup_all.sh --no-data                          # skip dataset extraction
#   bash ~/workspace/ORB_SLAM3/docker/setup_all.sh --dry-run                          # print steps only

set -euo pipefail

# ============================================================
# Configuration
# ============================================================
CONTAINER_NAME="tamirt_orbslam3"
IMAGE="sdk:dev_ub24"
USER_NAME="tamirt"
HOME_DIR="/home/${USER_NAME}"
WORKSPACE="/work/users/${USER_NAME}/workspace"
DATASET_DIR="${WORKSPACE}/datasets/EuRoC"
ORBSLAM_DIR="${WORKSPACE}/ORB_SLAM3"
DOCKER_DIR="${ORBSLAM_DIR}/docker"
GPUS="2"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

step()  { echo -e "\n${BOLD}${CYAN}=== Step $1: $2 ===${NC}"; }
ok()    { echo -e "${GREEN}[DONE]${NC} $*"; }
skip()  { echo -e "${YELLOW}[SKIP]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }

# Parse args
SKIP_DATA=false
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --name)     CONTAINER_NAME="$2"; shift 2 ;;
        --gpus)     GPUS="$2"; shift 2 ;;
        --no-data)  SKIP_DATA=true; shift ;;
        --dry-run)  DRY_RUN=true; shift ;;
        *)          echo "Unknown option: $1"; echo "Usage: $0 [--name <container_name>] [--gpus <gpu_ids>] [--no-data] [--dry-run]"; exit 1 ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    echo -e "${BOLD}=== ORB-SLAM3 Setup (dry run) ===${NC}"
    echo "1. Create container: ${CONTAINER_NAME} from ${IMAGE}"
    echo "2. Install system deps: docker exec ${CONTAINER_NAME} bash ${DOCKER_DIR}/install_deps.sh"
    echo "3. Build ORB-SLAM3:    docker exec ${CONTAINER_NAME} bash ${DOCKER_DIR}/build_orbslam3.sh"
    echo "4. Extract datasets:   Extract MH sequences from machine_hall.zip"
    echo "5. Validate:           docker exec ${CONTAINER_NAME} bash ${DOCKER_DIR}/validate_env.sh"
    echo "6. Smoke test:         docker exec ${CONTAINER_NAME} bash ${DOCKER_DIR}/run_euroc.sh --mode stereo --seq MH_01_easy --evaluate"
    exit 0
fi

echo -e "${BOLD}======================================${NC}"
echo -e "${BOLD}  ORB-SLAM3 Full Environment Setup${NC}"
echo -e "${BOLD}======================================${NC}"
echo "Container:  ${CONTAINER_NAME}"
echo "Image:      ${IMAGE}"
echo "GPUs:       ${GPUS}"
echo "Workspace:  ${WORKSPACE}"
echo ""

# ============================================================
# Step 1: Create Container
# ============================================================
step 1 "Create Docker Container"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        skip "Container '${CONTAINER_NAME}' already running"
    else
        info "Container exists but stopped — starting it"
        docker start "${CONTAINER_NAME}"
        ok "Container started"
    fi
else
    info "Creating container '${CONTAINER_NAME}'..."
    docker run -d \
        --name "${CONTAINER_NAME}" \
        --env CUDA_VISIBLE_DEVICES="${GPUS}" \
        --gpus all \
        -v /local:/local \
        -v /data:/data \
        -v /fastdata:/fastdata \
        -v /genai:/genai \
        -v "${HOME_DIR}/.ssh:${HOME_DIR}/.ssh" \
        -v "${HOME_DIR}/.local:${HOME_DIR}/.local" \
        -v "${HOME_DIR}/.claude:${HOME_DIR}/.claude" \
        -v "${HOME_DIR}/.cache:${HOME_DIR}/.cache" \
        -v "${WORKSPACE}:${HOME_DIR}/workspace" \
        -v /data/data/sdk_files:${HOME_DIR}/sdk_files \
        --user "${USER_NAME}" \
        "${IMAGE}" \
        sleep infinity
    ok "Container created"
fi

# Wait for container to be ready
sleep 2
docker exec "${CONTAINER_NAME}" echo "Container ready" >/dev/null 2>&1 || fail "Container not responding"

# ============================================================
# Step 2: Install System Dependencies
# ============================================================
step 2 "Install System Dependencies"

# Check if deps are already installed (quick check for a late-stage package)
if docker exec "${CONTAINER_NAME}" dpkg -l libeigen3-dev >/dev/null 2>&1 && \
   docker exec "${CONTAINER_NAME}" dpkg -l libglew-dev >/dev/null 2>&1 && \
   docker exec "${CONTAINER_NAME}" dpkg -l bc >/dev/null 2>&1; then
    skip "System dependencies already installed"
else
    info "Installing system dependencies..."
    docker exec "${CONTAINER_NAME}" bash "${HOME_DIR}/workspace/ORB_SLAM3/docker/install_deps.sh"
    ok "Dependencies installed"
fi

# ============================================================
# Step 3: Build ORB-SLAM3
# ============================================================
step 3 "Build ORB-SLAM3"

# Always run build script — it's idempotent (skips already-built steps)
# but ensures Pangolin is installed in THIS container (/usr/local is per-container)
info "Running build script (idempotent — installs Pangolin + skips already-built steps)..."
docker exec "${CONTAINER_NAME}" bash "${HOME_DIR}/workspace/ORB_SLAM3/docker/build_orbslam3.sh"
ok "Build script complete"

# ============================================================
# Step 4: Extract EuRoC Dataset
# ============================================================
step 4 "Prepare EuRoC Dataset"

if [ "$SKIP_DATA" = true ]; then
    skip "Dataset extraction skipped (--no-data)"
else
    MACHINE_HALL_ZIP="${DATASET_DIR}/machine_hall.zip"

    # Check if MH_01_easy is already extracted
    if [ -d "${DATASET_DIR}/MH_01_easy/mav0" ]; then
        skip "MH_01_easy already extracted"
    elif [ -f "${MACHINE_HALL_ZIP}" ]; then
        info "Extracting Machine Hall sequences from machine_hall.zip..."
        for seq in MH_01_easy MH_02_easy MH_03_medium MH_04_difficult MH_05_difficult; do
            if [ -d "${DATASET_DIR}/${seq}/mav0" ]; then
                skip "${seq} already extracted"
            else
                info "Extracting ${seq}..."
                cd "${DATASET_DIR}"
                unzip -o machine_hall.zip "machine_hall/${seq}/${seq}.zip" -d . >/dev/null 2>&1
                mkdir -p "${seq}"
                unzip -o "machine_hall/${seq}/${seq}.zip" -d "${seq}/" >/dev/null 2>&1
                ok "${seq}"
            fi
        done
        # Cleanup intermediate extraction
        rm -rf "${DATASET_DIR}/machine_hall"
        ok "All MH sequences extracted"
    else
        echo -e "${YELLOW}[WARN]${NC} machine_hall.zip not found at ${MACHINE_HALL_ZIP}"
        echo "       Download it first:"
        echo "       wget -L 'https://www.research-collection.ethz.ch/bitstreams/7b2419c1-62b5-4714-b7f8-485e5fe3e5fe/download' \\"
        echo "         -O ${MACHINE_HALL_ZIP}"
    fi
fi

# ============================================================
# Step 5: Validate Environment
# ============================================================
step 5 "Validate Environment"

info "Running 27-check validation..."
if docker exec "${CONTAINER_NAME}" bash "${HOME_DIR}/workspace/ORB_SLAM3/docker/validate_env.sh"; then
    ok "All validation checks passed"
else
    echo -e "${YELLOW}[WARN]${NC} Some validation checks failed (see above)"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${BOLD}${GREEN}======================================${NC}"
echo -e "${BOLD}${GREEN}  Setup Complete!${NC}"
echo -e "${BOLD}${GREEN}======================================${NC}"
echo ""
echo "Enter the container:"
echo "  docker exec -it ${CONTAINER_NAME} /bin/bash --login"
echo ""
echo "Run SLAM:"
echo "  bash ~/workspace/ORB_SLAM3/docker/run_euroc.sh --mode stereo --seq MH_01_easy --evaluate"
echo ""
echo "Available modes: mono, stereo, mono_inertial, stereo_inertial"
echo "Available sequences: MH_01_easy, MH_02_easy, MH_03_medium, MH_04_difficult, MH_05_difficult"
echo ""
