#!/usr/bin/env bash
# FilesChecker — logs, settings/user, IAS; RU/EU читы в строках логов

set -uo pipefail

MC="${MINECRAFT_DIR:-$HOME/.minecraft}"
LIMIT="${1:-500}"

echo "=== FilesChecker — logs · settings/user · IAS ==="
echo "Папка: $MC"
echo

if ! command -v python3 >/dev/null 2>&1; then
  echo "[ERR] Нужен python3."
  exit 1
fi

python3 - "$MC" "$LIMIT" <<'PY'
import gzip, glob, json, os, re, sys

MC = sys.argv[1]
LIMIT = int(sys.argv[2])

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
    "faker", "silent", "coldbypass", "bypassing", "intent", "monot", "skid",
)

MODULES = (
    "killaura", "triggerbot", "aimassist", "aimbot", "autoclick", "autocrystal",
    "velocity", "reach", "hitbox", "scaffold", "speed", "fly", "xray", "esp",
    "antiknockback", "selfdestruct", "self.destruct", "clickgui", "arraylist",
    "backtrack", "wtap", "autototem", "crystalaura", "legitaura", "trigger",
)

CHEAT_IP = re.compile(
    r"\b(?:165\.22|167\.172|144\.217|45\.142|185\.234)\.\d{1,3}\.\d{1,3}\b"
)

# IP в логах MC (не fabric-key-binding)
ANY_IP = re.compile(
    r"(?<![\w/-])\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b"
)

SKIP_LOG = re.compile(
    r"fabric-key-binding|key-binding-api|vertex_attrib_binding|Reloading ResourceManager",
    re.I,
)

CLIENT_BRACKET = re.compile(
    r"\[(?:[^\]]*\b(?:client|чит|hack|ghost)\b[^\]]*)\]",
    re.I,
)

client_alt = "|".join(re.escape(c) for c in CLIENTS)
CLIENT_NAME = re.compile(rf"\b(?:{client_alt})\b", re.I)
CLIENT_MOD_LINE = re.compile(rf"^\s*-\s+.*(?:{client_alt})", re.I)

mod_alt = "|".join(re.escape(m) for m in MODULES)
BIND_LINE = re.compile(
    rf"(?:\bbind\b|\bbound\b|\bkeybind\b).{{0,40}}(?:{mod_alt})|"
    rf"(?:{mod_alt}).{{0,40}}(?:\bbind\b|\bbound\b|\bkeybind\b)",
    re.I,
)
MODULE_LINE = re.compile(
    rf"(?:\[.*?\])?\s*(?:{client_alt}).{{0,30}}(?:{mod_alt})|"
    rf"(?:enabled|disabled|toggled|turned on|turned off|loaded module).{{0,25}}(?:{mod_alt})|"
    rf"(?:{mod_alt}).{{0,25}}(?:enabled|disabled|toggled|on|off)",
    re.I,
)

IAS_LINE = re.compile(
    r"\bias\b|in-game account switcher|account switcher|_IAS_|switching account|logged in as",
    re.I,
)

# Легит config — не трогаем
LEGIT_CONFIG = re.compile(
    r"^(sodium|iris|lithium|fabric|modmenu|yacl|ferritecore|immediatelyfast|"
    r"entityculling|badoptimizations|moreculling|exordium|transition|trender|"
    r"cloth|skyboxify|chrissi|custom-crosshair|ias)\.",
    re.I,
)

CHEAT_CONFIG = re.compile(
    rf"(?:{client_alt})|settings\.json|user\.json|accounts\.json|config\.json",
    re.I,
)

SUSPICIOUS_DIRS = re.compile(
    rf"(?:^|/)(?:{client_alt})(?:/|$)|"
    r"(?:^|/)(?:\.wexside|\.expensive|\.minced|\.delta|cheat|ghost|hack|client)[-/]",
    re.I,
)


def add_detect(msg):
    DETECT.append(msg)


def add_warn(msg):
    WARN.append(msg)


def add_info(msg):
    INFO.append(msg)


def open_text(path):
    if path.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, encoding="utf-8", errors="replace")


def iter_logs():
    for pat in (
        os.path.join(MC, "logs", "*.log"),
        os.path.join(MC, "logs", "*.log.gz"),
        os.path.join(MC, "debug", "*.txt"),
        os.path.join(MC, "crash-reports", "*.txt"),
    ):
        for p in sorted(glob.glob(pat)):
            yield p


def scan_log_line(line, log_name, line_no):
    if SKIP_LOG.search(line):
        return None
    if CHEAT_IP.search(line):
        return f"IP чит-auth: {line.strip()[:120]}"
    if CLIENT_BRACKET.search(line):
        return line.strip()[:120]
    if CLIENT_MOD_LINE.search(line):
        return f"мод в списке: {line.strip()[:100]}"
    if BIND_LINE.search(line):
        return line.strip()[:120]
    if MODULE_LINE.search(line):
        return line.strip()[:120]
    if CLIENT_NAME.search(line) and re.search(
        r"client|module|bind|enabled|disabled|inject|loaded|чит", line, re.I
    ):
        return line.strip()[:120]
    # Connecting / connected к внешнему IP (не localhost)
    if re.search(r"connect|socket|http|auth|session", line, re.I):
        ip = ANY_IP.search(line)
        if ip:
            ip_s = ip.group(0).split(":")[0]
            if not ip_s.startswith(("127.", "0.", "192.168.", "10.", "172.")):
                if not re.match(r"^23[0-9]\.", ip_s):  # не CDN Mojang 23x
                    return f"connect IP: {ip.group(0)} → {line.strip()[:80]}"
    return None


