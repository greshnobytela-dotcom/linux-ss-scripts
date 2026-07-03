#!/usr/bin/env bash
# SS Bypass Detector — Chameleon, .faker, второй ПК, Synergy/AnyDesk/Parsec
# Обход PC-check: чит на одном ПК, проверяют другой

set -uo pipefail

MC="${MINECRAFT_DIR:-$HOME/.minecraft}"
DETECT=()
WARN=()

add_detect() { DETECT+=("$1"); }
add_warn() { WARN+=("$1"); }
section() { echo; echo "━━ $1 ━━"; }

echo "=== SS Bypass Detector — Chameleon / Faker / 2-й ПК ==="
echo

# ── 1. Файлы Chameleon / Faker / обход SS ──
section "1 · Файлы (.faker / chameleon / bypass)"
PATTERNS='chameleon|\.faker|faker/|/faker|ss.?bypass|bypass.?ss|clean.?pc|fake.?launcher|process.?hider|self.?destruct|cold.?bypass|silent\.best|bypassing\.gg|obhod|обход.?ss|обход.?провер|второй.?пк|2.?й.?пк|dual.?pc|двойной.?пк'

while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  base=$(basename "$p")
  [[ "$base" =~ [Dd]etector|[Ss]cript|[Pp]latforms ]] && continue
  add_detect "файл: $p"
  echo "  [DETECT] $p"
done < <(
  find "$HOME" -maxdepth 5 \
    \( -iname '*chameleon*' -o -iname '*.faker' -o -iname '*faker*' \
       -o -iname '*ss-bypass*' -o -iname '*ss_bypass*' -o -iname '*cleanpc*' \
       -o -iname '*fake*launcher*' -o -path '*/.faker/*' \) \
    2>/dev/null | grep -ivE '/\.cache/|/node_modules/|linux-ss-scripts' | head -30
)

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  add_detect "history: $line"
  echo "  [DETECT] history → $line"
done < <(
  grep -iE "$PATTERNS" "$HOME/.bash_history" "$HOME/.zsh_history" 2>/dev/null \
    | grep -ivE 'detector\.sh|Platforms SS' | tail -15 || true
)

# ── 2. Второй ПК — KM sharing / remote ──
section "2 · Второй ПК — Synergy / Barrier / AnyDesk / Parsec"
DUAL_PROCS=(anydesk rustdesk teamviewer parsec sunshine moonlight
            barrier synergys synergy input-leap input-leapx
            x11vnc x0vncserver wayvnc xrdp tailscale zerotier)

for proc in "${DUAL_PROCS[@]}"; do
  if pgrep -xi "$proc" >/dev/null 2>&1; then
    pids=$(pgrep -xi "$proc" | tr '\n' ' ')
    case "$proc" in
      anydesk|rustdesk|teamviewer)
        add_detect "$proc запущен (PID $pids) — удалённый доступ / второй ПК для SS"
        ;;
      barrier|synergys|synergy|input-leap*)
        add_detect "$proc — общая мышь/клавиатура между ПК (чит на 2-м, SS на 1-м)"
        ;;
      parsec|sunshine|moonlight)
        add_detect "$proc — стрим игры с другого ПК (чит там, проверяют здесь)"
        ;;
      x11vnc|wayvnc|xrdp)
        add_detect "$proc — VNC/RDP (могут показывать «чистый» рабочий стол)"
        ;;
      tailscale|zerotier)
        add_warn "$proc VPN — часто связывают 2 ПК для обхода SS"
        ;;
    esac
    echo "  [DETECT] процесс: $proc (PID $pids)"
  fi
done

# AnyDesk incoming session
if command -v anydesk >/dev/null 2>&1; then
  anydesk --get-status 2>/dev/null | sed 's/^/  /' || true
fi

# ── 3. Minecraft на ЭТОМ ПК vs «я в игре» ──
section "3 · Minecraft на проверяемом ПК"
JAVA_PIDS=$(pgrep -f 'KnotClient|net.minecraft.client.main.Main' 2>/dev/null || true)
if [[ -z "$JAVA_PIDS" ]]; then
  echo "  java/KnotClient: НЕ запущен"
  add_warn "MC не запущен на этом ПК — если игрок «в игре» на экране = играет с ДРУГОГО ПК"
else
  echo "  java/KnotClient: PID $JAVA_PIDS"
fi

