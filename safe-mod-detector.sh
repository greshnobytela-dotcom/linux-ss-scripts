#!/usr/bin/env bash
# SafeMod Detector — сессии Minecraft: СТАРТ / КОНЕЦ / длительность
# Источники: ~/.minecraft/logs/*.log* (без TLauncher/journal — только игровые логи)

set -uo pipefail

MC="${MINECRAFT_DIR:-$HOME/.minecraft}"
LIMIT="${1:-200}"
[[ "$LIMIT" =~ ^[0-9]+$ ]] || LIMIT=200

echo "=== SafeMod Detector — сессии Minecraft (старт / стоп) ==="
echo

if ! command -v python3 >/dev/null 2>&1; then
  echo "[ERR] Нужен python3."
  exit 1
fi

python3 - "$MC" "$LIMIT" <<'PY'
import glob, gzip, os, re, sys
from datetime import datetime, timedelta

MC = sys.argv[1]
LIMIT = int(sys.argv[2])

TIME_RE = re.compile(r"^\[(\d{2}:\d{2}:\d{2})\]")
START_RE = re.compile(r"Loading Minecraft", re.I)
END_RES = [
    re.compile(r"Stopping worker threads", re.I),
    re.compile(r"Stopping!", re.I),
    re.compile(r"Game crashed", re.I),
    re.compile(r"Shutting down GL", re.I),
]

sessions = []


def parse_time(date_str, tstr):
    try:
        return datetime.strptime(f"{date_str} {tstr}", "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


def date_from_logname(name, path):
    m = re.match(r"(\d{4}-\d{2}-\d{2})-\d+\.log", name)
    if m:
        return m.group(1)
    if name == "latest.log":
        return datetime.fromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%d")
    return datetime.fromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%d")


def open_log(path):
    if path.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, encoding="utf-8", errors="replace")


def scan_file(path):
    name = os.path.basename(path)
    date_str = date_from_logname(name, path)
    start_t = end_t = None
    version = ""
    crashed = False
    mod_fail = False
    clean_stop = False

    try:
        with open_log(path) as f:
            for raw in f:
                line = raw.rstrip("\n")
                tm = TIME_RE.match(line)
                if not tm:
                    continue
                tstr = tm.group(1)
                if START_RE.search(line):
                    start_t = tstr
                    vm = re.search(r"Loading Minecraft ([0-9.]+)", line)
                    if vm:
                        version = vm.group(1)
                if re.search(r"Mod resolution failed", line, re.I):
                    mod_fail = True
                if re.search(r"Game crashed", line, re.I):
                    crashed = True
                for er in END_RES:
                    if er.search(line):
                        end_t = tstr
                        if "Stopping" in er.pattern:
                            clean_stop = True
                        break
                end_t = tstr
    except OSError:
        return

    if not start_t:
        return

    sd = parse_time(date_str, start_t)
    ed = parse_time(date_str, end_t or start_t)
    if not sd or not ed:
        return
    if ed < sd:
        ed += timedelta(days=1)
    dur = ed - sd

    status = "норма"
    if dur.total_seconds() < 30 and not clean_stop:
        status = "ошибка запуска"
    elif mod_fail and dur.total_seconds() < 90:
        status = "ошибка запуска"
    elif crashed:
        status = "краш"
    elif not clean_stop and name == "latest.log":
        status = "в игре / без stop"

    sessions.append({
        "start": sd, "end": ed, "dur": dur,
        "file": name, "version": version, "status": status,
    })


log_dir = os.path.join(MC, "logs")
if not os.path.isdir(log_dir):
    print("[OK] Сессии не найдены — нет ~/.minecraft/logs/")
    sys.exit(0)

files = sorted(
    glob.glob(os.path.join(log_dir, "*.log"))
    + glob.glob(os.path.join(log_dir, "*.log.gz")),
    key=lambda p: (date_from_logname(os.path.basename(p), p), os.path.getmtime(p)),
)

for path in files:
    scan_file(path)

if not sessions:
    print("[OK] Сессии Minecraft не найдены (логи пусты или удалены).")
    sys.exit(0)

# dedupe: один файл = одна строка; latest.log не дублирует архив если тот же старт ±1 мин
sessions.sort(key=lambda s: s["start"], reverse=True)
uniq = []
seen_starts = set()
for s in sessions:
    key = s["start"].strftime("%Y-%m-%d %H:%M")
    if key in seen_starts and s["file"] != "latest.log":
        continue
    if s["file"] == "latest.log":
        dup = any(
            abs((s["start"] - o["start"]).total_seconds()) < 120
            and o["file"] != "latest.log"
            for o in uniq
        )
        if dup:
            continue
    seen_starts.add(key)
    uniq.append(s)

uniq = uniq[:LIMIT]

print(f"{'СТАРТ':<20} {'КОНЕЦ':<20} {'ДЛИТ.':<10} {'СТАТУС':<18} {'ЛОГ':<22} {'ВЕРСИЯ'}")
print("-" * 110)
for s in uniq:
    d = s["dur"]
    sec = int(d.total_seconds())
    if sec >= 3600:
        dh = f"{sec // 3600}ч{(sec % 3600) // 60}м"
    elif sec >= 60:
        dh = f"{sec // 60}м"
    else:
        dh = f"{sec}с"
    ver = s["version"] or "—"
    print(
        f"{s['start'].strftime('%Y-%m-%d %H:%M:%S'):<20} "
        f"{s['end'].strftime('%Y-%m-%d %H:%M:%S'):<20} "
        f"{dh:<10} {s['status']:<18} {s['file']:<22} {ver}"
    )

print()
print(f"Всего запусков: {len(uniq)}")
print("Сверь время PC-check: игрок был в игре в момент проверки? (строка СТАРТ–КОНЕЦ)")
sys.exit(0)
PY

exit $?
