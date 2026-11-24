#!/usr/bin/env bash
# matugen, the same way on every version. matugen 4 asks which colour to use when it
# makes colours from an image (a prompt nobody sees when Tide runs it), and changed
# its JSON output; on 4+ this picks the main colour (--source-color-index 0) and asks
# for the JSON Tide reads (--old-json-output). Older versions get the arguments as is.
#   matugen.sh <matugen arguments...>
args=("$@")
if matugen --help 2>/dev/null | grep -q -- '--source-color-index' || matugen image --help 2>/dev/null | grep -q -- '--source-color-index'; then
    [ "${1:-}" = image ] && args+=(--source-color-index 0)
    for a in "$@"; do [ "$a" = -j ] || [ "$a" = --json ] && { args+=(--old-json-output); break; }; done
fi
exec matugen "${args[@]}"
