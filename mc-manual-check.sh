#!/usr/bin/env bash
# MC Manual Check — мануал SS шаги 1–8 (Linux)
# TLauncher/Fabric: ~/.minecraft  ·  Prism: ~/.local/share/PrismLauncher/instances/*/minecraft

set -uo pipefail

MC="${MINECRAFT_DIR:-$HOME/.minecraft}"
SS_START="${SS_START_EPOCH:-0}"   # export SS_START_EPOCH=$(date +%s) в начале SS
SCREEN_DAYS="${1:-21}"

echo "=== MC Manual Check (Linux) — мануал шаги 1–8 ==="
echo "Папка игры: $MC"
echo

if ! command -v python3 >/dev/null 2>&1; then
  echo "[ERR] Нужен python3."
  exit 1
fi

[[ -d "$MC" ]] || { echo "[ERR] Нет $MC"; exit 1; }

python3 - "$MC" "$SCREEN_DAYS" "$SS_START" <<'PY'
import glob, json, os, re, sys, time
from datetime import datetime, timedelta

MC = sys.argv[1]
SCREEN_DAYS = int(sys.argv[2])
SS_START = int(sys.argv[3]) if sys.argv[3].isdigit() else 0

DETECT = []
WARN = []
INFO = []

CLIENTS = (
    "nursultan", "wexside", "wexide", "expensive", "minced", "delta", "deltaclient",
    "celestial", "celka", "zenith", "haruka", "rockstar", "catlavan", "wildclient",
    "doomsday", "vape", "vapev4", "vapelite", "meteor", "liquidbounce", "wurst",
    "aristois", "fdp", "fdpclient", "novoline", "onetap", "manthe", "thunderhack",
    "bleachhack", "impact", "phobos", "xulu", "astolfo", "exosware", "grim",
    "entropy", "dream", "drip", "sunset", "slinky", "karma", "sigma", "moon",
    "zeroday", "rise", "akrien", "atomic", "raven", "flux", "weedhack",
    "eclipse", "nixware", "interium", "spirt", "matix", "deadcode", "relake",
    "venus", "quickclient", "fluger", "winzor", "ponos", "nevermore", "koid",
    "fusion", "huzuni", "sigma5", "remix", "cortex", "entrance", "nightmare",
    "nurik", "cataclysm", "wissend", "nuclear", "drogan", "spooky", "chameleon",
    "faker", "intent", "monot",
)

GENERIC = frozenset(("ghost", "hack", "cheat", "client", "skid"))
CLIENT_RE = re.compile("|".join(re.escape(c) for c in CLIENTS if c not in GENERIC), re.I)

LEGIT_ROOT = {
    "assets", "config", "data", "debug", "logs", "mods", "resourcepacks", "saves",
    "screenshots", "versions", "libraries", "downloads", "server-resource-packs",
    "shaderpacks", "crash-reports", "command_history.txt", "options.txt",
    "servers.dat", "servers.dat.bak", "servers.dat_old", "usercache.json",
    "launcher_profiles.json", "tlauncher_profiles.json", "crosshair_config.ccmcfg",
    "debug-profile.json", ".fabric", "fabricloader", "realms_persistence.json",
}

VANILLA_KB = {
    "1.16": 17083, "1.16.1": 17083,
    "1.16.2": 17096, "1.16.3": 17096,
    "1.16.4": 17136, "1.16.5": 17136,
    "1.17": 19079, "1.17.1": 19089,
    "1.18": 19569, "1.18.1": 19573, "1.18.2": 19785,
    "1.19": 20960, "1.19.1": 21137, "1.19.2": 21138, "1.19.3": 22173, "1.19.4": 22927,
    "1.20": 22489, "1.20.1": 22490, "1.20.2": 22643,
    "1.21": 26208, "1.21.4": 27672,
}

