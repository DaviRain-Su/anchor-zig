#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 <target-dir> [project-name]" >&2
  exit 1
fi

target_dir="$1"
project_name="${2:-}"

if [[ -z "$project_name" ]]; then
  "$script_dir/new-anchor-project.sh" "$target_dir"
else
  "$script_dir/new-anchor-project.sh" "$target_dir" "$project_name"
fi

"$script_dir/sync-template.sh" "$target_dir"

echo "Bootstrapped anchor project at $target_dir"
