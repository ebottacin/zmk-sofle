# Eyelash Sofle - Local Build and USB Debug Guide

This document describes the current `build-local.sh` options and how to enable and use USB logging.

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
- `target=[all|all-with-studio|right|left|left_studio|left_reset]`
  - `all`: `right + left + left_reset`
  - `all-with-studio`: `right + left_studio + left_reset`
  - `right`: `eyelash_sofle_right + nice_view_infos`
  - `left`: `eyelash_sofle_left + nice_view`
  - `left_studio`: `eyelash_sofle_left + nice_view + studio-rpc-usb-uart`
  - `left_reset`: `eyelash_sofle_left + settings_reset`
- `out_dir=/path/to/output`
  - Root directory where timestamped artifact folders are created
- `keep=<N>`
  - Keep only the latest `N` output folders (retention)
- `name=<suffix>`
  - Optional suffix appended to timestamp folder name

Examples:

- `./build-local.sh west-update=none pristine=no target=all`
- `./build-local.sh west-update=minimal pristine=yes target=all-with-studio keep=10`
- `./build-local.sh out_dir=/mnt/c/Users/<user>/zmk-sofle-builds name=test_caps`

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

- If no output appears, verify you are connected to the central half serial port.
- If a port opens but shows no logs, confirm the flashed firmware was built with `CONFIG_ZMK_USB_LOGGING=y`.
- On Linux, if you get access errors, add your user to `dialout` and re-login.

Alternative Windows commands (same result):

`python -m serial.tools.miniterm COM6 115200`

`py -m serial.tools.miniterm COM6 115200`

## Layouts

<img src="keymap-drawer/eyelash_sofle.svg" >
