#!/usr/bin/env bash
# =============================================================================
# run.sh — Launch the ros2-imx500-rpi5 container with correct device access
# =============================================================================
# Device majors for media, video4linux, and dma_heap are DYNAMICALLY assigned
# by the kernel and can change across reboots / kernel versions.  This script
# reads them from /proc/devices at launch time and builds the right cgroup rules.
#
# Usage:
#   ./run.sh                            # interactive bash (base image)
#   ./run.sh -- python3 my_script.py    # run a command
#   IMAGE=ros2-imx500-rpi5:full ./run.sh  # use the full image
#   ./run.sh -e DISPLAY=:1 -- bash      # extra docker flags before --
# =============================================================================
set -euo pipefail

IMAGE="${IMAGE:-ros2-imx500-rpi5:base}"
DOCKER=docker
docker info >/dev/null 2>&1 || DOCKER="sudo docker"

# Device majors for media and dma_heap are assigned dynamically; read them now.
rules=()
for n in video4linux media dma_heap; do
  m=$(awk -v n="$n" '$2==n {print $1}' /proc/devices)
  if [ -n "$m" ]; then rules+=(--device-cgroup-rule="c ${m}:* rmw"); fi
done

opts=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do opts+=("$1"); shift; done
if [ "${1:-}" = "--" ]; then shift; fi

tty=(-i)
if [ -t 0 ] && [ -t 1 ]; then tty=(-it); fi

exec $DOCKER run --rm "${tty[@]}" --network host \
  --security-opt systempaths=unconfined \
  -v /dev:/dev -v /run/udev:/run/udev:ro \
  "${rules[@]}" "${opts[@]}" "$IMAGE" "$@"
