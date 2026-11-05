#!/usr/bin/env bash
# PostToolUse hook: run `mix format` on the Elixir file Claude just edited.
file=$(jq -r '.tool_input.file_path // empty')

case "$file" in
  *.ex|*.exs) ;;
  *) exit 0 ;;
esac

[ -f "$file" ] || exit 0

cd "$CLAUDE_PROJECT_DIR" || exit 0

if ! out=$(mix format "$file" 2>&1); then
  echo "mix format failed for $file:" >&2
  echo "$out" >&2
  exit 2
fi