def scan_logs():
    hits = []
    ias_hits = []
    ias_present = False

    for path in iter_logs():
        log_name = os.path.basename(path)
        try:
            with open_text(path) as f:
                for i, line in enumerate(f, 1):
                    if IAS_LINE.search(line) or re.search(r"\bias:\s", line, re.I):
                        ias_present = True
                    reason = scan_log_line(line, log_name, i)
                    if not reason:
                        continue
                    entry = (log_name, i, reason)
                    hits.append(entry)
                    if IAS_LINE.search(line) or "ias" in line.lower():
                        ias_hits.append(entry)
        except OSError:
            continue

    return hits, ias_hits, ias_present


def scan_settings_user():
    found = []
    if not os.path.isdir(MC):
        return found

    # config/*.json — не легит имена
    cfg = os.path.join(MC, "config")
    if os.path.isdir(cfg):
        for name in os.listdir(cfg):
            low = name.lower()
            if LEGIT_CONFIG.match(name):
                continue
            if CHEAT_CONFIG.search(name):
                found.append(f"config/{name}")

    # подозрительные папки в .minecraft
    try:
        for name in os.listdir(MC):
            path = os.path.join(MC, name)
            if not os.path.isdir(path):
                if name.lower() in ("user.json", "settings.json", "accounts.json"):
                    found.append(name)
                continue
            if SUSPICIOUS_DIRS.search(name) or SUSPICIOUS_DIRS.search(path):
                found.append(f"папка: {name}/")
            for sub in ("settings.json", "user.json", "accounts.json", "config.json", "binds.json"):
                sp = os.path.join(path, sub)
                if os.path.isfile(sp):
                    found.append(f"{name}/{sub}")
    except OSError:
        pass

    # tlauncher userSet — много акков + cheat nick (warn only)
    tl = os.path.join(MC, "tlauncher_profiles.json")
    if os.path.isfile(tl):
        try:
            data = json.load(open(tl, encoding="utf-8"))
            users = data.get("userSet", {}).get("list", [])
            if len(users) > 3:
                add_warn(f"tlauncher_profiles: {len(users)} аккаунтов — сверь с IAS")
        except (json.JSONDecodeError, OSError):
            pass

    return found


def scan_ias():
    ias_cfg = os.path.join(MC, "config", "ias.json")
    ias_dir = os.path.join(MC, "_IAS_ACCOUNTS_DO_NOT_SEND_TO_ANYONE")
    if os.path.isfile(ias_cfg) or os.path.isdir(ias_dir):
        add_info("In-Game Account Switcher установлен — смотри строки IAS в логах")
    if os.path.isdir(ias_dir):
        n = len([x for x in os.listdir(ias_dir) if not x.endswith(".txt")])
        if n:
            add_info(f"IAS: {n} сохранённых аккаунтов в _IAS_ACCOUNTS…")


# ── run ──
print("━━ 1 · Логи MC — IP · [client] · bind · модули ━━")
log_hits, ias_log_hits, ias_in_logs = scan_logs()

seen = set()
shown = 0
for log_name, line_no, reason in log_hits[:LIMIT]:
    key = (log_name, line_no, reason[:80])
    if key in seen:
        continue
    seen.add(key)
    print(f"  [DETECT] {log_name}:{line_no} → {reason}")
    add_detect(f"{log_name}:{line_no} {reason[:100]}")
    shown += 1
    if shown >= 40:
        if len(log_hits) > 40:
            print(f"  … ещё {len(log_hits) - 40} строк (лимит)")
        break

if not log_hits:
    print("  [OK] в логах нет IP читов / bind killaura / [client] строк")

print()
print("━━ 2 · In-Game Account Switcher + строки в логах ━━")
scan_ias()
if ias_in_logs or ias_log_hits:
    print("  IAS упоминается в логах")
    for log_name, line_no, reason in ias_log_hits[:15]:
        print(f"  [DETECT] IAS+чит {log_name}:{line_no} → {reason}")
        add_detect(f"IAS log {log_name}:{line_no} {reason[:90]}")
    if ias_in_logs and not ias_log_hits:
        print("  [INFO] IAS есть, cheat-строк рядом не найдено")
elif os.path.isfile(os.path.join(MC, "config", "ias.json")):
    print("  [INFO] мод IAS установлен, в логах cheat-строк с IAS нет")

print()
print("━━ 3 · settings / user (не легит config) ━━")
susp_files = scan_settings_user()
if susp_files:
    for s in susp_files[:25]:
        print(f"  [DETECT] {s}")
        add_detect(f"settings/user: {s}")
else:
    print("  [OK] подозрительных settings/user в .minecraft нет")

# dedupe detect
u = []
seen_d = set()
for d in DETECT:
    if d in seen_d:
        continue
    seen_d.add(d)
    u.append(d)

print()
print("━━ Итог ━━")
for i in INFO:
    print(f"[INFO] {i}")
for w in WARN:
    print(f"[WARN] {w}")

if not u:
    print("[OK] FilesChecker — чисто.")
    sys.exit(0)

print(f"[DETECT] Найдено: {len(u)}")
for d in u[:20]:
    print(f"  → {d}")
if len(u) > 20:
    print(f"  … +{len(u) - 20}")
sys.exit(2)
PY
