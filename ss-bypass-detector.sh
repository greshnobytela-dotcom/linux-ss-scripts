#!/usr/bin/env bash
# SS Bypass — Chameleon / Faker / Silent / второй ПК (Synergy, Parsec, v4l2loopback)
# v2 — AnyDesk = INFO (не detect). CDN: jsdelivr (raw/main кэширует старое).

set -uo pipefail

MC="${MINECRAFT_DIR:-$HOME/.minecraft}"
DETECT=()
WARN=()
INFO=()

add_detect() { DETECT+=("$1"); }
add_warn()   { WARN+=("$1"); }
add_info()   { INFO+=("$1"); }
section()    { echo; echo "━━ $1 ━━"; }

find_mc_pids() {
  ps aux | grep '[j]ava' | grep -v cursor | grep -v cursorsandbox \
    | grep -E 'KnotClient|net\.minecraft\.client\.main\.Main' \
    | grep -v bootstrap | awk '{print $2}' | sort -u
}

echo "=== SS Bypass — Chameleon / Faker / Silent / 2-й ПК ==="
echo "  AnyDesk/RustDesk на ПК игрока при SS — норма (модер подключается сюда)."
echo

# ── 1. Chameleon / Faker / Silent / Cold — файлы и следы ──
section "1 · Chameleon / Faker / Silent / fileless"
HIST_PAT='chameleon|\.faker|faker.?launcher|faker.?mc|silent\.best|bypassing\.gg|cold.?bypass|cold.?client|process.?hider|self.?destruct|selfdestruct|fileless|memory.?only|обход.?ss|второй.?пк|dual.?pc|clean.?pc|fake.?launcher'

while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  base=$(basename "$p")
  [[ "$base" =~ [Dd]etector|[Ss]cript|[Pp]latforms|ss-bypass ]] && continue
  add_detect "файл bypass: $p"
  echo "  [DETECT] $p"
done < <(
  find "$HOME" -maxdepth 6 \
    \( -iname '*.faker' -o -path '*/.faker/*' \
       -o -iname '*chameleon*client*' -o -iname '*chameleon*.jar' \
       -o -iname '*silent*loader*' -o -iname '*cold*bypass*' \
       -o -iname '*ss-bypass*' -o -iname '*ss_bypass*' \
       -o -iname '*cleanpc*' -o -iname '*fake*launcher*' \) \
    2>/dev/null | grep -ivE '/\.cache/|/node_modules/|linux-ss-scripts|\.local/share/Trash' | head -25
)

# Faker = поддельный лаунчер (Electron): minecraft.html + config selfdestruct
while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  [[ -f "$d/minecraft.html" && -f "$d/index.html" ]] || continue
  if [[ -f "$d/config.json" ]] && grep -qiE 'selfdestruct|self.?destruct|autoclick' "$d/config.json" 2>/dev/null; then
    add_detect "Faker-launcher (fake MC UI): $d"
    echo "  [DETECT] Faker-kit: $d (minecraft.html + selfdestruct config)"
  elif [[ -f "$d/run.vbs" || -f "$d/main.html" ]]; then
    add_detect "подозрительный fake-launcher: $d"
    echo "  [DETECT] fake-launcher: $d"
  fi
done < <(find "$HOME/Downloads" "$HOME/Desktop" "$HOME/Загрузки" "$HOME/Рабочий стол" \
  -maxdepth 3 -type d 2>/dev/null | head -80)

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  add_detect "history: $line"
  echo "  [DETECT] history → $line"
done < <(
  grep -iE "$HIST_PAT" "$HOME/.bash_history" "$HOME/.zsh_history" 2>/dev/null \
    | grep -ivE 'detector\.sh|Platforms SS|ss-bypass' | tail -12 || true
)

# Chameleon/Silent = fileless: anonymous jar в java (не pipewire/memfd/jvm)
section "1b · Fileless / memfd в java (Chameleon-style)"
MC_PIDS=$(find_mc_pids || true)
if [[ -n "$MC_PIDS" ]]; then
  for pid in $MC_PIDS; do
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "$line" | grep -qiE 'pipewire|memfd:.*\[|libjvm|\.minecraft/versions|\.minecraft/libraries|ffi|cursor|gradle' && continue
      add_detect "PID $pid maps: $line"
      echo "  [DETECT] java $pid → $line"
    done < <(
      grep -iE '/tmp/|/dev/shm/|\(deleted\)|memfd:' "/proc/$pid/maps" 2>/dev/null \
        | grep -iE '\.jar|\.so|cheat|client|inject|ghost|chameleon|faker' \
        | grep -ivE 'pipewire|libpipewire|jvm|\.minecraft' | head -8 || true
    )
  done
