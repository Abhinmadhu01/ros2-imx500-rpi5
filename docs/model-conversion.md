# IMX500 Model Conversion Workflow (.rpk)

The Sony IMX500 executes neural networks on its internal DSP/NPU. Models must be converted into the proprietary Sony `.rpk` (Raspberry Pi Package) firmware format.

> [!TIP]
> Conversion and quantization tools (Sony Model Compression Toolkit / `imxconv`) run on an **x86_64 PC**, not directly on the Raspberry Pi.

---

## 1. Exporting YOLO to IMX500 format (PC)

Ultralytics YOLO (YOLOv8, YOLO11) supports direct export to the IMX500 `.rpk` format:

```bash
# On your PC with Python 3.10+:
pip install ultralytics

# Export YOLO11 nano model
yolo export model=yolo11n.pt format=imx500 imgsz=640
```

This generates `yolo11n.rpk` containing:
- Quantized INT8 weights
- On-chip post-processing firmware
- `network_info.txt` metadata

---

## 2. Using Pre-Compiled Raspberry Pi Models

If you do not want to convert models yourself, Raspberry Pi provides ready-to-run `.rpk` files in the `imx500-all` package located at:
```text
/usr/share/imx500-models/
```

Available models include:
- `imx500_network_ssd_mobilenetv2_fpnlite_320x320_pp.rpk` (Fastest, ~15 FPS)
- `imx500_network_nanodet_plus_416x416_pp.rpk`
- `imx500_network_posenet.rpk` (Pose estimation)
- `imx500_network_deeplabv3plus.rpk` (Semantic segmentation)

---

## 3. Copying Models to the Pi

Transfer your `.rpk` from your PC to the Pi:
```bash
scp yolo11n.rpk icod@<pi-ip>:~/models/
```

Then bind-mount the folder into the container using `run.sh`:
```bash
./run.sh -v $HOME/models:/models -- python3 scripts/imx500_publisher.py --ros-args -p model_path:=/models/yolo11n.rpk
```

