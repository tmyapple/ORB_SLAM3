#!/bin/bash
# Downloads EuRoC MAV dataset sequences.
# Usage:
#   bash download_euroc.sh              # all 11 sequences
#   bash download_euroc.sh MH_01_easy   # specific sequence

set -e

DEST_DIR="$HOME/workspace/datasets/EuRoC"
BASE_URL="http://robotics.ethz.ch/~asl-datasets/ijrr_euroc_mav_dataset"

ALL_SEQUENCES=(
    MH_01_easy
    MH_02_easy
    MH_03_medium
    MH_04_difficult
    MH_05_difficult
    V1_01_easy
    V1_02_medium
    V1_03_difficult
    V2_01_easy
    V2_02_medium
    V2_03_difficult
)

# If a specific sequence is requested, use only that one
if [ -n "$1" ]; then
    SEQUENCES=("$1")
else
    SEQUENCES=("${ALL_SEQUENCES[@]}")
fi

mkdir -p "$DEST_DIR"

for seq in "${SEQUENCES[@]}"; do
    SEQ_DIR="$DEST_DIR/$seq"
    ZIP_FILE="$DEST_DIR/${seq}.zip"
    URL="${BASE_URL}/${seq}/${seq}.zip"

    # Skip if already extracted
    if [ -d "$SEQ_DIR/mav0" ]; then
        echo "[SKIP] $seq — already extracted at $SEQ_DIR/mav0"
        continue
    fi

    echo "[DOWNLOAD] $seq from $URL"
    wget -c -q --show-progress -O "$ZIP_FILE" "$URL"

    echo "[EXTRACT] $seq"
    mkdir -p "$SEQ_DIR"
    unzip -q -o "$ZIP_FILE" -d "$SEQ_DIR"

    # Verify extraction
    if [ -d "$SEQ_DIR/mav0" ]; then
        echo "[CLEANUP] Removing $ZIP_FILE"
        rm -f "$ZIP_FILE"
        echo "[DONE] $seq"
    else
        echo "[WARN] $seq — mav0/ directory not found after extraction, keeping zip"
    fi
done

echo "All requested sequences processed. Dataset location: $DEST_DIR"
