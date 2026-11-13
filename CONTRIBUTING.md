# Contributing to ros2-imx500-rpi5

Thank you for your interest in improving this project!

## Submitting Issues
- Check the [Troubleshooting Guide](docs/troubleshooting.md) first.
- When opening a bug report, please run `./scripts/doctor.sh` and attach the output, along with your kernel version (`uname -r`) and Docker version.

## Development Workflow
1. Fork the repo and create a feature branch (`git checkout -b feature/amazing-feature`).
2. Make your edits and ensure the container builds cleanly (`docker build --target base -t test-build .`).
3. Test camera detection on a physical Raspberry Pi 5.
4. Commit your changes and open a Pull Request.

