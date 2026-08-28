#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
reader="$repo_dir/state_read.py"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

state="$test_dir/state.json"
head -c 2048 /dev/zero >"$state"
read_bytes=$(/usr/bin/timeout 2s /usr/bin/python3 "$reader" "$state" 1024 | wc -c)
[[ $read_bytes -eq 1025 ]]

mkfifo "$test_dir/fifo"
if /usr/bin/timeout 2s /usr/bin/python3 "$reader" "$test_dir/fifo" 1024 >/dev/null; then
  echo "FIFO state was accepted" >&2
  exit 1
fi

ln -s "$state" "$test_dir/state-link.json"
if /usr/bin/timeout 2s /usr/bin/python3 "$reader" "$test_dir/state-link.json" 1024 >/dev/null; then
  echo "symlink state was accepted" >&2
  exit 1
fi

if /usr/bin/timeout 2s /usr/bin/python3 "$reader" "$test_dir" 1024 >/dev/null; then
  echo "directory state was accepted" >&2
  exit 1
fi

echo "state_read.py: bounded descriptor tests passed"
