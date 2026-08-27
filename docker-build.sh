#!/usr/bin/env bash

# docker-build.sh
#
# Wrapper Docker per eseguire build-local.sh da checkout host.
# Modalita prevista: repository su filesystem host Windows.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DOCKER_BIN="${ZMK_DOCKER_BIN:-docker}"
DOCKER_IMAGE="${ZMK_DOCKER_IMAGE:-zmkfirmware/zmk-build-arm:stable}"
CONTAINER_WORKDIR="${ZMK_DOCKER_WORKDIR:-/workspace/zmk-sofle}"
CONTAINER_OUT_DIR="${ZMK_DOCKER_OUT_DIR:-/artifacts}"
DOCKER_VENV_PATH_DEFAULT="${DOCKER_VENV_PATH:-/opt/venv}"

if ! command -v "$DOCKER_BIN" >/dev/null 2>&1; then
  echo "Errore: comando Docker non trovato: $DOCKER_BIN"
  echo "Installa Docker Desktop oppure imposta ZMK_DOCKER_BIN"
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

# Git Bash su Windows: converte in formato C:/... per Docker Desktop.
if command -v cygpath >/dev/null 2>&1; then
  repo_mount="$(cygpath -m "$repo_mount")"
  out_mount="$(cygpath -m "$out_mount")"
fi

extra_docker_args=()
if [[ -n "${DOCKER_EXTRA_ARGS:-}" ]]; then
  # Splitting intenzionale per passare argomenti multipli, ad esempio: --pull always
  # shellcheck disable=SC2206
  extra_docker_args=( ${DOCKER_EXTRA_ARGS} )
fi

docker_cmd=(
  "$DOCKER_BIN" run --rm -t
  -v "$repo_mount:$CONTAINER_WORKDIR"
  -v "$out_mount:$CONTAINER_OUT_DIR"
  -w "$CONTAINER_WORKDIR"
  -e ZMK_DOCKER_MODE=1
  -e DOCKER_VENV_PATH="$DOCKER_VENV_PATH_DEFAULT"
)

docker_cmd+=("${extra_docker_args[@]}")
docker_cmd+=("$DOCKER_IMAGE" ./build-local.sh)
docker_cmd+=("${forward_args[@]}")
docker_cmd+=("out_dir=$CONTAINER_OUT_DIR")

echo "[docker-build] image: $DOCKER_IMAGE"
echo "[docker-build] repo mount: $repo_mount -> $CONTAINER_WORKDIR"
echo "[docker-build] out mount: $out_mount -> $CONTAINER_OUT_DIR"
printf '[docker-build] cmd:'
printf ' %q' "${docker_cmd[@]}"
printf '\n'

"${docker_cmd[@]}"
