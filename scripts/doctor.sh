#!/usr/bin/env bash
# =============================================================================
# doctor.sh — Health Check & Diagnostic Tool for ros2-imx500-rpi5
# =============================================================================
# Run this on the Raspberry Pi host to verify hardware, kernel, drivers, and
# Docker permissions before launching the container.
#
# Usage:
#   ./scripts/doctor.sh
# =============================================================================

set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0
warn_count=0

check_item() {
  local title="$1"
  local cmd="$2"
  local is_critical="${3:-true}"

  printf "  %-45s" "$title"
  if eval "$cmd" >/dev/null 2>&1; then
    echo -e "[ ${GREEN}PASS${NC} ]"
    pass_count=$((pass_count + 1))
    return 0
  else
    if [ "$is_critical" = "true" ]; then
      echo -e "[ ${RED}FAIL${NC} ]"
      fail_count=$((fail_count + 1))
      return 1
    else
      echo -e "[ ${YELLOW}WARN${NC} ]"
      warn_count=$((warn_count + 1))
      return 2
    fi
  fi
}

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}       ros2-imx500-rpi5 Environment Diagnostics      ${NC}"
echo -e "${BLUE}=====================================================${NC}"

echo -e "\n${YELLOW}[1] Hardware & OS Checks:${NC}"
check_item "Raspberry Pi 5 detected" "grep -qi 'Raspberry Pi 5' /proc/device-tree/model"
check_item "64-bit Architecture (aarch64)" "[ \"\$(uname -m)\" = 'aarch64' ]"
check_item "RPi OS / Debian host" "grep -qi 'Debian' /etc/os-release"

echo -e "\n${YELLOW}[2] Camera Hardware & Driver Checks:${NC}"
check_item "IMX500 detected on CSI port" "rpicam-hello --list-cameras 2>&1 | grep -qi 'imx500'"
check_item "V4L2 video devices present" "ls /dev/video* >/dev/null 2>&1"
check_item "Media controller devices present" "ls /dev/media* >/dev/null 2>&1"
check_item "DMA heap devices present" "ls /dev/dma_heap/* >/dev/null 2>&1"
check_item "imx500-all package installed" "dpkg -l | grep -q 'imx500-all'" false
check_item "Host imx500 models present" "ls /usr/share/imx500-models/*.rpk >/dev/null 2>&1" false

echo -e "\n${YELLOW}[3] Docker & Permission Checks:${NC}"
check_item "Docker installed" "command -v docker"
check_item "Docker daemon running" "docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1"
check_item "Non-root docker access" "docker info" false
check_item "udev database accessible" "[ -d /run/udev ]"

echo -e "\n${BLUE}=====================================================${NC}"
echo -e "Summary: ${GREEN}$pass_count Passed${NC} | ${YELLOW}$warn_count Warnings${NC} | ${RED}$fail_count Failed${NC}"
echo -e "${BLUE}=====================================================${NC}"

if [ "$fail_count" -gt 0 ]; then
  echo -e "\n${RED}Action required before running container:${NC}"
  echo "  1. If IMX500 not detected: check ribbon cable & ensure 'camera_auto_detect=1' in /boot/firmware/config.txt"
  echo "  2. If packages missing: run 'sudo apt update && sudo apt install -y imx500-all'"
  echo "  3. If Docker daemon not running: run 'sudo systemctl start docker'"
  exit 1
else
  echo -e "\n${GREEN}Everything is ready! Launch with: ./run.sh${NC}\n"
  exit 0
fi

