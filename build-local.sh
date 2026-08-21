#!/usr/bin/env bash

# build-local.sh
#
# Script di build locale per firmware ZMK del progetto eyelash_sofle.
# Replica le build principali definite in build.yaml (GitHub Actions)
# e prepara automaticamente il workspace west.
#
# Prerequisiti Linux (Ubuntu/Debian):
# 1) Pacchetti di sistema:
#    sudo apt update
#    sudo apt install -y \
#      git cmake ninja-build gperf ccache dfu-util device-tree-compiler \
#      wget python3-pip python3-venv xz-utils file make gcc gcc-multilib \
#      g++-multilib libsdl2-dev libmagic1 \
#      curl
#
# 2) Ambiente Python locale (consigliato):
#    python3 -m venv .venv
#    source .venv/bin/activate
#    pip install -U pip west
#
#    Nota compatibilità Python/nanopb:
#    Se in build compare "ModuleNotFoundError: No module named 'pkg_resources'",
#    usa questi comandi nel venv:
#      python3 -m pip uninstall -y setuptools
#      python3 -m pip install 'setuptools<81'
#      python3 -c "import pkg_resources; print(pkg_resources.__file__)"
#
# 3) Scarica e installa Zephyr SDK compatibile (consigliato: v0.16.9 minimal):
#    cd ~
#    wget https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.16.9/zephyr-sdk-0.16.9_linux-x86_64_minimal.tar.xz
#    tar -xf zephyr-sdk-0.16.9_linux-x86_64_minimal.tar.xz
#    cd zephyr-sdk-0.16.9
#    ./setup.sh
#
#    Risposte consigliate durante ./setup.sh:
#    - Install GNU toolchain? y
#    - Install GNU toolchains for all targets? n (se presente)
#    - Select toolchains: arm-zephyr-eabi (se richiesto)
#    - Install LLVM toolchain? n
#    - Install host tools? y
#    - Register Zephyr SDK CMake package? y
#    - Create symbolic links for old Zephyr bisectability? n
#
#    export ZEPHYR_SDK_INSTALL_DIR="$HOME/zephyr-sdk-0.16.9"
#
# 4) Esecuzione dalla root del repository (lo script si auto-posiziona).
#
# Nota toolchain:
# - Questo script usa esclusivamente Zephyr SDK.
# - In assenza dello SDK, la build viene fermata con istruzioni.
#
# Uso:
#   ./build-local.sh [target] [update_mode] [pristine_mode]
#
# Target disponibili:
#   all          Build di tutti i target (default)
#   right        eyelash_sofle_right + nice_view_custom
#   left_studio  eyelash_sofle_left + nice_view + studio-rpc-usb-uart
#   left_reset   eyelash_sofle_left + settings_reset
#
# Update mode disponibili:
#   minimal   west update con fetch ridotto (--narrow --depth=1) [default]
#   full      west update completo
#   no-update salta update/fetch e usa solo sorgenti già presenti in locale
#
# Pristine mode disponibili:
#   no-pristine usa la build incrementale (default)
#   pristine    esegue build pulita con `west build -p always`
#
# Esempi:
#   ./build-local.sh
#   ./build-local.sh right
#   ./build-local.sh left_studio full
#   ./build-local.sh all no-update
#   ./build-local.sh right no-update pristine

set -euo pipefail

# Config opzionale: imposta qui il path dello Zephyr SDK dopo l'installazione.
# Esempio: ZEPHYR_SDK_INSTALL_DIR_DEFAULT="$HOME/zephyr-sdk-0.16.9"
ZEPHYR_SDK_INSTALL_DIR_DEFAULT="$HOME/zephyr-sdk-0.16.9"

TARGET="${1:-all}"
UPDATE_MODE="${2:-no-update}"
PRISTINE_MODE="${3:-no-pristine}"
ARTIFACTS_OUT_DIR="build/artifacts"
ARTIFACT_SOURCES=()
ARTIFACT_DESTS=()

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -d "config" ]] || [[ ! -f "config/west.yml" ]]; then
  echo "Errore: esegui questo script dalla root del repository (cartella zmk-sofle)."
  exit 1
