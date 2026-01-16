#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template_dir="$script_dir/../template"

target_dir="${1:-}"

if [[ -z "$target_dir" ]]; then
  echo "Usage: $0 <target-dir>" >&2
  exit 1
fi

if command -v rsync >/dev/null 2>&1; then
  rsync -a --exclude '.git' "$template_dir"/ "$target_dir"/
else
  cp -R "$template_dir"/. "$target_dir"/
fi

echo "Synced template into $target_dir"
