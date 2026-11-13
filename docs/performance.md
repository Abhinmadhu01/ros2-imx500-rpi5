# Verified Benchmarks & Telemetry

Empirical performance benchmarks and hardware telemetry collected on the Raspberry Pi 5 Model B paired with the Sony IMX500 AI Camera running containerized ROS 2 Humble.

---

## 1. Test Environment Specifications

| Parameter | Specification |
| :--- | :--- |
| **Compute Board** | Raspberry Pi 5 Model B Rev 1.1 (8 GB RAM) |
| **Processor** | Broadcom BCM2712 quad-core ARM Cortex-A76 @ 2.4 GHz |
| **Vision Sensor** | Sony IMX500 AI Camera (12.3 MP, on-chip neural accelerator) |
| **Cooling Solution** | Raspberry Pi Active Cooler (PWM temperature-regulated) |
| **Host Operating System** | Raspberry Pi OS (Debian 13 Trixie 64-bit, Kernel `6.6.31+rpt-rpi-2712`) |
| **Container Environment** | Ubuntu 22.04 LTS (Jammy Jellyfish) · ROS 2 Humble Hawksbill |

---

## 2. Core Benchmark Results

| Performance Metric | SSD MobileNetV2 FPN-Lite | Ultralytics YOLO11n Base | Analysis & Notes |
| :--- | :--- | :--- | :--- |
| **Raw Video Stream Rate** | **30.0 FPS** | **30.0 FPS** | Continuous 640x480 RGB/BGR capture |
| **On-Chip Neural Inference** | **15.0 FPS** | **7.5 FPS** | 100% computed inside IMX500 hardware DSP |
| **Inference Hardware Cadence** | 1 every 2 video frames | 1 every 4 video frames | Clock-synchronized hardware timing |
| **Input Tensor Dimension** | 320 x 320 | 640 x 640 | Hardware cropped & scaled on sensor |
| **Sensor-to-ROS Latency** | **~24 ms** | **~38 ms** | Pipeline exposure to ROS message transmission |
| **Pi 5 CPU Utilization** | **~25% (single core)** | **~25% (single core)** | **~6% of total 4-core CPU** (zero inference load) |
| **SoC Operating Temperature** | **54.2 °C** | **56.8 °C** | Stabilized by Active Cooler |
| **System Power Consumption** | **5.4 W** | **5.8 W** | Entire board + active cooler + camera |

---

## 3. Live ROS 2 Topic Telemetry

Verification of live topic publishing rates using `ros2 topic hz`:

| Camera Raw Stream (`/camera/image_raw`) | Detection Topic (`/detections`) |
| :---: | :---: |
| ![Camera video stream 30 Hz](images/topic_hz.png) | ![Detection inference rate 7.5 Hz](images/detection_topic_hz.png) |
| *Continuous camera capture locked at exactly 30.0 Hz with zero dropped frames* | *Detection topic publishing at 30.0 Hz via anti-flicker cache with fresh 7.5 Hz on-chip inference* |

---

## 4. Why On-Chip Inference Matters for Autonomous UAVs

In traditional edge vision architectures (e.g., OpenCV DNN, TFLite, or PyTorch CPU on the companion computer):
- Running a 640x640 YOLO model consumes **350–400% CPU** (saturating all 4 cores).
- The CPU throttles thermally, increasing companion computer latency.
- Crucial robotics processes—such as MAVROS state estimation, visual-inertial odometry (VIO), EKF sensor fusion, and trajectory generation—suffer severe latency spikes or deadline misses.

### With the Sony IMX500 Silicon Accelerator:
- **Zero Host CPU Usage for Neural Math**: The host CPU never computes a single matrix multiplication.
- **Over 94% Total CPU Capacity Reserved**: Available for high-rate flight control, path planning, obstacle avoidance, and communication links.
- **Predictable Cadence**: Hardware-timed neural execution eliminates unpredictable software latency jitter.

---

<div align="center">

| [⬅️ Previous: **07 - RPK Model Conversion & Zoo**](model-conversion.md) | [📖 **Documentation Roadmap**](../README.md#documentation-roadmap) | [➡️ Next: **09 - Troubleshooting & FAQ**](troubleshooting.md) |
| :--- | :---: | ---: |

</div>

