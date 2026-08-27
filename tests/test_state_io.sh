#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_dir/state_io.sh"
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

primary="$test_dir/state.json"
backup="$primary.bak"
pending="$primary.next"

head -c 2048 /dev/zero >"$primary"
read_bytes=$(/usr/bin/bash "$helper" read "$primary" 1024 | wc -c)
[[ $read_bytes -eq 1025 ]]

printf old >"$primary"
printf new >"$pending"
/usr/bin/bash "$helper" commit "$pending" "$primary" "$backup" 1024
[[ $(<"$primary") == new ]]
[[ $(<"$backup") == old ]]

mkdir "$test_dir/backup-target"
rm -- "$backup"
ln -s "$test_dir/backup-target" "$backup"
printf old-again >"$primary"
printf new-again >"$pending"
/usr/bin/bash "$helper" commit "$pending" "$primary" "$backup" 1024
[[ -f "$backup" && ! -L "$backup" ]]
[[ $(<"$backup") == old-again ]]
[[ ! -e "$test_dir/backup-target/state.json" ]]

printf corrupt >"$primary"
printf valid-backup >"$backup"
printf restored >"$pending"
/usr/bin/bash "$helper" restore "$pending" "$primary" "$backup" 1024
[[ $(<"$primary") == restored ]]
[[ $(<"$backup") == valid-backup ]]
corrupt_files=("$test_dir"/state.json.corrupt.*)
[[ ${#corrupt_files[@]} -eq 1 ]]
[[ $(<"${corrupt_files[0]}") == corrupt ]]

printf keep-primary >"$primary"
printf keep-backup >"$backup"
head -c 1025 /dev/zero >"$pending"
if /usr/bin/bash "$helper" commit "$pending" "$primary" "$backup" 1024; then
  echo "oversized pending state was accepted" >&2
  exit 1
fi
[[ $(<"$primary") == keep-primary ]]
[[ $(<"$backup") == keep-backup ]]

mkfifo "$test_dir/fifo"
if /usr/bin/bash "$helper" read "$test_dir/fifo" 1024 >/dev/null; then
  echo "FIFO state was accepted" >&2
  exit 1
fi

echo "state_io.sh: transactional state tests passed"
