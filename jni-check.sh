#!/usr/bin/env bash
# JNI / ghost — только подозрительное (без простыни модов)

set -euo pipefail

echo "=== JNI / Ghost Check ==="

pid=""
if [[ $# -ge 1 ]]; then
  pid="$1"
else
  pid=$(ps aux | grep '[j]ava' | grep KnotClient | awk '{print $2}')
fi

if [[ -z "$pid" ]]; then
  echo "[!] KnotClient не найден. Запусти игру или укажи PID: bash jni-check.sh PID"
  exit 1
fi

echo "PID: $pid"
echo

hits=0
ok()  { echo "[OK] $*"; }
warn(){ echo "[?]  $*"; hits=$((hits + 1)); }
ban() { echo "[!!] $*"; hits=$((hits + 2)); }

echo "--- 1. Ghost jar (deleted + .jar) ---"
ghost=$(
  ls -l "/proc/$pid/fd/" 2>/dev/null \
    | grep '(deleted)' \
    | grep -iE '\.jar|cheat|doomsday' \
    | grep -ivE 'pipewire|memfd|ffi' || true
)
if [[ -z "$ghost" ]]; then ok "deleted jar нет"; else ban "ghost jar в RAM:"; echo "$ghost" | sed 's/^/    /'; fi
echo

echo "--- 2. .so из /tmp (не natives Minecraft) ---"
tmp_so=$(
  lsof -p "$pid" 2>/dev/null | grep '\.so' | grep -iE '/tmp/|/dev/shm/' || true
)
if [[ -z "$tmp_so" ]]; then ok ".so из /tmp нет"; else ban "инжект .so:"; echo "$tmp_so" | sed 's/^/    /'; fi
echo

echo "--- 3. maps: deleted .so НЕ из natives/jre ---"
bad_maps=$(
  cat "/proc/$pid/maps" 2>/dev/null \
    | grep -i deleted \
    | grep '\.so' \
    | grep -ivE '/natives/|java-runtime|/lib/lib(jvm|java|awt|nio)\.so' || true
)
if [[ -z "$bad_maps" ]]; then
  ok "подозрительных deleted .so в maps нет"
  echo "    (deleted в .../natives/libnetty_*.so — это норма MC, не бан)"
else
  ban "deleted .so вне natives/jre:"; echo "$bad_maps" | head -5 | sed 's/^/    /'
fi
echo

echo "--- 4. lsof +L1: deleted jar ---"
lsof_jar=$(
  lsof +L1 2>/dev/null \
    | grep " $pid " \
    | grep -i deleted \
    | grep -iE '\.jar|cheat|doomsday' \
    | grep -ivE 'pipewire|memfd|ffi' || true
)
if [[ -z "$lsof_jar" ]]; then ok "deleted jar в lsof нет"; else ban "ghost в lsof:"; echo "$lsof_jar" | sed 's/^/    /'; fi
echo

echo "--- Игнорируй (норма) ---"
echo "    pipewire-memfd (deleted) — звук"
echo "    /tmp/ffi* (deleted) — JNA temp"
echo "    /tmp/#12345 (deleted) 4KB — JVM temp, не jar"
echo

if [[ $hits -ge 2 ]]; then
  echo "=== ВЕРДИКТ: БАН / жёсткое подозрение ==="
  exit 2
elif [[ $hits -ge 1 ]]; then
  echo "=== ВЕРДИКТ: копать дальше (gcore, шаг 3 cmdline) ==="
  exit 1
else
  echo "=== ВЕРДИКТ: чисто по JNI/ghost ==="
  exit 0
fi
