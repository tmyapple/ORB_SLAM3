# ORB-SLAM3 Docker Environment

Reproducible Docker environment for running ORB-SLAM3 with EuRoC datasets, including evaluation, visualization, and timing profiling.

## Quick Start

If the container `tamirt_orbslam3` is already running:

```bash
# Enter the container
docker exec -it tamirt_orbslam3 /bin/bash --login

# Run stereo SLAM with evaluation on MH_01_easy
bash ~/workspace/ORB_SLAM3/docker/run_euroc.sh --mode stereo --seq MH_01_easy --evaluate
```

## Full Setup From Scratch

### Step 1: Create the Container

```bash
# From the host machine
docker run -d \
  --name tamirt_orbslam3 \
  --env CUDA_VISIBLE_DEVICES=2,3 \
  --gpus all \
  -v /local:/local \
  -v /data:/data \
  -v /fastdata:/fastdata \
  -v /genai:/genai \
  -v /home/tamirt/.ssh:/home/tamirt/.ssh \
  -v /home/tamirt/.local:/home/tamirt/.local \
  -v /home/tamirt/.claude:/home/tamirt/.claude \
  -v /home/tamirt/.cache:/home/tamirt/.cache \
  -v /work/users/tamirt/workspace:/home/tamirt/workspace \
  -v /data/data/sdk_files:/home/tamirt/sdk_files \
  --user tamirt \
  sdk:dev_ub24 \
  sleep infinity
```

### Step 2: Install System Dependencies

```bash
docker exec tamirt_orbslam3 bash ~/workspace/ORB_SLAM3/docker/install_deps.sh
```

This installs: Eigen3, Boost serialization, OpenSSL, GLEW, OpenCV, EGL/Mesa, Xvfb, numpy, matplotlib, bc, and more.

### Step 3: Build ORB-SLAM3

```bash
docker exec tamirt_orbslam3 bash ~/workspace/ORB_SLAM3/docker/build_orbslam3.sh
```

Builds (all idempotent — skips if already done):
1. Pangolin v0.8 (from `~/workspace/Pangolin/`)
2. Thirdparty/DBoW2
3. Thirdparty/g2o
4. Thirdparty/Sophus (with GCC 13 -Werror fix)
5. ORB vocabulary extraction
6. ORB-SLAM3 main library + all executables

Uses `-j4` to be conservative on shared machines. Takes ~10-15 minutes on first run.

### Step 4: Download EuRoC Dataset

**Option A — From ETH Research Collection (recommended):**

Download from host (the original robotics.ethz.ch is blocked from this network):

```bash
# Machine Hall sequences (~12.7GB)
wget -L "https://www.research-collection.ethz.ch/bitstreams/7b2419c1-62b5-4714-b7f8-485e5fe3e5fe/download" \
  -O ~/workspace/datasets/EuRoC/machine_hall.zip

# Extract all MH sequences
cd ~/workspace/datasets/EuRoC
for seq in MH_01_easy MH_02_easy MH_03_medium MH_04_difficult MH_05_difficult; do
  unzip -o machine_hall.zip "machine_hall/${seq}/${seq}.zip"
  mkdir -p ${seq}
  unzip -o machine_hall/${seq}/${seq}.zip -d ${seq}/
done
```

**Option B — Using the download script (if robotics.ethz.ch is reachable):**

```bash
docker exec tamirt_orbslam3 bash ~/workspace/ORB_SLAM3/docker/download_euroc.sh MH_01_easy
# Or download all 11 sequences:
docker exec tamirt_orbslam3 bash ~/workspace/ORB_SLAM3/docker/download_euroc.sh
```

**Optional — Calibration data and paper:**

```bash
wget -L "https://www.research-collection.ethz.ch/bitstreams/5732e864-10f1-49e7-befb-669ee29ff770/download" \
  -O ~/workspace/datasets/EuRoC/calibration.zip
wget -L "https://www.research-collection.ethz.ch/bitstreams/d861e63b-cfa9-4411-85a5-5ad6b3526e44/download" \
  -O ~/workspace/datasets/EuRoC/euroc_paper.pdf
```

### Step 5: Validate Environment

```bash
docker exec tamirt_orbslam3 bash ~/workspace/ORB_SLAM3/docker/validate_env.sh
```

Expected: 27/27 PASS.

### Step 6: Run SLAM

```bash
docker exec tamirt_orbslam3 bash ~/workspace/ORB_SLAM3/docker/run_euroc.sh \
  --mode stereo --seq MH_01_easy --evaluate
```

## Entering the Container for Interactive Work

```bash
# Interactive shell
docker exec -it tamirt_orbslam3 /bin/bash --login

# Once inside, you can run directly:
cd ~/workspace/ORB_SLAM3

# Run with the wrapper script
bash docker/run_euroc.sh --mode mono --seq MH_01_easy --evaluate

# Or run executables directly
./Examples/Stereo/stereo_euroc \
  Vocabulary/ORBvoc.txt \
  Examples/Stereo/EuRoC.yaml \
  ~/workspace/datasets/EuRoC/MH_01_easy \
  Examples/Stereo/EuRoC_TimeStamps/MH01.txt \
  my_output_name

# Evaluate manually
python3 evaluation/evaluate_ate_scale.py \
  evaluation/Ground_truth/EuRoC_left_cam/MH01_GT.txt \
  f_my_output_name.txt \
  --verbose --plot my_plot.pdf

# Rebuild after code changes
cd build && make -j4
```

