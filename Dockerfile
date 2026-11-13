# =============================================================================
# ros2-imx500-rpi5
# ROS 2 Humble (Ubuntu 22.04) + Raspberry Pi 5 + Sony IMX500 AI Camera
# =============================================================================
# The Raspberry Pi OS *host* provides the kernel, drivers and IMX500 firmware.
# This image provides the Ubuntu 22.04 / ROS 2 Humble userspace, a source-built
# Raspberry Pi libcamera (PiSP pipeline + Python bindings) and picamera2.
#
# Targets (each one builds on the previous one):
#   base      libcamera + picamera2 + ROS 2 core + cv_bridge/vision_msgs + colcon
#   uav       base + MAVROS, AprilTag, GStreamer streaming stack, GUI helpers
#   full      uav + compilers, PyTorch (CPU), Ultralytics (AGPL-3.0), MAVProxy
#
# Build:
#   docker build --target base     -t ros2-imx500-rpi5:base .
#   docker build --target uav      -t ros2-imx500-rpi5:uav .
#   docker build --target full     -t ros2-imx500-rpi5:full .
#
# Build args:
#   LIBCAMERA_TAG  Raspberry Pi libcamera tag (default: tested with kernel 6.18.x)
#   WITH_KMSXX     1 = also build kms++ / pykms (DRM preview). 0 = skip it.
#   ROS_BASE       Base image. Pin by digest for fully reproducible builds.
#
# Run (handles device rules, udev and the heap fix):  ./run.sh
# =============================================================================

ARG ROS_BASE=ros:humble-ros-core
ARG LIBCAMERA_TAG=v0.7.2+rpt20261009
ARG WITH_KMSXX=1
ARG KMSXX_BEFORE=2024-01-01

# =============================================================================
# Stage 1: libcamera-build  (compilers live here and never reach the final image)
# =============================================================================
FROM ${ROS_BASE} AS libcamera-build

ARG LIBCAMERA_TAG
ARG WITH_KMSXX
ARG KMSXX_BEFORE
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git build-essential cmake ninja-build pkg-config \
        python3-pip python3-dev python3-setuptools python3-wheel \
        python3-yaml python3-ply python3-jinja2 pybind11-dev python3-pybind11 \
        libgnutls28-dev openssl libtiff5-dev libjpeg-dev libpng-dev \
        libdrm-dev libegl1-mesa-dev libepoxy-dev libgbm-dev libudev-dev \
        libevent-dev libyaml-dev libcap-dev libfmt-dev \
        libglib2.0-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 22.04 ships meson 0.61, which is too old for current libcamera.
RUN pip3 install --no-cache-dir meson==1.5.2

# libcamera (Raspberry Pi fork). DESTDIR keeps the install in /stage so the
# final image gets only the libcamera files, not meson or the toolchain.
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
    && DESTDIR=/stage ninja -C build install \
    && test -f /stage/usr/local/lib/python3/dist-packages/libcamera/__init__.py

# kms++ / pykms (optional, used by the picamera2 DRM preview)
RUN if [ "${WITH_KMSXX}" = "1" ]; then \
        git clone https://github.com/tomba/kmsxx.git /tmp/kmsxx \
        && cd /tmp/kmsxx \
        && git checkout "$(git rev-list -n 1 --before="${KMSXX_BEFORE}" master)" \
        && meson setup build --prefix=/usr/local -Dbuildtype=release \
        && ninja -C build \
        && DESTDIR=/stage ninja -C build install; \
    fi

# =============================================================================
# Stage 2: base
# =============================================================================
FROM ${ROS_BASE} AS base

ARG USERNAME=ros
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

LABEL org.opencontainers.image.title="ros2-imx500-rpi5" \
      org.opencontainers.image.description="ROS 2 Humble with Raspberry Pi 5 IMX500 AI Camera support (source-built libcamera + picamera2)" \
      org.opencontainers.image.authors="Abhin M" \
      org.opencontainers.image.source="https://github.com/Abhinmadhu01/ros2-imx500-rpi5" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive

# Keep NumPy 1.x for every later pip install (cv_bridge and apt OpenCV need it).
RUN echo 'numpy==1.26.4' > /etc/pip-constraints.txt
ENV PIP_CONSTRAINT=/etc/pip-constraints.txt

