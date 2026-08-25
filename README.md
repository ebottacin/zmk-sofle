# Eyelash Sofle - Build and USB Debug Guide

English is now the primary documentation language for this repository.

## Changelog

- 2025/03/30: increased sleep timeout to 1 hour, increased debounce time, optimized post-sleep power usage.
- 2024/12/21: added ZMK Studio support (flash the left half only).
- 2024/10/24:
  - changed power mode to reduce consumption.
  - fixed RGB auto power-off behavior.

If your keyboard firmware is older than 2024/10/24, update to the latest firmware.

## Build Script Configuration

Run from repository root:

`./build-local.sh west-update=none pristine=no target=all`

Supported key=value parameters:

- `west-update=[minimal|full|none]`
  - `minimal`: `west update --narrow --fetch-opt=--depth=1`
  - `full`: full `west update`
  - `none`: skip update and use local sources
- `pristine=[yes|no]`
  - `yes`: clean build (`-p always`)
  - `no`: incremental build
- `target=[all|all-with-studio|right|left|left_right|left_studio|left_reset]`
  - `all`: `right + left + left_reset`
  - `all-with-studio`: `right + left_studio + left_reset`
  - `right`: `eyelash_sofle_right + nice_view_infos`
  - `left`: `eyelash_sofle_left + nice_view`
  - `left_right`: `eyelash_sofle_left + nice_view` and `eyelash_sofle_right + nice_view_infos`
  - `left_studio`: `eyelash_sofle_left + nice_view + studio-rpc-usb-uart`
  - `left_reset`: `eyelash_sofle_left + settings_reset`
- `out_dir=/path/to/output`
  - root directory where timestamped artifact folders are created
- `keep=<N>`
  - keep only the latest `N` output folders (retention)
- `name=<suffix>`
  - optional suffix appended to timestamp folder name
- `extras=reattach-custom-modules`
  - reattaches local module branches if they are in detached HEAD

Examples:

- `./build-local.sh west-update=none pristine=no target=all`
- `./build-local.sh west-update=minimal pristine=yes target=all-with-studio keep=10`
- `./build-local.sh out_dir=/mnt/c/Users/<user>/zmk-sofle-builds name=test_caps`

## Firmware Versioning

`BUILD_VERSION` is passed both locally and in CI:

- local build script behavior in `build-local.sh`:
  - if `HEAD` is exactly on a tag, `BUILD_VERSION=<tag>`
  - otherwise, `BUILD_VERSION=<short commit hash>` (8 chars)
- CI build behavior in `build.yaml`:
  - tag builds use `GITHUB_REF_NAME`
  - non-tag builds use short `GITHUB_SHA` (8 chars)

This keeps firmware version display consistent between local and CI artifacts.

## USB Logging (Enable)

Enable USB logging in `config/eyelash_sofle.conf`:

`CONFIG_ZMK_USB_LOGGING=y`

Then rebuild and flash the USB central half (usually left in this project setup).

## USB Logging (Read Logs with Python miniterm)

Install Python serial tools:

`python -m pip install --user pyserial`

List available serial ports:

`python -m serial.tools.list_ports -v`

### Windows host

Find the keyboard port in Device Manager (`Ports (COM & LPT)`) or with:

`python -m serial.tools.list_ports -v`

Then open miniterm on the detected `COMx` port:

`python -m serial.tools.miniterm COM6 115200`

If your Python command is `py`, use:

`py -m serial.tools.miniterm COM6 115200`

### Linux host

Find the device node:

`ls /dev/ttyACM*`

Then open miniterm:

`python3 -m serial.tools.miniterm /dev/ttyACM0 115200`

Exit miniterm:

- `Ctrl+]`

Notes:

- if no output appears, verify you are connected to the central half serial port.
- if a port opens but shows no logs, confirm the flashed firmware was built with `CONFIG_ZMK_USB_LOGGING=y`.
- on Linux, if you get access errors, add your user to `dialout` and re-login.

## Contact

For 3D-print model files or keyboard issues, contact: `380465425@qq.com`

## Layouts

<img src="keymap-drawer/eyelash_sofle.svg" >

## Host GUI (Build + Optional Reset + Optional Flash + Serial Logs)

A host-side GUI is available in the separate repository `zmk-host-gui`.

Repository:

`https://github.com/ebottacin/zmk-host-gui`

Clone it locally:

`git clone https://github.com/ebottacin/zmk-host-gui`

`cd zmk-host-gui`

Install dependencies:

`python -m pip install -r requirements.txt`

Run:

`python main.py`

Behavior in Build tab:

- `Reset 1200 baud` checkbox:
  - enabled: after a successful build, sends a 1200 baud touch-reset on configured COM ports.
  - disabled: no automatic reset is sent.
- `Flash UF2` checkbox:
  - enabled: after build (and optional reset), waits for configured drives and copies only UF2 files that exist in the latest out_dir build folder.
  - disabled: no UF2 copy is performed.

Serial tabs (Left/Right):

- each tab has COM port, baudrate, and log file path fields.
- serial output is shown live and appended to the configured log file path.

Configuration:

- `defaults.json`: base defaults.
- `runtime.json`: values saved from UI (`Save Runtime Config`).