## Running SLAM — Detailed Usage

### run_euroc.sh Options

```
--mode <mode>       mono | stereo | mono_inertial | stereo_inertial
--seq <sequence>    MH_01_easy | MH_02_easy | MH_03_medium | MH_04_difficult | MH_05_difficult
                    (also V1_01_easy..V1_03_difficult, V2_01_easy..V2_03_difficult if downloaded)
--evaluate          Run ATE evaluation against ground truth, generate PDF plot
--no-viewer         Force headless mode even if DISPLAY is available
```

### Available SLAM Modes

| Mode | Executable | Sensors | Viewer | Notes |
|------|-----------|---------|--------|-------|
| `mono` | mono_euroc | Left camera only | OFF | Scale ambiguity, may drift |
| `stereo` | stereo_euroc | Left + right cameras | ON (xvfb) | Best accuracy |
| `mono_inertial` | mono_inertial_euroc | Left camera + IMU | ON (xvfb) | Needs IMU initialization time |
| `stereo_inertial` | stereo_inertial_euroc | Left + right + IMU | OFF | Best overall (scale + IMU) |

### Output Structure

Each run creates a timestamped directory:

```
results/<mode>/<seq>/<YYYYMMDD_HHMMSS>/
  slam_output.log       # Full console output
  f_<seq>.txt           # Frame trajectory (TUM format: timestamp tx ty tz qx qy qz qw)
  kf_<seq>.txt          # Keyframe trajectory
  timing_profile.txt    # Wall time, per-frame ms, FPS
  ate_results.txt       # ATE metrics (if --evaluate)
  ate_plot.pdf          # Trajectory plot (if --evaluate)
```

### Expected Results — Stereo Mode (All MH Sequences)

Verified on 2026-03-23 using `run_euroc.sh --mode stereo --evaluate --no-viewer`:

| Sequence | ATE RMSE (m) | ATE Mean (m) | ATE Median (m) | Keyframes | Pose Pairs | Wall Time (s) | FPS |
|----------|-------------|-------------|----------------|-----------|------------|---------------|-----|
| MH_01_easy | 0.042 | 0.037 | 0.035 | 150 | 3638 | — | — |
| MH_02_easy | 0.030 | 0.026 | 0.022 | 148 | 2999 | 198.7 | 15.3 |
| MH_03_medium | 0.042 | 0.035 | 0.034 | 181 | 2631 | — | — |
| MH_04_difficult | 0.074 | 0.066 | 0.058 | 268 | 1976 | 133.8 | 15.2 |
| MH_05_difficult | 0.094 | 0.089 | 0.082 | 287 | 2221 | 148.4 | 15.3 |

**Notes:**
- Easy sequences (MH_01, MH_02) achieve ~3-4cm RMSE, matching published results
- Difficult sequences (MH_04, MH_05) show higher error due to fast motion and texture-poor areas
- MH_05 triggers loop closure detection
- Consistent ~15 FPS across all sequences (65ms/frame average)
- Segfault on Pangolin viewer teardown in headless mode is a known ORB-SLAM3 issue — does not affect results

### Expected Results — Other Modes on MH_01_easy

| Mode | ATE RMSE (m) | Keyframes | Wall Time (s) | FPS | Notes |
|------|-------------|-----------|---------------|-----|-------|
| mono | ~3.5 | 333 | — | — | Scale ambiguity causes large drift |
| stereo | 0.042 | 150 | — | — | Best accuracy for visual-only |
| mono_inertial | varies | 295 | — | — | Multiple IMU init resets expected |
| stereo_inertial | 0.069 | 131 | 212.9 | 17.3 | Scale-aware, ~58ms/frame |

### Run Full Test Suite

To run all sequences and modes, use the test script:

```bash
docker exec tamirt_orbslam3 bash ~/workspace/ORB_SLAM3/docker/run_full_test.sh
```

Or run selectively:

```bash
# Single sequence, single mode
docker exec tamirt_orbslam3 bash ~/workspace/ORB_SLAM3/docker/run_full_test.sh --seq MH_01_easy --mode stereo

# All sequences, single mode
docker exec tamirt_orbslam3 bash ~/workspace/ORB_SLAM3/docker/run_full_test.sh --mode stereo

# All sequences, all modes (takes ~1 hour)
docker exec tamirt_orbslam3 bash ~/workspace/ORB_SLAM3/docker/run_full_test.sh --all-modes
```

## Dataset Layout

