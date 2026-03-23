#!/usr/bin/env bash
# plot_trajectory.sh — Generate trajectory plot from existing SLAM results.
# Re-plots without re-running SLAM.
#
# Usage:
#   bash docker/plot_trajectory.sh --results results/stereo/MH_01_easy/20260323_125718
#   bash docker/plot_trajectory.sh --traj f_MH_01_easy.txt --gt evaluation/Ground_truth/EuRoC_left_cam/MH01_GT.txt --output my_plot.pdf

set -e

SLAM_DIR="$HOME/workspace/ORB_SLAM3"

# Defaults
RESULTS_DIR=""
TRAJ_FILE=""
GT_FILE=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --results)  RESULTS_DIR="$2"; shift 2 ;;
        --traj)     TRAJ_FILE="$2"; shift 2 ;;
        --gt)       GT_FILE="$2"; shift 2 ;;
        --output)   OUTPUT="$2"; shift 2 ;;
        -h|--help)
            echo "Usage:"
            echo "  $0 --results <results_dir>                    # re-plot from a run's output dir"
            echo "  $0 --traj <file> --gt <file> --output <file>  # plot specific files"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# If --results given, find the files automatically
if [ -n "$RESULTS_DIR" ]; then
    # Make path absolute if relative
    case "$RESULTS_DIR" in
        /*) ;;
        *) RESULTS_DIR="$SLAM_DIR/$RESULTS_DIR" ;;
    esac

    TRAJ_FILE=$(ls "$RESULTS_DIR"/f_*.txt 2>/dev/null | head -1)
    OUTPUT="${RESULTS_DIR}/ate_plot.pdf"

    # Detect sequence name from trajectory file
    SEQ_NAME=$(basename "$TRAJ_FILE" | sed 's/^f_//;s/\.txt$//')
    SHORT_NAME=$(echo "$SEQ_NAME" | sed -E 's/^(MH|V[0-9])_0*([0-9]+)_.*/\10\2/' | sed -E 's/0+([0-9]{2})/\1/')
    GT_FILE="$SLAM_DIR/evaluation/Ground_truth/EuRoC_left_cam/${SHORT_NAME}_GT.txt"
fi

# Validate
if [ -z "$TRAJ_FILE" ] || [ -z "$GT_FILE" ] || [ -z "$OUTPUT" ]; then
    echo "ERROR: Need --results <dir> or --traj, --gt, and --output"
    exit 1
fi

if [ ! -f "$TRAJ_FILE" ]; then
    echo "ERROR: Trajectory file not found: $TRAJ_FILE"
    exit 1
fi

if [ ! -f "$GT_FILE" ]; then
    echo "ERROR: Ground truth file not found: $GT_FILE"
    exit 1
fi

echo "Trajectory: $TRAJ_FILE"
echo "Ground truth: $GT_FILE"
echo "Output: $OUTPUT"
echo ""

cd "$SLAM_DIR"
python3 evaluation/evaluate_ate_scale.py \
    "$GT_FILE" \
    "$TRAJ_FILE" \
    --verbose \
    --plot "$OUTPUT"

echo ""
echo "Plot saved to: $OUTPUT"