LOADER_MARK = re.compile(r"fabric|forge|quilt|laby|lunar|feather|optifine|tlauncher", re.I)
CHEAT_MOD_RE = re.compile(
    r"killaura|triggerbot|aimassist|xray|scaffold|selfdestruct|clickgui|"
    r"combat|hack|ghost.?client|cheat",
    re.I,
)

FORBIDDEN_MOD_NAMES = CLIENT_RE


def add_detect(msg):
    DETECT.append(msg)


def add_warn(msg):
    WARN.append(msg)


def add_info(msg):
    INFO.append(msg)


def section(n, title):
    print(f"\n━━ Шаг {n} · {title} ━━")


def is_cheat_name(name):
    n = name.lower()
    if CLIENT_RE.search(n):
        return True
    return False


# ── Шаг 1 · скрытые элементы (Linux: dot-файлы в корне) ──
section(1, "Скрытые элементы в корне .minecraft (Linux: ls -la)")
hidden = []
try:
    for name in os.listdir(MC):
        if name.startswith("."):
            hidden.append(name)
        elif name.startswith("_") and "IAS" in name.upper():
            add_info(f"скрытая папка IAS: {name} (легит мод аккаунтов)")
except OSError:
    pass

if hidden:
    for h in sorted(hidden):
        path = os.path.join(MC, h)
        tag = "[DETECT]" if is_cheat_name(h) else "[INFO]"
        print(f"  {tag} {h}/")
        if tag == "[DETECT]":
            add_detect(f"скрытая папка чита: {h}")
else:
    print("  [INFO] dot-папок кроме .fabric нет")

print("  → Linux: Nautilus/Dolphin — Ctrl+H показать скрытые; проверь глазами")

# ── Шаг 2 · корень — папки с названием читов ──
section(2, "Корень .minecraft — папки с названием читов")
found_root = False
try:
    for name in sorted(os.listdir(MC)):
        path = os.path.join(MC, name)
        if not os.path.isdir(path):
            continue
        low = name.lower()
        if low in LEGIT_ROOT or name in LEGIT_ROOT:
            continue
        if low.startswith("_ias"):
            continue
        if is_cheat_name(name):
            print(f"  [DETECT] папка: {name}/")
            add_detect(f"корень .minecraft: {name}/")
            found_root = True
        elif low not in {x.lower() for x in LEGIT_ROOT}:
            print(f"  [WARN] нестандартная папка: {name}/ — проверь вручную")
            add_warn(f"нестандартная папка: {name}/")
except OSError:
    pass
if not found_root:
    print("  [OK] папок с именем чита в корне нет")

# ── Шаг 3 · screenshots 21 день ──
section(3, f"screenshots — последние {SCREEN_DAYS} дн. (смотри глазами)")
shot_dir = os.path.join(MC, "screenshots")
cutoff = time.time() - SCREEN_DAYS * 86400
recent = []
if os.path.isdir(shot_dir):
    for name in os.listdir(shot_dir):
        if not name.lower().endswith((".png", ".jpg", ".jpeg")):
            continue
        path = os.path.join(shot_dir, name)
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if mtime >= cutoff:
            recent.append((mtime, name, os.path.getsize(path)))
    recent.sort(reverse=True)
    if recent:
        print(f"  Найдено {len(recent)} скрин(ов) за {SCREEN_DAYS} дн. (новые сверху):")
        for mtime, name, size in recent[:30]:
            when = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
            print(f"    {when}  {name}  ({size // 1024} KB)")
        if len(recent) > 30:
            print(f"    … ещё {len(recent) - 30}")
    else:
        print("  [INFO] скринов за период нет")
else:
    print("  [WARN] папки screenshots нет")

print("  → Проверь на скрине: F3 (версия) · чат Nursultan/Celestial · трассеры/ESP ·")
print("    хитбоксы · над хотбаром (Freecam enabled…) · GUI чита")

# ── Шаг 4 · versions — имя и вес jar ──
section(4, "versions — папки и вес .jar (таблица vanilla)")
ver_dir = os.path.join(MC, "versions")
if not os.path.isdir(ver_dir):
    print("  [WARN] versions/ нет")