fi

if [[ -z "${VIRTUAL_ENV:-}" ]]; then
  echo "Errore: ambiente virtuale Python non attivo."
  if [[ -d ".venv" ]]; then
    echo "Attiva il venv e rilancia:"
    echo "  source .venv/bin/activate"
  else
    echo "Crea e attiva il venv, poi rilancia:"
    echo "  python3 -m venv .venv"
    echo "  source .venv/bin/activate"
  fi
  exit 1
fi

if ! command -v west >/dev/null 2>&1; then
  echo "Errore: west non trovato."
  echo "Installa prima i prerequisiti:"
  echo "  python3 -m venv .venv && source .venv/bin/activate"
  echo "  pip install -U pip west"
  exit 1
fi

echo "[1/3] Inizializzo/aggiorno workspace west..."
if [[ ! -d ".west" ]]; then
  west init -l config
fi

if [[ "$UPDATE_MODE" == "minimal" ]]; then
  west update --narrow --fetch-opt=--depth=1
elif [[ "$UPDATE_MODE" == "full" ]]; then
  west update
elif [[ "$UPDATE_MODE" == "no-update" ]]; then
  echo "Skip update: uso i sorgenti già presenti localmente."
else
  echo "Errore: update mode non valido: $UPDATE_MODE"
  echo "Uso: ./build-local.sh [all|right|left_studio|left_reset] [minimal|full|no-update] [no-pristine|pristine]"
  exit 1
fi

if [[ "$PRISTINE_MODE" == "pristine" ]]; then
  BUILD_PRISTINE_ARGS=(-p always)
elif [[ "$PRISTINE_MODE" == "no-pristine" ]]; then
  BUILD_PRISTINE_ARGS=()
else
  echo "Errore: pristine mode non valido: $PRISTINE_MODE"
  echo "Uso: ./build-local.sh [all|right|left_studio|left_reset] [minimal|full|no-update] [no-pristine|pristine]"
  exit 1
fi

west zephyr-export

if [[ -f "zephyr/scripts/requirements.txt" ]]; then
  python3 -m pip install -r zephyr/scripts/requirements.txt
fi

if ! python3 -c "import pkg_resources" >/dev/null 2>&1; then
  echo "Errore: pkg_resources non trovato nel venv."
  echo "Esegui:"
  echo "  python3 -m pip uninstall -y setuptools"
  echo "  python3 -m pip install 'setuptools<81'"
  echo "  python3 -c \"import pkg_resources; print(pkg_resources.__file__)\""
  exit 1
fi

configure_toolchain() {
  is_supported_sdk_dir() {
    local sdk_dir="$1"
    local version_file="$sdk_dir/cmake/Zephyr-sdkConfigVersion.cmake"

    [[ -f "$sdk_dir/cmake/Zephyr-sdkConfig.cmake" ]] || return 1

    if [[ -f "$version_file" ]] && grep -Eq 'set\(PACKAGE_VERSION "1\.0\.1"\)' "$version_file"; then
      return 2
    fi

    return 0
  }

  if [[ -n "$ZEPHYR_SDK_INSTALL_DIR_DEFAULT" ]]; then
    export ZEPHYR_SDK_INSTALL_DIR="$ZEPHYR_SDK_INSTALL_DIR_DEFAULT"
  fi

  if [[ -n "${ZEPHYR_SDK_INSTALL_DIR:-}" ]] && [[ -d "${ZEPHYR_SDK_INSTALL_DIR}" ]]; then
    if is_supported_sdk_dir "$ZEPHYR_SDK_INSTALL_DIR"; then
      echo "Toolchain: Zephyr SDK (${ZEPHYR_SDK_INSTALL_DIR})"
      return
    fi

    if [[ $? -eq 2 ]]; then
      echo "Errore: SDK non compatibile in ${ZEPHYR_SDK_INSTALL_DIR} (versione legacy 1.0.1)."
      echo "Installa uno Zephyr SDK moderno (sdk-ng, es. 0.16.x/0.17.x) e aggiorna ZEPHYR_SDK_INSTALL_DIR."
      exit 1
    fi
  fi

  local candidate
  for candidate in $(ls -d "$HOME"/opt/zephyr-sdk-* "$HOME"/zephyr-sdk-* /opt/zephyr-sdk-* 2>/dev/null | sort -V -r); do
    if is_supported_sdk_dir "$candidate"; then
      export ZEPHYR_SDK_INSTALL_DIR="$candidate"
      echo "Toolchain: Zephyr SDK (${ZEPHYR_SDK_INSTALL_DIR})"
      return
    fi
  done

  echo "Errore: Zephyr SDK non trovato (oppure è una versione legacy non compatibile)."
  echo "Installa Zephyr SDK sdk-ng (es. 0.16.x/0.17.x) e riesegui."
  echo "  vedi: https://docs.zephyrproject.org/latest/develop/toolchains/zephyr_sdk.html"
  echo "  poi: export ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk-<versione>"
  exit 1
}

