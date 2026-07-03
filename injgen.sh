#!/usr/bin/env bash
# INJGEN Linux — поиск строк в процессе (как InjGen / Process Hacker)

set -uo pipefail

PRESET='doomsday|meteor|killaura|liquidbounce|wurst|vape|novoline|rise|exhibition|sigma|flux|astolfo|entitlement'

PID=""
STRING=""
CASE=0
WHOLE=0
REGEX=0
LAST=""   # последний результат

find_pid() {
  ps aux | grep '[j]ava' | grep KnotClient | awk '{print $2}' | head -1
}

proc_name() {
  tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null | grep -oE 'KnotClient|Main' | head -1 || echo "java"
}

grep_build() {
  GREP_ARGS=()
  [[ $CASE -eq 0 ]] && GREP_ARGS+=(-i)
  [[ $WHOLE -eq 1 ]] && GREP_ARGS+=(-w)
  [[ $REGEX -eq 1 ]] && GREP_ARGS+=(-E) || GREP_ARGS+=(-F)
}

draw() {
  local disp="${STRING:-<введи строку — команда s>}"
  [[ ${#disp} -gt 44 ]] && disp="${disp:0:41}..."

  clear 2>/dev/null || printf '\033[2J\033[H'
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  INJGEN Linux — String Scanner                               ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  if [[ -n "$PID" ]]; then
    printf "║  Process: %-8s  %-44s ║\n" "$PID" "$(proc_name "$PID")"
  else
    echo "║  Process: (не найден — p)                                    ║"
  fi
  echo "╠══════════════════════════════════════════════════════════════╣"
  printf "║  Enter string: %-45s ║\n" "$disp"
  printf "║  [%s] Case sensitive    [%s] Match whole word              ║\n" \
    "$([[ $CASE -eq 1 ]] && echo x || echo ' ')" \
    "$([[ $WHOLE -eq 1 ]] && echo x || echo ' ')"
  printf "║  [%s] Regex mode                                            ║\n" \
    "$([[ $REGEX -eq 1 ]] && echo x || echo ' ')"
  echo "╠══════════════════════════════════════════════════════════════╣"
  echo "║  s — строка (остаётся)   h — пресет читов   p — PID         ║"
  echo "║  c — case   w — whole   r — regex                           ║"
  echo "║  l — scan light (быстро)   d — scan deep (gcore, sudo)      ║"
  echo "║  q — выход                                                   ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  if [[ -n "$LAST" ]]; then
    echo
    echo "$LAST"
    echo
  fi
}

need_string() {
  [[ -n "$STRING" ]] && return 0
  echo "[!] Сначала введи строку: s твой_текст"
  return 1
}

scan_light() {
  need_string || return 1
  [[ -z "$PID" ]] && { LAST="[!] PID пустой — нажми p"; return 1; }

  grep_build
  local g=("${GREP_ARGS[@]}") hits="" line src out=""
  out+="=== Scan LIGHT  PID $PID ===\n"
  out+="String: $STRING\n---\n"

  hits=$(tr '\0' '\n' < "/proc/$PID/cmdline" 2>/dev/null | grep "${g[@]}" -- "$STRING" || true)
  if [[ -n "$hits" ]]; then
    out+="[!!] HIT cmdline:\n$(echo "$hits" | sed 's/^/    /')\n"
    out+=">>> ВЕРДИКТ: БАН <<<\n"
    LAST="$out"; return 2
  fi

  hits=$(tr '\0' '\n' < "/proc/$PID/environ" 2>/dev/null | grep "${g[@]}" -- "$STRING" || true)
  if [[ -n "$hits" ]]; then
    out+="[!!] HIT environ:\n$(echo "$hits" | sed 's/^/    /')\n"
    out+=">>> ВЕРДИКТ: БАН <<<\n"
    LAST="$out"; return 2
  fi

  while IFS= read -r src; do
    [[ -z "$src" || ! -r "$src" ]] && continue
    line=$(grep -a -m1 "${g[@]}" -- "$STRING" "$src" 2>/dev/null || true)
    if [[ -n "$line" ]]; then
      out+="[!!] HIT file:\n    $src\n    $line\n"
      out+=">>> ВЕРДИКТ: БАН <<<\n"
      LAST="$out"; return 2
    fi
  done < <(
    awk '{print $6}' "/proc/$PID/maps" 2>/dev/null | sort -u \
      | grep -E '^/' \
      | grep -iE '/tmp/|/dev/shm/|\.cache/|cheat|doomsday|/Downloads/|/Загрузки/' \
      | grep -ivE '/\.minecraft/libraries/|/java-runtime-delta/' || true
  )

  out+="[OK] совпадений нет (light)\n"
  out+=">>> ВЕРДИКТ: чисто <<<\n"
  out+="    ghost только в heap? → d (deep/gcore)\n"
  LAST="$out"
  return 0
}

scan_deep() {
  need_string || return 1
  [[ -z "$PID" ]] && { LAST="[!] PID пустой — нажми p"; return 1; }

  grep_build
  local g=("${GREP_ARGS[@]}") core="core.$PID" hits="" out=""
  out+="=== Scan DEEP (gcore)  PID $PID ===\n"
  out+="[!] игра зависнет ~1 сек, звук может пискнуть\n"
  out+="String: $STRING\n---\n"

  if ! sudo gcore "$PID" 2>/dev/null; then
    out+="[!] gcore failed — нужен sudo\n"
    LAST="$out"; return 1
  fi

  hits=$(strings "$core" 2>/dev/null | grep "${g[@]}" -- "$STRING" | sort -u | head -25 || true)
  rm -f core.* 2>/dev/null || true

  if [[ -n "$hits" ]]; then
    out+="[!!] HIT RAM:\n$(echo "$hits" | sed 's/^/    /')\n"
    out+=">>> ВЕРДИКТ: БАН <<<\n"
    LAST="$out"; return 2
  fi

  out+="[OK] в дампе RAM — чисто\n"
  out+=">>> ВЕРДИКТ: чисто (deep) <<<\n"
  LAST="$out"
  return 0
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
    LAST="String сохранена: $STRING"
  else
    LAST="Строка не изменена."
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
  read -r -p "  PID (Enter = авто KnotClient): " p
  if [[ -z "$p" ]]; then
    PID=$(find_pid || true)
  else
    PID="$p"
  fi
  LAST="PID = ${PID:-не найден}"
}

usage() {
  cat <<EOF
INJGEN Linux — интерактивный поиск строк

  bash injgen.sh           меню (строка не пропадает)
  bash injgen.sh 249931    с PID

В меню: s — строка, l — light, d — deep, c/w/r — опции
EOF
}

# --- init ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --quick) STRING="$PRESET"; REGEX=1; shift; scan_light; exit $? ;;
    --deep)  STRING="$PRESET"; REGEX=1; shift; scan_deep; exit $? ;;
    [0-9]*) PID="$1"; shift ;;
    *) shift ;;
  esac