else:
    for folder in sorted(os.listdir(ver_dir)):
        fpath = os.path.join(ver_dir, folder)
        if not os.path.isdir(fpath):
            continue
        jars = glob.glob(os.path.join(fpath, "*.jar"))
        print(f"  📁 {folder}/")
        if LOADER_MARK.search(folder):
            add_info(f"versions/{folder} — loader (Fabric/Laby/…), таблица vanilla не применяется")
            for j in jars:
                kb = os.path.getsize(j) // 1024
                print(f"      {os.path.basename(j)}  {kb} KB  [INFO loader jar]")
            continue
        for j in jars:
            base = os.path.basename(j)
            kb = os.path.getsize(j) // 1024
            ver_m = re.search(r"(1\.\d+(?:\.\d+)?)", base) or re.search(r"(1\.\d+(?:\.\d+)?)", folder)
            ver = ver_m.group(1) if ver_m else None
            exp = VANILLA_KB.get(ver) if ver else None
            if exp is None and ver:
                # ближайшая minor
                for k, v in VANILLA_KB.items():
                    if ver.startswith(k.rsplit(".", 1)[0]):
                        exp = v
                        break
            if exp:
                diff = abs(kb - exp)
                if diff > 120:
                    print(f"      [DETECT] {base}  {kb} KB  (ожид. ~{exp} KB vanilla, Δ{diff})")
                    add_detect(f"versions: {folder}/{base} вес {kb} KB ≠ vanilla ~{exp} KB")
                else:
                    print(f"      [OK] {base}  {kb} KB  (vanilla ~{exp} KB)")
            else:
                if is_cheat_name(base) or is_cheat_name(folder):
                    print(f"      [DETECT] {base}  {kb} KB  (имя чита)")
                    add_detect(f"versions: {folder}/{base}")
                else:
                    print(f"      [WARN] {base}  {kb} KB  (нет в таблице — проверь вручную)")
                    add_warn(f"versions: {base} {kb} KB")

# ── Шаг 5 · mods ──
section(5, "mods — список + подозрительные (holycheck — вручную)")
mods_dir = os.path.join(MC, "mods")
mod_list = []
if os.path.isdir(mods_dir):
    for name in sorted(os.listdir(mods_dir)):
        if not name.lower().endswith(".jar"):
            continue
        path = os.path.join(mods_dir, name)
        kb = os.path.getsize(path) // 1024
        mod_list.append(name)
        if FORBIDDEN_MOD_NAMES.search(name) or CHEAT_MOD_RE.search(name):
            print(f"  [DETECT] {name}  ({kb} KB)")
            add_detect(f"mods: {name}")
        else:
            print(f"  [OK] {name}  ({kb} KB)")
    print(f"  Всего jar: {len(mod_list)}")
    print("  → Скопируй mods/*.jar к себе → holycheck / mod-analyzer.sh")
else:
    print("  [WARN] mods/ нет")

# ── Шаг 6 · LabyMod addons (Linux пути) ──
section(6, "LabyMod addons (Linux)")
LABY_PATHS = [
    os.path.join(MC, "LabyMod", "addons-1.16"),
    os.path.join(MC, "labymod", "addons-1.16"),
    os.path.join(MC, "LabyMod", "addons"),
    os.path.join(MC, "labymod-neo", "addons"),
    os.path.join(MC, ".minecraft", "labymod"),
    os.path.expanduser("~/.config/labymod/addons"),
    os.path.expanduser("~/.local/share/labymod/addons"),
]
laby_found = False
for p in LABY_PATHS:
    if not os.path.isdir(p):
        continue
    laby_found = True
    print(f"  📁 {p}")
    for root, _, files in os.walk(p):
        for f in files:
            if not f.lower().endswith((".jar", ".labymod")):
                continue
            fp = os.path.join(root, f)
            rel = os.path.relpath(fp, p)
            if is_cheat_name(f):
                print(f"    [DETECT] {rel}")
                add_detect(f"LabyMod: {rel}")
            else:
                print(f"    [OK] {rel}")
