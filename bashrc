# ~/.bashrc — ros2-imx500-rpi5 container
# =============================================================================

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------
HISTSIZE=2000
HISTFILESIZE=5000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend

# ---------------------------------------------------------------------------
# Shell behaviour
# ---------------------------------------------------------------------------
shopt -s checkwinsize   # update LINES/COLUMNS after each command
shopt -s globstar       # ** matches recursively

# ---------------------------------------------------------------------------
# ROS 2 Humble
# ---------------------------------------------------------------------------
if [ -f /opt/ros/humble/setup.bash ]; then
    source /opt/ros/humble/setup.bash
fi

# Source workspace overlay if it exists
if [ -f "$HOME/ws/install/setup.bash" ]; then
    source "$HOME/ws/install/setup.bash"
fi

# ROS 2 defaults
export ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0}
export ROS_LOCALHOST_ONLY=${ROS_LOCALHOST_ONLY:-0}
export RCUTILS_COLORIZED_OUTPUT=1

# Tab-completion for ros2 cli
eval "$(register-python-argcomplete3 ros2 2>/dev/null)" || true
eval "$(register-python-argcomplete3 colcon 2>/dev/null)" || true

# ---------------------------------------------------------------------------
# Prompt
# ---------------------------------------------------------------------------
PS1='\[\033[01;32m\]\u@ros2-imx500\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias cls='clear'

# ROS 2 shortcuts
alias rte='ros2 topic echo'
alias rtl='ros2 topic list'
alias rtf='ros2 topic info'
alias rnl='ros2 node list'
alias rpl='ros2 param list'
alias rsl='ros2 service list'

# colcon build from workspace root
alias cb='cd ~/ws && colcon build --symlink-install && source install/setup.bash && cd -'
alias cbs='cd ~/ws && colcon build --symlink-install --packages-select'

# Camera quick checks
alias cam-list='cam -l 2>/dev/null || echo "cam not found; use: python3 -c \"from picamera2 import Picamera2; print(Picamera2.global_camera_info())\""'
alias cam-info='python3 -c "from picamera2 import Picamera2; print(Picamera2.global_camera_info())"'

# ---------------------------------------------------------------------------
# Convenience functions
# ---------------------------------------------------------------------------
ros2_ws() {
    # Quick workspace build + source
    cd ~/ws && colcon build --symlink-install "$@" && source install/setup.bash
}

# ---------------------------------------------------------------------------
# Library / Python paths (match Dockerfile ENV)
# ---------------------------------------------------------------------------
export PYTHONPATH="/usr/local/lib/python3/dist-packages:/usr/local/lib/aarch64-linux-gnu/python3.10/site-packages:/usr/local/lib/python3.10/dist-packages${PYTHONPATH:+:$PYTHONPATH}"
export LD_LIBRARY_PATH="/usr/local/lib:/usr/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
