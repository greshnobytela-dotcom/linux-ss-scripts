#!/usr/bin/env bash
# INJGEN Linux — JNI/JVMTI inject (как NotRequiem/InjGen)
# Whitelist: Lunar, Feather, LabyMod, Fabric/Forge mods (не JNI)
# Detect: ghost jar, /tmp inject, javaagent, чит-клиенты, inject-софт
# https://github.com/NotRequiem/InjGen

set -uo pipefail

# --- Ghost / internal чит-клиенты (классы, jar, пакеты) ---
CHEAT_SIGS=(
  'DoomsdayClient|com/doomsday|doomsday/client|\.doomsday'
  'vape/v4|VapeV4|VapeLite|vapeclient|\.vape|com/vape|vape\.gg'
  'meteordevelopment|meteor-client|MeteorClient|meteorclient'
  'killaura|KillAura|TriggerBot|AutoCrystal|AutoTotem'
  'liquidbounce|LiquidBounce|net/ccbluex/liquidbounce'
  'net/wurstclient|WurstClient|wurstplus'
  'SunsetClient|SlinkyClient|KarmaClient|EntropyClient|DreamClient|DripClient'
  'FDPClient|fdpclient|FDP\.|github\.io/fdp'
  'Aristois|aristois|AristoisClient'
  'RiseClient|riseclient|rise/client'
  'Novoline|novoline|NovolineClient'
  'Onetap|onetap|OneTapClient'
  'Manthe|MantheClient|manthe'
  'ImpactClient|impact/client|SelfDestruct'
  'PhobosClient|phobos|KomatClient|komat'
  'ThunderHack|thunderhack|BleachHack|bleachhack'
  'FutureClient|future/client|SalHack|salhack'
  'XuluClient|xulu|AstolfoClient|astolfo'
  'ExosWare|exosware|GrimClient|grim.?client'
  'SigmaClient|sigma5|MoonClient|moonclient|ZeroDay|zeroday'
  'SystemDLC|SystemClient|RemixClient|fluxclient'
  'WexSide|wexside|Minced|minced|Expensive|expensiveclient'
  'Skid|skidfest|skid\.|SkidClient'
)

# --- Inject / agent / native (только подозрительные пути) ---
INJECT_SIGS=(
  'javaagent:|agentlib:|JVMTI|JNativeHook|jniinject|libinject'
  'Agent-Class|Premain-Class|agentmain|Can-Redefine-Classes'
  'com/sun/jna/z/Main|jna/platform|bytebuddy|instrumentation'
  'org/objectweb/asm|net/bytebuddy|Attach API'
  'Cortex|SystemDLC|injector|InjectClient|GhostInject'
  'hex.?agent|dropper|loader\.jar'
)

# --- IP чит-auth / CDN (из протокола + публичные диапазоны) ---
CHEAT_IP_RE='165\.22\.|167\.172\.|144\.217\.|45\.142\.|185\.234\.'

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
  echo "$p" | grep -qiE 'cheat|doomsday|vape|inject|ghost|hack|manthe|aristois|fdp|rise|novoline|onetap|meteor|liquidbounce|wurst|thunderhack|bleachhack|impact|phobos|sigma|grim|skid' && return 0
  # Vape Lite hex dropper: /tmp/a3f9b2c1.jar
  echo "$p" | grep -qiE '/[a-f0-9]{6,12}\.jar' && return 0
  return 1
}

