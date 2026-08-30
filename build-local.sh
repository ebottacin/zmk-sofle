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
# Uso (solo non posizionale):
#   ./build-local.sh west-update=none pristine=no target=all
#   ./build-local.sh west-update=minimal pristine=yes target=all-with-studio keep=10
#   ./build-local.sh out_dir=/mnt/c/Users/e.bottacin/zmk-sofle-builds name=test_caps
#   ./build-local.sh west-update=none pristine=no target=left_right extras=reattach-custom-modules
#
# Target disponibili:
#   all          Build di right + left + left_reset (default)
#   all-with-studio Build di right + left + left_studio + left_reset
#   right        eyelash_sofle_right + nice_view_infos
#   left         eyelash_sofle_left + nice_view
#   left_right   eyelash_sofle_left + eyelash_sofle_right (left: nice_view, right: nice_view_infos)
#   left_studio  eyelash_sofle_left + nice_view + studio-rpc-usb-uart
#   left_reset   eyelash_sofle_left + settings_reset
#
# Update mode disponibili:
#   minimal   west update con fetch ridotto (--narrow --depth=1)
#   full      west update completo
#   none      salta update/fetch e usa solo sorgenti già presenti in locale [default]
#
# Pristine mode disponibili:
#   no   usa la build incrementale (default)
#   yes  esegue build pulita con `west build -p always`
#
# Extras disponibili (parametro `extras`):
#   reattach-custom-modules    esegue la funzione reattach_custom_modules
#   generate-keymaps-svg       genera YAML/SVG keymap tramite script build-keymaps-svg (solo target all, all-with-studio, left_right)
#
# Esempi:
#   ./build-local.sh west-update=none pristine=no target=all
#   ./build-local.sh west-update=minimal pristine=yes target=all-with-studio keep=10
#   ./build-local.sh out_dir=/mnt/c/Users/e.bottacin/zmk-sofle-builds name=test_caps
#   ./build-local.sh target=left_right extras=reattach-custom-modules
#   ./build-local.sh target=all extras=reattach-custom-modules,generate-keymaps-svg

set -euo pipefail

ZMK_DOCKER_MODE="${ZMK_DOCKER_MODE:-0}"

is_docker_mode() {
  [[ "$ZMK_DOCKER_MODE" == "1" ]]
}

# Config opzionale: imposta qui il path dello Zephyr SDK dopo l'installazione.
# Esempio: ZEPHYR_SDK_INSTALL_DIR_DEFAULT="$HOME/zephyr-sdk-0.16.9"
ZEPHYR_SDK_INSTALL_DIR_DEFAULT="$HOME/zephyr-sdk-0.16.9"

TARGET="all"
UPDATE_MODE="none"
PRISTINE_MODE="no"
ARTIFACTS_ROOT_DEFAULT="/mnt/c/Users/e.bottacin/zmk-sofle-builds"
ARTIFACTS_ROOT_INPUT=""
KEEP_BUILDS="10"
BUILD_NAME=""
ARTIFACTS_OUT_DIR=""
BUILD_TIMESTAMP=""
ARTIFACT_SOURCES=()
ARTIFACT_DESTS=()
BUILD_VERSION_VALUE=""
BUILD_VERSION_CMAKE_ARG=""
EXTRAS=""

if is_docker_mode; then
  ARTIFACTS_ROOT_DEFAULT="/artifacts"
fi

for arg in "$@"; do
  if [[ "$arg" == *=* ]]; then
    key="${arg%%=*}"
    value="${arg#*=}"
    case "$key" in
      west-update)
        UPDATE_MODE="$value"
        ;;
      pristine)
        PRISTINE_MODE="$value"
        ;;
      out_dir)
        ARTIFACTS_ROOT_INPUT="$value"
        ;;
      keep)
        KEEP_BUILDS="$value"
        ;;
      target)
        TARGET="$value"
        ;;
      name)
        BUILD_NAME="$value"
        ;;
      extras)
        EXTRAS="$value"
        ;;
      *)
        echo "Errore: parametro non riconosciuto: $key"
        echo "Parametri validi: west-update, pristine, out_dir, keep, target, name, extras"
        exit 1
        ;;
    esac
  else
    echo "Errore: parametro non valido '$arg'."
    echo "Usa solo argomenti nel formato chiave=valore."
    echo "Esempio: ./build-local.sh west-update=none pristine=no target=all"
    exit 1
  fi
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if is_docker_mode; then
  echo "Modalita Docker attiva (ZMK_DOCKER_MODE=1)"
