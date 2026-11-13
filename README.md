# 🎯 ros2-imx500-rpi5

**Run the Sony IMX500 AI Camera with ROS 2 Humble on Raspberry Pi 5 — Fully Containerized.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-linux%2Farm64-lightgrey.svg)]()
[![ROS2](https://img.shields.io/badge/ROS2-Humble-blue.svg)](https://docs.ros.org/en/humble/)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED.svg?logo=docker)](https://www.docker.com/)
[![GitHub Container Registry](https://img.shields.io/badge/GHCR-Images%20Available-green.svg)](https://github.com/Abhinmadhu01/ros2-imx500-rpi5/pkgs/container/ros2-imx500-rpi5)

> Source-builds the Raspberry Pi downstream fork of **libcamera v0.7.2+rpt** (with Python bindings) inside Ubuntu 22.04 LTS, providing full Sony IMX500 12.3 MP camera access, on-chip AI neural inference, and the entire ROS 2 robotics ecosystem — all in a single reproducible Docker container.

---

<p align="center">
  <img src="docs/images/hardware_rpi_camera_connected_rpi5_active_cooler.jpg" width="750" alt="Raspberry Pi 5 with Sony IMX500 AI Camera and Active Cooler" />
  <br>
  <em>Production hardware setup: Raspberry Pi 5 (8 GB) paired with the Sony IMX500 AI Camera and Raspberry Pi Active Cooler.</em>
</p>

---

## 📑 Table of Contents

- [What's Inside](#-whats-inside)
- [Why This Exists](#-why-this-exists)
- [Key Features](#-key-features)
- [System Architecture](#-system-architecture)
- [Hardware & Avionics](#-hardware--avionics)
- [Docker Image Targets](#-docker-image-targets)
- [Verified Performance](#-verified-performance)
- [Quick Start](#-quick-start)
- [Python Inference Example](#-python-inference-example)
- [📖 Documentation Roadmap](#-documentation-roadmap)
- [Contributing](#-contributing)
- [License](#-license)

---

## 📦 What's Inside

| Component | Version / Specification | Role in System Stack |
| :--- | :--- | :--- |
| **Container Base OS** | Ubuntu 22.04 LTS (Jammy Jellyfish) | Standard ROS 2 Humble target environment |
| **Robotics Middleware** | ROS 2 Humble Hawksbill | Inter-process messaging, node graph, parameter server |
| **Camera Framework** | `libcamera` v0.7.2+rpt20261009 (RPi fork) | Source-built with `rpi/pisp` hardware pipeline handler |
| **Python Camera Interface** | `picamera2` (Latest) | Pythonic camera control, metadata, and request loops |
| **Computer Vision** | OpenCV 4.5.4 (system apt with Qt5 GUI) | Image filtering, resizing, and coordinate transforms |
| **ROS 2 Vision Stack** | `cv_bridge`, `vision_msgs`, `camera_info_manager` | Standard ROS message conversions and calibrations |
| **UAV Flight Stack** | `mavros`, `mavros_extras`, `apriltag_ros` | MAVLink autopilot bridge and fiducial marker tracking |
| **Video Streaming** | GStreamer 1.20 (good, bad, ugly, libav) | Low-latency RTMP, RTSP, and UDP H.264 video pipelines |
| **Machine Learning Suite** | PyTorch (CPU aarch64), ONNX Runtime, Ultralytics | Available in `full` image target for host model workflows |

---

## 🧩 Why This Exists

The **Sony IMX500** is an intelligent 12.3 MP image sensor featuring an **integrated hardware neural network accelerator**. It connects to the Raspberry Pi 5 via a 4-lane MIPI CSI-2 bus and offloads tensor convolution, activation, and bounding box post-processing entirely from the Pi's CPU.

However, a fundamental operating system incompatibility exists:

```text
Raspberry Pi OS (Host)                 Ubuntu 22.04 (ROS 2 Target)
-------------------------              ----------------------------
✅ Proprietary IMX500 drivers (imx500.ko)  ❌ No downstream IMX500 kernel drivers
✅ Downstream PiSP pipeline handler        ❌ No PiSP media controller patches
✅ Firmware packages (imx500-all)          ❌ No official RPK firmware support
❌ Officially lacks ROS 2 Humble debians   ✅ Official target tier for ROS 2 Humble
```

**Before this project, running ROS 2 Humble with the IMX500 was effectively impossible.** Developers had to choose between camera hardware support (Pi OS) or robotics middleware (Ubuntu).

### The Solution:
- Runs **Raspberry Pi OS 64-bit** on the bare metal host to maintain physical hardware drivers, device nodes, and kernel firmware.
- Executes an **Ubuntu 22.04** container on top of the host kernel.
- **Source-builds** the Raspberry Pi fork of `libcamera` with PiSP and Python bindings inside Ubuntu.
- Dynamically bind-mounts `/dev`, `/run/udev`, and grants character cgroups via [`run.sh`](run.sh).
- **Result**: Native-rate 30 FPS IMX500 camera access + on-chip AI inference + ROS 2 Humble with **zero compromise**.

---

## ⚡ Key Features

- **Full IMX500 Hardware Acceleration**: 12.3 MP capture, INT8 on-chip neural inference, and sensor metadata readback.
- **Zero Host CPU Inference Load**: Frees 94% of the Raspberry Pi 5 CPU for MAVROS, SLAM, state estimation, and trajectory control.
- **Automated Dynamic Cgroup Detection**: [`run.sh`](run.sh) parses `/proc/devices` at launch to handle dynamic kernel major numbers across reboots.
- **DMA Heap Memory Fix**: [`entrypoint.sh`](entrypoint.sh) symlinks `/dev/dma_heap/vidbuf_cached` to system RAM, preventing kernel CMA pool exhaustion (`Errno 12`).
- **Production-Ready Publisher Node**: [`scripts/imx500_publisher.py`](scripts/imx500_publisher.py) provides multi-threaded 30 FPS camera publishing, `vision_msgs/Detection2DArray` outputs, and an anti-flicker caching mechanism.
- **Secure Non-Root User Architecture**: Container executes as user `ros` (UID 1000) with `video`, `dialout`, and `audio` permissions.
- **Docker Compose & Headless Support**: Designed for autonomous drone companion computers with auto-restart and daemonized operation.

---

## 🏗 System Architecture

```mermaid
flowchart TD
    subgraph HOST["Host — Raspberry Pi OS (Bookworm / Trixie 64-bit)"]
        KD["Kernel Drivers<br/><code>imx500.ko · pisp_be.ko</code>"]
        DEV["Device Character Nodes<br/><code>/dev/media* · /dev/video* · /dev/dma_heap/*</code>"]
        UDEV["Udev Database<br/><code>/run/udev</code>"]
        DT["Device Tree<br/><code>/sys/firmware/devicetree</code>"]
    end

    subgraph CONTAINER["Container — Ubuntu 22.04 LTS"]
        LC["libcamera (RPi fork v0.7.2+rpt)<br/><code>rpi/pisp</code> pipeline handler"]
        PC["picamera2 Python Driver"]
        ROS["ROS 2 Humble Middleware"]
        PUB["imx500_publisher.py Node"]

        LC --> PC
        PC --> PUB
        PUB --> TOPICS["ROS 2 Topics:<br/>• <code>/camera/image_raw</code> (30 Hz)<br/>• <code>/detections</code> (30 Hz)"]
    end

    KD --> DEV
    DEV -- "Dynamic bind mount via run.sh" --> LC
    UDEV -- "ro bind mount" --> LC
    DT -- "systempaths=unconfined" --> LC
```

---

## 🛠 Hardware & Avionics

| Component | Model | Purpose |
| :--- | :--- | :--- |
| **Companion Computer** | Raspberry Pi 5 Model B (8 GB recommended) | Executes Docker container, ROS 2 Humble, and avionics nodes |
| **AI Vision Sensor** | Sony IMX500 AI Camera (Raspberry Pi AI Camera) | High-speed 12.3 MP image sensor with on-chip neural accelerator |
| **Thermal Solution** | Raspberry Pi Active Cooler | Temperature-controlled PWM fan maintaining SoC below 58 °C |
| **Ribbon Cable** | 22-to-15 Pin Asymmetric FPC (200 mm / 500 mm) | Connects camera module to Pi 5 CSI port (**CAM0**) |
| **Power Converter** | 5 V / 5 A High-Efficiency Buck BEC | Clean, isolated power from 4S–6S flight battery preventing brownouts |
| **Flight Controller** | CubePilot Cube Orange+ (ArduCopter / PX4) | Autopilot companion connected via USB telemetry |

| Key Hardware Showcase | Complete Test Bench Interconnect |
| :---: | :---: |
| ![Pi 5 bare board and CSI ports](docs/images/hardware_rpi5_bare_board_ports_top.jpg) | ![Bench interconnect with CubePilot Orange+](docs/images/hardware_bench_interconnect_rpi5_cubepilot_imx500.jpg) |
| *Raspberry Pi 5 board layout showing dual 22-pin CSI ports* | *Full avionics harness connecting Pi 5, IMX500, and Cube Orange+* |

---

## 🏷 Docker Image Targets

The repository includes a multi-stage [`Dockerfile`](Dockerfile) supporting three specialized targets:

| Target | Tags | Contents & Capabilities | Disk Size | Download Size | Best For |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`base`** | `base`, `humble`, `latest` | ROS 2 Humble + source-built libcamera + Picamera2 + OpenCV + colcon + `cv_bridge` + `vision_msgs` | **2.33 GB** | **558 MB** | Lightweight vision nodes, embedded perception |
| **`uav`** | `uav` | Everything in `base` + `mavros`, `apriltag_ros`, GStreamer RTMP/HLS streaming, GUI tools | **2.70 GB** | **637 MB** | Autonomous drones, precision landing, flight avionics |
| **`full`** | `full` | Everything in `uav` + PyTorch CPU, Ultralytics YOLO, ONNX Runtime, MAVProxy, compilers | **~6.1 GB** | **~1.38 GB** | Development workstations, model evaluation |

### Pull Pre-Built Images from GHCR

```bash
docker pull ghcr.io/abhinmadhu01/ros2-imx500-rpi5:base
docker pull ghcr.io/abhinmadhu01/ros2-imx500-rpi5:uav
docker pull ghcr.io/abhinmadhu01/ros2-imx500-rpi5:full
```

---

## 📊 Verified Performance

Empirical hardware telemetry measured on Raspberry Pi 5 Model B Rev 1.1 running Debian 13 Trixie host and Ubuntu 22.04 container:

| Performance Metric | SSD MobileNetV2 FPN-Lite | Ultralytics YOLO11n Base | Analysis & Notes |
| :--- | :--- | :--- | :--- |
| **Raw Video Stream Rate** | **30.0 FPS** | **30.0 FPS** | Continuous 640x480 RGB/BGR capture |
| **On-Chip Neural Inference** | **15.0 FPS** | **7.5 FPS** | 100% computed inside IMX500 hardware DSP |
| **Inference Hardware Cadence** | 1 every 2 video frames | 1 every 4 video frames | Clock-synchronized hardware timing |
| **Input Tensor Dimension** | 320 x 320 | 640 x 640 | Hardware cropped & scaled on sensor |
| **Pi 5 CPU Utilization** | **~25% (single core)** | **~25% (single core)** | **~6% of total 4-core CPU** (zero inference load) |
| **SoC Operating Temperature** | **54.2 °C** | **56.8 °C** | Stabilized by Active Cooler |

| Camera Raw Stream (`/camera/image_raw`) | Detection Topic (`/detections`) |
| :---: | :---: |
| ![Camera video stream 30 Hz](docs/images/topic_hz.png) | ![Detection inference rate 7.5 Hz](docs/images/detection_topic_hz.png) |
| *Continuous camera capture locked at exactly 30.0 Hz with zero dropped frames* | *Detection topic publishing at 30.0 Hz via anti-flicker cache with fresh 7.5 Hz on-chip inference* |

---

## 🚀 Quick Start

### 1. Clone Repository & Run Environment Diagnostics

```bash
git clone https://github.com/Abhinmadhu01/ros2-imx500-rpi5.git
cd ros2-imx500-rpi5

# Run host diagnostics
./scripts/doctor.sh
```

### 2. Build or Pull the Docker Image

```bash
# Option A: Pull pre-built base image from GHCR
docker pull ghcr.io/abhinmadhu01/ros2-imx500-rpi5:base

# Option B: Build locally on the Pi 5
docker build --target base -t ros2-imx500-rpi5:base .
```

### 3. Launch with `run.sh`

```bash
# Launch interactive container shell
./run.sh bash
```

### 4. Verify Camera Inside the Container

```bash
# Check camera hardware recognition
cam -l

# Launch ROS 2 IMX500 publisher node
python3 scripts/imx500_publisher.py
```

---

## 🧪 Python Inference Example

```python
#!/usr/bin/env python3
"""
IMX500 On-Chip Inference Example with Picamera2
"""
import time
from picamera2 import Picamera2
from picamera2.devices.imx500 import IMX500, NetworkIntrinsics

MODEL = "/usr/share/imx500-models/imx500_network_ssd_mobilenetv2_fpnlite_320x320_pp.rpk"

imx500 = IMX500(MODEL)
intrinsics = imx500.network_intrinsics or NetworkIntrinsics()
intrinsics.task = "object detection"

picam2 = Picamera2(imx500.camera_num)
config = picam2.create_preview_configuration(
    controls={"FrameRate": intrinsics.inference_rate or 15},
    buffer_count=12,
)
picam2.configure(config)
picam2.start()

print("Capturing frames with on-chip hardware inference...")
try:
    for i in range(50):
        metadata = picam2.capture_metadata()
        outputs = imx500.get_outputs(metadata, add_batch=True)
        if outputs is not None:
            boxes, scores, classes = outputs[0][0], outputs[1][0], outputs[2][0]
            print(f"Frame {i:02d}: Detected {len(scores)} objects (Top score: {scores[0]:.2f})")
        time.sleep(0.033)
finally:
    picam2.stop()
```

---

## 📖 Documentation Roadmap

Explore the comprehensive step-by-step documentation modules:

| Step | Documentation Guide | Key Topics Covered |
| :---: | :--- | :--- |
| **01** | [**Host Setup Guide**](docs/host-setup.md) | Raspberry Pi OS, downstream kernel, `config.txt`, `imx500-all`, and `doctor.sh` diagnostics |
| **02** | [**Hardware & Avionics Setup**](docs/hardware.md) | Bill of Materials, CSI ribbon routing on CAM0, 5V/5A BEC power, and Active Cooler |
| **03** | [**Device Access & Dynamic Cgroups**](docs/devices.md) | Dynamic major numbers (`/proc/devices`), character cgroups, and DMA heap memory symlink |
| **04** | [**Multi-Stage Container Builds**](docs/building.md) | Docker targets (`base`, `uav`, `full`), BuildKit caching, compilation times, and GHCR images |
| **05** | [**Running Containers & Orchestration**](docs/running.md) | `run.sh` launcher, manual `docker run`, `docker-compose.yml`, non-root user, and X11 forwarding |
| **06** | [**IMX500 ROS 2 Publisher Node**](docs/publisher-node.md) | Multi-threaded node architecture, `/camera/image_raw`, `/detections`, and anti-flicker caching |
| **07** | [**RPK Model Conversion & Zoo**](docs/model-conversion.md) | Sony IMX500 NPU architecture, `.rpk` format, Ultralytics YOLO export, and certified model zoo |
| **08** | [**Verified Benchmarks & Telemetry**](docs/performance.md) | 30 FPS raw capture, 15 FPS / 7.5 FPS inference, 0% CPU offload, and thermal telemetry |
| **09** | [**Troubleshooting & FAQ**](docs/troubleshooting.md) | DMA heap `Errno 12`, `camera_ros` conflicts, 25s RP2040 flash delay, and permission fixes |
| **10** | [**Known Limitations & Gotchas**](docs/known-issues.md) | Pi 5 exclusivity (PiSP), Raspberry Pi OS host requirement, CMA pool, and storage sizes |

---

## 🤝 Contributing

Contributions are welcome! Please check the [Contributing Guidelines](CONTRIBUTING.md) and review the [Troubleshooting Guide](docs/troubleshooting.md) before submitting pull requests.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <em>Developed by Abhin M — Empowering autonomous robotics with on-sensor AI vision.</em>
</p>
