#!/usr/bin/env bash
# Linux Services Forensics — встроенные службы и логи (journald, syslog, auditd, …)
# Не Windows. Только то, что реально есть на Mint/Ubuntu/Debian.

set -uo pipefail

MC="${MINECRAFT_DIR:-$HOME/.minecraft}"
HITS=()
WARN=()

add_hit() { HITS+=("$1"); }
add_warn() { WARN+=("$1"); }

svc() {
  local name="$1"
  if systemctl is-active --quiet "$name" 2>/dev/null; then
    echo "active"
  elif systemctl is-enabled --quiet "$name" 2>/dev/null; then
    echo "enabled (stopped)"
  elif systemctl list-unit-files "$name" 2>/dev/null | grep -q "$name"; then
    echo "installed"
  else
    echo "нет"
  fi
}

section() { echo; echo "━━ $1 ━━"; }

echo "=== Linux Services — службы и логи (PC Check) ==="
echo "Дистриб: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"' || uname -s)"
echo

# --- Статус ключевых служб ---
section "Службы (systemctl)"
printf "  %-28s %s\n" "systemd-journald" "$(svc systemd-journald.service)"
printf "  %-28s %s\n" "systemd-logind" "$(svc systemd-logind.service)"
rsys=$(svc rsyslog.service)
[[ "$rsys" == "нет" ]] && rsys=$(svc syslog.service)
printf "  %-28s %s\n" "rsyslog / syslog" "$rsys"
printf "  %-28s %s\n" "auditd" "$(svc auditd.service)"
printf "  %-28s %s\n" "systemd-coredump" "$(svc systemd-coredump.socket; svc systemd-coredump@.service 2>/dev/null | head -1)"
printf "  %-28s %s\n" "apport" "$(svc apport.service)"
printf "  %-28s %s\n" "cron" "$(svc cron.service)"
printf "  %-28s %s\n" "accounts-daemon" "$(svc accounts-daemon.service)"
printf "  %-28s %s\n" "NetworkManager" "$(svc NetworkManager.service)"
printf "  %-28s %s\n" "dbus" "$(svc dbus.service)"

# --- journald ---
section "systemd-journald — системный журнал"
if command -v journalctl >/dev/null 2>&1; then
  echo "  Размер: $(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[MGK]' | head -1 || echo '?')"
  echo "  Boot-записей: $(journalctl --list-boots 2>/dev/null | wc -l)"
  [[ $(journalctl --list-boots 2>/dev/null | wc -l) -lt 2 ]] && add_warn "journald: мало boot-записей — могли journalctl --vacuum"
  echo
  echo "  java / minecraft / tlauncher (system, 30 дней):"
  journalctl --since "30 days ago" --no-pager 2>/dev/null \
    | grep -iE 'java|minecraft|tlauncher|KnotClient|fabric|forge|gamemoded.*java' \
    | tail -20 | sed 's/^/    /' || echo "    (пусто)"
  echo
  echo "  Очистка журнала (подозрительно):"
  journalctl --since "30 days ago" --no-pager 2>/dev/null \
    | grep -iE 'vacuum|journal.*flush|Deleted archived journal' \
    | tail -5 | sed 's/^/    /' || echo "    (не найдено)"
else
  add_warn "journald/journalctl недоступен"
fi

# --- user journal ---
section "systemd-journald (user) — сессия пользователя"
if journalctl --user --disk-usage >/dev/null 2>&1; then
  echo "  Размер user journal: $(journalctl --user --disk-usage 2>/dev/null | grep -oE '[0-9.]+[MGK]' | head -1 || echo '?')"
  journalctl --user --since "30 days ago" --no-pager 2>/dev/null \
    | grep -iE 'java|minecraft|tlauncher|\.jar|cheat|doomsday' \
    | tail -15 | sed 's/^/    /' || echo "    (пусто)"
else
  echo "  user journal недоступен"
fi

# --- logind ---
section "systemd-logind — входы / сессии"
if command -v loginctl >/dev/null 2>&1; then
  loginctl list-sessions --no-pager 2>/dev/null | sed 's/^/    /' || true
  echo
  last -10 2>/dev/null | sed 's/^/    /' || echo "    last: нет wtmp"
else
  last -10 2>/dev/null | sed 's/^/    /'
fi

# --- rsyslog / syslog files ---
section "rsyslog — /var/log/syslog, auth.log"
for f in /var/log/syslog /var/log/auth.log /var/log/messages; do
  [[ -r "$f" ]] || continue
  echo "  $f (java/minecraft, последние):"
  grep -iE 'java|minecraft|tlauncher|sudo.*java' "$f" 2>/dev/null | tail -8 | sed 's/^/    /' || echo "    (нет)"
done
if [[ ! -r /var/log/syslog && ! -r /var/log/auth.log ]]; then
  echo "  нет прав на /var/log — только journalctl"