fi

if [[ ! -d "config" ]] || [[ ! -f "config/west.yml" ]]; then
  echo "Errore: esegui questo script dalla root del repository (cartella zmk-sofle)."
  exit 1
fi

resolve_build_version() {
  local version_from_tag=""
  local version_from_hash=""

  if [[ -n "${BUILD_VERSION_OVERRIDE:-}" ]]; then
    BUILD_VERSION_VALUE="$BUILD_VERSION_OVERRIDE"
    echo "Versione FW da BUILD_VERSION_OVERRIDE: $BUILD_VERSION_VALUE"
    BUILD_VERSION_CMAKE_ARG="-DBUILD_VERSION=$BUILD_VERSION_VALUE"
    return
  fi

  if version_from_tag="$(git describe --tags --exact-match 2>/dev/null)"; then
    BUILD_VERSION_VALUE="$version_from_tag"
    echo "Versione FW da tag HEAD: $BUILD_VERSION_VALUE"
  elif version_from_hash="$(git rev-parse --short=8 HEAD 2>/dev/null)"; then
    BUILD_VERSION_VALUE="$version_from_hash"
    echo "Versione FW da hash commit: $BUILD_VERSION_VALUE"
  else
    BUILD_VERSION_VALUE="unknown"
    echo "Attenzione: impossibile risolvere versione git, uso fallback: $BUILD_VERSION_VALUE"
  fi

  BUILD_VERSION_CMAKE_ARG="-DBUILD_VERSION=$BUILD_VERSION_VALUE"
}

if [[ -z "${VIRTUAL_ENV:-}" ]]; then
  if is_docker_mode; then
    echo "Skip check venv: modalita Docker"
  else
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
fi

if ! command -v west >/dev/null 2>&1; then
  echo "Errore: west non trovato."
  echo "Installa prima i prerequisiti:"
  echo "  python3 -m venv .venv && source .venv/bin/activate"
  echo "  pip install -U pip west"
  exit 1
fi

resolve_build_version

reattach_module_branch_if_detached() {
  local module_dir="$1"
  local remote_name="$2"
  local branch_name="$3"

  if [[ ! -d "$module_dir/.git" ]]; then
    echo "Skip reattach: modulo non trovato o non git repo: $module_dir"
    return 0
  fi

  local current_head
  current_head="$(git -C "$module_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

  if [[ "$current_head" != "HEAD" ]]; then
    return 0
  fi

  echo "Reattach branch per $module_dir: detached HEAD -> $branch_name"

  if ! git -C "$module_dir" fetch "$remote_name" "$branch_name" >/dev/null 2>&1; then
    echo "Attenzione: fetch fallita per $module_dir ($remote_name/$branch_name), lascio detached HEAD"
    return 0
  fi

  if git -C "$module_dir" show-ref --verify --quiet "refs/heads/$branch_name"; then
    git -C "$module_dir" checkout "$branch_name" >/dev/null
    git -C "$module_dir" branch --set-upstream-to="$remote_name/$branch_name" "$branch_name" >/dev/null 2>&1 || true
  else
    git -C "$module_dir" checkout -b "$branch_name" --track "$remote_name/$branch_name" >/dev/null
  fi
}

