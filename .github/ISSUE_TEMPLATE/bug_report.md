---
name: Bug Report
about: Report an issue with the ros2-imx500-rpi5 Docker image
title: "[BUG] "
labels: bug
assignees: ''
---

## Describe the Bug
A clear and concise description of what the bug is.

## Steps to Reproduce
1. Build / pull the image: `...`
2. Run: `...`
3. Execute: `...`
4. See error

## Expected Behaviour
What you expected to happen.

## Actual Behaviour
What actually happened. Paste the full error output.

## Environment

**Please fill in ALL of the following** — camera issues are almost always environment-specific:

| Field | Value |
|-------|-------|
| Pi model | e.g. Raspberry Pi 5 8GB |
| OS | e.g. Raspberry Pi OS Bookworm 64-bit |
| Kernel | `uname -r` output |
| Docker version | `docker --version` output |
| Image tag | e.g. `ros2-imx500-rpi5:base` |
| How you launched | `run.sh` / `docker compose` / manual `docker run` |

## Camera Diagnostics

Please run these **on the host** (outside Docker) and paste the output:

### `cam -l`
```
paste output here
```

### `rpicam-hello --list-cameras`
```
paste output here
```

### `ls -la /dev/video* /dev/media* /dev/v4l-subdev*`
```
paste output here
```

### `awk '$2=="video4linux" || $2=="media" || $2=="dma_heap"' /proc/devices`
```
paste output here
```

## Container Diagnostics

If you can get a shell in the container, run:

### `cam -l` (inside container)
```
paste output here
```

### `python3 -c "from picamera2 import Picamera2; print(Picamera2.global_camera_info())"`
```
paste output here
```

## Additional Context
Add any other context, screenshots, or log output.
