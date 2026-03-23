#!/usr/bin/env bash
# run_full_test.sh — Run ORB-SLAM3 on EuRoC sequences with evaluation and timing.
# Runs inside the container.
#
# Usage:
#   bash docker/run_full_test.sh                                    # stereo on all MH sequences
#   bash docker/run_full_test.sh --mode mono --seq MH_01_easy       # single mode + sequence
#   bash docker/run_full_test.sh --mode stereo                      # stereo on all MH sequences
#   bash docker/run_full_test.sh --all-modes                        # all 4 modes on all MH sequences
#   bash docker/run_full_test.sh --all-modes --seq MH_01_easy       # all 4 modes on one sequence

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLAM_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Defaults
MODE=""
SEQ=""
ALL_MODES=false

ALL_SEQUENCES=(MH_01_easy MH_02_easy MH_03_medium MH_04_difficult MH_05_difficult)
ALL_MODE_LIST=(stereo mono stereo_inertial mono_inertial)

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)       MODE="$2"; shift 2 ;;
        --seq)        SEQ="$2"; shift 2 ;;
        --all-modes)  ALL_MODES=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--mode <mode>] [--seq <sequence>] [--all-modes]"
            echo ""
            echo "Options:"
            echo "  --mode <mode>    mono, stereo, mono_inertial, stereo_inertial (default: stereo)"
            echo "  --seq <seq>      Specific sequence (default: all MH sequences)"
            echo "  --all-modes      Run all 4 modes (overrides --mode)"
            echo ""
            echo "Examples:"
            echo "  $0                                    # stereo on all MH"
            echo "  $0 --mode mono --seq MH_01_easy       # mono on MH_01"
            echo "  $0 --all-modes --seq MH_01_easy       # all modes on MH_01"
            echo "  $0 --all-modes                        # all modes on all MH (~1 hour)"
            exit 0
            ;;
        *)  echo "Unknown option: $1. Use --help for usage."; exit 1 ;;
    esac
done

# Determine modes to run
if [ "$ALL_MODES" = true ]; then
    MODES=("${ALL_MODE_LIST[@]}")
elif [ -n "$MODE" ]; then
    MODES=("$MODE")
else
    MODES=("stereo")
fi

# Determine sequences to run
if [ -n "$SEQ" ]; then
    SEQUENCES=("$SEQ")
else
    SEQUENCES=("${ALL_SEQUENCES[@]}")
fi

# Results tracking
TOTAL=0
PASSED=0
FAILED=0
declare -a RESULTS_TABLE=()

echo -e "${BOLD}=====================================================${NC}"
echo -e "${BOLD}  ORB-SLAM3 Full Test Suite${NC}"
echo -e "${BOLD}=====================================================${NC}"
echo "Modes:     ${MODES[*]}"
echo "Sequences: ${SEQUENCES[*]}"
echo "Total runs: $((${#MODES[@]} * ${#SEQUENCES[@]}))"
echo "Started:   $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BOLD}=====================================================${NC}"
echo ""

for mode in "${MODES[@]}"; do
    for seq in "${SEQUENCES[@]}"; do
        TOTAL=$((TOTAL + 1))
        echo -e "${CYAN}[${TOTAL}] Running: ${mode} / ${seq}${NC}"

        # Run SLAM
        RUN_OUTPUT=$("${SCRIPT_DIR}/run_euroc.sh" \
            --mode "$mode" \
            --seq "$seq" \
            --evaluate \
            --no-viewer 2>&1) || true

        # Extract results
        RMSE=$(echo "$RUN_OUTPUT" | grep "absolute_translational_error.rmse" | awk '{print $2}' || echo "N/A")
        MEAN=$(echo "$RUN_OUTPUT" | grep "absolute_translational_error.mean" | awk '{print $2}' || echo "N/A")
        PAIRS=$(echo "$RUN_OUTPUT" | grep "compared_pose_pairs" | awk '{print $2}' || echo "N/A")
        WALL_TIME=$(echo "$RUN_OUTPUT" | grep "^Wall time:" | awk '{print $3}' | tr -d 's' || echo "N/A")
        FPS=$(echo "$RUN_OUTPUT" | grep "^Effective FPS:" | awk '{print $3}' || echo "N/A")

        # Check result dir
        RESULT_DIR=$(echo "$RUN_OUTPUT" | grep "Run complete. Results at:" | awk '{print $NF}' || echo "")

        if [ -n "$RMSE" ] && [ "$RMSE" != "N/A" ]; then
            echo -e "  ${GREEN}[PASS]${NC} RMSE=${RMSE}m  mean=${MEAN}m  pairs=${PAIRS}  wall=${WALL_TIME}s  fps=${FPS}"
            PASSED=$((PASSED + 1))
            STATUS="PASS"
        elif [ -n "$RESULT_DIR" ] && [ -f "${RESULT_DIR}/f_${seq}.txt" ]; then
            echo -e "  ${YELLOW}[WARN]${NC} Trajectory produced but evaluation failed"
            PASSED=$((PASSED + 1))
            STATUS="WARN"
            RMSE="N/A"
        else
            echo -e "  ${RED}[FAIL]${NC} No trajectory output"
            FAILED=$((FAILED + 1))
            STATUS="FAIL"
            RMSE="N/A"
        fi

        RESULTS_TABLE+=("| ${mode} | ${seq} | ${STATUS} | ${RMSE:-N/A} | ${MEAN:-N/A} | ${PAIRS:-N/A} | ${WALL_TIME:-N/A} | ${FPS:-N/A} |")
    done
done

# Summary
echo ""
echo -e "${BOLD}=====================================================${NC}"
echo -e "${BOLD}  Test Results Summary${NC}"
echo -e "${BOLD}=====================================================${NC}"
echo "Finished:  $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "| Mode | Sequence | Status | RMSE (m) | Mean (m) | Pairs | Wall Time (s) | FPS |"
echo "|------|----------|--------|----------|----------|-------|---------------|-----|"
for row in "${RESULTS_TABLE[@]}"; do
    echo "$row"
done
echo ""
echo -e "  ${GREEN}PASSED${NC}: ${PASSED}"
echo -e "  ${RED}FAILED${NC}: ${FAILED}"
echo -e "  TOTAL:  ${TOTAL}"

# Save results to file
RESULTS_FILE="${SLAM_DIR}/results/test_results_$(date +%Y%m%d_%H%M%S).txt"
mkdir -p "${SLAM_DIR}/results"
{
    echo "ORB-SLAM3 Full Test Results"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Modes: ${MODES[*]}"
    echo "Sequences: ${SEQUENCES[*]}"
    echo ""
    echo "| Mode | Sequence | Status | RMSE (m) | Mean (m) | Pairs | Wall Time (s) | FPS |"
    echo "|------|----------|--------|----------|----------|-------|---------------|-----|"
    for row in "${RESULTS_TABLE[@]}"; do
        echo "$row"
    done
    echo ""
    echo "PASSED: ${PASSED}"
    echo "FAILED: ${FAILED}"
    echo "TOTAL:  ${TOTAL}"
} > "$RESULTS_FILE"
echo ""
echo "Results saved to: $RESULTS_FILE"

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}${FAILED} test(s) failed.${NC}"
    exit 1
fi
