#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template_dir="$script_dir/../template"

target_dir="${1:-}"
project_name="${2:-}"

if [[ -z "$target_dir" ]]; then
  echo "Usage: $0 <target-dir> [project-name]" >&2
  exit 1
fi

if [[ -z "$project_name" ]]; then
  project_name="$(basename "$target_dir")"
fi

mkdir -p "$target_dir"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --exclude '.git' "$template_dir"/ "$target_dir"/
else
  cp -R "$template_dir"/. "$target_dir"/
fi

zig_name="${project_name//-/_}"
zig_name="${zig_name//./_}"
zig_name="${zig_name// /_}"

if [[ -f "$target_dir/build.zig.zon" ]]; then
  sed -i "s/__PROJECT_NAME__/${zig_name}/g" "$target_dir/build.zig.zon"
fi

if [[ -f "$target_dir/README.md" ]]; then
  sed -i "s/__PROJECT_NAME__/${project_name}/g" "$target_dir/README.md"
fi

echo "Created anchor project at $target_dir"