```
~/workspace/datasets/EuRoC/
  MH_01_easy/
    mav0/
      cam0/          # Left camera (grayscale, 752x480, 20Hz)
        data/        # PNG images named by timestamp
        data.csv     # timestamp,filename
        sensor.yaml  # Camera intrinsics + extrinsics
      cam1/          # Right camera (same format)
      imu0/          # IMU (accelerometer + gyroscope, 200Hz)
        data.csv     # timestamp,wx,wy,wz,ax,ay,az
        sensor.yaml  # IMU noise parameters
      leica0/        # Laser tracker ground truth (not used by SLAM)
      state_groundtruth_estimate0/
        data.csv     # Full state ground truth
      body.yaml      # Body frame definition
```

## Visualization

Three options for viewing the SLAM viewer output (3D map, trajectory, features):

### Option 1: Real-time X11 Viewer

Requires SSH with X forwarding (`ssh -X`) or a local display.

```bash
# On host, allow X access to Docker
xhost +local:docker

# Run with display forwarded into container
docker exec -e DISPLAY=$DISPLAY tamirt_orbslam3 \
  bash ~/workspace/ORB_SLAM3/docker/run_euroc.sh --mode stereo --seq MH_01_easy
```

Shows real-time: 3D point cloud map, camera trajectory, current frame with ORB features.

### Option 2: Record Viewer to Video (headless)

Records the Pangolin viewer to an MP4 file using Xvfb + ffmpeg. No display needed.

```bash
# Inside container or via docker exec
bash ~/workspace/ORB_SLAM3/docker/run_euroc.sh --mode stereo --seq MH_01_easy --record --evaluate

# Output includes:
#   results/stereo/MH_01_easy/<timestamp>/slam_viewer.mp4   (H.264, 1280x720, ~100MB)
```

**Notes:**
- Only works with modes that have a viewer: `stereo`, `mono_inertial`
- Modes without viewer (`mono`, `stereo_inertial`) print a warning and skip recording
- Video can be copied to your local machine: `scp user@host:~/workspace/ORB_SLAM3/results/.../slam_viewer.mp4 .`

### Option 3: Static Trajectory Plots

PDF plots comparing estimated vs ground truth trajectory. Generated automatically with `--evaluate`.

```bash
# Generated during SLAM run with --evaluate:
#   results/<mode>/<seq>/<timestamp>/ate_plot.pdf

# Re-plot existing results without re-running SLAM:
bash ~/workspace/ORB_SLAM3/docker/plot_trajectory.sh --results results/stereo/MH_01_easy/<timestamp>

# Or specify files manually:
bash ~/workspace/ORB_SLAM3/docker/plot_trajectory.sh \
  --traj results/stereo/MH_01_easy/<timestamp>/f_MH_01_easy.txt \
  --gt evaluation/Ground_truth/EuRoC_left_cam/MH01_GT.txt \
  --output my_plot.pdf
```

### Viewer Behavior by Mode

| Mode | Viewer | Headless handling | `--record` |
|------|--------|-------------------|------------|
| `mono` | OFF (hardcoded) | N/A | Not supported |
| `stereo` | ON (hardcoded) | auto xvfb | Supported |
| `mono_inertial` | ON (hardcoded) | auto xvfb | Supported |
| `stereo_inertial` | OFF (hardcoded) | N/A | Not supported |

## Timing Profiling

The `run_euroc.sh` script automatically captures:
- **Wall time**: Total SLAM execution time
- **Per-frame average**: Wall time / number of output frames
- **Effective FPS**: Frames / wall time

Results saved in `timing_profile.txt`. Example:

```
=== ORB-SLAM3 Timing Profile ===
Mode:          stereo_inertial
Sequence:      MH_01_easy
Wall time:     212.94s
Frames output: 3678
Avg per frame: 57.89ms
Effective FPS: 17.27
```

For more detailed per-component profiling (tracking, local mapping, loop closing), the timing vectors are computed in the example source files but not currently exported. You can add timing output by modifying the example `.cc` files (look for `vTimesTrack` vectors).

## Troubleshooting

### SLAM hangs with no output
- Check that the timestamp file exists: `ls Examples/<type>/EuRoC_TimeStamps/MH01.txt`
- A missing timestamp file causes an infinite loop in the example binary

### Viewer crashes
- Ensure `xvfb` is installed: `which xvfb-run`
- Use `--no-viewer` flag to force headless

### matplotlib import error
- NumPy version conflict: run `pip3 install --user --break-system-packages 'numpy<2'`

### Build fails with C++ errors
- Ensure CMakeLists.txt uses `-std=c++14` (not c++11)
- Ensure Sophus `-Werror` is removed

### Cannot download from robotics.ethz.ch
- Use ETH Research Collection mirror (see Step 4 above)

## GPU Configuration

The container is configured with `CUDA_VISIBLE_DEVICES=2,3`. To change:

```bash
# When creating the container
docker run -d --env CUDA_VISIBLE_DEVICES=0,1 ...

# Or at runtime
docker exec -e CUDA_VISIBLE_DEVICES=0,1 tamirt_orbslam3 <command>
```

Note: ORB-SLAM3 is primarily CPU-based. GPU is used by OpenCV/CUDA operations if available, but is not required.
