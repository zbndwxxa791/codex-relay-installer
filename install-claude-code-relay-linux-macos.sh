#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
case "$(uname -s 2>/dev/null || true)" in
  Darwin)
    exec bash "$script_dir/installers/install-claude-code-relay-macos.sh" "$@"
    ;;
  Linux)
    exec bash "$script_dir/installers/install-claude-code-relay-linux.sh" "$@"
    ;;
  *)
    printf '[claude-relay] ERROR: unsupported OS: %s\n' "$(uname -s 2>/dev/null || true)" >&2
    exit 1
    ;;
esac
