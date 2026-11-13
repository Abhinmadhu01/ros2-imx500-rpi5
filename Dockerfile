# =============================================================================
# Dockerfile — ROS 2 Humble + Raspberry Pi 5 IMX500 AI Camera
# =============================================================================
# Builds libcamera from RPi's fork (with PiSP pipeline) inside an Ubuntu 22.04
# container so that picamera2 can drive the IMX500's on-chip inference engine.
#
# Targets:
#   base  – libcamera + picamera2 + ROS 2 + OpenCV + onnxruntime  (slim)
#   full  – base + PyTorch (CPU) + ultralytics + MAVProxy + scipy  (everything)
#
# Build:
#   docker build --target base -t ros2-imx500-rpi5:base .
#   docker build --target full -t ros2-imx500-rpi5:full .
#
# Run:  ./run.sh  (handles cgroup rules and device mounts automatically)
#
# Developed by Abhin M
# =============================================================================

# ---- Build args (override at build time with --build-arg) -------------------
ARG LIBCAMERA_TAG=v0.7.2+rpt20261009
ARG LAPTOP_IP=""
ARG MAV_DEVICE="/dev/ttyACM0:921600"

# =============================================================================
# Stage: base
# =============================================================================
FROM ros:humble-ros-core AS base

LABEL org.opencontainers.image.title="ros2-imx500-rpi5"
LABEL org.opencontainers.image.description="ROS 2 Humble with Raspberry Pi 5 IMX500 AI Camera support (source-built libcamera)"
LABEL org.opencontainers.image.authors="Abhin M"
LABEL org.opencontainers.image.source="https://github.com/Abhinmadhu01/ros2-imx500-rpi5"
LABEL org.opencontainers.image.licenses="MIT"

# Re-declare ARGs after FROM so they're available in this stage
ARG LIBCAMERA_TAG
ARG LAPTOP_IP
ARG MAV_DEVICE

ARG USERNAME=ros
ARG USER_UID=1000
ARG USER_GID=$USER_UID

ENV DEBIAN_FRONTEND=noninteractive

# Pin NumPy <2 globally via pip constraints
RUN echo 'numpy==1.26.4' > /etc/pip-constraints.txt
ENV PIP_CONSTRAINT=/etc/pip-constraints.txt

# ---------------------------------------------------------------------------
# Layer 1: System tools + build deps + libcamera deps + GStreamer + display libs
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # System utilities
    sudo wget curl git nano vim htop \
    netcat-openbsd iputils-ping iproute2 \
    # Build toolchain
    build-essential cmake meson ninja-build pkg-config \
    python3-pip python3-dev python3-setuptools python3-wheel \
    python3-yaml python3-ply python3-jinja2 python3-prctl \
    # libcamera deps (including pybind11 for python bindings)
    libgnutls28-dev openssl libtiff5-dev libjpeg-dev libpng-dev \
    libdrm-dev libegl1-mesa-dev libepoxy-dev libgbm-dev \
    libudev-dev libevent-dev libatlas-base-dev libopenjp2-7 libfmt-dev \
    libyaml-dev libcap-dev ffmpeg \
    pybind11-dev python3-pybind11 \
    # GStreamer (camera streaming & RTMP)
    libglib2.0-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    libgstreamer-plugins-bad1.0-dev \
    gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav \
    gstreamer1.0-x gstreamer1.0-alsa gstreamer1.0-gl \
    # Display / Qt / X11 (OpenCV GUI)
    qtbase5-dev libqt5gui5 libqt5widgets5 libqt5core5a libqt5test5 \
    libx11-dev libxext-dev libxrender-dev libxinerama-dev libxi-dev \
    libxrandr-dev libxcursor-dev libxfixes-dev libxss-dev \
    libxcomposite-dev libxdamage-dev libxft-dev \
    libxcb-xinerama0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
    libxcb-randr0 libxcb-render-util0 libxcb-xfixes0 libxcb-shape0 libxcb-xkb1 \
    x11-utils x11-xserver-utils \
    libgtk-3-dev libcanberra-gtk3-dev libgl1-mesa-glx libgl1-mesa-dri \
    # Locale
    locales \
    && locale-gen en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Upgrade meson/ninja to versions that can build modern libcamera
