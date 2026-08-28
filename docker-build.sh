#!/usr/bin/env bash

# docker-build.sh
#
# Wrapper Docker per eseguire build-local.sh da checkout host.
# Modalita prevista: repository su filesystem host Windows.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

detect_wsl() {
  [[ -r /proc/version ]] && grep -qi "microsoft" /proc/version
}

resolve_docker_bin() {
  if [[ -n "${ZMK_DOCKER_BIN:-}" ]]; then
    echo "$ZMK_DOCKER_BIN"
    return
  fi

  if detect_wsl && command -v docker.exe >/dev/null 2>&1; then
    # In WSL prefer Docker Desktop CLI to avoid distro-local Docker mismatches.
    echo "docker.exe"
    return
  fi

  echo "docker"
}

normalize_host_path() {
  local path_value="$1"

  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$path_value"
    return
  fi

  if [[ "$DOCKER_BIN" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
    wslpath -m "$path_value"
    return
  fi

  echo "$path_value"
}

run_docker_cmd() {
  if command -v cygpath >/dev/null 2>&1; then
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$@"
  else
    "$@"
  fi
}

DOCKER_BIN="$(resolve_docker_bin)"
DOCKER_IMAGE="${ZMK_DOCKER_IMAGE:-zmkfirmware/zmk-build-arm:stable}"
CONTAINER_WORKDIR="${ZMK_DOCKER_WORKDIR:-/workspace/zmk-sofle}"
CONTAINER_OUT_DIR="${ZMK_DOCKER_OUT_DIR:-/artifacts}"
DOCKER_VENV_PATH_DEFAULT="${DOCKER_VENV_PATH:-/opt/venv}"
ZMK_DOCKER_BUILD_VOLUME="zmk-sofle-build-cache"
ZMK_DOCKER_SOURCE_VOLUME="${ZMK_DOCKER_SOURCE_VOLUME:-zmk-sofle-source-cache}"
ZMK_DOCKER_RSYNC_IMAGE="${ZMK_DOCKER_RSYNC_IMAGE:-alpine:3.20}"
PULL_RETRIES="${ZMK_DOCKER_PULL_RETRIES:-4}"
PULL_BACKOFF_SECONDS="${ZMK_DOCKER_PULL_BACKOFF_SECONDS:-5}"

pull_image_with_retry() {
  local attempt=1
  local max_attempts="$PULL_RETRIES"

  while (( attempt <= max_attempts )); do
    echo "[docker-build] Pull image attempt ${attempt}/${max_attempts}: $DOCKER_IMAGE"
    if run_docker_cmd "$DOCKER_BIN" pull "$DOCKER_IMAGE"; then
      return 0
    fi

    if (( attempt == max_attempts )); then
      break
    fi

    local wait_time=$(( PULL_BACKOFF_SECONDS * attempt ))
    echo "[docker-build] Pull fallita, retry tra ${wait_time}s..."
    sleep "$wait_time"
    attempt=$((attempt + 1))
  done

  echo "Errore: impossibile scaricare immagine Docker dopo ${max_attempts} tentativi: $DOCKER_IMAGE"
  echo "Suggerimenti:"
  echo "  - Verifica accesso a https://registry-1.docker.io e https://auth.docker.io"
  echo "  - Riprova con VPN/proxy disattivati o DNS diverso"
  echo "  - Esegui: docker login"
  return 1
}

if ! command -v "$DOCKER_BIN" >/dev/null 2>&1; then
  echo "Errore: comando Docker non trovato: $DOCKER_BIN"
  if detect_wsl; then
    echo "In WSL abilita Docker Desktop -> Settings -> Resources -> WSL Integration"
    echo "Oppure imposta ZMK_DOCKER_BIN a un path valido (es. docker.exe)"
  else
    echo "Installa Docker Desktop oppure imposta ZMK_DOCKER_BIN"
  fi
  exit 1
fi

if [[ "${1:-}" == "clean-cache" ]]; then
  echo "[docker-build] clean cache volumes: $ZMK_DOCKER_BUILD_VOLUME, $ZMK_DOCKER_SOURCE_VOLUME"
  failed=0
  if ! run_docker_cmd "$DOCKER_BIN" volume rm -f "$ZMK_DOCKER_BUILD_VOLUME"; then
    echo "[docker-build] warning: build volume removal failed"
    failed=1
  fi
  if ! run_docker_cmd "$DOCKER_BIN" volume rm -f "$ZMK_DOCKER_SOURCE_VOLUME"; then
    echo "[docker-build] warning: source volume removal failed"
    failed=1
  fi

  if (( failed == 0 )); then
    echo "[docker-build] clean cache completata"
    exit 0
  fi
  echo "[docker-build] clean cache fallita"
  exit 1
fi

if [[ ! -x "$SCRIPT_DIR/build-local.sh" ]]; then
  echo "Errore: build-local.sh non trovato o non eseguibile in $SCRIPT_DIR"
  exit 1
fi

forward_args=()
host_out_dir=""

for arg in "$@"; do
  if [[ "$arg" == out_dir=* ]]; then
    host_out_dir="${arg#*=}"
  else
    forward_args+=("$arg")
  fi
done

if [[ -z "$host_out_dir" ]]; then
  host_out_dir="$SCRIPT_DIR/build/docker-artifacts"
fi

mkdir -p "$host_out_dir"

repo_mount="$SCRIPT_DIR"
out_mount="$host_out_dir"

repo_mount="$(normalize_host_path "$repo_mount")"
out_mount="$(normalize_host_path "$out_mount")"

extra_docker_args=()
if [[ -n "${DOCKER_EXTRA_ARGS:-}" ]]; then
  # Splitting intenzionale per passare argomenti multipli, ad esempio: --pull always
  # shellcheck disable=SC2206
  extra_docker_args=( ${DOCKER_EXTRA_ARGS} )
fi

HOST_BUILD_VERSION="unknown"
if command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if host_tag="$(git -C "$SCRIPT_DIR" describe --tags --exact-match 2>/dev/null)"; then
    HOST_BUILD_VERSION="$host_tag"
  elif host_hash="$(git -C "$SCRIPT_DIR" rev-parse --short=8 HEAD 2>/dev/null)"; then
    HOST_BUILD_VERSION="$host_hash"
  fi
fi

docker_cmd=(
  "$DOCKER_BIN" run --rm -t
  -v "$ZMK_DOCKER_SOURCE_VOLUME:$CONTAINER_WORKDIR"
  -v "$ZMK_DOCKER_BUILD_VOLUME:$CONTAINER_WORKDIR/build"
  -v "$out_mount:$CONTAINER_OUT_DIR"
  -w "$CONTAINER_WORKDIR"
  -e ZMK_DOCKER_MODE=1
  -e DOCKER_VENV_PATH="$DOCKER_VENV_PATH_DEFAULT"
  -e BUILD_VERSION_OVERRIDE="$HOST_BUILD_VERSION"
)

docker_cmd+=("${extra_docker_args[@]}")
docker_cmd+=("$DOCKER_IMAGE" ./build-local.sh)
docker_cmd+=("${forward_args[@]}")
docker_cmd+=("out_dir=$CONTAINER_OUT_DIR")

echo "[docker-build] image: $DOCKER_IMAGE"
echo "[docker-build] host repo mount: $repo_mount -> /workspace/zmk-sofle-host (rsync source)"
echo "[docker-build] source volume: $ZMK_DOCKER_SOURCE_VOLUME -> $CONTAINER_WORKDIR (workspace)"
echo "[docker-build] build volume: $ZMK_DOCKER_BUILD_VOLUME -> $CONTAINER_WORKDIR/build"
echo "[docker-build] out mount: $out_mount -> $CONTAINER_OUT_DIR"
printf '[docker-build] cmd:'
printf ' %q' "${docker_cmd[@]}"
printf '\n'

pull_image_with_retry

tmp_sync_entries_file="$(mktemp)"
tmp_sync_entries_mount="$(normalize_host_path "$tmp_sync_entries_file")"
cleanup_sync_temp() {
  rm -f "$tmp_sync_entries_file"
}
trap cleanup_sync_temp EXIT

use_gitignore_sync=0
if command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  {
    git -C "$SCRIPT_DIR" ls-files -co --exclude-standard
  } | awk 'NF && !seen[$0]++' > "$tmp_sync_entries_file"

  if [[ -s "$tmp_sync_entries_file" ]]; then
    use_gitignore_sync=1
    entry_count="$(wc -l < "$tmp_sync_entries_file" | tr -d ' ')"
    echo "[docker-build] sync filter: git/.gitignore entries=$entry_count"
  fi
fi

if (( use_gitignore_sync == 1 )); then
  sync_cmd=(
    "$DOCKER_BIN" run --rm -t
    -v "$repo_mount:/workspace/zmk-sofle-host:ro"
    -v "$ZMK_DOCKER_SOURCE_VOLUME:$CONTAINER_WORKDIR"
    -v "$tmp_sync_entries_mount:/tmp/sync_entries:ro"
    -w "$CONTAINER_WORKDIR"
    "$ZMK_DOCKER_RSYNC_IMAGE" sh -lc
    "apk add --no-cache rsync >/dev/null && sync_state_file=${CONTAINER_WORKDIR}/.zmk-sync-entries && [ -d \"\$sync_state_file\" ] && rm -rf \"\$sync_state_file\" || true && touch \"\$sync_state_file\" && while IFS= read -r old_entry; do [ -z \"\$old_entry\" ] && continue; if ! grep -Fxq \"\$old_entry\" /tmp/sync_entries; then echo \"[docker-build] sync: remove stale \$old_entry\"; rm -rf \"${CONTAINER_WORKDIR}/\$old_entry\"; fi; done < \"\$sync_state_file\" && while IFS= read -r entry; do [ -z \"\$entry\" ] && continue; src=\"/workspace/zmk-sofle-host/\$entry\"; dst=\"${CONTAINER_WORKDIR}/\$entry\"; if [ -d \"\$src\" ]; then mkdir -p \"\$dst\"; echo \"[docker-build] sync: rsync dir \$entry\"; dir_sync_start=\$(date +%s); rsync -a --delete --info=NAME --exclude='/.git/' --exclude='/.git' --exclude='**/.git/' --exclude='**/.git' \"\$src/\" \"\$dst/\"; dir_sync_end=\$(date +%s); echo \"[docker-build] sync: rsync dir \$entry done in \$((dir_sync_end - dir_sync_start))s\"; elif [ -f \"\$src\" ]; then mkdir -p \"\$(dirname \"\$dst\")\"; echo \"[docker-build] sync: rsync file \$entry\"; rsync -a --delete --info=NAME \"\$src\" \"\$dst\"; fi; done < /tmp/sync_entries && cat /tmp/sync_entries > \"\$sync_state_file\""
  )
else
  sync_cmd=(
    "$DOCKER_BIN" run --rm -t
    -v "$repo_mount:/workspace/zmk-sofle-host:ro"
    -v "$ZMK_DOCKER_SOURCE_VOLUME:$CONTAINER_WORKDIR"
    -w "$CONTAINER_WORKDIR"
    "$ZMK_DOCKER_RSYNC_IMAGE" sh -lc
    "apk add --no-cache rsync >/dev/null && rsync -a --delete --info=NAME /workspace/zmk-sofle-host/ ${CONTAINER_WORKDIR}/"
  )
fi

echo "[docker-build] rsync image: $ZMK_DOCKER_RSYNC_IMAGE"
echo "[docker-build] sync: rsync host -> source volume"
run_docker_cmd "${sync_cmd[@]}"

run_docker_cmd "${docker_cmd[@]}"
