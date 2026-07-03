#!/usr/bin/env bash
# INJGEN Linux — JNI/JVMTI ghost detect (логика как NotRequiem/InjGen)
# https://github.com/NotRequiem/InjGen

set -uo pipefail

# Строгие сигнатуры (классы/пакеты), не короткие слова
PATTERNS=(
  'DoomsdayClient|com/doomsday|doomsday/client'
  'vape/v4|VapeV4|VapeLite|vapeclient|Vape Client'
  'meteordevelopment|meteor-client|MeteorClient'
  'killaura|KillAura|kill aura'
  'liquidbounce|LiquidBounce|net/ccbluex/liquidbounce'
  'net/wurstclient|wurstplus|WurstClient'
  'SunsetClient|sunset/client'
  'SlinkyClient|slinky/client'
  'KarmaClient|karma/client'
  'EntropyClient|entropy/client'
  'DreamClient|dream/client'
  'DripClient|drip/client'
  'NovolineClient|novoline/client'
  'riseclient|rise/client'
  'sigma/client|SigmaClient'
  'fluxclient|flux/client'
  'astolfo/client|AstolfoClient'
)

find_pid() {
  ps aux | grep '[j]ava' | grep KnotClient | sort -k6 -rn | awk '{print $2}' | head -1
}

proc_label() {
  local c
  c=$(tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null || true)
  echo "$c" | grep -q KnotClient && echo "KnotClient" && return
  echo "$c" | grep -q Main && echo "java" && return
  echo "java"
}

add_hit() {
  DETECTS+=("$1")
}

match_patterns() {
  local text="$1" label="$2" p hit name
  [[ -z "$text" ]] && return
  for p in "${PATTERNS[@]}"; do
    hit=$(echo "$text" | grep -oiE "$p" | head -1 || true)
    if [[ -n "$hit" ]]; then
      name=$(echo "$p" | cut -d'|' -f1)
      add_hit "Known client ($label): $hit"
    fi
  done
}

scan_pid() {
  local pid="$1"
  local cmdline agent path t line

  DETECTS=()
  cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)

  # --- Java Agent (JNI/JVMTI inject) ---
  while IFS= read -r agent; do
    [[ -n "$agent" ]] && add_hit "Java Agent (cmdline): $agent"
  done < <(echo "$cmdline" | grep -oiE -- '-javaagent:[^ ]+' || true)

  if echo "$cmdline" | grep -q -- '-noverify'; then
    add_hit "JVM flag -noverify (cmdline)"
  fi

  while IFS= read -r path; do
    [[ -n "$path" ]] && add_hit "Suspicious JAR in cmdline: $path"
  done < <(echo "$cmdline" | grep -oiE '/tmp/[^ ]+\.jar|[^ ]*\.cache/[^ ]+\.jar' || true)

  match_patterns "$cmdline" "cmdline"

  # --- Ghost JAR ---
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    add_hit "Ghost JAR (deleted fd): $t"
    match_patterns "$t" "ghost path"
  done < <(
    ls -l "/proc/$pid/fd/" 2>/dev/null \
      | grep '(deleted)' \
      | grep -iE '\.jar' \
      | grep -ivE 'pipewire|memfd|ffi' \
      | awk '{print $NF}' || true
  )

  # --- JNI .so ---
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    add_hit "JNI .so (inject path): $(echo "$line" | awk '{print $NF}')"
  done < <(lsof -p "$pid" 2>/dev/null | grep '\.so' | grep -iE '/tmp/|/dev/shm/' || true)

  # --- deleted native вне jre/natives ---
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    t=$(echo "$line" | awk '{print $NF}')
    add_hit "Native library (deleted): $t"
  done < <(
    cat "/proc/$pid/maps" 2>/dev/null \
      | grep -i deleted \
      | grep '\.so' \
      | grep -ivE '/natives/|java-runtime|/lib/lib(jvm|java|awt|nio)\.so' || true
  )

  # --- JVMTI markers только в cmdline + ghost/deleted jar content ---
  if echo "$cmdline" | grep -qiE 'Agent-Class|premain|instrument\.|JVMTI'; then
    add_hit "JVMTI marker (cmdline): $(echo "$cmdline" | grep -oiE 'Agent-Class|premain|JVMTI' | head -1)"
  fi

  # dedupe
  local -A seen=()
  local u=() h
  for h in "${DETECTS[@]}"; do
    [[ -n "${seen[$h]:-}" ]] && continue
    seen[$h]=1
    u+=("$h")
  done
  DETECTS=("${u[@]}")
}

print_result() {
  local pid="$1"
  echo "Reading virtual memory in '$(proc_label "$pid")' process with PID $pid"

  if [[ ${#DETECTS[@]} -eq 0 ]]; then
    echo "[+] No suspicious java agents were loaded in the game instance."
    return 0
  fi

  local generic=0 h
  for h in "${DETECTS[@]}"; do
    if echo "$h" | grep -qiE 'Ghost JAR|Java Agent|Known client|JNI .so|JVMTI'; then
      generic=1
      break
    fi
  done

  if [[ $generic -eq 1 ]]; then
    echo "[!] Generic injection detected."
  else
    echo "[-] Injection detected in untested game client."
  fi

  echo "Detected:"
  for h in "${DETECTS[@]}"; do
    echo "    → $h"
  done
  return 2
}

usage() {
  cat <<'EOF'
INJGEN Linux — аналог https://github.com/NotRequiem/InjGen

  bash injgen.sh           авто (KnotClient)
  bash injgen.sh 249931    один PID
  bash injgen.sh -i        доп.: поиск своей строки

Вывод:
  [+] No suspicious java agents...
  [!] Generic injection detected.
  Detected:
      → что именно
EOF
}

interactive_search() {
  local pid="${1:-}" STRING="" CASE=0 REGEX=0 LAST=""
  [[ -z "$pid" ]] && pid=$(find_pid || true)
  [[ -z "$pid" ]] && { echo "Minecraft Java not detected."; exit 1; }

  while true; do
    clear 2>/dev/null || true
    echo "=== INJGEN String Search (доп.) PID $pid ==="
    echo "String: ${STRING:-<пусто>}"
    echo "  s — строка   f — find   a — auto injgen   q — quit"
    [[ -n "$LAST" ]] && { echo; echo "$LAST"; }
    read -r -p "> " cmd rest _ || exit 0
    case "${cmd,,}" in
      q) exit 0 ;;
      a) scan_pid "$pid"; print_result "$pid"; read -r -p "Enter..." _ ;;
      s)
        if [[ -n "${rest:-}" ]]; then STRING="$rest"
        elif [[ -n "$STRING" ]] && [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then read -e -i "$STRING" -r -p "Enter string: " STRING
        else read -r -p "Enter string: " STRING; fi
        ;;
      f)
        [[ -z "$STRING" ]] && { LAST="Сначала s строка"; continue; }
        g=(-F)
        [[ $CASE -eq 0 ]] && g=(-Fi)
        [[ $REGEX -eq 1 ]] && g=(-E) && [[ $CASE -eq 0 ]] && g=(-Ei)
        hits=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | grep "${g[@]}" -- "$STRING" || true)
        if [[ -n "$hits" ]]; then LAST="[!!] HIT cmdline:\n$hits"; else LAST="[OK] не найдено в cmdline"; fi
        ;;
      *) [[ -n "$cmd" ]] && STRING="$cmd${rest:+ $rest}" ;;
    esac
  done
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ "${1:-}" == "-i" || "${1:-}" == "--interactive" ]] && { interactive_search "${2:-}"; exit; }

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