if [[ -f "$MC/logs/latest.log" ]]; then
  log_age=$(( $(date +%s) - $(stat -c %Y "$MC/logs/latest.log" 2>/dev/null || echo 0) ))
  echo "  latest.log: обновлён ${log_age} сек назад"
  if [[ -z "$JAVA_PIDS" && "$log_age" -gt 600 ]]; then
    add_detect "java нет, но latest.log старый (${log_age}s) — типичный «чистый» ПК для SS, игра на другом"
  fi
  if [[ -n "$JAVA_PIDS" && "$log_age" -gt 120 ]]; then
    add_warn "java есть, но latest.log не пишется ${log_age}s — подозрительно"
  fi
else
  add_warn "latest.log нет"
fi

# Слишком «чистый» .minecraft при активном аккаунте
if [[ -d "$MC" ]]; then
  mod_n=$(find "$MC/mods" -maxdepth 1 -name '*.jar' 2>/dev/null | wc -l)
  log_n=$(find "$MC/logs" -maxdepth 1 \( -name '*.log' -o -name '*.log.gz' \) 2>/dev/null | wc -l)
  echo "  mods: $mod_n jar · logs: $log_n файлов"
  [[ "$mod_n" -eq 0 && "$log_n" -lt 3 ]] && add_warn "mods пуст + мало logs — свежий/фейковый .minecraft для SS?"
fi

# ── 4. OBS / виртуальная камера (подмена экрана) ──
section "4 · Подмена экрана (OBS / v4l2loopback)"
lsmod 2>/dev/null | grep -q v4l2loopback && {
  add_detect "v4l2loopback загружен — виртуальная webcam (подмена демонстрации экрана)"
  echo "  [DETECT] kernel: v4l2loopback"
}
pgrep -x obs >/dev/null 2>&1 || pgrep -f 'obs-studio' >/dev/null 2>&1 && {
  add_warn "OBS запущен — проверь что показывает AnyDesk (не виртуальная камера)"
  echo "  [WARN] OBS процесс активен"
}
[[ -e /dev/video10 || -e /dev/video2 ]] && ls -l /dev/video* 2>/dev/null | sed 's/^/  /' || true

# ── 5. Браузер — Chameleon / Faker / обход SS ──
section "5 · Браузер (Chameleon / Faker / dual PC)"
if command -v python3 >/dev/null 2>&1; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "  [DETECT] $line"
    add_detect "browser: $line"
  done < <(python3 - "$HOME" <<'PY'
import glob, os, re, shutil, sqlite3, sys, tempfile
HOME = sys.argv[1]
RE = re.compile(
    r"chameleon|\.faker|faker.?tool|faker.?mc|ss.?bypass|bypass.?ss|"
    r"второй.?пк|2.?й.?пк|dual.?pc|обход.?ss|обход.?провер|"
    r"clean.?pc|fake.?launcher|silent\.best|bypassing|cold.?bypass|"
    r"synergy|barrier.?km|input.?leap|process.?hider|self.?destruct",
    re.I,
)
for pat in (
    ".config/google-chrome/*/History",
    ".config/chromium/*/History",
    ".config/BraveSoftware/Brave-Browser/*/History",
    ".config/microsoft-edge/*/History",
):
    for db in glob.glob(os.path.join(HOME, pat)):
        tmp = tempfile.mktemp(suffix=".db")
        try:
            shutil.copy2(db, tmp)
            con = sqlite3.connect(tmp)
            for url, title in con.execute("SELECT url, IFNULL(title,'') FROM urls"):
                if RE.search(f"{url} {title}"):
                    print(f"{url[:100]} | {title[:60]}")
            con.close()
        except Exception:
            pass
        finally:
            try:
                os.unlink(tmp)
            except OSError:
                pass
PY
  )
fi

# dedupe DETECT array
declare -A seen=()
uniq=()
for d in "${DETECT[@]}"; do
  [[ -n "${seen[$d]:-}" ]] && continue
  seen[$d]=1
  uniq+=("$d")
done

# ── Итог ──
section "Итог"
echo "Схема обхода: чит на ПК-1 → AnyDesk/Synergy на ПК-2 (чистый) → команды SS там."
echo "Chameleon/Faker — софт/файлы для «чистого» прохождения проверки."
echo

if [[ ${#WARN[@]} -gt 0 ]]; then
  for w in "${WARN[@]}"; do echo "[WARN] $w"; done
  echo
fi

if [[ ${#uniq[@]} -eq 0 ]]; then
  echo "[OK] Chameleon/Faker/2-й ПК — явных следов нет."
  echo "     Сверь: игрок реально на ЭТОМ ПК? java запущен? экран = этот монитор?"
  exit 0
fi

echo "[DETECT] Найдено: ${#uniq[@]}"
for d in "${uniq[@]}"; do
  echo "  → $d"
done
echo
echo "Вердикт: второй ПК / Faker / Chameleon → проверка на другой машине или подмена экрана."
exit 2
