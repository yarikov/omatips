#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tips="$repo_dir/tips.json"

jq -e '
  length == 229
  and ([.[].id] | unique | length == 229)
  and all(.[];
    (.id | type == "string" and length > 0)
    and (.category | type == "string" and length > 0)
    and (.title | type == "string" and length > 0)
    and (.description | type == "string" and length > 0)
    and (.shortcut | type == "string" and length > 0)
    and ((.action? // null) == null or
      (.action.kind == "copy" and (.action.text | type == "string" and length > 0)) or
      (.action.kind == "exec"
       and .action.argv[0:3] == ["omarchy-shell", "shell", "summon"]
       and (.action.argv[3] == "omarchy.menu"
            or .action.argv[3] == "omarchy.clipboard"
            or .action.argv[3] == "omarchy.emojis")
       and .action.argv[4] == "{}"
       and (.action.argv | length == 5)))
  )
' "$tips" >/dev/null

echo "tips.json: 229 unique, valid hotkey tips"
