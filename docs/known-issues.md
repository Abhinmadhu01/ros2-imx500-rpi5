# Known Limitations & Technical Gotchas

A detailed technical summary of architectural constraints, hardware prerequisites, and kernel gotchas when working with the Sony IMX500 on the Raspberry Pi 5 platform.

---

## 1. Hardware Exclusivity to Raspberry Pi 5

| Platform | Supported? | Technical Reason |
| :--- | :---: | :--- |
| **Raspberry Pi 5 Model B** | **YES** | Features the Broadcom BCM2712 SoC and RP1 Southbridge with hardware **PiSP** (Raspberry Pi Image Signal Processor) pipeline support. |
| **Raspberry Pi 4 Model B** | **NO** | Relies on the legacy VideoCore VI ISP (`bcm2835-unicam` / `vc4`), which lacks support for the IMX500 tensor metadata stream and PiSP pipeline handler. |
| **Compute Module 4 (CM4)** | **NO** | Legacy Broadcom VideoCore architecture cannot route the IMX500 CSI-2 dual data stream. |
| **Raspberry Pi 3 / Zero 2W** | **NO** | Insufficient RAM, outdated kernel pipeline, and lacks PiSP silicon. |

> [!IMPORTANT]
> The `ros2-imx500-rpi5` repository is specifically engineered for the **Raspberry Pi 5**. Attempting to run this container on a Pi 4 will result in device binding failures and missing media controllers.

---

## 2. Host Operating System Constraints

- **Raspberry Pi OS Host Is Mandatory**: The host operating system must run Raspberry Pi OS (Debian 12 Bookworm or 13 Trixie 64-bit). The downstream Raspberry Pi kernel contains proprietary driver modules (`imx500.ko` and `pisp_be.ko`) not present in generic Linux distributions.
- **Why Ubuntu Host Fails**: Canonical's official Ubuntu Server for Raspberry Pi does not package the `imx500-all` firmware blobs or downstream PiSP media controller patches. Attempting to run on bare-metal Ubuntu results in unmapped CSI devices.
- **The Container Architecture Solution**: By running Raspberry Pi OS on the bare metal host and containerizing Ubuntu 22.04 + ROS 2 Humble in Docker, you get the best of both worlds: complete hardware driver support from the host and full ROS 2 Humble package compatibility in user-space.

---

## 3. Kernel CMA Memory Exhaustion

- **The Limitation**: The Linux kernel's default Contiguous Memory Allocator (`linux,cma`) pool on Raspberry Pi OS is allocated only **64 MB**.
- **The Failure Mode**: High-resolution 12 MP camera captures or multi-buffer queues in `picamera2` exhaust 64 MB almost immediately, causing `OSError: [Errno 12] Cannot allocate memory`.
- **The Mitigation**: Handled automatically by [`entrypoint.sh`](../entrypoint.sh) via symlinking `/dev/dma_heap/vidbuf_cached` to `/dev/dma_heap/system`. If running standalone without the entrypoint, you must create this symlink manually.

---

## 4. Container Storage Footprint

The Docker images range from lightweight to full-featured:

| Build Target | Disk Footprint | Download Size | Optimization Guidance |
| :--- | :--- | :--- | :--- |
| **`base`** | **2.33 GB** | **558 MB** | Minimal footprint for single-purpose perception publishers. |
| **`uav`** | **2.70 GB** | **637 MB** | Optimized companion computer flight image (includes MAVROS and GStreamer). |
| **`full`** | **~6.1 GB** | **~1.38 GB** | Contains PyTorch (CPU), Ultralytics, and build toolchains. Use an SD card or NVMe SSD of at least 32 GB. |

> [!TIP]
> For production flight deployments where SD card space is limited, deploy the **`uav`** or **`base`** target. Only deploy **`full`** on test benches where local PyTorch development and YOLO training are required.

---

## 5. CSI Port Selection & Ribbon Cable Pinout

The Raspberry Pi 5 features two dual-purpose MIPI CSI/DSI ports:
- **Port 0 (`CAM/DISP0`)**: Positioned closest to the power button and USB-C port. This is the primary camera port enumerated as `/dev/video0` and `/dev/media0`.
- **Port 1 (`CAM/DISP1`)**: Positioned between the micro-HDMI ports.
- **Ribbon Pinout Gotcha**: The 22-to-15 pin ribbon cable is asymmetric:
  - On the Pi 5 motherboard, the silver conductive pins **must face inward towards the board center**.
  - On the IMX500 camera board, the conductive pins **must face toward the circuit board**.
  - Inserting the ribbon upside down will not damage hardware (ground pins protect the bus), but the sensor will fail to initialize.

---

<div align="center">

| [Previous: **09 - Troubleshooting & FAQ**](troubleshooting.md) | [**Documentation Roadmap**](../README.md#documentation-roadmap) | [Next: **Master Overview**](../README.md) |
| :--- | :---: | ---: |

</div>

