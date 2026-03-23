#!/bin/bash
# Runs ORB-SLAM3 on EuRoC sequences with optional ATE evaluation.
# Usage:
#   bash run_euroc.sh --mode mono --seq MH_01_easy --evaluate
#   bash run_euroc.sh --mode stereo --seq MH_01_easy --no-viewer
#   bash run_euroc.sh --mode mono_inertial --seq V1_01_easy --evaluate
#   bash run_euroc.sh --mode stereo --seq MH_01_easy --record --evaluate
#   bash run_euroc.sh --mode stereo_inertial --seq MH_03_medium

set -e

export CUDA_VISIBLE_DEVICES=2,3

SLAM_DIR="$HOME/workspace/ORB_SLAM3"
DATASET_DIR="$HOME/workspace/datasets/EuRoC"

# Defaults
MODE=""
SEQ=""
EVALUATE=false
NO_VIEWER=false
RECORD=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)      MODE="$2"; shift 2 ;;
        --seq)       SEQ="$2"; shift 2 ;;
        --evaluate)  EVALUATE=true; shift ;;
        --no-viewer) NO_VIEWER=true; shift ;;
        --record)    RECORD=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$MODE" ] || [ -z "$SEQ" ]; then
    echo "Usage: $0 --mode <mono|stereo|mono_inertial|stereo_inertial> --seq <sequence_name> [--evaluate] [--no-viewer] [--record]"
    exit 1
fi

# Map mode to executable, config, and viewer behavior
case $MODE in
    mono)
        EXECUTABLE="Examples/Monocular/mono_euroc"
        CONFIG="Examples/Monocular/EuRoC.yaml"
        TS_DIR="Examples/Monocular/EuRoC_TimeStamps"
        VIEWER_HARDCODED=false
        ;;
    stereo)
        EXECUTABLE="Examples/Stereo/stereo_euroc"
        CONFIG="Examples/Stereo/EuRoC.yaml"
        TS_DIR="Examples/Stereo/EuRoC_TimeStamps"
        VIEWER_HARDCODED=true
        ;;
    mono_inertial)
        EXECUTABLE="Examples/Monocular-Inertial/mono_inertial_euroc"
        CONFIG="Examples/Monocular-Inertial/EuRoC.yaml"
        TS_DIR="Examples/Monocular-Inertial/EuRoC_TimeStamps"
        VIEWER_HARDCODED=true
        ;;
    stereo_inertial)
        EXECUTABLE="Examples/Stereo-Inertial/stereo_inertial_euroc"
        CONFIG="Examples/Stereo-Inertial/EuRoC.yaml"
        TS_DIR="Examples/Stereo-Inertial/EuRoC_TimeStamps"
        VIEWER_HARDCODED=false
        ;;
    *)
        echo "Unknown mode: $MODE. Use: mono, stereo, mono_inertial, stereo_inertial"
        exit 1
        ;;
esac

# Convert sequence name to short name: MH_01_easy -> MH01, V1_02_medium -> V102
SHORT_NAME=$(echo "$SEQ" | sed -E 's/^(MH|V[0-9])_0*([0-9]+)_.*/\10\2/' | sed -E 's/0+([0-9]{2})/\1/')

DATASET_PATH="$DATASET_DIR/$SEQ"
TIMESTAMP_FILE="$TS_DIR/${SHORT_NAME}.txt"

# Verify paths
if [ ! -d "$DATASET_PATH" ]; then
    echo "ERROR: Dataset not found at $DATASET_PATH"
    echo "Run download_euroc.sh first."
    exit 1
fi

if [ ! -f "$SLAM_DIR/$EXECUTABLE" ]; then
    echo "ERROR: Executable not found at $SLAM_DIR/$EXECUTABLE"
    echo "Build ORB-SLAM3 first."
    exit 1
fi

# Create output directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$SLAM_DIR/results/$MODE/$SEQ/$TIMESTAMP"
mkdir -p "$OUTPUT_DIR"

OUTPUT_NAME="$SEQ"

# Determine display/viewer strategy
PREFIX=""
XVFB_PID=""
FFMPEG_PID=""
RECORD_FILE=""
MANAGED_XVFB=false
XVFB_DISPLAY=""

if [ "$RECORD" = true ] && [ "$VIEWER_HARDCODED" = false ]; then
    echo "[WARN] --record only works with modes that have a viewer (stereo, mono_inertial)."
    echo "       Mode '$MODE' has viewer disabled in source. Ignoring --record."
    RECORD=false
fi

if [ "$RECORD" = true ]; then
    # Recording: start our own Xvfb + ffmpeg
    XVFB_DISPLAY=":$((RANDOM % 100 + 50))"
    RECORD_FILE="$OUTPUT_DIR/slam_viewer.mp4"
    echo "[RECORD] Starting Xvfb on display $XVFB_DISPLAY..."
    Xvfb "$XVFB_DISPLAY" -screen 0 1280x720x24 &
    XVFB_PID=$!
    sleep 1
    export DISPLAY="$XVFB_DISPLAY"
    MANAGED_XVFB=true
    # No PREFIX needed — we set DISPLAY directly
elif [ "$VIEWER_HARDCODED" = true ]; then
    if [ "$NO_VIEWER" = true ] || [ -z "$DISPLAY" ]; then
        PREFIX="xvfb-run -a"
    fi
fi

echo "============================================"
echo "ORB-SLAM3 EuRoC Run"
echo "============================================"
echo "Mode:       $MODE"
echo "Sequence:   $SEQ ($SHORT_NAME)"
echo "Dataset:    $DATASET_PATH"
echo "Output:     $OUTPUT_DIR"
echo "Evaluate:   $EVALUATE"
echo "Record:     $RECORD"
echo "GPU:        CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
echo "============================================"

