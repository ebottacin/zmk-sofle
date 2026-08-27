# Build and Technical Guide

This page contains all technical build and debug details for the Eyelash Sofle firmware.

## Local Build Script

Run from repository root:

```bash
./build-local.sh west-update=none pristine=no target=all
```

## Docker Build Script

Run from repository root:

```bash
./docker-build.sh west-update=none pristine=no target=left_right out_dir=C:/Users/<user>/zmk-sofle-builds
```

Docker mode details:

- Uses image `zmkfirmware/zmk-build-arm:stable` by default
- Mounts repo root into container workdir `/workspace/zmk-sofle`
- Mounts the provided host `out_dir` to `/artifacts` in container
- Executes `build-local.sh` inside container with `ZMK_DOCKER_MODE=1`
- Accepts optional extra Docker args through env var `DOCKER_EXTRA_ARGS`

Examples:

```bash
./docker-build.sh west-update=none pristine=no target=left_right out_dir=C:/Users/<user>/zmk-sofle-builds
DOCKER_EXTRA_ARGS="--pull always" ./docker-build.sh west-update=minimal pristine=yes target=all-with-studio out_dir=C:/Users/<user>/zmk-sofle-builds
DOCKER_EXTRA_ARGS="--pull always" ./docker-build.sh west-update=none pristine=no target=all extras=generate-keymaps-svg out_dir=C:/Users/<user>/zmk-sofle-builds
```

Supported parameters:

- `west-update=[minimal|full|none]`
  - `minimal`: runs `west update --narrow --fetch-opt=--depth=1`
  - `full`: runs full `west update`
  - `none`: skips update and uses local sources
- `pristine=[yes|no]`
  - `yes`: clean build (`-p always`)
  - `no`: incremental build
- `target=[all|all-with-studio|right|left|left_right|left_studio|left_reset]`
  - `all`: right + left + left_reset
  - `all-with-studio`: right + left_studio + left_reset
  - `right`: `eyelash_sofle_right` + `nice_view_infos`
  - `left`: `eyelash_sofle_left` + `nice_view`
  - `left_right`: left + right
  - `left_studio`: left + `studio-rpc-usb-uart`
  - `left_reset`: `settings_reset`
- `out_dir=/path/to/output`
  - destination root for timestamped artifact folders
- `keep=<N>`
  - keeps only the most recent `N` build folders
- `name=<suffix>`
  - optional suffix appended to build folder name
- `extras=reattach-custom-modules,generate-keymaps-svg`
  - `reattach-custom-modules`: checks out local custom modules from detached HEAD after west updates
  - `generate-keymaps-svg`: generates keymap-drawer YAML/SVG outputs

Examples:

```bash
./build-local.sh west-update=none pristine=no target=all
./build-local.sh west-update=minimal pristine=yes target=all-with-studio keep=10
./build-local.sh out_dir=/mnt/c/Users/<user>/zmk-sofle-builds name=test_caps
./build-local.sh west-update=none pristine=no target=all extras=generate-keymaps-svg
```

## CI Build Matrix

Defined in [build.yaml](build.yaml):

- Left half (`nice_view`) with USB logging snippet
- Right half (`nice_view_infos`) with USB logging snippet
- Left Studio build with `studio-rpc-usb-uart`
- Left reset build (`settings_reset`)

## Keymap SVG Generation

Standalone command:

```bash
./build-keymaps-svg
```

Pipeline:

- Parses each `config/*.keymap` to `keymap-drawer/<name>.yaml`
- Renders each YAML to `keymap-drawer/<name>.svg`
- Uses `keymap_drawer.config.yaml`

Requirement:

- `keymap` CLI from `keymap-drawer` must be available in your active environment
- In Docker mode, you can set `DOCKER_VENV_PATH` to point to a venv containing `keymap`

## Firmware Versioning

`BUILD_VERSION` is injected both locally and in CI.

- Local (`build-local.sh`):
  - exact tag on `HEAD` -> `<tag>`
  - otherwise -> short commit hash (8 chars)
- CI (`build.yaml`):
  - tag build -> `GITHUB_REF_NAME`
  - non-tag build -> short `GITHUB_SHA` (8 chars)

## USB Logging

Enable in [config/eyelash_sofle.conf](config/eyelash_sofle.conf):

```conf
CONFIG_ZMK_USB_LOGGING=y
```

Rebuild and flash the USB central half (typically the left half).

Read logs with `pyserial`:

```bash
python -m pip install --user pyserial
python -m serial.tools.list_ports -v
```

Windows example:

```bash
python -m serial.tools.miniterm COM6 115200
```

Linux example:

```bash
python3 -m serial.tools.miniterm /dev/ttyACM0 115200
```

Exit miniterm with `Ctrl+]`.

## Optional Host GUI

Repository: [ebottacin/zmk-host-gui](https://github.com/ebottacin/zmk-host-gui)

Quick start:

```bash
git clone https://github.com/ebottacin/zmk-host-gui
cd zmk-host-gui
python -m pip install -r requirements.txt
python main.py
```

The GUI supports build execution, optional 1200-baud reset, optional UF2 copy/flash, and serial log capture.