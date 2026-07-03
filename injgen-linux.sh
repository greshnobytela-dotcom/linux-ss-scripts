#!/usr/bin/env bash
# INJGEN Linux — JNI/JVMTI inject (как NotRequiem/InjGen)
# Whitelist: Lunar, Feather, LabyMod, Fabric/Forge mods (не JNI)
# Detect: ghost jar, /tmp inject, javaagent вне легит путей, чит-классы
# https://github.com/NotRequiem/InjGen

set -uo pipefail

# Только явные чит-клиенты (классы/пакеты), не слова типа rise/flux
CHEAT_SIGS=(
  'DoomsdayClient|com/doomsday|doomsday/client'
  'vape/v4|VapeV4|VapeLite|vapeclient'
  'meteordevelopment|meteor-client|MeteorClient'
  'killaura|KillAura'
  'liquidbounce|LiquidBounce|net/ccbluex/liquidbounce'
  'net/wurstclient|WurstClient'
  'SunsetClient|SlinkyClient|KarmaClient'
  'EntropyClient|DreamClient|DripClient'
)

DETECTS=()
CLIENT_LABEL=""

find_pid() {
  local p
  p=$(ps aux | grep '[j]ava' | grep KnotClient | sort -k6 -rn | awk '{print $2}' | head -1)
  [[ -n "$p" ]] && { echo "$p"; return; }
  p=$(ps aux | grep '[j]ava' | grep 'net.minecraft.client.main.Main' | grep -v bootstrap | sort -k6 -rn | awk '{print $2}' | head -1)
  [[ -n "$p" ]] && { echo "$p"; return; }
  ps aux | grep '[j]ava' | grep '\.minecraft' | grep -v bootstrap | sort -k6 -rn | awk '{print $2}' | head -1
}

add_hit() { DETECTS+=("$1"); }

# Lunar / Feather / LabyMod — как в README InjGen (не false positive)
detect_client() {
  local cmd="$1"
  if echo "$cmd" | grep -qiE 'lunarclient|lunar/client|\.lunarclient'; then
    CLIENT_LABEL="Lunar Client (whitelisted)"; return 0
  fi
  if echo "$cmd" | grep -qiE 'featherclient|feather/client|feathermc'; then
    CLIENT_LABEL="Feather Client (whitelisted)"; return 0
  fi
  if echo "$cmd" | grep -qiE 'labymod|laby/mod'; then
    CLIENT_LABEL="LabyMod (whitelisted)"; return 0
  fi
  if echo "$cmd" | grep -qiE 'KnotClient|fabric-loader|forge'; then
    CLIENT_LABEL="Fabric/Forge (normal mods OK)"; return 0
  fi
  CLIENT_LABEL="java"
  return 1
}

is_suspicious_path() {
  local p="$1"
  echo "$p" | grep -qiE '/tmp/|/dev/shm/|/run/user/[^/]+/[^/]*\.jar' && return 0
  echo "$p" | grep -qiE '\.cache/' && ! echo "$p" | grep -qiE '\.minecraft' && return 0
  echo "$p" | grep -qiE 'cheat|doomsday|vape|inject|ghost|hack' && return 0
  return 1
}

is_legit_javaagent() {
  local agent="$1"
  local path="${agent#-javaagent:}"
  path="${path%=*}"
  # легит: .minecraft, лаунчеры, jvm — не инжект поверх
  if echo "$path" | grep -qiE '/\.minecraft/|lunarclient|feather|labymod|legacylauncher|tlauncher|multimc|prismlauncher|/usr/lib/jvm|java-runtime'; then
    return 0
  fi
  is_suspicious_path "$path" && return 1
  # неизвестный agent вне .minecraft — подозрительно
  [[ "$path" == /* ]] && return 1
  return 0
}

match_cheat_in() {
  local text="$1" label="$2" p hit
  [[ -z "$text" ]] && return
  for p in "${CHEAT_SIGS[@]}"; do
    hit=$(echo "$text" | grep -oiE "$p" | head -1 || true)
    [[ -n "$hit" ]] && add_hit "Cheat signature ($label): $hit"
  done
}

scan_pid() {
  local pid="$1" cmdline agent path t whitelisted=0
  DETECTS=()
  CLIENT_LABEL=""
  cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)

  detect_client "$cmdline" && whitelisted=1

  # --- 1. Ghost JAR (главный признак ghost/inject) — всегда, даже на whitelist ---
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    add_hit "Ghost JAR (inject): $t"
    match_cheat_in "$t" "ghost"
  done < <(
    ls -l "/proc/$pid/fd/" 2>/dev/null | grep '(deleted)' | grep -iE '\.jar' \
      | grep -ivE 'pipewire|memfd|ffi' | awk '{print $NF}' || true
  )

  # --- 2. JNI .so из /tmp (инжект native) ---
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    add_hit "JNI inject (.so): $(echo "$line" | awk '{print $NF}')"
  done < <(lsof -p "$pid" 2>/dev/null | grep '\.so' | grep -iE '/tmp/|/dev/shm/' || true)

  # --- 3. javaagent только если НЕ легит путь ---
  while IFS= read -r agent; do
    [[ -z "$agent" ]] && continue
    if ! is_legit_javaagent "$agent"; then
      add_hit "Java Agent (inject): $agent"
    fi
  done < <(echo "$cmdline" | grep -oiE -- '-javaagent:[^ ]+' || true)

  # --- 4. jar в cmdline только /tmp .cache вне mc ---
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    is_suspicious_path "$path" && add_hit "Suspicious JAR (cmdline): $path"
  done < <(echo "$cmdline" | grep -oiE '/[^ ]+\.jar' || true)

  # --- 5. noverify ТОЛЬКО вместе с другим или на подозрительном agent ---
  if echo "$cmdline" | grep -q -- '-noverify'; then
    if [[ ${#DETECTS[@]} -gt 0 ]]; then
      add_hit "JVM flag: -noverify (with inject signals)"
    elif [[ $whitelisted -eq 0 ]]; then
      : # solo noverify на fabric — не бан (часто лаунчеры)
    fi
  fi

  # --- 6. сигнатуры читов — только в подозрительных путях, НЕ весь cmdline ---
  if [[ $whitelisted -eq 0 ]]; then
    # vanilla/unknown: ищем cheat sig только в /tmp/.cache путях из cmdline
    while IFS= read -r path; do
      is_suspicious_path "$path" && match_cheat_in "$path" "path"
    done < <(echo "$cmdline" | grep -oiE '/[^ ]+\.jar' || true)
  fi

  # dedupe
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
  [[ -n "$CLIENT_LABEL" ]] && echo "Client:       $CLIENT_LABEL"

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

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && {
  cat <<'EOF'
INJGEN Linux — bash injgen-linux.sh [PID]

Whitelist (не false): Lunar, Feather, LabyMod, Fabric/Forge mods
Detect: ghost jar, /tmp .so, javaagent inject, cheat in /tmp
EOF
  exit 0
}

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
