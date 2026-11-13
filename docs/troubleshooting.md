# Troubleshooting & FAQ

---

### 1. `OSError: [Errno 12] Cannot allocate memory`
**Symptom**: `picamera2` crashes during buffer allocation.  
**Cause**: By default, `picamera2` looks for `/dev/dma_heap/vidbuf_cached` (system memory). If missing, it falls back to `/dev/dma_heap/linux,cma`, which is a tiny 64 MB kernel pool that runs out of contiguous pages immediately.  
**Fix**: Handled automatically by [`entrypoint.sh`](file:///home/icod/pi5_imx500_ros2_ws/entrypoint.sh), which creates the symlink:
```bash
ln -sf system /dev/dma_heap/vidbuf_cached
```

---

### 2. `no cameras available` in `camera_ros`
**Symptom**: `ros2 run camera_ros camera_node` throws an exception stating `no cameras available`.  
**Cause**: The pre-built Ubuntu package `ros-humble-camera-ros` ships its own old `libcamera.so.0.1.0`. That library lacks the Raspberry Pi PiSP pipeline handler needed for Pi 5.  
**Fix**: Use `picamera2` directly (e.g. `scripts/imx500_publisher.py`), which uses the container's custom-built `libcamera v0.7.2+rpt` with full PiSP and IMX500 support.

---

### 3. First-run delay (20–30 seconds) on a new `.rpk` model
**Symptom**: The camera appears stuck for ~25 seconds on the very first time a new `.rpk` is loaded.  
**Cause**: The camera board's RP2040 microcontroller is flashing the neural network weights into the camera's non-volatile flash memory over SPI.  
**Fix**: Normal behavior. Subsequent boots of the same model will load in < 1 second.

---

### 4. `Failed to open media device: Operation not permitted`
**Symptom**: libcamera logs `Operation not permitted` when opening `/dev/media0` or `/dev/media1`.  
**Cause**: The cgroup device major number for `media` changed across reboots.  
**Fix**: Always launch with `./run.sh` or check your current device majors:
```bash
grep -E " (media|video4linux|dma_heap)$" /proc/devices
```

---

### 5. Display / GUI Issues over SSH (`Cannot connect to X server`)
If running visualization tools (`rqt_image_view`):
```bash
# On your local machine (if SSHing):
ssh -X icod@<pi-ip>

# On the Pi host before running the container:
xhost +local:root
```
Pass `-e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix:ro` to `./run.sh`.