is_legit_javaagent() {
  local agent="$1"
  local path="${agent#-javaagent:}"
  path="${path%=*}"
  if echo "$path" | grep -qiE '/\.minecraft/|lunarclient|feather|labymod|legacylauncher|tlauncher|multimc|prismlauncher|/usr/lib/jvm|java-runtime|\.tlauncher|\.local/share/Trash'; then
    return 0
  fi
  is_suspicious_path "$path" && return 1
  [[ "$path" == /* ]] && return 1
  return 0
}

match_sigs_in() {
  local text="$1" label="$2" arr=("${@:3}") p hit
  [[ -z "$text" ]] && return
  for p in "${arr[@]}"; do
    hit=$(echo "$text" | grep -oiE "$p" | head -1 || true)
    [[ -n "$hit" ]] && add_hit "$label: $hit"
  done
}

match_cheat_in() { match_sigs_in "$1" "Cheat signature ($2)" "${CHEAT_SIGS[@]}"; }
match_inject_in() { match_sigs_in "$1" "Inject signature ($2)" "${INJECT_SIGS[@]}"; }

scan_pid() {
  local pid="$1" cmdline agent path t maps whitelisted=0
  DETECTS=()
  CLIENT_LABEL=""
  cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
  maps=$(cat "/proc/$pid/maps" 2>/dev/null || true)

  detect_client "$cmdline" && whitelisted=1

  # --- 1. Ghost JAR ---
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    add_hit "Ghost JAR (inject): $t"
    match_cheat_in "$t" "ghost"
    match_inject_in "$t" "ghost"
  done < <(
    ls -l "/proc/$pid/fd/" 2>/dev/null | grep '(deleted)' | grep -iE '\.jar' \
      | grep -ivE 'pipewire|memfd|ffi' | awk '{print $NF}' || true
  )

  # --- 2. JNI .so из /tmp ---
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    add_hit "JNI inject (.so): $(echo "$line" | awk '{print $NF}')"
  done < <(lsof -p "$pid" 2>/dev/null | grep '\.so' | grep -iE '/tmp/|/dev/shm/' || true)

  # --- 3. javaagent / agentlib ---
  while IFS= read -r agent; do
    [[ -z "$agent" ]] && continue
    if ! is_legit_javaagent "$agent"; then
      add_hit "Java Agent (inject): $agent"
      match_cheat_in "$agent" "agent"
      match_inject_in "$agent" "agent"
    fi
  done < <(echo "$cmdline" | grep -oiE -- '-javaagent:[^ ]+|-agentlib:[^ ]+' || true)

  # --- 4. jar в cmdline — подозрительные пути + hex dropper ---
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if is_suspicious_path "$path"; then
      add_hit "Suspicious JAR (cmdline): $path"
      match_cheat_in "$path" "path"
      match_inject_in "$path" "path"
    fi
  done < <(echo "$cmdline" | grep -oiE '/[^ ]+\.jar' || true)

  # --- 5. maps: jar/so из /tmp (не pipewire/memfd) ---
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line" | grep -qiE 'pipewire|memfd|ffi|jvm|libjvm|\.minecraft' && continue
    echo "$line" | grep -qiE '/tmp/|/dev/shm/' || continue
    echo "$line" | grep -qiE '\.jar|\.so' || continue
    path=$(echo "$line" | awk '{print $(NF-1)}')
    [[ "$path" == "(deleted)" ]] && path=$(echo "$line" | awk '{print $(NF-2)}')
    [[ -z "$path" || "$path" == "(deleted)" ]] && continue
    add_hit "Memory map (inject): $path"
  done < <(echo "$maps" | grep -iE '\.jar|\.so' || true)

  # --- 6. IP чит-серверов в cmdline/maps (редко, но бывает) ---
  if echo "$cmdline $maps" | grep -qiE "$CHEAT_IP_RE"; then
    hit=$(echo "$cmdline $maps" | grep -oiE "$CHEAT_IP_RE[0-9]{1,3}(\.[0-9]{1,3}){0,3}" | head -3 | tr '\n' ' ')
    [[ -n "$hit" ]] && add_hit "Cheat server IP in process: $hit"
  fi

  # --- 7. -noverify только с другими сигналами ---
  if echo "$cmdline" | grep -q -- '-noverify'; then
    [[ ${#DETECTS[@]} -gt 0 ]] && add_hit "JVM flag: -noverify (with inject signals)"
  fi

  # --- 8. Xbootclasspath / dynamic agent (inject loaders) ---
  while IFS= read -r flag; do
    [[ -z "$flag" ]] && continue
    is_suspicious_path "$flag" && add_hit "JVM inject flag: $flag"
  done < <(echo "$cmdline" | grep -oiE -- '-Xbootclasspath/a:[^ ]+|-XX:\+EnableDynamicAgentLoading' || true)

  # --- 9. cheat/inject sig в maps (только /tmp, deleted, вне .minecraft) ---
  if [[ -n "$maps" ]]; then
    local suspicious_maps
    suspicious_maps=$(echo "$maps" | grep -iE '/tmp/|/dev/shm/|\(deleted\)' | grep -ivE '\.minecraft|pipewire|memfd' || true)
    [[ -n "$suspicious_maps" ]] && match_cheat_in "$suspicious_maps" "maps"
    [[ -n "$suspicious_maps" ]] && match_inject_in "$suspicious_maps" "maps"
  fi

  if [[ $whitelisted -eq 0 ]]; then
    while IFS= read -r path; do
      is_suspicious_path "$path" && match_cheat_in "$path" "path"
    done < <(echo "$cmdline" | grep -oiE '/[^ ]+\.jar' || true)
  fi

  local -A seen=() u=() h
  for h in "${DETECTS[@]}"; do
    [[ -z "${h// /}" ]] && continue
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

Whitelist: Lunar, Feather, LabyMod, Fabric/Forge mods
Detect: ghost jar, /tmp .so, javaagent, inject agents, cheat clients (40+ sigs)
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
