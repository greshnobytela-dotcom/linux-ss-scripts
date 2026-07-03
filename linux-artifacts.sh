#!/usr/bin/env bash
# Linux Artifacts — аналог Windows EventLog / BAM / DPS / (частично SysMain)
# journalctl, recently-used, bash history, last, coredump, apport, auditd

set -uo pipefail

MC="${MINECRAFT_DIR:-$HOME/.minecraft}"
HITS=()
WARN=()

add_hit() { HITS+=("$1"); }
add_warn() { WARN+=("$1"); }

section() { echo; echo "=== $1 ==="; }

echo "=== Linux Artifacts — EventLog / BAM / DPS (PC Check) ==="
echo
echo "Windows → Linux (что включено по умолчанию на Mint/Ubuntu):"
printf "  %-12s → %-30s %s\n" "EventLog" "journalctl (systemd)" "✅ обычно"
printf "  %-12s → %-30s %s\n" "BAM" "recently-used + history + last" "✅ частично"
printf "  %-12s → %-30s %s\n" "DPS" "coredumpctl + apport" "✅ частично"
printf "  %-12s → %-30s %s\n" "PcaSvc" "—" "❌ нет аналога"
printf "  %-12s → %-30s %s\n" "SysMain" "locate/plocate (не forensic)" "⚠️ слабо"
echo

# --- EventLog: journalctl ---
section "EventLog → journalctl"

if command -v journalctl >/dev/null 2>&1; then
  echo "Журнал (system): $(journalctl --disk-usage 2>/dev/null | tail -1 || echo '?')"
  echo "Журнал (user):   $(journalctl --user --disk-usage 2>/dev/null | tail -1 || echo '?')"
  echo
  echo "Java / Minecraft (system, 14 дней):"
  journalctl --since "14 days ago" 2>/dev/null \
    | grep -iE 'java|minecraft|tlauncher|KnotClient|fabric' \
    | tail -15 | sed 's/^/  /' || echo "  (пусто или нет прав)"
  echo
  echo "Java / Minecraft (user, 14 дней):"
  journalctl --user --since "14 days ago" 2>/dev/null \
    | grep -iE 'java|minecraft|tlauncher|KnotClient|fabric' \
    | tail -15 | sed 's/^/  /' || echo "  (пусто)"
  if journalctl --list-boots 2>/dev/null | wc -l | grep -qx '1'; then
    add_warn "journal: только 1 boot — могли чистить (--vacuum)"
  fi
else
  add_warn "journalctl не найден (не systemd?)"
fi

# --- BAM-like: recently used + history + last ---
section "BAM → recently-used.xbel + history + last"

XBEL="$HOME/.local/share/recently-used.xbel"
if [[ -f "$XBEL" ]]; then
  echo "recently-used.xbel — jar/exe/minecraft (последние):"
  grep -oiE 'file://[^"]+\.(jar|deb|AppImage|sh)' "$XBEL" 2>/dev/null \
    | sed 's|file://||' | tail -20 | sed 's/^/  /' || echo "  (нет jar/exe)"
  grep -iE 'cheat|doomsday|vape|inject|client\.jar|\.minecraft/mods' "$XBEL" 2>/dev/null \
    | head -5 | sed 's/^/  [DETECT] /' && add_hit "recently-used: подозрительные пути"
else
  echo "  recently-used.xbel не найден"
fi

echo
echo "bash/zsh history — java/minecraft/cheat:"
for f in "$HOME/.bash_history" "$HOME/.zsh_history"; do
  [[ -f "$f" ]] || continue
  lines=$(grep -iE 'java|minecraft|tlauncher|fabric|forge|cheat|doomsday|vape|wget.*jar|curl.*jar' "$f" 2>/dev/null | tail -12 || true)
  if [[ -n "$lines" ]]; then
    echo "  --- $(basename "$f") ---"
    echo "$lines" | sed 's/^/    /'
  fi
  [[ $(wc -l < "$f" 2>/dev/null || echo 0) -lt 3 ]] && add_warn "$(basename "$f"): почти пуст — могли чистить"
done

echo
echo "last (входы в систему):"
last -8 2>/dev/null | sed 's/^/  /' || echo "  (нет wtmp)"

# --- DPS: crashes / diagnostics ---
section "DPS → coredump + apport"

if command -v coredumpctl >/dev/null 2>&1; then
  echo "coredumpctl (java, все время):"
  coredumpctl list 2>/dev/null | grep -i java | tail -10 | sed 's/^/  /' || echo "  (нет java coredump)"
else
  echo "  coredumpctl не установлен"
fi

if [[ -d /var/crash ]]; then
  shopt -s nullglob
  crashes=(/var/crash/*)
  shopt -u nullglob
  if [[ ${#crashes[@]} -gt 0 ]]; then
    echo "apport /var/crash:"
    ls -lt /var/crash/ 2>/dev/null | head -8 | sed 's/^/  /'
  else
    echo "  /var/crash пуст"
  fi
else
  echo "  apport (/var/crash) — нет"
fi

# --- auditd (BAM-like if enabled) ---
section "auditd (BAM exec — если включён)"

if [[ -r /var/log/audit/audit.log ]]; then
  echo "audit.log — java/minecraft exec (последние):"
  grep -iE 'java|minecraft|tlauncher' /var/log/audit/audit.log 2>/dev/null | tail -12 | sed 's/^/  /' \
    && add_hit "auditd: есть следы java" || echo "  (нет совпадений)"
else
  echo "  auditd выключен или нет прав (на Mint/Ubuntu по умолчанию OFF)"
fi

# --- Сокрытие улик ---
section "Проверка сокрытия (очистка логов)"

[[ ! -d "$MC/logs" || -z "$(ls -A "$MC/logs" 2>/dev/null)" ]] && add_hit "Minecraft logs/ пуст или удалён"
[[ -f "$MC/logs/latest.log" ]] || add_warn "latest.log отсутствует"

if command -v journalctl >/dev/null 2>&1; then
  boots=$(journalctl --list-boots 2>/dev/null | wc -l)
  [[ "${boots:-0}" -lt 2 ]] && add_warn "journal: мало записей boot ($boots)"
fi

# --- Итог ---
echo
echo "=== Итог ==="
if [[ ${#WARN[@]} -gt 0 ]]; then
  for w in "${WARN[@]}"; do echo "[WARN] $w"; done
fi
if [[ ${#HITS[@]} -gt 0 ]]; then
  for h in "${HITS[@]}"; do echo "[DETECT] $h"; done
  exit 2
fi
echo "[OK] Критичных следов сокрытия в артефактах не найдено."
echo "     BAM на Linux слабее Windows — смотри также safe-mod-detector (сессии MC)."
exit 0
