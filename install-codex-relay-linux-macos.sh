#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
case "$(uname -s 2>/dev/null || true)" in
  Darwin)
    exec bash "$script_dir/installers/install-codex-relay-macos.sh" "$@"
    ;;
  Linux)
    exec bash "$script_dir/installers/install-codex-relay-linux.sh" "$@"
    ;;
  *)
    printf '[codex-relay] ERROR: unsupported OS: %s\n' "$(uname -s 2>/dev/null || true)" >&2
    exit 1
    ;;
esac
