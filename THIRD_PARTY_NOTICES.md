# Third Party Notices

This repository packages and integrates several open-source projects. Below are the licenses and notices for these third-party components:

---

### 1. libcamera (Raspberry Pi Fork)
- **Upstream**: https://github.com/raspberrypi/libcamera
- **License**: LGPL-2.1-or-later / GPL-2.0-or-later
- **Usage**: Built from source inside the container to provide Raspberry Pi 5 PiSP pipeline and Python bindings (`pycamera`).

### 2. ROS 2 (Robot Operating System)
- **Upstream**: Open Source Robotics Foundation (OSRF)
- **License**: Apache License 2.0
- **Packages**: `ros-humble-ros-core`, `ros-humble-mavros`, `ros-humble-cv-bridge`, `ros-humble-vision-msgs`, `ros-humble-apriltag-ros`, `ros-humble-image-transport`

### 3. picamera2
- **Upstream**: Raspberry Pi Ltd
- **License**: BSD 2-Clause License
- **Usage**: High-level camera interface and hardware abstraction layer for libcamera and IMX500.

### 4. OpenCV
- **Upstream**: OpenCV Foundation
- **License**: Apache License 2.0
- **Usage**: Computer vision and GUI display rendering (`cv2`).

### 5. ONNX Runtime
- **Upstream**: Microsoft Corporation
- **License**: MIT License

### 6. Notice Regarding YOLO Models & Weights (Ultralytics)
- If you use or export models derived from Ultralytics YOLO (e.g. YOLOv8, YOLO11), please be aware that Ultralytics software and model weights are licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.
- `.rpk` firmware files compiled from YOLO models inherit AGPL-3.0 obligations. Do not commit proprietary or commercial weights without reviewing the licensing terms.
- The base container image does not bundle pre-compiled `.rpk` neural network files to maintain license compliance.