RUN pip3 install --upgrade meson ninja

# ---------------------------------------------------------------------------
# Layer 2: Build libcamera from RPi fork (pinned tag for reproducibility)
# ---------------------------------------------------------------------------
# NOTE: The official ros-humble-camera-ros package ships libcamera v0.1.0 which
# CONFLICTS with this v0.7.x source build.  picamera2 (which uses this build)
# works perfectly; camera_ros does not unless rebuilt against this libcamera.
RUN git clone --branch "${LIBCAMERA_TAG}" --depth 1 \
        https://github.com/raspberrypi/libcamera.git /tmp/libcamera \
    && cd /tmp/libcamera \
    && meson setup build \
        --buildtype=release \
        --prefix=/usr/local \
        -Dpipelines=rpi/vc4,rpi/pisp \
        -Dipas=rpi/vc4,rpi/pisp \
        -Dv4l2=enabled \
        -Dgstreamer=enabled \
        -Dpycamera=enabled \
        -Dtest=false \
        -Dlc-compliance=disabled \
        -Dcam=enabled \
        -Dqcam=disabled \
        -Ddocumentation=disabled \
    && ninja -C build \
    && ninja -C build install \
    && ldconfig \
    # Verify python bindings exist somewhere
    && (ls /usr/local/lib/python*/site-packages/libcamera* 2>/dev/null || \
        ls /usr/local/lib/python*/dist-packages/libcamera* 2>/dev/null || \
        ls /usr/local/lib/aarch64-linux-gnu/python3*/site-packages/libcamera* 2>/dev/null || \
        (echo "WARNING: Python bindings not in expected locations, checking..." && \
         find /usr/local -name "libcamera*.so" 2>/dev/null | head -5)) \
    && rm -rf /tmp/libcamera

# ---------------------------------------------------------------------------
# Layer 3: Build kmsxx (display/DRM support)
# ---------------------------------------------------------------------------
RUN git clone https://github.com/tomba/kmsxx.git /tmp/kmsxx \
    && cd /tmp/kmsxx \
    && git checkout $(git rev-list -n 1 --before="2024-01-01" master) \
    && meson setup build --prefix=/usr/local -Dbuildtype=release \
    && ninja -C build \
    && ninja -C build install \
    && ldconfig \
    && rm -rf /tmp/kmsxx

# Ensure /usr/local/lib is on the dynamic linker path
RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/99-local.conf && ldconfig