configure_toolchain

register_artifact() {
  ARTIFACT_SOURCES+=("$1")
  ARTIFACT_DESTS+=("$2")
}

copy_artifacts() {
  mkdir -p "$ARTIFACTS_OUT_DIR"

  local index
  for index in "${!ARTIFACT_SOURCES[@]}"; do
    local source_file="${ARTIFACT_SOURCES[$index]}"
    local dest_file="${ARTIFACT_DESTS[$index]}"
    if [[ -f "$source_file" ]]; then
      cp "$source_file" "$ARTIFACTS_OUT_DIR/$dest_file"
      echo "Artifact copiato: $ARTIFACTS_OUT_DIR/$dest_file"
    else
      echo "Attenzione: artifact non trovato: $source_file"
    fi
  done
}

build_right() {
  echo "[2/3] Build right (eyelash_sofle_right + nice_view_custom)..."
  west build "${BUILD_PRISTINE_ARGS[@]}" -s zmk/app -d build/right -b eyelash_sofle_right -- \
    -DSHIELD=nice_view_custom \
    -DBOARD_ROOT="$PWD" \
    -DZMK_CONFIG="$PWD/config"
  register_artifact "build/right/zephyr/zmk.uf2" "eyelash_sofle_right.uf2"
}

build_left_studio() {
  echo "[2/3] Build left studio (eyelash_sofle_left + nice_view + studio snippet)..."
  west build "${BUILD_PRISTINE_ARGS[@]}" -s zmk/app -d build/left_studio -b eyelash_sofle_left -- \
    -DSHIELD=nice_view \
    -DSNIPPET=studio-rpc-usb-uart \
    -DCONFIG_ZMK_STUDIO=y \
    -DCONFIG_ZMK_STUDIO_LOCKING=n \
    -DBOARD_ROOT="$PWD" \
    -DZMK_CONFIG="$PWD/config"
  register_artifact "build/left_studio/zephyr/zmk.uf2" "eyelash_sofle_left_studio.uf2"
}

build_left_reset() {
  echo "[2/3] Build left reset (eyelash_sofle_left + settings_reset)..."
  west build "${BUILD_PRISTINE_ARGS[@]}" -s zmk/app -d build/left_reset -b eyelash_sofle_left -- \
    -DSHIELD=settings_reset \
    -DBOARD_ROOT="$PWD" \
    -DZMK_CONFIG="$PWD/config"
  register_artifact "build/left_reset/zephyr/zmk.uf2" "eyelash_sofle_left_reset.uf2"
}

case "$TARGET" in
  all)
    build_right
    build_left_studio
    build_left_reset
    ;;
  right)
    build_right
    ;;
  left_studio)
    build_left_studio
    ;;
  left_reset)
    build_left_reset
    ;;
  *)
    echo "Uso: ./build-local.sh [all|right|left_studio|left_reset] [minimal|full|no-update] [no-pristine|pristine]"
    exit 1
    ;;
esac

  copy_artifacts

echo "[3/3] Build completata."
echo "Artefatti principali:"
echo "  build/right/zephyr/zmk.uf2"
echo "  build/left_studio/zephyr/zmk.uf2"
echo "  build/left_reset/zephyr/zmk.uf2"
  echo "Artefatti copiati in:"
  echo "  build/artifacts"