ensure_module_origin_remote() {
  local module_dir="$1"
  local fallback_remote="$2"

  if [[ ! -d "$module_dir/.git" ]]; then
    echo "Skip origin setup: modulo non trovato o non git repo: $module_dir"
    return 0
  fi

  if git -C "$module_dir" remote get-url origin >/dev/null 2>&1; then
    return 0
  fi

  local origin_url=""
  origin_url="$(git -C "$module_dir" remote get-url "$fallback_remote" 2>/dev/null || true)"

  if [[ -z "$origin_url" ]]; then
    echo "Attenzione: impossibile aggiungere origin in $module_dir (fallback remoto '$fallback_remote' non trovato)"
    return 0
  fi

  git -C "$module_dir" remote add origin "$origin_url"
  echo "Origin aggiunto in $module_dir -> $origin_url"
}

reattach_custom_modules() {
  ensure_module_origin_remote "$PWD/zmk-caps-lock-events" "ebottacin"
  ensure_module_origin_remote "$PWD/zmk-info-widget" "ebottacin"
  reattach_module_branch_if_detached "$PWD/zmk-caps-lock-events" "ebottacin" "main"
  reattach_module_branch_if_detached "$PWD/zmk-info-widget" "ebottacin" "main"
}

is_keymap_svg_target_enabled() {
  case "$TARGET" in
    all|all-with-studio|left_right)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

generate_keymaps_svg() {
  local script_path="$PWD/build-keymaps-svg"

  if ! is_keymap_svg_target_enabled; then
    echo "Skip generate_keymaps-svg: target '$TARGET' non supportato (usa: all, all-with-studio, left_right)."
    return 0
  fi

  if [[ ! -f "$script_path" ]]; then
    echo "Errore: script non trovato: $script_path"
    return 1
  fi

  if [[ ! -x "$script_path" ]]; then
    echo "Errore: script non eseguibile: $script_path"
    echo "Esegui: chmod +x $script_path"
    return 1
  fi

  echo "[extra] Generazione keymap YAML/SVG..."
  "$script_path"
}

echo "[1/3] Inizializzo/aggiorno workspace west..."
if [[ ! -d ".west" ]]; then
  west init -l config
fi

if [[ "$UPDATE_MODE" == "minimal" ]]; then
  west update --narrow --fetch-opt=--depth=1
elif [[ "$UPDATE_MODE" == "full" ]]; then
  west update
elif [[ "$UPDATE_MODE" == "none" ]]; then
  echo "Skip update: uso i sorgenti già presenti localmente."
else
  echo "Errore: update mode non valido: $UPDATE_MODE"
  echo "Uso: ./build-local.sh west-update=[minimal|full|none] pristine=[yes|no] [keep=10] [out_dir=/mnt/c/Users/e.bottacin/zmk-sofle-builds] [extras=reattach-custom-modules,generate-keymaps-svg]"
  exit 1
fi

EXTRAS_NORMALIZED=",${EXTRAS// /,},"
if [[ "$EXTRAS_NORMALIZED" == *",reattach-custom-modules,"* ]]; then
  reattach_custom_modules
else
  echo "Skip reattach_custom_modules (extras=$EXTRAS)"
fi

if [[ "$PRISTINE_MODE" == "yes" ]]; then
  BUILD_PRISTINE_ARGS=(-p always)
elif [[ "$PRISTINE_MODE" == "no" ]]; then
  BUILD_PRISTINE_ARGS=()
else
  echo "Errore: pristine mode non valido: $PRISTINE_MODE"
  echo "Uso: ./build-local.sh west-update=[minimal|full|none] pristine=[yes|no] [keep=10] [out_dir=/mnt/c/Users/e.bottacin/zmk-sofle-builds] [extras=reattach-custom-modules,generate-keymaps-svg]"
  exit 1
fi

west_export_log="$(mktemp)"
if west zephyr-export >"$west_export_log" 2>&1; then
  :
else
  if grep -q 'unknown command "zephyr-export"' "$west_export_log"; then
    echo "Skip zephyr-export: comando non disponibile in questo workspace west."
  else
    cat "$west_export_log"
    rm -f "$west_export_log"
    exit 1
  fi
fi
rm -f "$west_export_log"

