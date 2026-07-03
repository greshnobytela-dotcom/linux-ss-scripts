#!/usr/bin/env bash
# Обёртка: --quick / --deep без меню; иначе → injgen

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--quick" || "${1:-}" == "-q" ]]; then
  shift
  exec bash "$DIR/injgen.sh" --quick "$@"
elif [[ "${1:-}" == "--deep" || "${1:-}" == "-d" ]]; then
  shift
  exec bash "$DIR/injgen.sh" --deep "$@"
else
  exec bash "$DIR/injgen.sh" "$@"
fi