# Runtime libraries only (no -dev packages, no compilers).
RUN apt-get update && apt-get install -y --no-install-recommends \
        sudo ca-certificates curl git nano htop \
        netcat-openbsd iputils-ping iproute2 locales \
        python3-pip python3-setuptools python3-wheel python3-yaml python3-prctl \
        python3-opencv \
        libgnutls30 libssl3 libtiff5 libjpeg-turbo8 libpng16-16 libopenjp2-7 \
        libdrm2 libegl1 libepoxy0 libgbm1 libudev1 \
        libevent-2.1-7 libevent-pthreads-2.1-7 libyaml-0-2 libcap2 libfmt8 \
        libglib2.0-0 libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
        libqt5gui5 libqt5widgets5 libqt5core5a libqt5test5 \
        libxcb-xinerama0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
        libxcb-randr0 libxcb-render-util0 libxcb-xfixes0 libxcb-shape0 libxcb-xkb1 \
    && locale-gen en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# libcamera (+ kms++) from the builder stage, then fail the build loudly if any
# shared library it needs is missing from this runtime image.
COPY --from=libcamera-build /stage/ /
RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/99-local.conf \
    && ldconfig \
    && missing="$(find /usr/local/lib /usr/local/bin -type f \( -name '*.so*' -o -name cam \) \
            -exec ldd {} \; 2>/dev/null | grep 'not found' | sort -u)" \
    && if [ -n "${missing}" ]; then \
            echo "ERROR: missing runtime libraries:"; echo "${missing}"; exit 1; \
       fi \
    && cam --version

