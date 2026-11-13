#!/usr/bin/env bash
set -e

# ROS 2 environment
source /opt/ros/humble/setup.bash
if [ -f "$HOME/ws/install/setup.bash" ]; then
  source "$HOME/ws/install/setup.bash"
fi

# picamera2 prefers /dev/dma_heap/vidbuf_cached (-> system heap) and falls back to
# the small linux,cma pool. A Docker-generated /dev lacks that symlink.
if [ -e /dev/dma_heap/system ] && [ ! -e /dev/dma_heap/vidbuf_cached ]; then
  sudo -n ln -sf system /dev/dma_heap/vidbuf_cached 2>/dev/null || \
    echo "[entrypoint] WARNING: /dev/dma_heap/vidbuf_cached is missing; the camera may fail with 'Cannot allocate memory'. Start with run.sh or -v /dev:/dev." >&2
fi

if ! ls /dev/v4l-subdev* >/dev/null 2>&1; then
  echo "[entrypoint] WARNING: no camera device nodes visible. Start with run.sh (see README)." >&2
fi
if [ ! -d /run/udev ]; then
  echo "[entrypoint] WARNING: /run/udev is not mounted; libcamera will not find the camera." >&2
fi

exec "$@"
