#!/usr/bin/env bash
# Cleaning Detector — что чистили и что это ломает в PC-check скриптах

set -uo pipefail

MC="${MINECRAFT_DIR:-$HOME/.minecraft}"
HOME="${HOME:-/home/$USER}"

DETECT=()
WARN=()

add_detect() { DETECT+=("$1"); }
add_warn() { WARN+=("$1"); }

section() { echo; echo "━━ $1 ━━"; }

echo "=== Cleaning Detector — следы очистки улик ==="
echo "Показывает что могло сломать browser-history, all-downloads, safe-mod, linux-artifacts…"
echo

# ─────────────────────────────────────────────
section "1 · Терминал (history)"
# ─────────────────────────────────────────────
for f in "$HOME/.bash_history" "$HOME/.zsh_history"; do
  [[ -f "$f" ]] || { add_warn "$f — файла нет"; continue; }
  lines=$(wc -l < "$f" 2>/dev/null || echo 0)
  size=$(stat -c %s "$f" 2>/dev/null || echo 0)
  echo "  $f: $lines строк, ${size} байт"
  if [[ "$lines" -lt 5 && "$size" -lt 200 ]]; then
    add_detect "$f почти пуст ($lines строк) → linux-artifacts, all-downloads (wget/curl), doomsday"
  fi
  if grep -qE 'history -c|history -w|> *\.bash_history|> *\.zsh_history|unset HISTFILE|HISTSIZE=0|HISTFILESIZE=0' "$f" 2>/dev/null; then
    add_detect "В $f есть команды очистки history → все скрипты с history"
    grep -E 'history -c|> *\..*history|unset HISTFILE|HISTSIZE=0' "$f" 2>/dev/null | tail -3 | sed 's/^/    /'
  fi
  if grep -qiE 'bleachbit|shred -|rm -rf.*\.minecraft|rm -rf.*logs|rm -rf.*cache|journalctl.*vacuum|sqlite3.*DELETE' "$f" 2>/dev/null; then
    add_detect "В $f — bleachbit/shred/rm/vacuum → множество скриптов"
    grep -iE 'bleachbit|shred |rm -rf|vacuum|DELETE FROM' "$f" 2>/dev/null | tail -5 | sed 's/^/    /'
  fi
done

live_hist=$(history 2>/dev/null | wc -l || echo 0)
file_hist=$(wc -l < "$HOME/.bash_history" 2>/dev/null || echo 0)
if [[ "$live_hist" -gt 20 && "$file_hist" -lt 5 ]]; then
  add_detect "history в памяти ($live_hist) >> .bash_history ($file_hist) — файл обнулили после сессии"
fi

# ─────────────────────────────────────────────
section "2 · journald (systemd)"
# ─────────────────────────────────────────────
if command -v journalctl >/dev/null 2>&1; then
  boots=$(journalctl --list-boots 2>/dev/null | wc -l)
  usage=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[MGK]' | head -1 || echo "?")
  echo "  boot-записей: $boots, размер: $usage"
  [[ "${boots:-0}" -lt 2 ]] && add_detect "journal: мало boot ($boots) — могли journalctl --vacuum → linux-artifacts"
  vac=$(journalctl --since "90 days ago" 2>/dev/null \
    | grep -iE 'journalctl.*vacuum|Deleted archived journal|Vacuuming done|freed.*archive' | tail -3 || true)
  if [[ -n "$vac" ]]; then
    echo "$vac" | sed 's/^/    /'
    add_detect "journal: очистка vacuum/flush → linux-artifacts"
  fi
  oldest=$(journalctl --reverse --no-pager -n 1 --output=short-iso 2>/dev/null | tail -1 | cut -d' ' -f1 || true)
  echo "  самая старая запись (хвост reverse): $oldest"
else
  add_warn "journalctl недоступен"
fi

# ─────────────────────────────────────────────
section "3 · Браузер (History / Downloads)"
# ─────────────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "  $line"
    [[ "$line" == "[!]"* ]] && add_detect "${line#[!] }"
  done < <(python3 - "$HOME" <<'PY'
import glob, os, shutil, sqlite3, sys, tempfile
HOME = sys.argv[1]
found = False
for pat in (
    ".config/google-chrome/*/History",
    ".config/chromium/*/History",
    ".config/BraveSoftware/Brave-Browser/*/History",
    ".config/microsoft-edge/*/History",
    ".config/vivaldi/*/History",
):
    for db in glob.glob(os.path.join(HOME, pat)):
        found = True
        label = db.replace(HOME + "/", "")
        size = os.path.getsize(db)
        tmp = tempfile.mktemp(suffix=".db")
        try:
            shutil.copy2(db, tmp)
            con = sqlite3.connect(tmp)
            urls = con.execute("SELECT COUNT(*) FROM urls").fetchone()[0]
            dl = con.execute("SELECT COUNT(*) FROM downloads").fetchone()[0]
            con.close()
            print(f"{label}: {size} байт, URL={urls}, downloads={dl}")
            if urls < 10 and size < 80000:
                print(f"[!] {label} — мало URL ({urls}) → browser-history, all-downloads")
        except Exception as e:
            print(f"{label}: не читается ({e})")
        finally:
            try:
                os.unlink(tmp)
            except OSError:
                pass
if not found:
    print("браузеры History: не найдены")
PY
  )
else
  add_warn "python3 нет — проверка браузера пропущена"
fi