if [[ -f "zephyr/scripts/requirements.txt" ]]; then
  if python3 -m pip --version >/dev/null 2>&1; then
    python3 -m pip install -r zephyr/scripts/requirements.txt
  elif is_docker_mode; then
    echo "Attenzione: python3 pip non disponibile nel container, skip install requirements Zephyr."
  else
    echo "Errore: python3 pip non disponibile. Installa pip nel tuo ambiente e rilancia."
    exit 1
  fi
fi

USB_LOG_SNIPPET=""
USB_LOGGING_ENABLED=0
if grep -Eq '^[[:space:]]*CONFIG_ZMK_USB_LOGGING=y[[:space:]]*\r?$' "config/eyelash_sofle.conf"; then
  USB_LOG_SNIPPET="zmk-usb-logging"
  USB_LOGGING_ENABLED=1
  echo "USB logging abilitato: uso snippet zmk-usb-logging"
fi

resolved_snippet_value() {
  local base_snippet="$1"
  if [[ -n "$USB_LOG_SNIPPET" && -n "$base_snippet" ]]; then
    echo "$USB_LOG_SNIPPET;$base_snippet"
  elif [[ -n "$USB_LOG_SNIPPET" ]]; then
    echo "$USB_LOG_SNIPPET"
  elif [[ -n "$base_snippet" ]]; then
    echo "$base_snippet"
  else
    echo ""
  fi
}

ensure_snippet_compatible_build_dir() {
  local build_dir="$1"
  local base_snippet="$2"

  # In pristine mode west already forces a clean configure/build.
  if [[ "$PRISTINE_MODE" == "yes" ]]; then
    return 0
  fi

  local cache_file="$build_dir/CMakeCache.txt"
  if [[ ! -f "$cache_file" ]]; then
    return 0
  fi

  local requested_snippet=""
  local cached_snippet=""

  requested_snippet="$(resolved_snippet_value "$base_snippet")"
  cached_snippet="$(grep -E '^SNIPPET:STRING=' "$cache_file" | head -n1 | cut -d= -f2- || true)"

  if [[ "$cached_snippet" == "$requested_snippet" ]]; then
    return 0
  fi

  echo "Snippet cambiato per $build_dir: '$cached_snippet' -> '$requested_snippet'."
  echo "Pulizia mirata della build directory per evitare cache CMake incoerente."
  rm -rf "$build_dir"
}

if ! python3 -c "import pkg_resources" >/dev/null 2>&1; then
  if is_docker_mode; then
    echo "Skip check pkg_resources: modalita Docker"
  else
    echo "Errore: pkg_resources non trovato nel venv."
    echo "Esegui:"
    echo "  python3 -m pip uninstall -y setuptools"
    echo "  python3 -m pip install 'setuptools<81'"
    echo "  python3 -c \"import pkg_resources; print(pkg_resources.__file__)\""
    exit 1
  fi
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

  if is_docker_mode; then
    if [[ -n "${ZEPHYR_SDK_INSTALL_DIR:-}" ]]; then
      echo "Toolchain: Zephyr SDK (${ZEPHYR_SDK_INSTALL_DIR})"
    else
      echo "Toolchain: modalita Docker (skip probe Zephyr SDK host)"
    fi
    return
  fi

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

detect_windows_home() {
  local windows_home=""

  if command -v wslpath >/dev/null 2>&1 && command -v cmd.exe >/dev/null 2>&1; then
    local windows_home_win
    windows_home_win="$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')"
    if [[ -n "$windows_home_win" ]]; then
      windows_home="$(wslpath "$windows_home_win" 2>/dev/null || true)"
    fi
  fi

  if [[ -z "$windows_home" ]] && [[ -d "/mnt/c/Users/$USER" ]]; then
    windows_home="/mnt/c/Users/$USER"
  fi

  echo "$windows_home"
}

