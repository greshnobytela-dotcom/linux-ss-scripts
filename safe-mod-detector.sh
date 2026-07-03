#!/usr/bin/env bash
# SafeMod Detector — все сессии Minecraft: СТАРТ / КОНЕЦ / длительность
# Источники: ~/.minecraft/logs/*.log*, TLauncher logs, journalctl (доп.)

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

python3 - "$MC" "$HOME" "$LIMIT" <<'PY'
import glob, gzip, os, re, subprocess, sys
from datetime import datetime, timedelta

MC = sys.argv[1]
HOME = sys.argv[2]
LIMIT = int(sys.argv[3])

TIME_RE = re.compile(r"^\[(\d{2}:\d{2}:\d{2})\]")
START_RE = re.compile(r"Loading Minecraft|Starting Minecraft|Launching minecraft", re.I)
END_RES = [
    re.compile(r"Stopping worker threads", re.I),
    re.compile(r"Stopping!", re.I),
    re.compile(r"Game crashed", re.I),
    re.compile(r"Shutting down GL", re.I),
    re.compile(r"Normal exit", re.I),
    re.compile(r"Child process closed with exit code", re.I),
    re.compile(r"Minecraft process unregistered", re.I),
    re.compile(r"Launcher has stopped", re.I),
]
TL_TIME = re.compile(r"(\d{2}:\d{2}:\d{2}),\d{3}")

sessions = []  # start_dt, end_dt, source, logfile, version, note


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
    m = re.match(r"(\d{4}-\d{2}-\d{2})", name)
    if m:
        return m.group(1)
    return datetime.fromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%d")


def open_log(path):
    if path.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, encoding="utf-8", errors="replace")


def scan_lines(lines, date_str, source, logfile):
    start_t = end_t = None
    version = ""
    end_note = ""
    for raw in lines:
        line = raw.rstrip("\n")
        # TLauncher format: [39m17:17:01,146 [MinecraftLauncher] ...
        tm = TIME_RE.match(line)
        tstr = tm.group(1) if tm else None
        if not tstr:
            m = TL_TIME.search(line)
            if m:
                tstr = m.group(1)
        if START_RE.search(line) and tstr:
            start_t = tstr
            vm = re.search(r"Loading Minecraft ([0-9.]+)", line, re.I)
            if vm:
                version = vm.group(1)
        for er in END_RES:
            if er.search(line) and tstr:
                end_t = tstr
                end_note = er.pattern[:30]
                break
        if tm and not end_t:
            end_t = tstr  # last timestamp fallback
    if not start_t:
        return
    if not end_t:
        end_t = start_t
        end_note = "нет явного stop (kill/crash?)"
    sd = parse_time(date_str, start_t)
    ed = parse_time(date_str, end_t)
    if not sd or not ed:
        return
    if ed < sd:
        ed += timedelta(days=1)
    dur = ed - sd
    sessions.append({
        "start": sd, "end": ed, "dur": dur,
        "source": source, "file": os.path.basename(logfile),
        "version": version, "note": end_note,
    })


def scan_mc_logs():
    log_dir = os.path.join(MC, "logs")
    if not os.path.isdir(log_dir):
        return
    files = sorted(
        glob.glob(os.path.join(log_dir, "*.log"))
        + glob.glob(os.path.join(log_dir, "*.log.gz")),
        key=lambda p: os.path.getmtime(p),
    )
    for path in files:
        name = os.path.basename(path)
        date_str = date_from_logname(name, path)
        try:
            with open_log(path) as f:
                scan_lines(f, date_str, "minecraft/logs", path)
        except OSError:
            pass


def scan_tlauncher():
    for path in sorted(glob.glob(os.path.join(HOME, ".tlauncher/logs/launcher.log*"))):
        date_str = datetime.fromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%d")
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                scan_lines(f, date_str, "TLauncher", path)
        except OSError:
            pass


def scan_journal():
    try:
        out = subprocess.run(
            ["journalctl", "--user", "--since", "90 days ago", "-o", "short-iso", "--no-pager"],
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return
    if out.returncode != 0:
        return
    cur_start = None
    for line in out.stdout.splitlines():
        if "KnotClient" not in line and "minecraft" not in line.lower():
            continue
        if "Started" in line or "starting" in line.lower():
            try:
                cur_start = datetime.fromisoformat(line[:19].replace(" ", "T"))
            except ValueError:
                pass
        if cur_start and ("Stopped" in line or "terminated" in line.lower()):
            try:
                end = datetime.fromisoformat(line[:19].replace(" ", "T"))
                sessions.append({
                    "start": cur_start, "end": end,
                    "dur": end - cur_start,
                    "source": "journalctl", "file": "—",
                    "version": "", "note": "user journal",
                })
            except ValueError:
                pass
            cur_start = None


scan_mc_logs()
scan_tlauncher()
scan_journal()

if not sessions:
    print("[OK] Сессии Minecraft не найдены.")
    print("     Нет logs/ или всё удалено.")
    sys.exit(0)

# dedupe close sessions same minute
sessions.sort(key=lambda s: s["start"], reverse=True)
uniq = []
seen = set()
for s in sessions:
    key = (s["start"].strftime("%Y-%m-%d %H:%M"), s["source"], s["file"])
    if key in seen:
        continue
    seen.add(key)
    uniq.append(s)

uniq = uniq[:LIMIT]

print(f"{'СТАРТ':<20} {'КОНЕЦ':<20} {'ДЛИТ.':<10} {'ИСТОЧНИК':<16} {'ЛОГ':<22} {'ВЕРСИЯ'}")
print("-" * 105)
for s in uniq:
    d = s["dur"]
    dh = f"{int(d.total_seconds()//3600)}ч{int((d.total_seconds()%3600)//60)}м" if d.total_seconds() >= 60 else f"{int(d.total_seconds())}с"
    ver = s["version"] or "—"
    note = f" ({s['note']})" if s.get("note") and "Stopping" not in s["note"] else ""
    print(f"{s['start'].strftime('%Y-%m-%d %H:%M:%S'):<20} {s['end'].strftime('%Y-%m-%d %H:%M:%S'):<20} {dh:<10} {s['source']:<16} {s['file']:<22} {ver}{note}")

print()
print(f"Всего сессий: {len(uniq)}")
if len(uniq) >= 2:
    gaps = []
    sorted_asc = sorted(uniq, key=lambda x: x["start"])
    for i in range(1, len(sorted_asc)):
        gap = sorted_asc[i]["start"] - sorted_asc[i - 1]["end"]
        if gap.total_seconds() > 300:
            gaps.append((sorted_asc[i - 1]["end"], sorted_asc[i]["start"], gap))
    if gaps:
        print()
        print("Перерывы между сессиями (>5 мин) — окно для инжекта/перезапуска с читом:")
        for a, b, g in gaps[-8:]:
            h = int(g.total_seconds() // 3600)
            m = int((g.total_seconds() % 3600) // 60)
            print(f"  {a.strftime('%Y-%m-%d %H:%M')} → {b.strftime('%Y-%m-%d %H:%M')}  ({h}ч{m}м)")

print()
print("[INFO] SafeMod: сравни время SS с таблицей — игра была запущена во время проверки?")
sys.exit(0)
PY

exit $?