done

[[ -z "$PID" ]] && PID=$(find_pid || true)
LAST="Готов. s — введи строку, l — искать."

# --- main loop ---
while true; do
  draw
  read -r -p "  injgen> " cmd extra _ 2>/dev/null || exit 0
  cmd="${cmd,,}"
  case "$cmd" in
    q|quit|exit) exit 0 ;;
    s|string)
      if [[ -n "${extra:-}" ]]; then
        STRING="$extra"
        REGEX=0
        LAST="String сохранена: $STRING"
      else
        edit_string
      fi
      ;;
    h|preset)
      STRING="$PRESET"
      REGEX=1
      LAST="Пресет читов загружен (regex ON)"
      ;;
    c) CASE=$((1-CASE)); LAST="Case sensitive: $([[ $CASE -eq 1 ]] && echo ON || echo off)" ;;
    w) WHOLE=$((1-WHOLE)); LAST="Whole word: $([[ $WHOLE -eq 1 ]] && echo ON || echo off)" ;;
    r) REGEX=$((1-REGEX)); LAST="Regex: $([[ $REGEX -eq 1 ]] && echo ON || echo off)" ;;
    l|scan|find) scan_light || true ;;
    d|deep|gcore) scan_deep || true ;;
    p|pid) pick_pid ;;
    "")
      : ;;
    *)
      # если набрал текст без команды — это строка поиска
      STRING="$cmd${extra:+ $extra}"
      REGEX=0
      LAST="String сохранена: $STRING"
      ;;
  esac
done