# Run SLAM with timing
cd "$SLAM_DIR"
echo "[RUN] Starting ORB-SLAM3..."

# Start ffmpeg recording if requested (after a brief delay for viewer to init)
if [ "$RECORD" = true ]; then
    (
        sleep 3  # wait for Pangolin viewer window to appear
        echo "[RECORD] Starting ffmpeg capture to $RECORD_FILE..."
        ffmpeg -y -video_size 1280x720 -framerate 10 \
            -f x11grab -i "$XVFB_DISPLAY" \
            -c:v libx264 -preset ultrafast -crf 23 \
            -pix_fmt yuv420p \
            "$RECORD_FILE" </dev/null >/dev/null 2>&1
    ) &
    FFMPEG_PID=$!
fi

SLAM_START=$(date +%s%N)

$PREFIX ./$EXECUTABLE \
    Vocabulary/ORBvoc.txt \
    "$CONFIG" \
    "$DATASET_PATH" \
    "$TIMESTAMP_FILE" \
    "$OUTPUT_NAME" \
    2>&1 | tee "$OUTPUT_DIR/slam_output.log"

SLAM_END=$(date +%s%N)
SLAM_ELAPSED_MS=$(( (SLAM_END - SLAM_START) / 1000000 ))
SLAM_ELAPSED_S=$(echo "scale=2; $SLAM_ELAPSED_MS / 1000" | bc)

echo "[RUN] ORB-SLAM3 finished."

# Stop recording if active
if [ -n "$FFMPEG_PID" ] && kill -0 "$FFMPEG_PID" 2>/dev/null; then
    sleep 1  # let ffmpeg flush
    kill "$FFMPEG_PID" 2>/dev/null || true
    wait "$FFMPEG_PID" 2>/dev/null || true
    echo "[RECORD] ffmpeg stopped"
fi
if [ "$MANAGED_XVFB" = true ] && [ -n "$XVFB_PID" ]; then
    kill "$XVFB_PID" 2>/dev/null || true
    wait "$XVFB_PID" 2>/dev/null || true
    echo "[RECORD] Xvfb stopped"
fi
if [ "$RECORD" = true ] && [ -f "$RECORD_FILE" ]; then
    RECORD_SIZE=$(du -h "$RECORD_FILE" | cut -f1)
    echo "[RECORD] Video saved: $RECORD_FILE ($RECORD_SIZE)"
fi

echo "[TIMING] Total SLAM wall time: ${SLAM_ELAPSED_S}s (${SLAM_ELAPSED_MS}ms)"

# Save timing profile
TIMING_FILE="$OUTPUT_DIR/timing_profile.txt"
{
    echo "=== ORB-SLAM3 Timing Profile ==="
    echo "Mode:          $MODE"
    echo "Sequence:      $SEQ"
    echo "Date:          $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Wall time:     ${SLAM_ELAPSED_S}s"
    echo "Wall time ms:  ${SLAM_ELAPSED_MS}"
    # Count frames from trajectory file
    NFRAMES=$(wc -l < "$SLAM_DIR/f_${OUTPUT_NAME}.txt" 2>/dev/null || echo "0")
    echo "Frames output: $NFRAMES"
    if [ "$NFRAMES" -gt 0 ] && [ "$SLAM_ELAPSED_MS" -gt 0 ]; then
        AVG_MS=$(echo "scale=2; $SLAM_ELAPSED_MS / $NFRAMES" | bc)
        FPS=$(echo "scale=2; $NFRAMES * 1000 / $SLAM_ELAPSED_MS" | bc)
        echo "Avg per frame: ${AVG_MS}ms"
        echo "Effective FPS: ${FPS}"
    fi
    echo "GPU:           CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
    echo "Host:          $(hostname)"
} | tee "$TIMING_FILE"
echo "[TIMING] Profile saved to $TIMING_FILE"

# Move output trajectory files to results directory
for f in f_${OUTPUT_NAME}.txt kf_${OUTPUT_NAME}.txt; do
    if [ -f "$SLAM_DIR/$f" ]; then
        mv "$SLAM_DIR/$f" "$OUTPUT_DIR/"
        echo "[OUTPUT] $f -> $OUTPUT_DIR/$f"
    fi
done

# Evaluation
if [ "$EVALUATE" = true ]; then
    TRAJ_FILE="$OUTPUT_DIR/f_${OUTPUT_NAME}.txt"
    GT_FILE="$SLAM_DIR/evaluation/Ground_truth/EuRoC_left_cam/${SHORT_NAME}_GT.txt"
    ATE_RESULTS="$OUTPUT_DIR/ate_results.txt"
    ATE_PLOT="$OUTPUT_DIR/ate_plot.pdf"

    if [ ! -f "$TRAJ_FILE" ]; then
        echo "[EVAL] WARNING: Trajectory file not found: $TRAJ_FILE"
        echo "Skipping evaluation."
    elif [ ! -f "$GT_FILE" ]; then
        echo "[EVAL] WARNING: Ground truth file not found: $GT_FILE"
        echo "Skipping evaluation."
    else
        echo "[EVAL] Running ATE evaluation..."
        python3 "$SLAM_DIR/evaluation/evaluate_ate_scale.py" \
            "$GT_FILE" \
            "$TRAJ_FILE" \
            --verbose \
            --plot "$ATE_PLOT" \
            2>&1 | tee "$ATE_RESULTS"
        echo "[EVAL] Results saved to $ATE_RESULTS"
        echo "[EVAL] Plot saved to $ATE_PLOT"
    fi
fi

echo "============================================"
echo "Run complete. Results at: $OUTPUT_DIR"
echo "============================================"
