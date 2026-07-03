#!/usr/bin/env bash
# Поиск строк в RAM (gcore) — интерактив как Process Hacker / System Informer

set -euo pipefail

PRESET='doomsday|meteor|killaura|liquidbounce|wurst|vape|novoline|rise|exhibition|sigma|flux|astolfo|entitlement'

pid=""
query=""
case_sensitive=0
whole_word=0
use_regex=0
use_preset=1

find_pid() {
  ps aux | grep '[j]ava' | grep KnotClient | awk '{print $2}' | head -1
}

usage() {
  cat <<'EOF'
memory-search.sh [PID] [опции]

Интерактив (меню как Process Hacker):
  bash memory-search.sh
  bash memory-search.sh 249931

Без меню — пресет читов:
  bash memory-search.sh --quick
  bash memory-search.sh 249931 --quick

Опции:
  -s, --string TEXT   строка для поиска
  -c, --case          case sensitive
  -w, --whole         whole word
  -r, --regex         regex mode
  -p, --preset        пресет читов (по умолчанию в меню вкл)
  -q, --quick         gcore + пресет, без меню
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -q|--quick) use_preset=1; query="$PRESET"; shift; [[ "${1:-}" =~ ^[0-9]+$ ]] && { pid="$1"; shift; } ;;
    -c|--case) case_sensitive=1; shift ;;
    -w|--whole) whole_word=1; shift ;;
    -r|--regex) use_regex=1; shift ;;
    -p|--preset) use_preset=1; query="$PRESET"; shift ;;
    -s|--string) query="${2:?нужен текст после --string}"; use_preset=0; shift 2 ;;
    [0-9]*) pid="$1"; shift ;;
    *) echo "[!] неизвестно: $1"; usage; exit 1 ;;
  esac
done

[[ -z "$pid" ]] && pid=$(find_pid || true)
[[ -z "$pid" ]] && { echo "[!] PID не найден. Запусти MC или: memory-search.sh PID"; exit 1; }

draw_box() {
  local qshow="${query:-<пусто>}"
  [[ ${#qshow} -gt 36 ]] && qshow="${qshow:0:33}..."

  clear 2>/dev/null || true
  echo "╔══════════════════════════════════════════════════════════╗"
  printf "║  %-56s ║\n" "Memory String Search  (gcore + strings)"
  echo "╠══════════════════════════════════════════════════════════╣"
  printf "║  Enter string: %-41s ║\n" "$qshow"
  echo "║                                                          ║"
  printf "║  [%s] Case sensitive                                     ║\n" "$([[ $case_sensitive -eq 1 ]] && echo x || echo ' ')"
  printf "║  [%s] Match whole word                                   ║\n" "$([[ $whole_word -eq 1 ]] && echo x || echo ' ')"
  printf "║  [%s] Regex mode                                         ║\n" "$([[ $use_regex -eq 1 ]] && echo x || echo ' ')"
  printf "║  [%s] Cheat preset list                                  ║\n" "$([[ $use_preset -eq 1 ]] && echo x || echo ' ')"
  echo "║                                                          ║"
  printf "║  PID: %-49s ║\n" "$pid"
  echo "╠══════════════════════════════════════════════════════════╣"
  echo "║  1 Case   2 Whole   3 Regex   4 Preset   5 String  6 PID ║"
  echo "║  0 Search   q Quit                                       ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo "  [!] gcore: игра зависнет ~1 сек, звук может пискнуть (Linux)"
}

run_search() {
  local pattern="$1"
  local grep_args=()
  local core="core.$pid"

  [[ -z "$pattern" ]] && { echo "[!] Строка пустая"; return 1; }

  if [[ $case_sensitive -eq 0 ]]; then grep_args+=(-i); fi
  if [[ $whole_word -eq 1 ]]; then grep_args+=(-w); fi
  if [[ $use_regex -eq 1 ]]; then grep_args+=(-E); else grep_args+=(-F); fi

  echo
  echo "=== gcore PID $pid ==="
  if ! sudo gcore "$pid" 2>/dev/null; then
    echo "[!] gcore не удался (sudo? права?)"
    return 1
  fi

  echo "=== strings → grep ==="
  echo "Pattern: $pattern"
  echo "Case: $([[ $case_sensitive -eq 1 ]] && echo sensitive || echo insensitive) | Whole: $([[ $whole_word -eq 1 ]] && echo yes || echo no) | Regex: $([[ $use_regex -eq 1 ]] && echo yes || echo no)"
  echo "---"

  local hits
  hits=$(strings "$core" 2>/dev/null | grep "${grep_args[@]}" -- "$pattern" | sort -u | head -50 || true)

  if [[ -n "$hits" ]]; then
    echo "[!!] НАЙДЕНО:"
    echo "$hits" | sed 's/^/    /'
    echo
    echo "=== ВЕРДИКТ: БАН / жёсткое подозрение ==="
    rc=2
  else
    echo "[OK] совпадений нет"
    echo "=== ВЕРДИКТ: чисто по этому паттерну ==="
    rc=0
  fi

  rm -f core.* 2>/dev/null || true
  return "$rc"
}

# Быстрый режим без меню
if [[ -n "$query" ]]; then
  run_search "$query"
  exit $?
fi

# Интерактив
while true; do
  draw_box
  read -r -p "  > " choice
  case "$choice" in
    1) case_sensitive=$((1 - case_sensitive)) ;;
    2) whole_word=$((1 - whole_word)) ;;
    3) use_regex=$((1 - use_regex)) ;;
    4)
      use_preset=$((1 - use_preset))
      if [[ $use_preset -eq 1 ]]; then query="$PRESET"; else query=""; fi
      ;;
    5)
      read -r -p "  Enter string: " query
      use_preset=0
      ;;
    6)
      read -r -p "  PID: " pid
      [[ -z "$pid" ]] && pid=$(find_pid || true)
      ;;
    0)
      if [[ $use_preset -eq 1 ]]; then
        run_search "$PRESET"
      else
        run_search "$query"
      fi
      read -r -p "  Enter — в меню..." _
      ;;
    q|Q) exit 0 ;;
    *) ;;
  esac
done
