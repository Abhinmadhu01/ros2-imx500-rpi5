#!/usr/bin/env python3
"""
imx500_probe.py — Verify IMX500 AI camera works inside the container.

Loads a model onto the IMX500's on-chip NPU, captures frames, and reports
capture FPS and inference throughput.

Usage:
    python3 imx500_probe.py /path/to/model.rpk [duration_seconds]

Example:
    python3 imx500_probe.py /home/ros/models/mobilenet_v2.rpk 15

Exit codes:
    0  — Camera and inference working
    1  — Error (no camera, no inference, or exception)
"""

import sys
import time
import statistics


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 imx500_probe.py <model.rpk> [seconds]", file=sys.stderr)
        sys.exit(1)

    model_path = sys.argv[1]
    duration = float(sys.argv[2]) if len(sys.argv) > 2 else 15

    # Import here so missing deps give a clear error
    from picamera2 import Picamera2
    from picamera2.devices.imx500 import IMX500

    print(f"[probe] Loading model: {model_path}")
    t0 = time.time()
    imx500 = IMX500(model_path)
    picam2 = Picamera2(imx500.camera_num)

    print("[probe] Uploading network firmware to IMX500...")
    imx500.show_network_fw_progress_bar()

    cfg = picam2.create_preview_configuration(
        main={"format": "BGR888", "size": (640, 480)},
        controls={"FrameRate": 30},
        buffer_count=12,
    )
    picam2.configure(cfg)
    picam2.start()

    t_start = time.time()
    sensor_ts = []      # SensorTimestamp values (seconds)
    exposures = []      # ExposureTime values (µs)
    inference_ts = []   # wall-clock times when inference output arrived
    first_inference = None
    best_score = 0.0

    print(f"[probe] Capturing for {duration:.0f}s ...")
    while time.time() - t_start < duration:
        req = picam2.capture_request()
        md = req.get_metadata()
        outputs = imx500.get_outputs(md, add_batch=True)
        req.release()

        sensor_ts.append(md["SensorTimestamp"] / 1e9)
        exposures.append(md.get("ExposureTime", 0))

        if outputs is not None:
            now = time.time()
            if first_inference is None:
                first_inference = now - t0
            inference_ts.append(now)
            try:
                best_score = max(best_score, float(outputs[1].max()))
            except Exception:
                pass

    picam2.stop()

    # ---- Report ----
    print()
    print("=" * 60)
    print("  IMX500 Probe Results")
    print("=" * 60)

    if len(sensor_ts) > 1:
        capture_fps = (len(sensor_ts) - 1) / (sensor_ts[-1] - sensor_ts[0])
        print(f"  Capture FPS (SensorTimestamp):  {capture_fps:.1f}")
    else:
        print("  Capture FPS: insufficient frames")
        capture_fps = 0

    if exposures:
        print(f"  Mean exposure time:            {statistics.mean(exposures)/1000:.1f} ms")

    if first_inference is None:
        print("  Inference output:              NONE RECEIVED  ✗")
        print("=" * 60)
        sys.exit(1)
    else:
        print(f"  First inference after:         {first_inference:.1f}s")
        if len(inference_ts) > 1:
            inf_fps = (len(inference_ts) - 1) / (inference_ts[-1] - inference_ts[0])
            print(f"  Inference FPS:                 {inf_fps:.1f}")
        print(f"  Best confidence score:         {best_score:.2f}")

    print("=" * 60)
    print("  ✓ IMX500 is working correctly")
    print("=" * 60)


if __name__ == "__main__":
    main()
