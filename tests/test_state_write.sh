#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
writer="$repo_dir/state_write.py"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
state="$test_dir/state.json"

first='{"schemaVersion":1,"storageRevision":1,"nextNewIndex":3,"cards":{},"lastNotificationDate":""}'
/usr/bin/python3 "$writer" commit "$state" "$state.bak" 1024 1 "$(printf '%s\n' "$first" | base64 -w0)"
jq -e '.nextNewIndex == 3' "$state" >/dev/null

if /usr/bin/python3 "$writer" commit "$state" "$state.bak" 1024 2 "$(printf '%s' '{invalid' | base64 -w0)"; then
  echo "Invalid state was accepted" >&2
  exit 1
fi
jq -e '.nextNewIndex == 3' "$state" >/dev/null

oversized=$(head -c 1025 /dev/zero | base64 -w0)
if /usr/bin/python3 "$writer" commit "$state" "$state.bak" 1024 2 "$oversized"; then
  echo "Oversized state was accepted" >&2
  exit 1
fi
jq -e '.nextNewIndex == 3' "$state" >/dev/null

newer='{"schemaVersion":1,"storageRevision":3,"nextNewIndex":4,"cards":{},"lastNotificationDate":""}'
older='{"schemaVersion":1,"storageRevision":2,"nextNewIndex":2,"cards":{},"lastNotificationDate":""}'
/usr/bin/python3 "$writer" commit "$state" "$state.bak" 1024 3 "$(printf '%s\n' "$newer" | base64 -w0)"
/usr/bin/python3 "$writer" commit "$state" "$state.bak" 1024 2 "$(printf '%s\n' "$older" | base64 -w0)"
jq -e '.nextNewIndex == 4' "$state" >/dev/null
jq -e '.nextNewIndex == 3' "$state.bak" >/dev/null

printf 'protected' >"$test_dir/target"
rm -- "$state"
ln -s "$test_dir/target" "$state"
if /usr/bin/python3 "$writer" commit "$state" "$state.bak" 1024 4 "$(printf '%s\n' "$newer" | base64 -w0)"; then
  echo "Symlink state was overwritten" >&2
  exit 1
fi
[[ $(<"$test_dir/target") == protected ]]
rm -- "$state"
/usr/bin/python3 "$writer" commit "$state" "$state.bak" 1024 3 "$(printf '%s\n' "$newer" | base64 -w0)"

/usr/bin/python3 "$writer" delete "$state" "$state.bak" 1024 4
jq -e '.nextNewIndex == 0 and .storageRevision == 4' "$state" >/dev/null
[[ ! -e "$state.bak" ]]

echo "state_write.py: atomic durability tests passed"
