# Raspberry Pi 5 Host Setup Guide

The container relies on the Raspberry Pi 5 host for the physical hardware drivers and kernel support.

---

## 1. Operating System
- **Recommended OS**: Raspberry Pi OS (Bookworm or Trixie) 64-bit.
- **Kernel**: 6.6+ or 6.18+ with Raspberry Pi downstream patches (`rpt-rpi-2712`).

Verify your host kernel:
```bash
uname -r
# Output should contain: +rpt-rpi-2712
```

---

## 2. Hardware Connection
Connect the Sony IMX500 AI Camera to either of the Pi 5's two CSI/DSI ports using a 22-pin to 15-pin ribbon cable (copper pins facing the board).

Check that camera auto-detection is enabled in `/boot/firmware/config.txt`:
```ini
camera_auto_detect=1
```

Reboot if you changed this file:
```bash
sudo reboot
```

---

## 3. Install Host IMX500 Packages
Install the firmware and models on the host:
```bash
sudo apt update
sudo apt install -y imx500-all
```

---

## 4. Test Camera on the Host
Verify that the host kernel recognizes the sensor:
```bash
rpicam-hello --list-cameras
```
Expected output:
```text
Available cameras
-----------------
0 : imx500 [4056x3040 10-bit RGGB] (/base/axi/pcie@1000120000/rp1/i2c@88000/imx500@1a)
```

Test a quick preview with on-chip AI detection on the host:
```bash
rpicam-hello -t 5s --post-process-file /usr/share/rpi-camera-assets/imx500_mobilenet_ssd.json
```
If you see the camera feed with bounding boxes, the hardware is 100% ready for the Docker container.

