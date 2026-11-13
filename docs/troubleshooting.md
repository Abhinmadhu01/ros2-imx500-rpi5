# Troubleshooting & Frequently Asked Questions (FAQ)

Common issues, diagnostic solutions, and failure modes when working with the Sony IMX500, Raspberry Pi 5, and containerized ROS 2.

---

### 1. `OSError: [Errno 12] Cannot allocate memory`

- **Symptom**: `picamera2` crashes immediately during buffer configuration or preview startup.
- **Root Cause**: By default, `picamera2` searches for `/dev/dma_heap/vidbuf_cached`. If this node is missing, it falls back to `/dev/dma_heap/linux,cma`. The default kernel CMA (Contiguous Memory Allocator) pool is only **64 MB**, which is instantly exhausted by multi-frame 12 MP camera buffers.
- **Solution**: Handled automatically on startup by [`entrypoint.sh`](../entrypoint.sh), which creates a symlink from the unlimited system heap:
  ```bash
  ln -sf system /dev/dma_heap/vidbuf_cached
  ```
  If running manual `docker run` commands without `entrypoint.sh`, execute this symlink command as root inside the container before launching `picamera2`.

---

### 2. `no cameras available` When Running `camera_ros`

- **Symptom**: `ros2 run camera_ros camera_node` throws a runtime exception reporting `no cameras available`.
- **Root Cause**: The standard Ubuntu apt package `ros-humble-camera-ros` bundles a statically linked older release of `libcamera.so.0.1.0`. That outdated release lacks the Raspberry Pi PiSP (Raspberry Pi Image Signal Processor) pipeline handler and cannot interface with Pi 5 hardware.
- **Solution**: Use [`imx500_publisher.py`](../scripts/imx500_publisher.py) or `picamera2` directly. The container includes a custom source-built Raspberry Pi fork of `libcamera v0.7.2+rpt` with full PiSP and IMX500 sensor support.

---

### 3. First-Run 20–30 Second Delay on New `.rpk` Models

- **Symptom**: When loading a new neural network model, the application hangs for 20 to 30 seconds before video starts.
- **Root Cause**: The camera module features an on-board RP2040 microcontroller. When a new model is introduced, the RP2040 flashes the neural weights into the camera board's onboard non-volatile SPI flash memory.
- **Solution**: Expected factory behavior. Once the model is flashed to the camera's hardware memory, all subsequent launches load in **under 1 second**.

---

### 4. `Failed to open media device: Operation not permitted`

- **Symptom**: Libcamera logs `Operation not permitted` when attempting to open `/dev/media0` or `/dev/media1`.
- **Root Cause**: Linux kernels dynamically assign character device major numbers. If your Docker cgroup rule specifies `c 235:* rmw` but your current kernel assigned `media` to major `510`, access is denied by cgroups.
- **Solution**: Always launch using [`run.sh`](../run.sh). The script dynamically queries `/proc/devices` at startup to grant the exact assigned major number. Alternatively, check your host major numbers:
  ```bash
  grep -E " (media|video4linux|dma_heap)$" /proc/devices
  ```

---

### 5. Camera Not Detected on Boot (`rpicam-hello` Reports No Cameras)

- **Symptom**: `rpicam-hello --list-cameras` reports `No cameras available`.
- **Root Cause**: Physical ribbon cable seated incorrectly or auto-detect disabled.
- **Troubleshooting Steps**:
  1. Verify `/boot/firmware/config.txt` contains:
     ```ini
     camera_auto_detect=1
     ```
  2. Inspect the 22-to-15 pin ribbon cable:
     - On the Pi 5 CSI port (CAM0), silver contact pins must face **inward towards the USB ports**.
     - Ensure the plastic retaining collar is pushed down flush on both sides.
  3. Run [`scripts/doctor.sh`](../scripts/doctor.sh) to diagnose host hardware detection.

---

### 6. Display / GUI Errors (`Cannot connect to X server`)

- **Symptom**: GUI tools like `rqt_image_view` or RViz fail with `Cannot connect to X server :0`.
- **Solution**:
  1. Allow local container connections on the host:
     ```bash
     xhost +local:root
     ```
  2. Pass the display environment variable and X11 Unix socket into Docker:
     ```bash
     ./run.sh -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix:rw -- rqt_image_view
     ```

---

### 7. Pi 5 Undervoltage Throttling (`0x50000`) or Spontaneous Reboots

- **Symptom**: Kernel reports undervoltage in `dmesg`, USB devices disconnect, or the Pi reboots under load.
- **Root Cause**: Power supply voltage sagging below 4.75 V under the combined load of the 2.4 GHz Cortex-A76 cores, Active Cooler fan, and IMX500 camera.
- **Solution**:
  - For bench testing, use the **Raspberry Pi Official 27 W USB-C Power Supply** (5.1 V / 5.0 A).
  - For vehicle integration, power the Pi 5 from a dedicated **5 V / 5 A High-Efficiency Buck BEC** directly connected to the main battery. Never power from the flight controller's 5V telemetry port.

---

### 8. ROS 2 Topics Not Visible Across Network / Ground Station

- **Symptom**: Nodes publish successfully inside the container, but Ground Control Station (GCS) or external PCs cannot see `/camera/image_raw` or `/detections`.
- **Root Cause**: Docker bridge networking blocks UDP multicast packets required by FastDDS / CycloneDDS discovery.
- **Solution**: Ensure `--network host` is passed to `docker run` (handled automatically by `run.sh` and `docker-compose.yml`). Additionally, ensure all machines share the same `ROS_DOMAIN_ID`:
  ```bash
  export ROS_DOMAIN_ID=0
  ```

---

<div align="center">

| [Previous: **08 - Verified Benchmarks & Telemetry**](performance.md) | [**Documentation Roadmap**](../README.md#documentation-roadmap) | [Next: **10 - Known Limitations & Gotchas**](known-issues.md) |
| :--- | :---: | ---: |

</div>
