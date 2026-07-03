#!/usr/bin/env bash
# INJGEN Linux — меню + авто-детект (NotRequiem/InjGen)
# https://github.com/NotRequiem/InjGen

set -uo pipefail

PRESET='doomsday|meteor|killaura|liquidbounce|wurst|vape|novoline|rise|exhibition|sigma|flux|astolfo|entitlement'

PATTERNS=(
  'DoomsdayClient|com/doomsday|doomsday/client'
  'vape/v4|VapeV4|VapeLite|vapeclient'
  'meteordevelopment|meteor-client|MeteorClient'
  'killaura|KillAura'
  'liquidbounce|LiquidBounce|net/ccbluex/liquidbounce'
  'net/wurstclient|WurstClient'
  'SunsetClient|SlinkyClient|KarmaClient'
)

PID=""
STRING=""
CASE=0
WHOLE=0
REGEX=0
LAST=""
DETECTS=()

find_pid() {
  ps aux | grep '[j]ava' | grep KnotClient | sort -k6 -rn | awk '{print $2}' | head -1
}

proc_label() {
  local c
  c=$(tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null || true)
  echo "$c" | grep -q KnotClient && echo "KnotClient" && return
  echo "java"
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

injgen_scan() {
  local pid="$1" cmdline agent path t line
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

injgen_print() {
  local pid="$1" out=""
  out+="Reading virtual memory in '$(proc_label "$pid")' process with PID $pid\n"

  if [[ ${#DETECTS[@]} -eq 0 ]]; then
    out+="[+] No suspicious java agents were loaded in the game instance.\n"
    LAST="$out"
    return 0
  fi

  out+="[!] Generic injection detected.\nDetected:\n"
  for h in "${DETECTS[@]}"; do
    out+="    → $h\n"
  done
  LAST="$out"
  return 2
}

grep_build() {
  G=()
  [[ $CASE -eq 0 ]] && G+=(-i)
  [[ $WHOLE -eq 1 ]] && G+=(-w)
  [[ $REGEX -eq 1 ]] && G+=(-E) || G+=(-F)
}

string_light() {
  local pid="$1" pattern="$2" hits="" out=""
  grep_build
  out+="=== String scan LIGHT ===\nString: $pattern\n---\n"

  hits=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | grep "${G[@]}" -- "$pattern" || true)
  if [[ -n "$hits" ]]; then
    out+="[!!] HIT cmdline:\n$(echo "$hits" | sed 's/^/    /')\n>>> DETECT <<<\n"
    LAST="$out"; return
  fi

  while IFS= read -r f; do
    [[ -z "$f" || ! -r "$f" ]] && continue
    line=$(grep -a -m1 "${G[@]}" -- "$pattern" "$f" 2>/dev/null || true)
    if [[ -n "$line" ]]; then
      out+="[!!] HIT file: $f\n    $line\n>>> DETECT <<<\n"
      LAST="$out"; return
    fi
  done < <(
    awk '{print $6}' "/proc/$pid/maps" 2>/dev/null | sort -u \
      | grep -iE '/tmp/|\.cache/|cheat|doomsday' \
      | grep -ivE '/libraries/|java-runtime' || true
  )

  out+="[OK] не найдено (light)\n"
  LAST="$out"
}

string_deep() {
  local pid="$1" pattern="$2" core="core.$pid" hits="" out=""
  grep_build
  out+="=== String scan DEEP (gcore) ===\n[!] звук может пискнуть\nString: $pattern\n---\n"

  if ! sudo gcore "$pid" 2>/dev/null; then
    out+="[!] gcore failed — нужен sudo\n"
    LAST="$out"; return
  fi

  hits=$(strings "$core" 2>/dev/null | grep "${G[@]}" -- "$pattern" | sort -u | head -20 || true)
  rm -f core.* 2>/dev/null || true

  if [[ -n "$hits" ]]; then
    out+="[!!] HIT RAM:\n$(echo "$hits" | sed 's/^/    /')\n>>> DETECT <<<\n"
  else
    out+="[OK] не найдено (deep)\n"
  fi
  LAST="$out"
}

draw() {
  local disp="${STRING:-<введи строку — s>}"
  [[ ${#disp} -gt 44 ]] && disp="${disp:0:41}..."

  clear 2>/dev/null || printf '\033[2J\033[H'
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  INJGEN Linux — String Scanner                               ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  printf "║  Process: %-8s  %-44s ║\n" "${PID:-?}" "$(proc_label "${PID:-0}" 2>/dev/null || echo java)"
  echo "╠══════════════════════════════════════════════════════════════╣"
  printf "║  Enter string: %-45s ║\n" "$disp"
  printf "║  [%s] Case sensitive    [%s] Match whole word              ║\n" \
    "$([[ $CASE -eq 1 ]] && echo x || echo ' ')" \
    "$([[ $WHOLE -eq 1 ]] && echo x || echo ' ')"
  printf "║  [%s] Regex mode                                            ║\n" \
    "$([[ $REGEX -eq 1 ]] && echo x || echo ' ')"
  echo "╠══════════════════════════════════════════════════════════════╣"
  echo "║  a — INJGEN авто ([+] / [!] + Detected)                     ║"
  echo "║  s — строка   h — пресет   p — PID   c/w/r — опции          ║"
  echo "║  l — string light   d — string deep (gcore)   q — выход     ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  if [[ -n "$LAST" ]]; then
    echo
    printf '%b' "$LAST"
    echo
  fi
}

edit_string() {
  local new=""
  echo
  echo "  Текущая: ${STRING:-<пусто>}"
  if [[ -n "$STRING" ]] && [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
    read -e -r -i "$STRING" -p "  Enter string: " new
  else
    read -r -p "  Enter string: " new
  fi
  if [[ -n "$new" ]]; then
    STRING="$new"
    REGEX=0
    LAST="String: $STRING"
  fi
}

pick_pid() {
  echo
  ps aux | grep '[j]ava' | grep -v cursor | while read -r line; do
    id=$(echo "$line" | awk '{print $2}')
    ram=$(echo "$line" | awk '{print $4}')
    if echo "$line" | grep -q KnotClient; then
      echo "  >>> $id  RAM=${ram}%  ИГРА"
    else
      echo "      $id  RAM=${ram}%"
    fi
  done
  echo
  read -r -p "  PID (Enter=авто): " p
  [[ -z "$p" ]] && PID=$(find_pid || true) || PID="$p"
  LAST="PID = $PID"
}

resolve_string() {
  [[ -n "$STRING" ]] && echo "$STRING" || echo "$PRESET"
}

run_menu() {
  [[ -z "$PID" ]] && PID=$(find_pid || true)
  [[ -z "$PID" ]] && { echo "Minecraft Java not detected."; exit 1; }
  LAST="Готов.  a — INJGEN авто   s — строка   l — искать"

  while true; do
    draw
    read -r -p "  injgen> " cmd extra _ || exit 0
    cmd="${cmd,,}"
    case "$cmd" in
      q|quit|exit) exit 0 ;;
      a|auto)
        injgen_scan "$PID"
        injgen_print "$PID" || true
        ;;
      s|string)
        if [[ -n "${extra:-}" ]]; then STRING="$extra"; REGEX=0; LAST="String: $STRING"
        else edit_string; fi
        ;;
      h|preset) STRING="$PRESET"; REGEX=1; LAST="Пресет читов (regex ON)" ;;
      c) CASE=$((1-CASE)) ;;
      w) WHOLE=$((1-WHOLE)) ;;
      r) REGEX=$((1-REGEX)) ;;
      p|pid) pick_pid ;;
      l|light)
        string_light "$PID" "$(resolve_string)"
        ;;
      d|deep)
        string_deep "$PID" "$(resolve_string)"
        ;;
      "")
        : ;;
      *)
        STRING="$cmd${extra:+ $extra}"
        REGEX=0
        LAST="String: $STRING"
        ;;
    esac
  done
}

run_auto() {
  [[ -z "$PID" ]] && PID=$(find_pid || true)
  [[ -z "$PID" ]] && { echo "Minecraft Java not detected."; exit 1; }
  injgen_scan "$PID"
  injgen_print "$PID"
  exit $?
}

usage() {
  cat <<'EOF'
INJGEN Linux — https://github.com/NotRequiem/InjGen

  bash injgen.sh           меню (как на скрине)
  bash injgen.sh --auto    только [+] / [!] без меню
  bash injgen.sh 249931
EOF
}

# --- init ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --auto|-a) MODE=auto; shift ;;
    [0-9]*) PID="$1"; shift ;;
    *) shift ;;
  esac
done

if [[ "${MODE:-menu}" == "auto" ]]; then
  run_auto
else
  run_menu
fi
