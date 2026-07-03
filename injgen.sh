#!/usr/bin/env bash
# INJGEN Linux — JNI/JVMTI detect (как NotRequiem/InjGen, БЕЗ меню)
# https://github.com/NotRequiem/InjGen

set -uo pipefail

PATTERNS=(
  'DoomsdayClient|com/doomsday|doomsday/client'
  'vape/v4|VapeV4|VapeLite|vapeclient'
  'meteordevelopment|meteor-client|MeteorClient'
  'killaura|KillAura'
  'liquidbounce|LiquidBounce|net/ccbluex/liquidbounce'
  'net/wurstclient|WurstClient'
  'SunsetClient|SlinkyClient|KarmaClient'
)

DETECTS=()

find_pid() {
  local p
  p=$(ps aux | grep '[j]ava' | grep KnotClient | sort -k6 -rn | awk '{print $2}' | head -1)
  [[ -n "$p" ]] && { echo "$p"; return; }
  p=$(ps aux | grep '[j]ava' | grep 'net.minecraft.client.main.Main' | grep -v bootstrap | sort -k6 -rn | awk '{print $2}' | head -1)
  [[ -n "$p" ]] && { echo "$p"; return; }
  ps aux | grep '[j]ava' | grep '\.minecraft' | grep -v bootstrap | sort -k6 -rn | awk '{print $2}' | head -1
}

add_hit() { DETECTS+=("$1"); }

match_patterns() {
  local text="$1" label="$2" p hit
  [[ -z "$text" ]] && return
  for p in "${PATTERNS[@]}"; do
    hit=$(echo "$text" | grep -oiE "$p" | head -1 || true)
    [[ -n "$hit" ]] && add_hit "Known client ($label): $hit"
  done
}

scan_pid() {
  local pid="$1" cmdline agent path t
  DETECTS=()
  cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)

  while IFS= read -r agent; do
    [[ -n "$agent" ]] && add_hit "Java Agent: $agent"
  done < <(echo "$cmdline" | grep -oiE -- '-javaagent:[^ ]+' || true)

  echo "$cmdline" | grep -q -- '-noverify' && add_hit "JVM flag: -noverify"

  while IFS= read -r path; do
    [[ -n "$path" ]] && add_hit "Suspicious JAR (cmdline): $path"
  done < <(echo "$cmdline" | grep -oiE '/tmp/[^ ]+\.jar|[^ ]*\.cache/[^ ]+\.jar' || true)

  match_patterns "$cmdline" "cmdline"

  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    add_hit "Ghost JAR: $t"
    match_patterns "$t" "ghost"
  done < <(
    ls -l "/proc/$pid/fd/" 2>/dev/null | grep '(deleted)' | grep -iE '\.jar' \
      | grep -ivE 'pipewire|memfd|ffi' | awk '{print $NF}' || true
  )

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    add_hit "JNI .so: $(echo "$line" | awk '{print $NF}')"
  done < <(lsof -p "$pid" 2>/dev/null | grep '\.so' | grep -iE '/tmp/|/dev/shm/' || true)

  local -A seen=() u=() h
  for h in "${DETECTS[@]}"; do
    [[ -n "${seen[$h]:-}" ]] && continue
    seen[$h]=1; u+=("$h")
  done
  DETECTS=("${u[@]}")
}

print_result() {
  local pid="$1"
  echo "Reading virtual memory in 'java' process with PID $pid"

  if [[ ${#DETECTS[@]} -eq 0 ]]; then
    echo "[+] No suspicious java agents were loaded in the game instance."
    return 0
  fi

  echo "[!] Generic injection detected."
  echo "Detected:"
  for h in "${DETECTS[@]}"; do
    echo "    → $h"
  done
  return 2
}

usage() {
  echo "INJGEN Linux — bash injgen.sh [PID]"
  echo "https://github.com/NotRequiem/InjGen"
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }

PID=""
[[ $# -ge 1 && "$1" =~ ^[0-9]+$ ]] && PID="$1"
[[ -z "$PID" ]] && PID=$(find_pid || true)

if [[ -z "$PID" ]]; then
  echo "Minecraft Java not detected."
  exit 1
fi

scan_pid "$PID"
print_result "$PID"
exit $?
