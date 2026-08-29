#!/usr/bin/env bash

# docker-sync-ignored.sh
#
# Sincronizza i file e directory presenti nel container Docker (volume sorgenti)
# che corrispondono alle regole di .gitignore verso l'host Windows.
# Utile ad esempio quando 'west update' nel container scarica o aggiorna moduli/dipendenze.

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
CONTAINER_WORKDIR="${ZMK_DOCKER_WORKDIR:-/workspace/zmk-sofle}"
ZMK_DOCKER_SOURCE_VOLUME="${ZMK_DOCKER_SOURCE_VOLUME:-zmk-sofle-source-cache}"
ZMK_DOCKER_RSYNC_IMAGE="${ZMK_DOCKER_RSYNC_IMAGE:-alpine:3.20}"

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

if [[ ! -d "$SCRIPT_DIR/.git" ]] && ! (command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1); then
  echo "Errore: $SCRIPT_DIR non e' un repository git valido."
  exit 1
fi

repo_mount="$(normalize_host_path "$SCRIPT_DIR")"

echo "[docker-sync-ignored] source volume: $ZMK_DOCKER_SOURCE_VOLUME -> $CONTAINER_WORKDIR"
echo "[docker-sync-ignored] host destination: $repo_mount -> /workspace/zmk-sofle-host"

tmp_sync_entries_file="$(mktemp)"
tmp_sync_entries_mount="$(normalize_host_path "$tmp_sync_entries_file")"
cleanup_sync_temp() {
  rm -f "$tmp_sync_entries_file"
}
trap cleanup_sync_temp EXIT

echo "[docker-sync-ignored] ricavo elenco elementi presenti nel volume Docker..."
container_entries=$(
  run_docker_cmd "$DOCKER_BIN" run --rm \
    -v "$ZMK_DOCKER_SOURCE_VOLUME:$CONTAINER_WORKDIR:ro" \
    -w "$CONTAINER_WORKDIR" \
    "$ZMK_DOCKER_RSYNC_IMAGE" sh -c \
    "find . -mindepth 1 -maxdepth 2 -not -path './.git*' -not -path './build*' -not -path './.zmk-sync*' | sed 's|^\./||'" \
    2>/dev/null || true
)

host_ignored=$(git -C "$SCRIPT_DIR" ls-files -io --exclude-standard --directory 2>/dev/null || true)

# Filtra solo percorsi relativi validi del workspace ed esegue check-ignore
{
  echo "$container_entries"
  echo "$host_ignored"
} | tr -d '\r' | sed 's|/\{1,\}$||' | awk '
  NF && !seen[$0]++ && !/:/ && !/^\// && !/^\.\./ && !/^\.git/ && !/^build/ && !/^\.zmk-sync/
' | { git -C "$SCRIPT_DIR" check-ignore --stdin 2>/dev/null || true; } | tr -d '\r' | sed 's|/\{1,\}$||' | sort -u | awk '
{
  gsub(/\r/, "")
  sub(/\/+$/, "")
  if (!NF) next
  n = split($0, parts, "/")
  prefix = parts[1]
  if (prefix in seen_dirs) {
    next
  }
  is_sub = 0
  for (i = 2; i < n; i++) {
    prefix = prefix "/" parts[i]
    if (prefix in seen_dirs) {
      is_sub = 1
      break
    }
  }
  if (!is_sub) {
    seen_dirs[$0] = 1
    print $0
  }
}' > "$tmp_sync_entries_file"

if [[ ! -s "$tmp_sync_entries_file" ]]; then
  echo "[docker-sync-ignored] Nessun file o directory ignorata da .gitignore trovata nel container."
  exit 0
fi

entry_count="$(wc -l < "$tmp_sync_entries_file" | tr -d ' ')"
echo "[docker-sync-ignored] Trovati $entry_count elementi ignorati da sincronizzare verso l'host:"
while IFS= read -r entry; do
  echo "  - $entry"
done < "$tmp_sync_entries_file"

sync_cmd=(
  "$DOCKER_BIN" run --rm -t
  -v "$repo_mount:/workspace/zmk-sofle-host"
  -v "$ZMK_DOCKER_SOURCE_VOLUME:$CONTAINER_WORKDIR:ro"
  -v "$tmp_sync_entries_mount:/tmp/sync_entries:ro"
  -w "$CONTAINER_WORKDIR"
  "$ZMK_DOCKER_RSYNC_IMAGE" sh -lc
  "apk add --no-cache rsync >/dev/null && while IFS= read -r entry; do [ -z \"\$entry\" ] && continue; src=\"${CONTAINER_WORKDIR}/\$entry\"; dst=\"/workspace/zmk-sofle-host/\$entry\"; if [ -d \"\$src\" ]; then mkdir -p \"\$dst\"; echo \"[docker-sync-ignored] sync dir \$entry\"; rsync -a --delete --info=NAME --exclude='/.git/' --exclude='/.git' --exclude='**/.git/' --exclude='**/.git' \"\$src/\" \"\$dst/\"; elif [ -f \"\$src\" ]; then mkdir -p \"\$(dirname \"\$dst\")\"; echo \"[docker-sync-ignored] sync file \$entry\"; rsync -a --delete --info=NAME \"\$src\" \"\$dst\"; fi; done < /tmp/sync_entries"
)

echo "[docker-sync-ignored] rsync: container volume -> host..."
run_docker_cmd "${sync_cmd[@]}"
echo "[docker-sync-ignored] Sincronizzazione verso host completata con successo."
