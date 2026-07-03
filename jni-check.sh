#!/usr/bin/env bash
# JNI / .so в процессе Minecraft

set -euo pipefail

echo "=== JNI Check ==="

pid=""
if [[ $# -ge 1 ]]; then
  pid="$1"
else
  pid=$(ps aux | grep java | grep -E 'KnotClient|gameDir|net.minecraft.client.main.Main' | grep -v grep \
    | sort -k6 -rn | head -1 | awk '{print $2}')
fi

if [[ -z "$pid" ]]; then
  echo "[!] Java/Minecraft не найден. Запусти игру."
  exit 1
fi

echo "PID: $pid"
echo "cmdline: $(tr '\0' ' ' < "/proc/$pid/cmdline"; echo)"
echo

echo "{ /proc/fd — jar/so/deleted }"
ls -l "/proc/$pid/fd/" 2>/dev/null | grep -iE '\.jar|\.so|deleted' || echo "(пусто)"
echo

echo "{ /proc/maps — deleted }"
cat "/proc/$pid/maps" 2>/dev/null | grep -E '\.so|\.jar' | grep -i deleted || echo "(пусто)"
echo

echo "{ lsof .so из /tmp и скрытых }"
lsof -p "$pid" 2>/dev/null | grep '\.so' | grep -iE '/tmp/|/home.*/\.' || echo "(пусто)"
echo

echo "{ lsof +L1 deleted }"
lsof +L1 2>/dev/null | grep "$pid" | grep -i deleted || echo "(пусто)"

if ls -l "/proc/$pid/fd/" 2>/dev/null | grep -qi 'deleted.*\.jar\|deleted.*\.so'; then
  echo
  echo "[!] БАН: (deleted) jar/so"
  exit 2
fi

echo
echo "Явных JNI-инжектов не видно (проверь gcore при подозрении)."
