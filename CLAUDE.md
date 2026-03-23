# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Docker Environment

The primary development environment is a Docker container. **Always run as user tamirt** (never -u root). Use sudo inside if root is needed.

```bash
# Container name
tamirt_orbslam3

# Enter the running container
docker exec -it tamirt_orbslam3 /bin/bash --login

# Run a command inside
docker exec tamirt_orbslam3 <command>
```

**Resource constraints (shared machine):**
- Use `-j4` max for builds (NOT -j$(nproc))
- GPUs: ONLY GPU 2 and 3 (`CUDA_VISIBLE_DEVICES=2,3`)
- NEVER remove Docker containers — user manages lifecycle

**Docker scripts** are in `docker/`:
- `install_deps.sh` — system packages (uses sudo, idempotent)
- `build_orbslam3.sh` — full build pipeline (Pangolin, thirdparty, ORB-SLAM3)
- `download_euroc.sh` — EuRoC dataset download
- `run_euroc.sh` — SLAM execution + evaluation + timing profiling
- `validate_env.sh` — 27-check environment validation
- `setup_all.sh` — quick-start reference

## Build

### Inside Docker (recommended)
```bash
bash ~/workspace/ORB_SLAM3/docker/build_orbslam3.sh
```

This handles everything: Pangolin v0.8, DBoW2, g2o, Sophus, vocabulary extraction, and ORB-SLAM3. All idempotent.

### Rebuild only main library
```bash
cd ~/workspace/ORB_SLAM3/build && make -j4
```

### Key build fixes applied
- `CMakeLists.txt`: `-std=c++14` (was c++11, Pangolin v0.8 requires c++14)
- Sophus: `-Werror` removed (GCC 13 compatibility)
- `install_deps.sh`: includes `libopencv-dev`, `bc`, numpy<2 downgrade

## Running Examples

### Using run_euroc.sh (recommended)
```bash
# Monocular with evaluation
bash ~/workspace/ORB_SLAM3/docker/run_euroc.sh --mode mono --seq MH_01_easy --evaluate

# Stereo headless with evaluation
bash ~/workspace/ORB_SLAM3/docker/run_euroc.sh --mode stereo --seq MH_01_easy --evaluate --no-viewer

# Stereo with video recording of the viewer
bash ~/workspace/ORB_SLAM3/docker/run_euroc.sh --mode stereo --seq MH_01_easy --record --evaluate

# Mono-inertial
bash ~/workspace/ORB_SLAM3/docker/run_euroc.sh --mode mono_inertial --seq MH_01_easy --evaluate

# Stereo-inertial
bash ~/workspace/ORB_SLAM3/docker/run_euroc.sh --mode stereo_inertial --seq MH_01_easy --evaluate
```

**Modes:** `mono`, `stereo`, `mono_inertial`, `stereo_inertial`

**Available sequences:** MH_01_easy through MH_05_difficult (all extracted)

**Output** goes to `results/<mode>/<seq>/<timestamp>/` containing:
- `slam_output.log` — full SLAM console output
- `f_<seq>.txt` — frame trajectory (TUM format)
- `kf_<seq>.txt` — keyframe trajectory
- `ate_results.txt` — ATE metrics (with --evaluate)
- `slam_viewer.mp4` — recorded viewer video (with --record, modes with viewer only)
- `ate_plot.pdf` — trajectory plot (with --evaluate)
- `timing_profile.txt` — wall time, per-frame ms, FPS

### Direct execution
```bash
./Examples/<SensorType>/<executable> Vocabulary/ORBvoc.txt <settings.yaml> <dataset_path> <timestamp_file> <output_name>
```

### Viewer handling
| Mode | Viewer hardcoded | Headless |
|------|-----------------|----------|
| mono | false | N/A |
| stereo | true | xvfb-run -a |
| mono_inertial | true | xvfb-run -a |
| stereo_inertial | false | N/A |

When viewer is hardcoded ON but no `$DISPLAY`, `run_euroc.sh` auto-uses `xvfb-run`.

## Visualization

Three options for viewing SLAM output:

**Option 1 — Real-time X11 viewer** (requires `ssh -X` or local display):
```bash
xhost +local:docker
docker exec -e DISPLAY=$DISPLAY tamirt_orbslam3 \
  bash ~/workspace/ORB_SLAM3/docker/run_euroc.sh --mode stereo --seq MH_01_easy
```

**Option 2 — Record viewer to video** (headless, saves MP4):
```bash
bash ~/workspace/ORB_SLAM3/docker/run_euroc.sh --mode stereo --seq MH_01_easy --record --evaluate
# Output: results/stereo/MH_01_easy/<timestamp>/slam_viewer.mp4
```
Only works with modes that have a viewer (`stereo`, `mono_inertial`). Uses Xvfb + ffmpeg.

