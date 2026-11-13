#!/usr/bin/env python3
"""
IMX500 ROS 2 Publisher Node
===========================
Publishes camera frames as `sensor_msgs/Image` and on-chip IMX500 AI detections
as `vision_msgs/Detection2DArray`.

Run example:
    python3 imx500_publisher.py --ros-args \
      -p model_path:=/usr/share/imx500-models/imx500_network_ssd_mobilenetv2_fpnlite_320x320_pp.rpk \
      -p resolution:=640x480 \
      -p fps:=30

Developed by Abhin M
GitHub: https://github.com/Abhinmadhu01/ros2-imx500-rpi5
"""

import collections
import copy
import os
import sys
import threading
import time

import cv2
import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from rcl_interfaces.msg import SetParametersResult
from sensor_msgs.msg import Image
from vision_msgs.msg import Detection2DArray, Detection2D, ObjectHypothesisWithPose
from cv_bridge import CvBridge

from picamera2 import Picamera2
from picamera2.devices.imx500 import IMX500


class IMX500Publisher(Node):

    def __init__(self):
        super().__init__('imx500_publisher')

        # ── ROS 2 Parameters ──────────────────────────────────────────
        self.declare_parameter('resolution', '640x480')
        self.declare_parameter('fps', 30)
        self.declare_parameter('conf_threshold', 0.50)
        self.declare_parameter('nms_threshold', 0.45)
        self.declare_parameter('model_path', 'imx500_network_ssd_mobilenetv2_fpnlite_320x320_pp.rpk')
        self.declare_parameter('target_class', 0)
        self.declare_parameter('target_label', 'person')
        self.declare_parameter('max_cache_age_sec', 0.4)

        res_str = str(self.get_parameter('resolution').value)
        self.resolution = tuple(map(int, res_str.split('x')))
        self.fps = int(self.get_parameter('fps').value)
        self.conf_threshold = float(self.get_parameter('conf_threshold').value)
        self.nms_threshold = float(self.get_parameter('nms_threshold').value)
        self.model_path = str(self.get_parameter('model_path').value)
        self.target_class = int(self.get_parameter('target_class').value)
        self.target_label = str(self.get_parameter('target_label').value)
        self.max_cache_age_sec = float(self.get_parameter('max_cache_age_sec').value)

        # ── Publishers ────────────────────────────────────────────────
        self.image_pub = self.create_publisher(Image, 'camera/image_raw', qos_profile_sensor_data)
        self.detection_pub = self.create_publisher(Detection2DArray, 'detections', qos_profile_sensor_data)
        self.bridge = CvBridge()

        # ── Queues & Threading ────────────────────────────────────────
        self._frame_deque = collections.deque(maxlen=4)
        self._deque_cond = threading.Condition()

        self._img_lock = threading.Lock()
        self._latest_img = None
        self._img_event = threading.Event()

        # Cached last detection (anti-flicker with stale expiry)
        self._last_valid_det = None
        self._last_inference_time = 0.0

        # Stats tracking
        self.running = True
        self._streaming_active = False
        self._stat_lock = threading.Lock()
        self._cap_count = 0
        self._unique_inf_count = 0
        self._det_pub_count = 0
        self._img_count = 0
        self._stat_t0 = time.time()

        # Model tensor dimension cache
        self.model_in_w = 640
        self.model_in_h = 640

        # Initialize Camera
        self._init_camera()

        # Worker Threads
        self._process_thread = threading.Thread(target=self._process_loop, name='process', daemon=True)
        self._image_thread = threading.Thread(target=self._image_publish_loop, name='img_pub', daemon=True)
        self._process_thread.start()
        self._image_thread.start()

        self.create_timer(5.0, self._log_stats)
        self.add_on_set_parameters_callback(self._parameters_callback)
        self.get_logger().info(
            f'IMX500 Publisher ready | {self.resolution[0]}x{self.resolution[1]} @ {self.fps}fps | '
            f'class={self.target_class} ({self.target_label}) | model={os.path.basename(self.model_path)}'
        )

    def _resolve_model_path(self, raw_path: str) -> str:
        """Resolve model path from current dir, absolute path, or standard paths."""
        candidates = [
            raw_path,
            os.path.abspath(raw_path),
            os.path.join('/usr/share/imx500-models', os.path.basename(raw_path)),
            os.path.join('/models', os.path.basename(raw_path)),
            os.path.join(os.path.expanduser('~'), 'models', os.path.basename(raw_path)),
        ]
        for cand in candidates:
            if os.path.isfile(cand):
                return os.path.abspath(cand)
        return raw_path

    def _init_camera(self):
        resolved = self._resolve_model_path(self.model_path)
        if not os.path.isfile(resolved):
            raise FileNotFoundError(
                f'Model not found: "{self.model_path}". '
                f'Provide a valid path with: --ros-args -p model_path:=/path/to/model.rpk'
            )

        self.model_path = resolved
        self.get_logger().info(f'Loading IMX500 model: {self.model_path}')
        self.imx500 = IMX500(self.model_path)
        try:
            w, h = self.imx500.get_input_size()
            if w and h:
                self.model_in_w, self.model_in_h = w, h
        except Exception:
            pass

        self.picam2 = Picamera2(self.imx500.camera_num)
        self.imx500.show_network_fw_progress_bar()

        config = self.picam2.create_preview_configuration(
            main={'format': 'BGR888', 'size': self.resolution},
            controls={'FrameRate': self.fps},
            buffer_count=12,
        )
        self.picam2.configure(config)
        self.picam2.pre_callback = self._on_frame
        self.picam2.start()
        time.sleep(0.3)
        self.get_logger().info('Camera pipeline started. Waiting for first frame & inference...')

    def _parameters_callback(self, params):
        for param in params:
            if param.name == 'conf_threshold':
                self.conf_threshold = float(param.value)
                self.get_logger().info(f'conf_threshold set to: {self.conf_threshold}')
            elif param.name == 'nms_threshold':
                self.nms_threshold = float(param.value)
                self.get_logger().info(f'nms_threshold set to: {self.nms_threshold}')
            elif param.name == 'target_class':
                self.target_class = int(param.value)
                self.get_logger().info(f'target_class set to: {self.target_class}')
        return SetParametersResult(successful=True)

    def _on_frame(self, request):
        if not self.running:
            return

        try:
            if not self._streaming_active:
                self._streaming_active = True
                self.get_logger().info('IMX500 camera active: receiving frames and AI inference.')

            metadata = request.get_metadata()
            np_outputs = self.imx500.get_outputs(metadata, add_batch=True)
            raw_frame = request.make_array("main")
            frame = np.copy(raw_frame)
            stamp = self.get_clock().now().to_msg()

            with self._img_lock:
                self._latest_img = (frame, stamp)
            self._img_event.set()

            with self._deque_cond:
                self._frame_deque.append((np_outputs, stamp))
                self._deque_cond.notify()

            with self._stat_lock:
                self._cap_count += 1

        except Exception as e:
            self.get_logger().debug(f'Frame callback error: {e}')

    def _process_loop(self):
        while self.running and rclpy.ok():
            with self._deque_cond:
                while not self._frame_deque and self.running:
                    self._deque_cond.wait(timeout=1.0)
                if not self._frame_deque:
                    continue
                np_outputs, stamp = self._frame_deque.popleft()

            try:
                now_sec = time.time()
                if np_outputs is not None:
                    det_array = self._build_detections(np_outputs, stamp)
                    self._last_valid_det = det_array
                    self._last_inference_time = now_sec
                    with self._stat_lock:
                        self._unique_inf_count += 1
                else:
                    # Check cache age — anti-flicker with max expiry
                    if self._last_valid_det is not None and (now_sec - self._last_inference_time) < self.max_cache_age_sec:
                        det_array = copy.deepcopy(self._last_valid_det)
                        det_array.header.stamp = stamp
                    else:
                        det_array = Detection2DArray()
                        det_array.header.stamp = stamp
                        det_array.header.frame_id = 'camera_imx500'

                self.detection_pub.publish(det_array)
                with self._stat_lock:
                    self._det_pub_count += 1

            except Exception as e:
                if self.running:
                    self.get_logger().error(f'Process error: {e}')

    def _image_publish_loop(self):
        while self.running and rclpy.ok():
            triggered = self._img_event.wait(timeout=1.0)
            if not triggered or not self.running:
                continue

            with self._img_lock:
                data = self._latest_img
                self._latest_img = None
            self._img_event.clear()

            if data is None:
                continue

            frame, stamp = data
            try:
                msg = self.bridge.cv2_to_imgmsg(frame, encoding='bgr8')
                msg.header.stamp = stamp
                msg.header.frame_id = 'camera_imx500'
                self.image_pub.publish(msg)

                with self._stat_lock:
                    self._img_count += 1

            except Exception as e:
                if self.running:
                    self.get_logger().error(f'Image publish error: {e}')

    def _build_detections(self, np_outputs, stamp) -> Detection2DArray:
        det_array = Detection2DArray()
        det_array.header.stamp = stamp
        det_array.header.frame_id = 'camera_imx500'

        if np_outputs is None or len(np_outputs) < 3:
            return det_array

        boxes = np_outputs[0][0] if np_outputs[0].ndim >= 2 else np_outputs[0]
        scores = np_outputs[1][0] if np_outputs[1].ndim >= 2 else np_outputs[1]
        classes = np_outputs[2][0] if np_outputs[2].ndim >= 2 else np_outputs[2]

        W, H = self.resolution
        valid_boxes, valid_scores, valid_classes = [], [], []

        for i in range(len(scores)):
            conf = float(scores[i])
            class_id = int(classes[i])

            if class_id != self.target_class or conf < self.conf_threshold:
                continue

            raw_b = [float(v) for v in boxes[i]]
            # Determine if coordinates are normalized [0..1] or pixel space [0..model_size]
            is_pixel = max(raw_b) > 1.5

            if is_pixel:
                # YOLO format: x0, y0, x1, y1 in model tensor pixels
                x0 = (raw_b[0] / self.model_in_w) * W
                y0 = (raw_b[1] / self.model_in_h) * H
                x1 = (raw_b[2] / self.model_in_w) * W
                y1 = (raw_b[3] / self.model_in_h) * H
            else:
                # SSD format: y0, x0, y1, x1 in normalized [0..1]
                y0, x0 = raw_b[0] * H, raw_b[1] * W
                y1, x1 = raw_b[2] * H, raw_b[3] * W

            px_min = max(0, min(W - 1, int(min(x0, x1))))
            py_min = max(0, min(H - 1, int(min(y0, y1))))
            w = max(1, min(W - px_min, int(abs(x1 - x0))))
            h = max(1, min(H - py_min, int(abs(y1 - y0))))

            valid_boxes.append([px_min, py_min, w, h])
            valid_scores.append(conf)
            valid_classes.append(class_id)

        if not valid_boxes:
            return det_array

        indices = cv2.dnn.NMSBoxes(valid_boxes, valid_scores, self.conf_threshold, self.nms_threshold)
        if len(indices) > 0:
            for i in indices.flatten():
                box = valid_boxes[i]
                conf = valid_scores[i]
                px_min, py_min, w, h = box

                det = Detection2D()
                det.bbox.center.position.x = float(px_min + w / 2.0)
                det.bbox.center.position.y = float(py_min + h / 2.0)
                det.bbox.size_x = float(w)
                det.bbox.size_y = float(h)

                hyp = ObjectHypothesisWithPose()
                hyp.hypothesis.class_id = self.target_label
                hyp.hypothesis.score = conf
                det.results.append(hyp)
                det_array.detections.append(det)

        return det_array

    def _log_stats(self):
        with self._stat_lock:
            dt = time.time() - self._stat_t0
            if dt <= 0:
                return
            cap = self._cap_count / dt
            inf = self._unique_inf_count / dt
            img = self._img_count / dt
            self._cap_count = self._unique_inf_count = self._det_pub_count = self._img_count = 0
            self._stat_t0 = time.time()

        self.get_logger().info(
            f'Camera: {cap:.1f} fps | '
            f'On-chip AI: {inf:.1f} Hz | '
            f'ROS Image: {img:.1f} Hz'
        )

    def stop(self):
        self.running = False
        with self._deque_cond:
            self._deque_cond.notify_all()
        self._img_event.set()
        if hasattr(self, 'picam2'):
            try:
                self.picam2.stop()
                self.picam2.close()
            except Exception:
                pass


def main(args=None):
    rclpy.init(args=args)
    node = IMX500Publisher()
    try:
        from rclpy.executors import ExternalShutdownException
        shutdown_exceptions = (KeyboardInterrupt, ExternalShutdownException)
    except ImportError:
        shutdown_exceptions = (KeyboardInterrupt,)

    try:
        rclpy.spin(node)
    except shutdown_exceptions:
        print('Shutting down IMX500 publisher...', flush=True)
    finally:
        node.stop()
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()