fi

# --- auditd ---
section "auditd — аудит exec (если включён)"
if systemctl is-active --quiet auditd 2>/dev/null && [[ -r /var/log/audit/audit.log ]]; then
  echo "  Статус: $(svc auditd.service)"
  grep -iE 'type=EXECVE.*java|type=EXECVE.*minecraft|type=EXECVE.*tlauncher|\.jar' /var/log/audit/audit.log 2>/dev/null \
    | tail -12 | sed 's/^/    /' || echo "    (нет java exec)"
else
  echo "  auditd: $(svc auditd.service) — на Mint/Ubuntu по умолчанию выключен"
fi

# --- coredump ---
section "systemd-coredump — падения процессов"
if command -v coredumpctl >/dev/null 2>&1; then
  echo "  java coredumps:"
  coredumpctl list --no-pager 2>/dev/null | grep -i java | tail -8 | sed 's/^/    /' || echo "    (нет)"
else
  echo "  coredumpctl не установлен"
fi

# --- apport ---
section "apport — отчёты о сбоях (Ubuntu/Mint)"
if systemctl list-unit-files apport.service >/dev/null 2>&1; then
  echo "  apport: $(svc apport.service)"
  if [[ -d /var/crash ]] && ls /var/crash/ >/dev/null 2>&1; then
    ls -lt /var/crash/ 2>/dev/null | head -6 | sed 's/^/    /'
  else
    echo "    /var/crash пуст"
  fi
else
  echo "  apport не установлен"
fi

# --- cron ---
section "cron — отложенные задачи"
if [[ -r /var/spool/cron/crontabs/"$USER" ]]; then
  echo "  crontab $USER:"
  cat "/var/spool/cron/crontabs/$USER" 2>/dev/null | sed 's/^/    /'
elif crontab -l >/dev/null 2>&1; then
  echo "  crontab $USER:"
  crontab -l 2>/dev/null | sed 's/^/    /'
else
  echo "  crontab пуст"
fi
journalctl -u cron --since "30 days ago" --no-pager 2>/dev/null \
  | grep -iE 'java|minecraft|cheat|\.sh' | tail -5 | sed 's/^/    /' || true

# --- shell history (служба shell, не systemd) ---
section "shell — ~/.bash_history / ~/.zsh_history"
for f in "$HOME/.bash_history" "$HOME/.zsh_history"; do
  [[ -f "$f" ]] || continue
  n=$(wc -l < "$f" 2>/dev/null || echo 0)
  echo "  $f: $n строк"
  [[ "$n" -lt 3 ]] && add_warn "$f почти пуст — history -c?"
  grep -iE 'java|minecraft|tlauncher|cheat|doomsday|vape|wget.*jar|curl.*jar|history -c|>.*history' "$f" 2>/dev/null \
    | tail -10 | sed 's/^/    /' || true
  grep -qiE 'history -c|> *\.bash_history|> *\.zsh_history' "$f" 2>/dev/null && add_hit "history очищали: $f"
done

# --- GTK recently-used (десктоп, не systemd) ---
section "GTK recently-used — недавние файлы"
XBEL="$HOME/.local/share/recently-used.xbel"
if [[ -f "$XBEL" ]]; then
  grep -oiE 'file://[^"]+' "$XBEL" 2>/dev/null \
    | sed 's|file://||' | grep -iE '\.jar|minecraft|cheat|doomsday|vape|/tmp/' \
    | tail -15 | sed 's/^/    /' || echo "    (нет jar/cheat)"
  grep -qiE 'cheat|doomsday|vape' "$XBEL" 2>/dev/null && add_hit "recently-used: cheat paths"
else
  echo "  recently-used.xbel нет"
fi

# --- Minecraft logs integrity ---
section "minecraft logs — целостность"
if [[ ! -d "$MC/logs" ]] || [[ -z "$(ls -A "$MC/logs" 2>/dev/null)" ]]; then
  add_hit "Minecraft logs/ пуст или удалён"
elif [[ ! -f "$MC/logs/latest.log" ]]; then
  add_warn "latest.log отсутствует"
else
  echo "  logs/: $(ls "$MC/logs" 2>/dev/null | wc -l) файлов, latest.log $(stat -c %y "$MC/logs/latest.log" 2>/dev/null | cut -d. -f1)"
fi

# --- Итог ---
section "Итог"
if [[ ${#WARN[@]} -gt 0 ]]; then
  for w in "${WARN[@]}"; do echo "[WARN] $w"; done
fi
if [[ ${#HITS[@]} -gt 0 ]]; then
  for h in "${HITS[@]}"; do echo "[DETECT] $h"; done
  exit 2
fi
echo "[OK] Критичных следов сокрытия в службах/логах Linux не найдено."
exit 0
