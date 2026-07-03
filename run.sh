#!/usr/bin/env bash
# Запуск на ПК подозреваемого — только через curl.
# mods | doomsday | jni [PID] | scan

set -euo pipefail

REMOTE="${LINUX_SS_RAW:-https://raw.githubusercontent.com/greshnobytela-dotcom/linux-ss-scripts/main}"

run() {
  local file="$1"
  shift
  curl -fsSL "$REMOTE/$file" | bash -s -- "$@"
}

case "${1:-}" in
  mods|mod|mod-analyzer)     run mod-analyzer.sh "${@:2}" ;;
  doomsday|doom)             run doomsday-detector.sh "${@:2}" ;;
  jni|jni-check)             run jni-check.sh "${@:2}" ;;
  scan|common|common-dirs)   run common-dirs-scan.sh "${@:2}" ;;
  mem|memory|gcore|strings)  run memory-search.sh "${@:2}" ;;
  inj|injgen)                run injgen.sh "${@:2}" ;;
  *)
    echo "Использование: curl -fsSL URL/run.sh | bash -s -- {mods|doomsday|jni|inj|mem|scan} [PID]"
    exit 1
    ;;
esac