else
  echo "  java MC не найден — пропуск maps"
fi

# ── 2. Второй ПК — НЕ AnyDesk (это SS), а KM-share / стрим ──
section "2 · Второй ПК — Synergy / Barrier / Parsec (не AnyDesk)"
# AnyDesk/RustDesk/TeamViewer — инфо, не detect
for proc in anydesk rustdesk teamviewer; do
  if pgrep -xi "$proc" >/dev/null 2>&1; then
    pids=$(pgrep -xi "$proc" | tr '\n' ' ')
    add_info "$proc PID $pids — норма: модер подключается через него"
    echo "  [INFO] $proc (PID $pids) — стандартный SS, не бан"
  fi
done

# Реальные признаки dual PC
DUAL_DETECT=(barrier synergys synergy input-leap input-leapx parsec sunshine)
for proc in "${DUAL_DETECT[@]}"; do
  if pgrep -xi "$proc" >/dev/null 2>&1; then
    pids=$(pgrep -xi "$proc" | tr '\n' ' ')
    case "$proc" in
      barrier|synergys|synergy|input-leap*)
        add_detect "$proc — одна мышь/клавиатура на 2 ПК: чит на одном, команды SS на другом"
        ;;
      parsec|sunshine)
        add_detect "$proc — стрим игры с другого ПК (на экране игра, проверяют «чистый» десктоп)"
        ;;
    esac
    echo "  [DETECT] $proc (PID $pids)"
  fi
done

pgrep -xi moonlight >/dev/null 2>&1 && {
  add_warn "moonlight — клиент стрима с другого ПК, сверь что java локальный"
  echo "  [WARN] moonlight активен"
}

for proc in tailscale zerotier; do
  pgrep -xi "$proc" >/dev/null 2>&1 && {
    add_warn "$proc — VPN между ПК, часто в паре с Barrier для dual PC"
    echo "  [WARN] $proc"
  }
done

# VNC-сервер на этом ПК = могут показывать «чистый» рабочий стол модеру
for proc in x11vnc x0vncserver wayvnc; do
  pgrep -xi "$proc" >/dev/null 2>&1 && {
    pids=$(pgrep -xi "$proc" | tr '\n' ' ')
    add_detect "$proc сервер (PID $pids) — удалённый просмотр этого экрана / подмена"
    echo "  [DETECT] $proc (PID $pids)"
  }
done

# ── 3. Minecraft реально на ЭТОМ ПК ──
section "3 · Minecraft на проверяемом ПК"
JAVA_PIDS="$MC_PIDS"
if [[ -z "$JAVA_PIDS" ]]; then
  echo "  KnotClient/java MC: НЕ запущен"
  add_detect "java MC не запущен — если на экране видна игра = dual PC / Parsec / подмена"
else
  echo "  KnotClient/java MC: PID $(echo "$JAVA_PIDS" | tr '\n' ' ')"
  for pid in $JAVA_PIDS; do
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-120)
    echo "    $pid: $cmd"
  done
fi

# latest.log — только если MC не запущен или log не открыт java
log_age=999999
[[ -f "$MC/logs/latest.log" ]] && log_age=$(( $(date +%s) - $(stat -c %Y "$MC/logs/latest.log" 2>/dev/null || echo 0) ))
echo "  latest.log ($MC): ${log_age}s назад"

log_open=false
if [[ -n "$JAVA_PIDS" && -f "$MC/logs/latest.log" ]]; then
  for pid in $JAVA_PIDS; do
    readlink -f "/proc/$pid/fd/"* 2>/dev/null | grep -q "$MC/logs/latest.log" && log_open=true
  done
fi

if [[ -z "$JAVA_PIDS" ]]; then
  [[ "$log_age" -lt 300 ]] && add_warn "java нет, но latest.log свежий (${log_age}s) — MC только что закрыли?"
  [[ "$log_age" -gt 600 ]] && add_warn "java нет, latest.log старый — могли показать «чистый» ПК без игры"
