#!/usr/bin/env bash
set -euo pipefail
readonly PATH=/usr/bin:/bin
export PATH

mode=${1:-}

case "$mode" in
  read)
    path=$2
    max_bytes=$3
    [[ -e "$path" || -L "$path" ]] || exit 10
    [[ -f "$path" && ! -L "$path" ]] || exit 11
    timeout 2s head -c "$((max_bytes + 1))" -- "$path" || exit 12
    ;;
  commit|restore)
    pending=$2
    primary=$3
    backup=$4
    max_bytes=$5
    state_dir=$(dirname -- "$primary")
    [[ -f "$pending" && ! -L "$pending" ]] || exit 20
    pending_size=$(stat -c %s -- "$pending")
    ((pending_size <= max_bytes)) || exit 21
    sync -f -- "$pending"

    if [[ "$mode" == restore ]]; then
      if [[ -e "$primary" || -L "$primary" ]]; then
        corrupt="${primary}.corrupt.$(date +%s).$$"
        mv -T -- "$primary" "$corrupt"
        sync -f -- "$state_dir"
      fi
    elif [[ -e "$primary" || -L "$primary" ]]; then
      [[ -f "$primary" && ! -L "$primary" ]] || exit 22
      mv -T -f -- "$primary" "$backup"
      sync -f -- "$state_dir"
    fi

    mv -T -f -- "$pending" "$primary"
    sync -f -- "$primary"
    sync -f -- "$state_dir"
    ;;
  *)
    exit 64
    ;;
esac
