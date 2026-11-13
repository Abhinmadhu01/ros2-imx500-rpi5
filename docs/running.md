# Running Containers & Orchestration

This guide covers running the `ros2-imx500-rpi5` container using the automated `run.sh` launcher, manual `docker run` commands, and Docker Compose orchestration.

---

## 1. Automated Execution via `run.sh` (Recommended)

The [`run.sh`](../run.sh) script handles all dynamic device major detection, cgroups, udev mapping, and non-root user permissions automatically.

### Interactive Bash Shell
```bash
# Launch interactive shell with default (base) image:
./run.sh

# Inside container:
ros@raspberrypi:~$ cam -l
```

### Run a Specific Command Directly
Use `--` to separate container runtime arguments from the container command:

```bash
# Run the environment probe:
./run.sh -- python3 examples/imx500_probe.py /usr/share/imx500-models/imx500_network_ssd_mobilenetv2_fpnlite_320x320_pp.rpk

# Launch the ROS 2 camera publisher:
./run.sh -- python3 scripts/imx500_publisher.py
```

### Specifying Image Target & Custom Mounts
```bash
# Use the UAV flight stack image:
IMAGE=ros2-imx500-rpi5:uav ./run.sh

# Mount a host folder containing custom models into the container:
./run.sh -v $HOME/custom_models:/models -- python3 scripts/imx500_publisher.py --ros-args -p model_path:=/models/yolo11n.rpk
```

---

## 2. Manual `docker run` Reference

If deploying through Kubernetes, Nomad, or automated CI/CD runners, use the standard `docker run` invocation:

```bash
docker run -it --rm \
    --name ros2-imx500 \
    \
    # ── Networking ──────────────────────────────────────────────
    --network host \                         # Required for ROS 2 DDS discovery
    \
    # ── Device Nodes & Udev ─────────────────────────────────────
    -v /dev:/dev \                           # Device character nodes
    -v /run/udev:/run/udev:ro \             # Hardware device enumeration
    \
    # ── Cgroup Permissions ──────────────────────────────────────
    --device-cgroup-rule='c 81:* rmw' \     # video4linux (/dev/video*)
    --device-cgroup-rule='c 235:* rmw' \    # media controller (standard)
    --device-cgroup-rule='c 510:* rmw' \    # media controller (alternate kernel major)
    --device-cgroup-rule='c 252:* rmw' \    # dma_heap (/dev/dma_heap/*)
    --device-cgroup-rule='c 226:* rmw' \    # DRM render nodes
    \
    # ── Security Options ────────────────────────────────────────
    --security-opt systempaths=unconfined \  # Unmasks /sys/firmware/devicetree
    \
    # ── Display Forwarding (Optional) ───────────────────────────
    -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    \
    ros2-imx500-rpi5:base bash
```

---

## 3. Orchestration with Docker Compose

For persistent companion computer setups on autonomous drones, use the provided [`docker-compose.yml`](../docker-compose.yml):

```yaml
version: "3.8"

services:
  ros2-imx500:
    image: ros2-imx500-rpi5:uav
    container_name: ros2-imx500
    restart: unless-stopped
    stdin_open: true
    tty: true
    network_mode: host
    security_opt:
      - systempaths=unconfined
    volumes:
      - /dev:/dev
      - /run/udev:/run/udev:ro
      - /tmp/.X11-unix:/tmp/.X11-unix:rw
    environment:
      - DISPLAY=${DISPLAY}
    device_cgroup_rules:
      - "c 81:* rmw"
      - "c 235:* rmw"
      - "c 510:* rmw"
      - "c 252:* rmw"
      - "c 226:* rmw"
```

### Managing the Service

```bash
# Start container in background:
docker compose up -d

# Check live logs:
docker compose logs -f

# Attach an interactive bash session:
docker compose exec ros2-imx500 bash

# Stop container:
docker compose down
```

---

## 4. Non-Root Security & User Architecture

The container runs as non-root user `ros` (**UID 1000, GID 1000**) for maximum security:
- **Supplementary Groups**: Automatically added to `video`, `dialout` (for serial telemetry to autopilots), and `audio`.
- **Sudo Rights**: Configured with passwordless `sudo` inside the container if package installations are required during debugging.
- **Entrypoint Hook**: Runs [`entrypoint.sh`](../entrypoint.sh) as root to set up the `/dev/dma_heap/vidbuf_cached` symlink before dropping privileges to `ros`.

---

## 5. X11 Display & GUI Forwarding

To visualize camera streams using `rqt_image_view` or RViz2 from within the container:

### On the Host
Allow local container connections to the X server:
```bash
xhost +local:root
```

### Launch Container with Display Forwarding
```bash
./run.sh -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix:rw -- rqt_image_view
```

---

## 6. Verifying Camera Access Inside the Container

Once inside the container shell, verify camera recognition:

### Step 1: List Cameras
```bash
cam -l
```
Expected output:
```text
Available cameras:
0: imx500 [4056x3040] (/base/axi/pcie@1000120000/rp1/i2c@88000/imx500@1a)
```

### Step 2: Test Frame Capture with Picamera2
```bash
python3 -c "
from picamera2 import Picamera2
picam2 = Picamera2()
picam2.start()
frame = picam2.capture_array()
print(f'Successfully captured frame: {frame.shape}')
picam2.stop()
"
```
Expected output:
```text
Successfully captured frame: (480, 640, 3)
```

---

<div align="center">

| [⬅️ Previous: **04 - Multi-Stage Container Builds**](building.md) | [📖 **Documentation Roadmap**](../README.md#documentation-roadmap) | [➡️ Next: **06 - IMX500 ROS 2 Publisher Node**](publisher-node.md) |
| :--- | :---: | ---: |

</div>

