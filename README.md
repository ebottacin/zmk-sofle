# Eyelash Sofle

## Changelog

Commit summary generated from recent repository history.

### v 1.4.1

- Keymap layout fixes and keymap-drawer updates for cleaner rendered layers.
- Added and integrated `zmk-dynamic-logging`.
- Migrated caps workflow to the event-driven `zmk-caps-lock-events` module.
- Added a custom split sync channel for caps state and fixed split sync label issues.
- Added `zmk-usb-logging` snippet support.
- Improved build scripts and CI stability, including Node 20 warning fixes.
- Refined auto-layer and num-word behavior.
- Improved combos and hold-tap behavior for daily typing/navigation.
- Prepared release updates and keymap iteration.

### v 1.0

- Continued board and keymap refinements.
- Added/updated split and studio support.
- Updated build matrix and core configuration files.

## Keyboard Layout

- SVG layout: [keymap-drawer/eyelash_sofle.svg](keymap-drawer/eyelash_sofle.svg)

<img src="keymap-drawer/eyelash_sofle.svg" alt="Eyelash Sofle keymap" />

## Features and Used Repositories

- ZMK firmware base: [zmkfirmware/zmk](https://github.com/zmkfirmware/zmk)
- Tri-state behavior: [urob/zmk-tri-state](https://github.com/urob/zmk-tri-state)
- Auto-layer and num-word: [urob/zmk-auto-layer](https://github.com/urob/zmk-auto-layer)
- Listener framework: [ssbb/zmk-listeners](https://github.com/ssbb/zmk-listeners)
- Caps lock/caps word events and split sync: [ebottacin/zmk-caps-lock-events](https://github.com/ebottacin/zmk-caps-lock-events)
- Runtime logging controls: [ebottacin/zmk_dynamic-logging](https://github.com/ebottacin/zmk_dynamic-logging)
- Display info widget: [ebottacin/zmk-info-widget](https://github.com/ebottacin/zmk-info-widget)
- Keymap rendering: [caksoylar/keymap-drawer](https://github.com/caksoylar/keymap-drawer)
- Optional host-side utility: [ebottacin/zmk-host-gui](https://github.com/ebottacin/zmk-host-gui)

## Build and Technical Documentation

- See [BUILD.md](BUILD.md) for build scripts, CI matrix, keymap SVG generation, versioning, and USB logging.