# ---------------------------------------------------------------------------
# Layer 4: ROS 2 packages
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-mavros \
    ros-humble-mavros-extras \
    ros-humble-v4l2-camera \
    ros-humble-usb-cam \
    ros-humble-image-transport-plugins \
    ros-humble-cv-bridge \
    ros-humble-camera-info-manager \
    ros-humble-image-geometry \
    ros-humble-apriltag-ros \
    ros-humble-camera-ros \
    ros-humble-camera-calibration \
    ros-humble-vision-msgs \
    # Colcon & dev tools
    python3-colcon-common-extensions \
    python3-colcon-mixin \
    python3-rosdep \
    python3-vcstool \
    python3-opencv \
    && rm -rf /var/lib/apt/lists/*

# GeographicLib datasets (MAVROS GPS)
RUN wget -q https://raw.githubusercontent.com/mavlink/mavros/master/mavros/scripts/install_geographiclib_datasets.sh \
    && chmod +x install_geographiclib_datasets.sh \
    && ./install_geographiclib_datasets.sh \
    && rm install_geographiclib_datasets.sh

# ---------------------------------------------------------------------------
# Layer 5: Python packages (base set — no torch)
# ---------------------------------------------------------------------------
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel \
    && pip3 install --no-cache-dir \
        picamera2 \
        'numpy==1.26.4' \
        Pillow \
        pyserial \
        pymavlink \
        transforms3d \
        tqdm \
        colorama \
        simplejson \
        onnxruntime \
        matplotlib \
        requests \
        filelock

# Force NumPy 1.x and ensure apt-OpenCV is the only cv2
RUN pip3 install --no-cache-dir --force-reinstall 'numpy==1.26.4' \
    && pip3 uninstall -y opencv-python opencv-python-headless opencv-contrib-python 2>/dev/null || true

# ---------------------------------------------------------------------------
# Environment variables
# ---------------------------------------------------------------------------
ENV PYTHONPATH="/usr/local/lib/python3/dist-packages:/usr/local/lib/aarch64-linux-gnu/python3.10/site-packages:/usr/local/lib/python3.10/dist-packages"
ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/lib/aarch64-linux-gnu"
ENV LANG="en_US.UTF-8"
ENV LC_ALL="en_US.UTF-8"
ENV QT_QPA_PLATFORM="xcb"
ENV QT_QPA_PLATFORM_PLUGIN_PATH="/usr/lib/aarch64-linux-gnu/qt5/plugins"
ENV QT_AUTO_SCREEN_SCALE_FACTOR="0"
ENV OPENCV_GUI_BACKEND="QT5"
ENV DISPLAY=":0"
ENV LAPTOP_IP="${LAPTOP_IP}"
ENV MAV_DEVICE="${MAV_DEVICE}"

# ---------------------------------------------------------------------------
# User setup
# ---------------------------------------------------------------------------
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd -s /bin/bash --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && mkdir -p /home/$USERNAME/.config /home/$USERNAME/scripts \
                /home/$USERNAME/data /home/$USERNAME/models \
                /home/$USERNAME/ws/src \
    && chown -R $USER_UID:$USER_GID /home/$USERNAME \
    && echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && usermod -aG video,dialout,audio,sudo $USERNAME

# Copy configuration files
COPY --chown=$USERNAME:$USERNAME bashrc /home/$USERNAME/.bashrc
COPY --chown=$USERNAME:$USERNAME entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ---------------------------------------------------------------------------
# Build-time sanity checks (build stops here if something is wrong)
# ---------------------------------------------------------------------------
RUN . /opt/ros/humble/setup.sh \
    && python3 -c "\
import numpy, cv2, cv_bridge; \
assert numpy.__version__.startswith('1.'), 'NumPy is ' + numpy.__version__; \
assert cv2.__file__.startswith('/usr/lib/python3'), 'cv2 is not the apt build: ' + cv2.__file__; \
print('OK numpy', numpy.__version__, '| cv2', cv2.__version__, '| cv_bridge import OK')" \
    && gst-inspect-1.0 x264enc h264parse flvmux rtmp2sink > /dev/null \
    && echo "OK RTMP GStreamer plugins present"

WORKDIR /home/$USERNAME
USER $USERNAME

HEALTHCHECK --interval=60s --timeout=15s --start-period=20s --retries=3 \
    CMD python3 -c "import picamera2" || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]


# =============================================================================
# Stage: full (everything on top of base)
# =============================================================================
FROM base AS full

USER root

# PyTorch CPU + ML stack
RUN pip3 install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu
RUN pip3 install --no-cache-dir \
    'numpy==1.26.4' \
    ultralytics \
    lap \
    scipy \
    polars \
    sympy \
    networkx \
    fsspec \
    pexpect \
    future \
    mavproxy

# Re-pin NumPy after all pip installs
RUN pip3 install --no-cache-dir --force-reinstall 'numpy==1.26.4' \
    && pip3 uninstall -y opencv-python opencv-python-headless opencv-contrib-python 2>/dev/null || true

USER $USERNAME
