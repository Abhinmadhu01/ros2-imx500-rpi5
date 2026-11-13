# Device Node Access & Dynamic Major Numbers

Running hardware-accelerated cameras inside Docker without `--privileged` requires mapping device nodes and granting cgroup permissions.

---

## The Dynamic Major Number Problem

Linux assigns device major numbers dynamically for certain subsystems. On Raspberry Pi 5 kernels, the major numbers can change between kernel versions or reboots:

| Subsystem | Typical Major Number | Device Nodes |
|---|---|---|
| `video4linux` | `81` | `/dev/video*`, `/dev/v4l-subdev*` |
| `media` | `235` or `510` (dynamic!) | `/dev/media*` |
| `dma_heap` | `252` or `261` (dynamic!) | `/dev/dma_heap/*` |

If you run with static flags like `--device-cgroup-rule='c 235:* rmw'` on a kernel where `media` was assigned `510`, you will receive:
```text
Operation not permitted: Failed to open media device at /dev/media1
```

---

## How `run.sh` Solves This

The `run.sh` script dynamically queries `/proc/devices` at launch:

```bash
rules=()
for n in video4linux media dma_heap; do
  m=$(awk -v n="$n" '$2==n {print $1}' /proc/devices)
  if [ -n "$m" ]; then rules+=(--device-cgroup-rule="c ${m}:* rmw"); fi
done
```

This ensures your container always receives the exact permissions needed on that specific boot.

---

## Required Mounts Explained

- `-v /dev:/dev`: Exposes the video, media, and DMA buffer nodes.
- `-v /run/udev:/run/udev:ro`: Grants libcamera access to the udev database for camera pipeline enumeration.
- `--security-opt systempaths=unconfined`: Unmasks `/sys/firmware/devicetree` so libcamera's DeviceEnumerator can match CSI bridge endpoints.