if not laby_found:
    print("  [INFO] LabyMod addons не найдены (Linux/Prism/Fabric — пропуск)")

# ── Шаг 7 · корзина (Linux Trash) ──
section(7, "Корзина — ~/.local/share/Trash (аналог $RECYCLE.BIN)")
trash_files = os.path.expanduser("~/.local/share/Trash/files")
trash_info = os.path.expanduser("~/.local/share/Trash/info")
n_files = 0
if os.path.isdir(trash_files):
    n_files = len([x for x in os.listdir(trash_files) if not x.startswith(".")])
if os.path.isdir(trash_info):
    n_info = len([x for x in os.listdir(trash_info) if x.endswith(".trashinfo")])
else:
    n_info = 0

print(f"  files/: {n_files} объектов · info/: {n_info} записей")

if n_files == 0 and n_info > 0:
    add_warn("корзина files/ пуста, но info/ есть — могли выборочно удалить")
    print("  [WARN] files пусто, trashinfo остались")

try:
    t_mtime = os.path.getmtime(trash_info) if os.path.isdir(trash_info) else 0
    if SS_START and t_mtime > SS_START and n_files == 0:
        add_detect("корзина очищена после начала SS")
        print("  [DETECT] корзина изменена после SS_START и пуста — бан за очистку")
    elif n_files == 0:
        print("  [INFO] корзина пуста")
        if t_mtime > time.time() - 3600:
            add_warn("корзина пуста и trash недавно трогали (<1ч)")
            print("  [WARN] Trash/info менялся недавно — могли Empty Trash перед SS")
except OSError:
    pass

# ── Шаг 8 · загрузки, рабочий стол, документы, диск ──
section(8, "Загрузки · рабочий стол · документы · home (остатки читов)")
SCAN_DIRS = [
    os.path.expanduser("~/Downloads"),
    os.path.expanduser("~/Загрузки"),
    os.path.expanduser("~/Desktop"),
    os.path.expanduser("~/Рабочий стол"),
    os.path.expanduser("~/Documents"),
    os.path.expanduser("~/Документы"),
    "/tmp",
]
seen = set()
hits = 0
for base in SCAN_DIRS:
    if not os.path.isdir(base):
        continue
    for root, dirs, files in os.walk(base):
        depth = root[len(base):].count(os.sep)
        if depth > 3:
            dirs.clear()
            continue
        for f in files + dirs:
            if is_cheat_name(f):
                fp = os.path.join(root, f)
                if fp in seen:
                    continue
                if re.search(r"Platforms SS|linux-ss-scripts|detector\.sh|/scripts/", fp, re.I):
                    continue
                seen.add(fp)
                print(f"  [DETECT] {fp}")
                add_detect(f"остаток: {fp}")
                hits += 1
                if hits >= 40:
                    print("  … лимит 40, копай find вручную")
                    break
        if hits >= 40:
            break
if hits == 0:
    print("  [OK] явных имён читов в типичных папках нет")

# ── Итог ──
print("\n━━ Итог ━━")
for i in INFO[:8]:
    print(f"[INFO] {i}")
if len(INFO) > 8:
    print(f"[INFO] … +{len(INFO) - 8}")
for w in WARN:
    print(f"[WARN] {w}")

u = list(dict.fromkeys(DETECT))
if not u:
    print("[OK] MC Manual Check — автоматика чистая.")
    print("     Шаг 3 (скрины) и holycheck модов — только глазами.")
    sys.exit(0)

print(f"[DETECT] Найдено: {len(u)}")
for d in u[:25]:
    print(f"  → {d}")
if len(u) > 25:
    print(f"  … +{len(u) - 25}")
sys.exit(2)
PY