# ─────────────────────────────────────────────
section "4 · Minecraft logs (safe-mod, doomsday, injgen)"
# ─────────────────────────────────────────────
LOGDIR="$MC/logs"
if [[ ! -d "$LOGDIR" ]]; then
  add_detect "~/.minecraft/logs/ отсутствует → safe-mod-detector, doomsday, mod-analyzer"
elif [[ -z "$(ls -A "$LOGDIR" 2>/dev/null)" ]]; then
  add_detect "logs/ пуст → safe-mod-detector, doomsday"
else
  nlogs=$(find "$LOGDIR" -maxdepth 1 \( -name '*.log' -o -name '*.log.gz' \) 2>/dev/null | wc -l)
  oldest=$(find "$LOGDIR" -maxdepth 1 \( -name '*.log' -o -name '*.log.gz' \) -printf '%T+ %f\n' 2>/dev/null | sort | head -1)
  newest=$(find "$LOGDIR" -maxdepth 1 \( -name '*.log' -o -name '*.log.gz' \) -printf '%T+ %f\n' 2>/dev/null | sort -r | head -1)
  echo "  файлов логов: $nlogs"
  echo "  старейший: $oldest"
  echo "  новейший:  $newest"
  [[ ! -f "$LOGDIR/latest.log" ]] && add_detect "latest.log удалён → safe-mod, ручная проверка logs"
  if [[ "$nlogs" -lt 3 ]]; then
    add_warn "мало log-файлов ($nlogs) — могли удалять старые → safe-mod-detector"
  fi
  # пустой latest при запущенной игре — подозрительно (не проверяем процесс здесь)
  if [[ -f "$LOGDIR/latest.log" && $(stat -c %s "$LOGDIR/latest.log" 2>/dev/null || echo 1) -lt 50 ]]; then
    add_warn "latest.log почти пуст ($(stat -c %s "$LOGDIR/latest.log") байт)"
  fi
fi

if [[ ! -d "$MC/mods" ]]; then
  add_warn "~/.minecraft/mods/ нет"
elif [[ -z "$(ls -A "$MC/mods" 2>/dev/null)" ]]; then
  add_warn "mods/ пуст перед проверкой"
fi

# ─────────────────────────────────────────────
section "5 · TLauncher / лаунчер"
# ─────────────────────────────────────────────
if [[ -d "$HOME/.tlauncher/logs" ]]; then
  tl_n=$(find "$HOME/.tlauncher/logs" -type f 2>/dev/null | wc -l)
  echo "  .tlauncher/logs: $tl_n файлов"
  [[ "$tl_n" -lt 2 ]] && add_warn "мало логов TLauncher"
else
  echo "  .tlauncher/logs: нет (не TLauncher)"
fi

# ─────────────────────────────────────────────
section "6 · GTK recently-used"
# ─────────────────────────────────────────────
XBEL="$HOME/.local/share/recently-used.xbel"
if [[ ! -f "$XBEL" ]]; then
  add_warn "recently-used.xbel отсутствует → linux-artifacts (BAM-подобное)"
elif [[ $(stat -c %s "$XBEL" 2>/dev/null || echo 0) -lt 500 ]]; then
  add_detect "recently-used.xbel почти пуст → linux-artifacts"
else
  echo "  recently-used.xbel: $(stat -c %s "$XBEL") байт, $(grep -c bookmark "$XBEL" 2>/dev/null || echo 0) записей"
fi

# ─────────────────────────────────────────────
section "7 · Корзина / cache"
# ─────────────────────────────────────────────
TRASH="$HOME/.local/share/Trash/info"
if [[ -d "$TRASH" ]]; then
  trash_n=$(find "$TRASH" -type f 2>/dev/null | wc -l)
  echo "  корзина: $trash_n файлов"
  if [[ "$trash_n" -eq 0 ]]; then
    add_warn "корзина пуста (могли Empty Trash перед SS)"
  fi
else
  echo "  корзина: нет"
fi

for hist in "$HOME/.bash_history" "$HOME/.zsh_history"; do
  [[ -f "$hist" ]] || continue
  grep -qiE 'rm -.*\.minecraft|rm -.*logs|rm -.*History|bleachbit|srm ' "$hist" 2>/dev/null \
    && add_detect "history: rm/bleachbit по .minecraft или History"
done

# ─────────────────────────────────────────────
section "8 · Софт для очистки"
# ─────────────────────────────────────────────
for pkg in bleachbit secure-delete; do
  if command -v "$pkg" >/dev/null 2>&1; then
    echo "  установлен: $pkg"
    add_warn "на ПК есть $pkg — мог использоваться для очистки"
  fi
done
dpkg -l bleachbit 2>/dev/null | grep -q ^ii && add_warn "bleachbit установлен (apt)"

# ─────────────────────────────────────────────
section "Итог — что ломает проверку"
# ─────────────────────────────────────────────
echo
if [[ ${#WARN[@]} -gt 0 ]]; then
  echo "Предупреждения:"
  for w in "${WARN[@]}"; do echo "  [WARN] $w"; done
  echo
fi

if [[ ${#DETECT[@]} -eq 0 ]]; then
  echo "[OK] Явных следов очистки под PC-check не найдено."
  echo "     (Скрытая очистка всё равно возможна — incognito, live USB и т.д.)"
  exit 0
fi

echo "[DETECT] Найдено ${#DETECT[@]} — возможная очистка улик:"
for d in "${DETECT[@]}"; do
  echo "  → $d"
done
echo
echo "Вердикт модерации: пустые history/logs/browser + команды очистки = отказ/сокрытие улик."
exit 2
