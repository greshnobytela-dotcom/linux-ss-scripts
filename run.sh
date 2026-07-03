#!/usr/bin/env bash
# Запуск на ПК подозреваемого — только через curl.
# mods | doomsday | jni | inj | browser | downloads | scan

set -euo pipefail

REMOTE="${LINUX_SS_RAW:-https://cdn.jsdelivr.net/gh/greshnobytela-dotcom/linux-ss-scripts@main}"

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
  inj|injgen)                run injgen-linux.sh "${@:2}" ;;
  sys|sysinfo|host)          run sysinfo.sh "${@:2}" ;;
  browser|history|bh)        run browser-history.sh "${@:2}" ;;
  downloads|alldownloads|ad) run all-downloads.sh "${@:2}" ;;
  safemod|sessions|mc-sessions|safe) run safe-mod-detector.sh "${@:2}" ;;
  clean|cleaning|wipe)       run cleaning-detector.sh "${@:2}" ;;
  ss|bypass|dualpc|faker|chameleon) run ss-bypass-detector.sh "${@:2}" ;;
  files|filecheck|fc|fileschecker) run files-checker.sh "${@:2}" ;;
  *)
    echo "Использование: curl -fsSL URL/run.sh | bash -s -- {mods|doomsday|jni|inj|browser|downloads|safemod|clean|ss|files|sys|scan} [args]"
    exit 1
    ;;
esac