# ROS 2 packages for the camera node and for building your own packages.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-humble-cv-bridge \
        ros-humble-vision-msgs \
        ros-humble-camera-info-manager \
        ros-humble-image-transport-plugins \
        ros-humble-image-geometry \
        ros-humble-camera-calibration \
        python3-colcon-common-extensions \
        python3-colcon-mixin \
        python3-rosdep \
        python3-vcstool \
    && rm -rf /var/lib/apt/lists/*

# Python packages for the camera node and utilities.
# PiDNG (required by picamera2) builds a C extension (ljpegCompress); gcc is installed
# temporarily to build it, then purged without --auto-remove so ROS is not touched.
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc libc6-dev \
    && pip3 install --no-cache-dir \
        picamera2==0.3.38 \
        numpy==1.26.4 \
        Pillow \
        pyserial \
        transforms3d \
        tqdm \
        colorama \
        simplejson \
    && apt-get purge -y gcc \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/ros2-imx500-rpi5 \
    && pip3 freeze > /opt/ros2-imx500-rpi5/pip-freeze-base.txt

ENV PYTHONPATH="/usr/local/lib/python3/dist-packages:/usr/local/lib/aarch64-linux-gnu/python3.10/site-packages:/usr/local/lib/python3.10/dist-packages"
ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/lib/aarch64-linux-gnu"
ENV LANG="en_US.UTF-8"
ENV LC_ALL="en_US.UTF-8"
ENV QT_QPA_PLATFORM="xcb"
ENV QT_QPA_PLATFORM_PLUGIN_PATH="/usr/lib/aarch64-linux-gnu/qt5/plugins"
ENV QT_AUTO_SCREEN_SCALE_FACTOR="0"
ENV OPENCV_GUI_BACKEND="QT5"

# Non-root user. Passwordless sudo is intentional: the entrypoint uses it to
# repair /dev/dma_heap/vidbuf_cached, and it is handy for a development image.
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd -s /bin/bash --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} \
    && mkdir -p /home/${USERNAME}/.config /home/${USERNAME}/scripts \
                /home/${USERNAME}/data /home/${USERNAME}/models \
                /home/${USERNAME}/ws/src \
    && chown -R ${USER_UID}:${USER_GID} /home/${USERNAME} \
    && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && usermod -aG video,dialout,audio,sudo ${USERNAME}

COPY --chown=${USERNAME}:${USERNAME} bashrc /home/${USERNAME}/.bashrc
COPY entrypoint.sh /entrypoint.sh
# An empty or shebang-less entrypoint gives "exec format error"; catch it here.
RUN chmod 0755 /entrypoint.sh \
    && test -s /entrypoint.sh \
    && head -n 1 /entrypoint.sh | grep -q '^#!'

# Build-time sanity checks: the build stops here if the camera stack is broken.
RUN . /opt/ros/humble/setup.sh \
    && python3 -c "\
import numpy, cv2, cv_bridge, libcamera; \
from picamera2 import Picamera2; \
from picamera2.devices.imx500 import IMX500; \
assert numpy.__version__.startswith('1.'), 'NumPy is ' + numpy.__version__; \
assert cv2.__file__.startswith('/usr/lib/python3'), 'cv2 is not the apt build: ' + cv2.__file__; \
print('OK numpy', numpy.__version__, '| cv2', cv2.__version__, '| libcamera + picamera2 + IMX500 import OK')" \
    && test -z "$(find /opt/ros -name 'libcamera.so*' 2>/dev/null)" \
    && echo "OK: no second libcamera under /opt/ros"

WORKDIR /home/${USERNAME}
USER ${USERNAME}

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]

# =============================================================================
# Stage 3: uav  (drone / streaming / GUI extras)
# =============================================================================
FROM base AS uav

ARG USERNAME=ros
USER root

# Set these at run time:  docker run -e LAPTOP_IP=... -e MAV_DEVICE=...
ENV LAPTOP_IP=""
ENV MAV_DEVICE="/dev/ttyACM0:921600"

RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-humble-mavros \
        ros-humble-mavros-extras \
        ros-humble-apriltag-ros \
        ros-humble-v4l2-camera \
        ros-humble-usb-cam \
        ffmpeg \
        gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav \
        gstreamer1.0-x gstreamer1.0-alsa gstreamer1.0-gl \
        x11-utils x11-xserver-utils libgl1-mesa-dri \
        wget \
    && rm -rf /var/lib/apt/lists/* \
    && find /opt/ros -name 'libcamera*.so*' -delete

# GeographicLib datasets (MAVROS GPS)
RUN wget -q https://raw.githubusercontent.com/mavlink/mavros/master/mavros/scripts/install_geographiclib_datasets.sh \
    && chmod +x install_geographiclib_datasets.sh \
    && ./install_geographiclib_datasets.sh \
    && rm install_geographiclib_datasets.sh

RUN pip3 install --no-cache-dir pymavlink

RUN . /opt/ros/humble/setup.sh \
    && gst-inspect-1.0 x264enc h264parse flvmux rtmp2sink > /dev/null \
    && echo "OK: RTMP GStreamer plugins present" \
    && test -z "$(find /opt/ros -name 'libcamera.so*' 2>/dev/null)" \
    && echo "OK: no second libcamera under /opt/ros"

WORKDIR /home/${USERNAME}
USER ${USERNAME}

# =============================================================================
# Stage 4: full  (everything: compilers, ML stack, SITL tools)
# =============================================================================
FROM uav AS full

ARG USERNAME=ros
USER root

LABEL org.opencontainers.image.description="Full ROS 2 Humble + Pi 5 IMX500 image with compilers, PyTorch (CPU), Ultralytics (AGPL-3.0) and MAVProxy"

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake python3-dev libcap-dev vim \
    && rm -rf /var/lib/apt/lists/*

# Versions below are the ones tested on the Pi 5. Ultralytics is AGPL-3.0.
RUN pip3 install --no-cache-dir torch==2.14.1 torchvision==0.29.2 \
        --index-url https://download.pytorch.org/whl/cpu

RUN pip3 install --no-cache-dir \
        ultralytics==8.4.194 \
        onnxruntime==1.23.2 \
        mavproxy==1.8.75 \
        lap scipy matplotlib requests filelock pexpect future

# Ultralytics pulls in a pip OpenCV that would shadow the apt build ROS uses.
RUN pip3 uninstall -y opencv-python opencv-python-headless opencv-contrib-python || true

RUN . /opt/ros/humble/setup.sh \
    && python3 -c "\
import numpy, cv2, torch, ultralytics; \
assert numpy.__version__.startswith('1.'), 'NumPy is ' + numpy.__version__; \
assert cv2.__file__.startswith('/usr/lib/python3'), 'cv2 is not the apt build: ' + cv2.__file__; \
print('OK numpy', numpy.__version__, '| cv2', cv2.__version__, '| torch', torch.__version__, '| ultralytics', ultralytics.__version__)" \
    && pip3 freeze > /opt/ros2-imx500-rpi5/pip-freeze-full.txt

WORKDIR /home/${USERNAME}
USER ${USERNAME}