init_artifacts_output_dir() {
  if ! [[ "$KEEP_BUILDS" =~ ^[0-9]+$ ]] || [[ "$KEEP_BUILDS" -lt 1 ]]; then
    echo "Errore: keep_builds deve essere un intero >= 1 (valore attuale: $KEEP_BUILDS)"
    exit 1
  fi

  local artifacts_root="${ARTIFACTS_ROOT_DEFAULT/#\~/$HOME}"
  if [[ -n "$ARTIFACTS_ROOT_INPUT" ]]; then
    artifacts_root="${ARTIFACTS_ROOT_INPUT/#\~/$HOME}"
  fi

  local build_name_suffix=""
  if [[ -n "$BUILD_NAME" ]]; then
    local safe_build_name="${BUILD_NAME//\//_}"
    build_name_suffix="_$safe_build_name"
  fi

  BUILD_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
  ARTIFACTS_OUT_DIR="$artifacts_root/${BUILD_TIMESTAMP}${build_name_suffix}"
  mkdir -p "$ARTIFACTS_OUT_DIR"
}

prune_old_builds() {
  local root_dir
  root_dir="$(dirname "$ARTIFACTS_OUT_DIR")"

  if [[ ! -d "$root_dir" ]]; then
    return
  fi

  mapfile -t build_dirs < <(find "$root_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r)

  local count="${#build_dirs[@]}"
  if (( count <= KEEP_BUILDS )); then
    return
  fi

  local index
  for ((index=KEEP_BUILDS; index<count; index++)); do
    local old_dir="$root_dir/${build_dirs[$index]}"
    rm -rf "$old_dir"
    echo "Build rimossa (retention): $old_dir"
  done
}

copy_artifacts() {
  local legacy_artifacts_dir="$PWD/build/artifacts"

  mkdir -p "$legacy_artifacts_dir"
  find "$legacy_artifacts_dir" -mindepth 1 -maxdepth 1 -type f -delete
  echo "Pulizia artifact legacy completata: $legacy_artifacts_dir"

  local index
  for index in "${!ARTIFACT_SOURCES[@]}"; do
    local source_file="${ARTIFACT_SOURCES[$index]}"
    local dest_file="${ARTIFACT_DESTS[$index]}"
    if [[ -f "$source_file" ]]; then
      cp "$source_file" "$ARTIFACTS_OUT_DIR/$dest_file"
      echo "Artifact copiato: $ARTIFACTS_OUT_DIR/$dest_file"
      cp "$source_file" "$legacy_artifacts_dir/$dest_file"
      echo "Artifact copiato: $legacy_artifacts_dir/$dest_file"
    else
      echo "Attenzione: artifact non trovato: $source_file"
    fi
  done
}

build_right() {
  echo "[2/3] Build right (eyelash_sofle_right + nice_view_infos)..."
  ensure_snippet_compatible_build_dir "build/right" ""
  local snippet_value
  local west_snippet_args=()
  snippet_value="$(resolved_snippet_value "")"
  if [[ -n "$snippet_value" ]]; then
    west_snippet_args=(-S "$snippet_value")
  fi
  west build "${BUILD_PRISTINE_ARGS[@]}" -s zmk/app -d build/right -b eyelash_sofle_right "${west_snippet_args[@]}" -- \
    "$BUILD_VERSION_CMAKE_ARG" \
    -DSHIELD=nice_view_infos \
    -DBOARD_ROOT="$PWD" \
    -DZMK_CONFIG="$PWD/config"
  register_artifact "build/right/zephyr/zmk.uf2" "eyelash_sofle_right.uf2"
}

build_left() {
  echo "[2/3] Build left (eyelash_sofle_left + nice_view)..."
  ensure_snippet_compatible_build_dir "build/left" ""
  local snippet_value
  local west_snippet_args=()
  snippet_value="$(resolved_snippet_value "")"
  if [[ -n "$snippet_value" ]]; then
    west_snippet_args=(-S "$snippet_value")
  fi
  west build "${BUILD_PRISTINE_ARGS[@]}" -s zmk/app -d build/left -b eyelash_sofle_left "${west_snippet_args[@]}" -- \
    "$BUILD_VERSION_CMAKE_ARG" \
    -DSHIELD=nice_view \
    -DBOARD_ROOT="$PWD" \
    -DZMK_CONFIG="$PWD/config"
  register_artifact "build/left/zephyr/zmk.uf2" "eyelash_sofle_left.uf2"
}

build_left_reset() {
  echo "[2/3] Build left reset (eyelash_sofle_left + settings_reset)..."
  ensure_snippet_compatible_build_dir "build/left_reset" ""
  local snippet_value
  local west_snippet_args=()
  snippet_value="$(resolved_snippet_value "")"
  if [[ -n "$snippet_value" ]]; then
    west_snippet_args=(-S "$snippet_value")
  fi
  west build "${BUILD_PRISTINE_ARGS[@]}" -s zmk/app -d build/left_reset -b eyelash_sofle_left "${west_snippet_args[@]}" -- \
    "$BUILD_VERSION_CMAKE_ARG" \
    -DSHIELD=settings_reset \
    -DBOARD_ROOT="$PWD" \
    -DZMK_CONFIG="$PWD/config"
  register_artifact "build/left_reset/zephyr/zmk.uf2" "eyelash_sofle_left_reset.uf2"
}

build_left_studio() {
  echo "[2/3] Build left studio (eyelash_sofle_left + nice_view + studio snippet)..."
  ensure_snippet_compatible_build_dir "build/left_studio" "studio-rpc-usb-uart"
  local snippet_value
  local west_snippet_args=()
  snippet_value="$(resolved_snippet_value "studio-rpc-usb-uart")"
  if [[ -n "$snippet_value" ]]; then
    west_snippet_args=(-S "$snippet_value")
  fi
  west build "${BUILD_PRISTINE_ARGS[@]}" -s zmk/app -d build/left_studio -b eyelash_sofle_left "${west_snippet_args[@]}" -- \
    "$BUILD_VERSION_CMAKE_ARG" \
    -DSHIELD=nice_view \
    -DCONFIG_ZMK_STUDIO=y \
    -DCONFIG_ZMK_STUDIO_LOCKING=n \
    -DBOARD_ROOT="$PWD" \
    -DZMK_CONFIG="$PWD/config"
  register_artifact "build/left_studio/zephyr/zmk.uf2" "eyelash_sofle_left_studio.uf2"
}

case "$TARGET" in
  all)
    build_right
    build_left
    build_left_reset
    ;;
  all-with-studio)
    build_right
    build_left
    build_left_studio
    build_left_reset
    ;;
  right)
    build_right
    ;;
  left)
    build_left
    ;;
  left_right)
    build_left
    build_right
    ;;
  left_studio)
    build_left_studio
    ;;
  left_reset)
    build_left_reset
    ;;
  *)
    echo "Uso: ./build-local.sh west-update=[minimal|full|none] pristine=[yes|no] target=[all|all-with-studio|right|left|left_right|left_studio|left_reset] [keep=10] [out_dir=/mnt/c/Users/e.bottacin/zmk-sofle-builds] [name=<suffix>] [extras=reattach-custom-modules,generate-keymaps-svg]"
    exit 1
    ;;
esac

if [[ "$EXTRAS_NORMALIZED" == *",generate-keymaps-svg,"* ]]; then
  generate_keymaps_svg
else
  echo "Skip generate_keymaps_svg (extras=$EXTRAS)"
fi

  init_artifacts_output_dir
  copy_artifacts
  prune_old_builds

echo "[3/3] Build completata."
echo "Artefatti principali:"
echo "  build/right/zephyr/zmk.uf2"
if [[ "$TARGET" == "all" || "$TARGET" == "left" || "$TARGET" == "all-with-studio" ]]; then
  echo "  build/left/zephyr/zmk.uf2"
fi
if [[ "$TARGET" == "all-with-studio" || "$TARGET" == "left_studio" ]]; then
  echo "  build/left_studio/zephyr/zmk.uf2"
fi
echo "  build/left_reset/zephyr/zmk.uf2"
  echo "Artefatti copiati in:"
  echo "  $ARTIFACTS_OUT_DIR"