elif [[ "$log_open" == false && "$log_age" -gt 300 ]]; then
  add_warn "java есть, но latest.log не в fd процесса и старый — MC может идти с другого .minecraft или другого ПК"
fi

if [[ -d "$MC" ]]; then
  mod_n=$(find "$MC/mods" -maxdepth 1 -name '*.jar' 2>/dev/null | wc -l)
  log_n=$(find "$MC/logs" -maxdepth 1 \( -name '*.log' -o -name '*.log.gz' \) 2>/dev/null | wc -l)
  ver_n=$(find "$MC/versions" -maxdepth 1 -name '*.jar' 2>/dev/null | wc -l)
  echo "  mods: $mod_n · logs: $log_n · versions jar: $ver_n"
  [[ "$mod_n" -eq 0 && "$log_n" -lt 2 && "$ver_n" -lt 2 ]] && \
    add_warn "пустой .minecraft (mods/logs/versions) — фейковый профиль для SS?"
fi

# ── 4. Подмена экрана (OBS virtual cam) ──
section "4 · Подмена экрана (v4l2loopback + OBS)"
v4l2=false
lsmod 2>/dev/null | grep -q v4l2loopback && v4l2=true
obs=false
pgrep -x obs >/dev/null 2>&1 || pgrep -f 'obs-studio' >/dev/null 2>&1 && obs=true

if $v4l2; then
  add_detect "v4l2loopback — виртуальная webcam (AnyDesk может показывать не рабочий стол)"
  echo "  [DETECT] kernel module v4l2loopback"
fi
if $v4l2 && $obs; then
  add_detect "OBS + v4l2loopback — типичная подмена картинки для SS"
  echo "  [DETECT] OBS + virtual cam одновременно"
elif $obs; then
  add_info "OBS запущен — ок для записи; бан только с v4l2loopback / virtual cam"
  echo "  [INFO] OBS без v4l2loopback — не detect"
fi
$v4l2 && ls -l /dev/video* 2>/dev/null | sed 's/^/  /' || true

# ── 5. Браузер ──
section "5 · Браузер (Chameleon / Faker / Silent / dual PC)"
if command -v python3 >/dev/null 2>&1; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "  [DETECT] $line"
    add_detect "browser: $line"
  done < <(python3 - "$HOME" <<'PY'
import glob, os, re, shutil, sqlite3, sys, tempfile
HOME = sys.argv[1]
RE = re.compile(
    r"chameleon|\.faker|faker.?launcher|faker.?mc|silent\.best|bypassing\.gg|"
    r"cold.?bypass|cold.?client|process.?hider|self.?destruct|fileless|"
    r"второй.?пк|dual.?pc|обход.?ss|обход.?провер|clean.?pc|fake.?launcher|"
    r"barrier.?km|input.?leap|pcaclient|launcher.?clicker",
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

# dedupe
declare -A seen=()
uniq=()
for d in "${DETECT[@]}"; do
  [[ -n "${seen[$d]:-}" ]] && continue
  seen[$d]=1
  uniq+=("$d")
done

# ── Итог ──
section "Итог"
echo "Chameleon/Silent/Cold — fileless, без следов на диске, self-destruct."
echo "Faker — поддельный лаунчер MC (Electron, minecraft.html, selfdestruct)."
echo "2-й ПК — Barrier/Synergy + чит на другой машине; Parsec/Sunshine стримят игру."
echo "AnyDesk при SS — норма, не detect."
echo

[[ ${#INFO[@]} -gt 0 ]] && { for i in "${INFO[@]}"; do echo "[INFO] $i"; done; echo; }
[[ ${#WARN[@]} -gt 0 ]]  && { for w in "${WARN[@]}"; do echo "[WARN] $w"; done; echo; }

if [[ ${#uniq[@]} -eq 0 ]]; then
  echo "[OK] Chameleon / Faker / dual PC — явных следов нет."
  echo "     Проверь: java на этом ПК · Barrier/Parsec нет · не virtual cam."
  exit 0
fi

echo "[DETECT] Найдено: ${#uniq[@]}"
for d in "${uniq[@]}"; do echo "  → $d"; done
echo
echo "Вердикт: см. пункты выше (не AnyDesk сам по себе)."
exit 2
