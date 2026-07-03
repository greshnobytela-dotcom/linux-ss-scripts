#!/usr/bin/env bash
# Поиск строк читов в процессе MC — без gcore по умолчанию

set -euo pipefail

PRESET='doomsday|meteor|killaura|liquidbounce|wurst|vape|novoline|rise|exhibition|sigma|flux|astolfo|entitlement'

pid=""
query=""
mode="light"   # light | deep | menu
case_sensitive=0
whole_word=0
use_regex=1
use_preset=1

find_pid() {
  ps aux | grep '[j]ava' | grep KnotClient | awk '{print $2}' | head -1
}

usage() {
  cat <<'EOF'
memory-search.sh — поиск строк читов (шаг 6 протокола)

  bash memory-search.sh              меню
  bash memory-search.sh --quick      быстро, БЕЗ gcore (рекомендуется)
  bash memory-search.sh --deep       gcore + RAM (sudo, звук может пискнуть)
  bash memory-search.sh 249931 --quick

  -s TEXT   своя строка    -c case   -w whole word   -r regex
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --quick|-q) mode="light"; use_preset=1; query="$PRESET"; shift ;;
    --deep|-d) mode="deep"; use_preset=1; query="$PRESET"; shift ;;
    --menu|-m) mode="menu"; shift ;;
    -c|--case) case_sensitive=1; shift ;;
    -w|--whole) whole_word=1; shift ;;
    -r|--regex) use_regex=1; shift ;;
    -p|--preset) use_preset=1; query="$PRESET"; shift ;;
    -s|--string) query="${2:?нужен текст}"; use_preset=0; use_regex=0; shift 2 ;;
    [0-9]*) pid="$1"; shift ;;
    *) echo "[!] неизвестно: $1"; usage; exit 1 ;;
  esac
done

[[ -z "$pid" ]] && pid=$(find_pid || true)
[[ -z "$pid" ]] && { echo "[!] PID не найден. Запусти MC."; exit 1; }

grep_hits() {
  local pattern="$1"
  local args=()
  [[ $case_sensitive -eq 0 ]] && args+=(-i)
  [[ $whole_word -eq 1 ]] && args+=(-w)
  if [[ $use_regex -eq 1 ]]; then args+=(-E); else args+=(-F); fi
  grep "${args[@]}" -- "$pattern" 2>/dev/null || true
}

collect_light() {
  {
    tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null
    tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null
    awk '{print $6}' "/proc/$pid/maps" 2>/dev/null | grep -E '^/' | sort -u | while read -r f; do
      [[ -r "$f" ]] && strings "$f" 2>/dev/null
    done
    for fd in "/proc/$pid/fd/"*; do
      [[ -e "$fd" ]] || continue
      t=$(readlink "$fd" 2>/dev/null || true)
      [[ -n "$t" && -r "$t" && "$t" == /* ]] && strings "$t" 2>/dev/null
    done
  } 2>/dev/null
}

run_light() {
  local pattern="$1"
  echo "=== Memory Search (light) PID $pid ==="
  echo "Источник: cmdline, maps, открытые файлы — без gcore, без лагов"
  echo "Pattern: $pattern"
  echo "---"

  local hits
  hits=$(collect_light | grep_hits "$pattern" | sort -u | head -30)

  if [[ -n "$hits" ]]; then
    echo "[!!] НАЙДЕНО:"
    echo "$hits" | sed 's/^/    /'
    echo
    echo "=== ВЕРДИКТ: БАН / подозрение ==="
    return 2
  fi

  echo "[OK] в загруженных файлах и cmdline — чисто"
  echo "=== ВЕРДИКТ: чисто (light) ==="
  echo "    ghost-чит только в heap? → bash ... --deep  (gcore, sudo, звук может пискнуть)"
  return 0
}

run_deep() {
  local pattern="$1"
  local core="core.$pid"
  local grep_args=()
  [[ $case_sensitive -eq 0 ]] && grep_args+=(-i)
  [[ $whole_word -eq 1 ]] && grep_args+=(-w)
  [[ $use_regex -eq 1 ]] && grep_args+=(-E) || grep_args+=(-F)

  echo "=== Memory Search (deep / gcore) PID $pid ==="
  echo "[!] Игра зависнет ~1 сек. На Linux звук может пискнуть — норма."
  echo "---"

  if ! sudo gcore "$pid" 2>/dev/null; then
    echo "[!] gcore не удался — нужен sudo"
    return 1
  fi

  local hits
  hits=$(strings "$core" 2>/dev/null | grep "${grep_args[@]}" -- "$pattern" | sort -u | head -30 || true)
  rm -f core.* 2>/dev/null || true

  if [[ -n "$hits" ]]; then
    echo "[!!] НАЙДЕНО в RAM:"
    echo "$hits" | sed 's/^/    /'
    echo "=== ВЕРДИКТ: БАН ==="
    return 2
  fi

  echo "[OK] в дампе RAM — чисто"
  echo "=== ВЕРДИКТ: чисто (deep) ==="
  return 0
}

draw_box() {
  local qshow="${query:-$PRESET}"
  [[ ${#qshow} -gt 38 ]] && qshow="${qshow:0:35}..."

  clear 2>/dev/null || true
  echo "╔══════════════════════════════════════════════════════════╗"
  printf "║  %-56s ║\n" "Memory String Search"
  echo "╠══════════════════════════════════════════════════════════╣"
  printf "║  String: %-47s ║\n" "$qshow"
  printf "║  [%s] Case sensitive   [%s] Whole word   [%s] Regex   ║\n" \
    "$([[ $case_sensitive -eq 1 ]] && echo x || echo ' ')" \
    "$([[ $whole_word -eq 1 ]] && echo x || echo ' ')" \
    "$([[ $use_regex -eq 1 ]] && echo x || echo ' ')"
  printf "║  PID: %-49s ║\n" "$pid"
  echo "╠══════════════════════════════════════════════════════════╣"
  echo "║  1 Case  2 Whole  3 Regex  4 String  5 PID             ║"
  echo "║  0 Light search (без gcore)   9 Deep (gcore + sudo)    ║"
  echo "║  q Quit                                                  ║"
  echo "╚══════════════════════════════════════════════════════════╝"
}

resolve_pattern() {
  if [[ $use_preset -eq 1 ]]; then echo "$PRESET"; else echo "$query"; fi
}

# --- запуск ---
if [[ "$mode" == "light" ]]; then
  run_light "$(resolve_pattern)"
  exit $?
fi

if [[ "$mode" == "deep" ]]; then
  run_deep "$(resolve_pattern)"
  exit $?
fi

# меню
query="${query:-$PRESET}"
while true; do
  draw_box
  read -r -p "  > " choice || exit 0
  case "$choice" in
    1) case_sensitive=$((1 - case_sensitive)) ;;
    2) whole_word=$((1 - whole_word)) ;;
    3) use_regex=$((1 - use_regex)) ;;
    4) read -r -p "  Enter string: " query; use_preset=0 ;;
    5) read -r -p "  PID: " pid; [[ -z "$pid" ]] && pid=$(find_pid || true) ;;
    0) run_light "$(resolve_pattern)"; read -r -p "  Enter..." _ ;;
    9) run_deep "$(resolve_pattern)"; read -r -p "  Enter..." _ ;;
    q|Q) exit 0 ;;
  esac
done
