# Eyelash Sofle

## Changelog


### v1.6.0

- Added the L0 backlight toggle, implemented through the generic status selector module.
- Updated keymap-drawer configuration and the rendered keymap layout.

### v1.5.2

- Added Compose support to `zmk-info-widget`.

### v1.5.1

- Improved extended-character handling with WinCompose macros.

### v1.5.0

- Added Docker build support, image-pull caching, and the related build-script workflow.
- Added the `zmk-usb-logging` snippet and improved local build scripts.
- Fixed Node 20 warnings in CI.
- Refined keymap-drawer configuration, generated layout, and documentation.
- Updated the custom character configuration to use vowel-only handling.

### v1.4.1

- Corrected keymap-drawer configuration.

### v1.4.0

- Added and integrated `zmk-dynamic-logging` runtime controls.

### v 1.0

- Continued board and keymap refinements.
- Added/updated split and studio support.
- Updated build matrix and core configuration files.

## Keyboard Layout

- SVG layout: [keymap-drawer/eyelash_sofle.svg](keymap-drawer/eyelash_sofle.svg)

<img src="keymap-drawer/eyelash_sofle.svg" alt="Eyelash Sofle keymap" />

## Features and Used Repositories

- Tri-state behavior: [urob/zmk-tri-state](https://github.com/urob/zmk-tri-state)
- Auto-layer and num-word: [urob/zmk-auto-layer](https://github.com/urob/zmk-auto-layer)
- Listener framework: [ssbb/zmk-listeners](https://github.com/ssbb/zmk-listeners)
- Caps lock/caps word events and split sync: [ebottacin/zmk-caps-lock-events](https://github.com/ebottacin/zmk-caps-lock-events)
- Runtime logging controls: [ebottacin/zmk_dynamic-logging](https://github.com/ebottacin/zmk_dynamic-logging)
- Display info widget: [ebottacin/zmk-info-widget](https://github.com/ebottacin/zmk-info-widget)
- Generic status selector: [ebottacin/zmk-status-selector](https://github.com/ebottacin/zmk-status-selector)

- Optional host-side utility: [ebottacin/zmk-host-gui](https://github.com/ebottacin/zmk-host-gui)

## Build and Technical Documentation

- See [BUILD.md](BUILD.md) for build scripts, CI matrix, keymap SVG generation, versioning, and USB logging.

