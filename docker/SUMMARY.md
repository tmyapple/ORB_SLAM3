# ORB-SLAM3 Docker Environment — Work Summary

## Date: 2026-03-23

## Objective

Create a reproducible Docker environment for ORB-SLAM3 that supports building, running SLAM on EuRoC datasets, ATE evaluation with plots, headless visualization, and timing profiling.

## What Was Done

### 1. Docker Environment Setup
- Created container `tamirt_orbslam3` from `sdk:dev_ub24` image
- Configured with GPU access (devices 2,3), workspace mounts, user tamirt
- Installed all system dependencies via `install_deps.sh`

### 2. Build Pipeline (`build_orbslam3.sh`)
- Built Pangolin v0.8 from source (installed to /usr/local)
- Built Thirdparty libraries: DBoW2, g2o, Sophus
- Extracted ORB vocabulary
- Built ORB-SLAM3 (libORB_SLAM3.so + all example executables)
- All idempotent — safe to re-run

### 3. Build Fixes
| Issue | Fix |
|-------|-----|
| Pangolin v0.8 requires C++14 (`signal.hpp`) | Changed CMakeLists.txt from `-std=c++11` to `-std=c++14` |
| Sophus `-Werror` fails with GCC 13 | Removed `-Werror` via sed + cmake flag |
| `libopencv-dev` missing from sdk:dev_ub24 | Added to install_deps.sh |
| NumPy 2.x breaks system matplotlib | Downgraded to numpy<2 in install_deps.sh |
| `bc` missing for timing calculations | Added to install_deps.sh |

### 4. Python Evaluation Scripts Fixed
- `evaluation/evaluate_ate_scale.py`: Python 2 `print` statements converted to `print()`, `dict.keys().sort()` changed to `sorted(dict.keys())`
- `evaluation/associate.py`: `dict.keys()` wrapped in `list()` for `.remove()` compatibility with Python 3

### 5. EuRoC Dataset Download
- Original server (`robotics.ethz.ch`) unreachable from this network
- Downloaded from ETH Research Collection mirrors instead
- All 5 Machine Hall sequences extracted (MH_01 through MH_05)
- Calibration data and dataset paper also downloaded

### 6. Run Script (`run_euroc.sh`)
- Supports 4 modes: mono, stereo, mono_inertial, stereo_inertial
- Automatic headless viewer via xvfb when no display
- ATE evaluation with `--evaluate` flag (metrics + PDF plot)
- Timing profiling: wall time, per-frame ms, effective FPS
- Timestamped output directories under `results/`

### 7. Environment Validation (`validate_env.sh`)
- 27 automated checks covering: system deps, build artifacts, data, Python scripts, GPU
- Color-coded PASS/FAIL/WARN output
- Final result: **27/27 PASS**

## Verified Results on MH_01_easy

| Mode | ATE RMSE | Keyframes | Wall Time | FPS | Evaluation | Viewer |
|------|----------|-----------|-----------|-----|------------|--------|
| mono | 3.49m | 333 | — | — | OK | N/A |
| stereo | **0.042m** | 150 | — | — | OK | xvfb OK |
| mono_inertial | — | 295 | — | — | OK | xvfb OK |
| stereo_inertial | 0.069m | 131 | 212.9s | 17.27 | OK | N/A |

Stereo ATE RMSE of 0.042m matches published results (~0.03-0.05m).

## Files Created

```
docker/
  install_deps.sh          # System package installation
  build_orbslam3.sh        # Full build pipeline
  download_euroc.sh        # EuRoC dataset downloader
  run_euroc.sh             # SLAM runner + evaluation + timing
  validate_env.sh          # 27-check environment validation
  setup_all.sh             # Quick-start reference
  SUMMARY.md               # This file
  orchestrator_plan.md     # Orchestrator agent plan
  docker_expert_plan.md    # Docker expert agent plan
  packages_expert_plan.md  # Packages expert agent plan
  data_engineer_plan.md    # Data engineer agent plan
  validation_engineer_plan.md  # Validation engineer agent plan
  qa_engineer_plan.md      # QA engineer agent plan
```

## Bugs Found and Fixed During Setup

1. **Infinite loop in mono_euroc.cc**: When timestamp file doesn't exist, `ifstream::eof()` returns false (fail state, not EOF), causing `while(!fTimes.eof())` to loop forever. Fix: corrected sequence name mapping in `run_euroc.sh` (MH1 -> MH01).

2. **Short name regex bug**: Original sed regex `s/^(MH|V[0-9])_0?([0-9]+)_.*/\1\2/` produced "MH1" instead of "MH01". Fixed to preserve two-digit format.

## Agent Coordination

Work was parallelized across 5 specialized agents:
- **Docker Expert**: Container creation, install_deps.sh, setup_all.sh
- **Packages Expert**: build_orbslam3.sh, executed build, fixed C++14 and OpenCV issues
- **Data Engineer**: download_euroc.sh, run_euroc.sh, dataset download
- **Validation Engineer**: validate_env.sh with 27 checks
- **QA Engineer**: Manual testing of all 4 SLAM modes
