#!/usr/bin/env bash
# Поиск строк читов в процессе MC — без gcore по умолчанию

set -euo pipefail

PRESET='doomsday|meteor|killaura|liquidbounce|wurst|vape|novoline|rise|exhibition|sigma|flux|astolfo|entitlement'

pid=""
query=""
mode="menu"
case_sensitive=0
whole_word=0
use_regex=1
use_preset=1

find_pid() {
  ps aux | grep '[j]ava' | grep KnotClient | awk '{print $2}' | head -1
}

usage() {
  cat <<'EOF'
memory-search.sh — шаг 6

  --quick     быстро, без gcore (рекомендуется)
  --deep      gcore + RAM (sudo, звук может пискнуть)
  (без флагов) меню

  bash memory-search.sh --quick
  bash memory-search.sh 249931 --deep
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --quick|-q) mode="light"; use_preset=1; query="$PRESET"; shift ;;
    --deep|-d) mode="deep"; use_preset=1; query="$PRESET"; shift ;;
    -c|--case) case_sensitive=1; shift ;;
    -w|--whole) whole_word=1; shift ;;
    -r|--regex) use_regex=1; shift ;;
    -s|--string) query="${2:?нужен текст}"; use_preset=0; use_regex=0; shift 2 ;;
    [0-9]*) pid="$1"; shift ;;
    *) echo "[!] неизвестно: $1"; usage; exit 1 ;;
  esac
done

[[ -z "$pid" ]] && pid=$(find_pid || true)
[[ -z "$pid" ]] && { echo "[!] PID не найден. Запусти MC."; exit 1; }

grep_opts() {
  local -n out=$1
  [[ $case_sensitive -eq 0 ]] && out+=(-i)
  [[ $whole_word -eq 1 ]] && out+=(-w)
  [[ $use_regex -eq 1 ]] && out+=(-E) || out+=(-F)
}

resolve_pattern() {
  if [[ $use_preset -eq 1 ]]; then echo "$PRESET"; else echo "$query"; fi
}

run_light() {
  local pattern="$1"
  local g=() hits="" line src
  grep_opts g

  echo "=== Memory Search (light) PID $pid ==="
  echo "cmdline + подозрительные файлы — без gcore"
  echo "Pattern: $pattern"
  echo "---"

  hits=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | grep "${g[@]}" -- "$pattern" || true)
  if [[ -n "$hits" ]]; then
    echo "[!!] cmdline:"; echo "$hits" | sed 's/^/    /'
    echo "=== ВЕРДИКТ: БАН ==="; return 2
  fi

  hits=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep "${g[@]}" -- "$pattern" || true)
  if [[ -n "$hits" ]]; then
    echo "[!!] environ:"; echo "$hits" | sed 's/^/    /'
    echo "=== ВЕРДИКТ: БАН ==="; return 2
  fi

  while IFS= read -r src; do
    [[ -z "$src" || ! -r "$src" ]] && continue
    line=$(grep -a -m1 "${g[@]}" -- "$pattern" "$src" 2>/dev/null || true)
    if [[ -n "$line" ]]; then
      echo "[!!] $src"
      echo "    $line"
      echo "=== ВЕРДИКТ: БАН ==="
      return 2
    fi
  done < <(
    awk '{print $6}' "/proc/$pid/maps" 2>/dev/null | sort -u \
      | grep -E '^/' \
      | grep -iE '/tmp/|/dev/shm/|\.cache/|cheat|doomsday|/Downloads/|/Загрузки/' \
      | grep -ivE '/\.minecraft/libraries/|/java-runtime-delta/' || true
  )

  while IFS= read -r t; do
    [[ -z "$t" || ! -r "$t" ]] && continue
    [[ "$t" =~ /tmp/|\.cache/|cheat|doomsday ]] || continue
    line=$(grep -a -m1 "${g[@]}" -- "$pattern" "$t" 2>/dev/null || true)
    if [[ -n "$line" ]]; then
      echo "[!!] fd → $t"
      echo "    $line"
      echo "=== ВЕРДИКТ: БАН ==="
      return 2
    fi
  done < <(ls -l "/proc/$pid/fd/" 2>/dev/null | awk '{print $NF}' | grep -E '^/' || true)

  echo "[OK] чисто"
  echo "=== ВЕРДИКТ: чисто (light) ==="
  echo "    heap-only ghost? → --deep (gcore, sudo)"
  return 0
}

run_deep() {
  local pattern="$1"
  local core="core.$pid" g=() hits=""
  grep_opts g

  echo "=== Memory Search (deep) PID $pid ==="
  echo "[!] gcore: зависание ~1 сек, звук может пискнуть"
  echo "---"

  if ! sudo gcore "$pid" 2>/dev/null; then
    echo "[!] gcore не удался — нужен sudo"
    return 1
  fi

  hits=$(strings "$core" 2>/dev/null | grep "${g[@]}" -- "$pattern" | sort -u | head -20 || true)
  rm -f core.* 2>/dev/null || true

  if [[ -n "$hits" ]]; then
    echo "[!!] RAM:"; echo "$hits" | sed 's/^/    /'
    echo "=== ВЕРДИКТ: БАН ==="
    return 2
  fi

  echo "[OK] в дампе RAM — чисто"
  echo "=== ВЕРДИКТ: чисто (deep) ==="
  return 0
}

draw_box() {
  local qshow
  qshow=$(resolve_pattern)
  [[ ${#qshow} -gt 38 ]] && qshow="${qshow:0:35}..."

  clear 2>/dev/null || true
  echo "╔══════════════════════════════════════════════════════════╗"
  printf "║  %-56s ║\n" "Memory String Search"
  echo "╠══════════════════════════════════════════════════════════╣"
  printf "║  String: %-47s ║\n" "$qshow"
  printf "║  PID: %-49s ║\n" "$pid"
  echo "║  0 Light (без gcore)    9 Deep (gcore)    q Quit       ║"
  echo "╚══════════════════════════════════════════════════════════╝"
}

[[ "$mode" == "light" ]] && { run_light "$(resolve_pattern)"; exit $?; }
[[ "$mode" == "deep" ]] && { run_deep "$(resolve_pattern)"; exit $?; }

while true; do
  draw_box
  read -r -p "  > " choice || exit 0
  case "$choice" in
    0) run_light "$(resolve_pattern)"; read -r -p "  Enter..." _ ;;
    9) run_deep "$(resolve_pattern)"; read -r -p "  Enter..." _ ;;
    q|Q) exit 0 ;;
  esac
done