**Option 3 — Static trajectory plot** (PDF, always available with `--evaluate`):
```bash
# Generated automatically with --evaluate, or re-plot existing results:
bash ~/workspace/ORB_SLAM3/docker/plot_trajectory.sh --results results/stereo/MH_01_easy/<timestamp>
```

## Dataset Locations

```
~/workspace/datasets/EuRoC/
├── MH_01_easy/mav0/       # Machine Hall sequences (cam0, cam1, imu0, leica0, ground truth)
├── MH_02_easy/mav0/
├── MH_03_medium/mav0/
├── MH_04_difficult/mav0/
├── MH_05_difficult/mav0/
├── calibration.zip         # Calibration datasets (rosbag format)
├── machine_hall.zip        # Original download (can be deleted to save space)
└── euroc_paper.pdf         # Dataset paper
```

**Ground truth:** `evaluation/Ground_truth/EuRoC_left_cam/MH01_GT.txt` etc.
**Timestamps:** `Examples/<type>/EuRoC_TimeStamps/MH01.txt` etc.

**Download source:** ETH Research Collection (robotics.ethz.ch is blocked from this network):
- Machine Hall: `https://www.research-collection.ethz.ch/bitstreams/7b2419c1-62b5-4714-b7f8-485e5fe3e5fe/download`

## Evaluation

Python 3 evaluation scripts (fixed from original Python 2):
- `evaluation/evaluate_ate_scale.py` — ATE with scale alignment
- `evaluation/associate.py` — timestamp association

```bash
python3 evaluation/evaluate_ate_scale.py \
    evaluation/Ground_truth/EuRoC_left_cam/MH01_GT.txt \
    results/stereo/MH_01_easy/<timestamp>/f_MH_01_easy.txt \
    --verbose --plot output_plot.pdf
```

## Architecture

**Multi-threaded pipeline** with 4 concurrent threads:

1. **Tracking** (main thread, real-time) — ORB feature extraction, frame-to-frame matching, pose estimation. Entry point: `System::TrackMonocular/Stereo/RGBD()`.
2. **LocalMapping** (async thread) — Processes new keyframes, creates map points, runs local bundle adjustment, culls redundant keyframes.
3. **LoopClosing** (async thread) — DBoW2 place recognition, loop closure with pose graph optimization, multi-map merging via Atlas.
4. **Viewer** (async thread) — Pangolin-based OpenGL visualization.

**Key class relationships:**
- **System** orchestrates everything, owns Tracking/LocalMapping/LoopClosing/Viewer threads
- **Atlas** manages multiple sub-**Map** instances, enabling multi-session and map merging
- **Frame** → temporary per-image data; **KeyFrame** → persistent map anchors stored in Map
- **MapPoint** — 3D points observed by multiple KeyFrames (covisibility graph)
- **Optimizer** — all g2o-based optimization (local BA, global BA, pose graph, inertial BA)

**Camera models** (`include/CameraModels/`): `Pinhole` and `KannalaBrandt8` (fisheye), both inherit `GeometricCamera`.

**IMU pipeline** (`ImuTypes.h`): Preintegration between frames, bias estimation, gravity/scale initialization. Active when sensor type includes "Inertial".

**Serialization:** Boost-based save/load of entire Atlas via `System.SaveAtlasToFile` / `System.LoadAtlasFromFile` YAML settings.

## Key Source Files by Size/Complexity

- `src/Optimizer.cc` (~189KB) — All bundle adjustment variants, most complex file
- `src/Tracking.cc` (~135KB) — Main tracking state machine (NOT_INITIALIZED → OK → RECENTLY_LOST → LOST)
- `src/LoopClosing.cc` (~94KB) — Loop detection, map merging, essential graph optimization
- `src/LocalMapping.cc` (~50KB) — Keyframe processing, point creation, local BA

## Configuration (YAML)

Settings files define camera intrinsics, ORB extractor params, IMU calibration, and viewer config. Parsed by `Settings` class. Key parameters:
- `Camera.type`: "PinHole" or "KannalaBrandt8"
- `Camera1.fx/fy/cx/cy`: Intrinsics
- `ORBextractor.nFeatures/scaleFactor/nLevels`: Feature extraction tuning
- `IMU.*`: Noise, walk, frequency, camera-IMU transform (inertial modes only)

## Thirdparty

All in `Thirdparty/` — **modified** forks, not upstream:
- **DBoW2**: Bag-of-words for place recognition
- **g2o**: Graph optimization for bundle adjustment (custom vertex/edge types in `G2oTypes.h/cc`)
- **Sophus**: SE3/SO3/Sim3 Lie group operations (header-only)

External (built from source in `~/workspace/Pangolin/`):
- **Pangolin v0.8**: OpenGL visualization, installed to `/usr/local`
