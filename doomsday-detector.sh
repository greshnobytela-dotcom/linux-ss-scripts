#!/usr/bin/env bash
# Поиск следов Doomsday

set -euo pipefail

echo "=== Doomsday Detector (Linux) ==="
echo

found=0

# IP чит-auth / CDN (Doomsday, Vape и др.)
CHEAT_IP_RE='165\.22\.|167\.172\.|144\.217\.|45\.142\.|185\.234\.'

report() {
  echo "[DETECT] $*"
  ((found++)) || true
}

echo "{ Поиск по имени }"
SEARCH_DIRS=(
  "$HOME/.minecraft"
  "$HOME/Downloads" "$HOME/Загрузки"
  "$HOME/Desktop" "$HOME/Рабочий стол"
  "$HOME/.cache" "$HOME/.local/share"
  "/tmp"
)
for dir in "${SEARCH_DIRS[@]}"; do
  [[ -d "$dir" ]] || continue
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    base=$(basename "$p")
    [[ "$base" =~ [Dd]etector|[Ss]cript|[Pp]latforms ]] && continue
    report "файл: $p"
  done < <(find "$dir" -maxdepth 4 -iname '*doomsday*' 2>/dev/null)
done

echo "{ History }"
if grep -qi 'doomsday' "$HOME/.bash_history" 2>/dev/null; then
  echo "[DETECT] bash_history:"
  grep -i 'doomsday' "$HOME/.bash_history" | tail -5 | sed 's/^/    /'
  ((found++)) || true
fi
if grep -qi 'doomsday' "$HOME/.zsh_history" 2>/dev/null; then
  report "zsh_history"
fi

echo "{ mods/ }"
MODS="$HOME/.minecraft/mods"
shopt -s nullglob
if [[ -d "$MODS" ]]; then
  for jar in "$MODS"/*.jar; do
    if unzip -l "$jar" 2>/dev/null | grep -qi 'doomsday'; then
      echo "[DETECT] doomsday в jar: $(basename "$jar")"
      unzip -l "$jar" 2>/dev/null | grep -i doomsday | head -5 | sed 's/^/    /'
      ((found++)) || true
    fi
    if strings "$jar" 2>/dev/null | grep -qiE 'doomsday|DoomsdayClient'; then
      report "strings doomsday: $(basename "$jar")"
    fi
  done
fi

echo "{ GUI следы }"
if [[ -f "$HOME/.local/share/recently-used.xbel" ]] && grep -qi 'doomsday' "$HOME/.local/share/recently-used.xbel"; then
  echo "[DETECT] recently-used.xbel → doomsday"
  grep -oiE 'file://[^"]*doomsday[^"]*' "$HOME/.local/share/recently-used.xbel" | head -5 | sed 's/^/    /'
  ((found++)) || true
fi

echo "{ Память (игра запущена) }"
for pid in $(pgrep -f 'KnotClient|net.minecraft.client.main.Main' 2>/dev/null || true); do
  if ls -l "/proc/$pid/fd/" 2>/dev/null | grep -qi 'doomsday'; then
    echo "[DETECT] /proc/$pid/fd → doomsday"
    ls -l "/proc/$pid/fd/" 2>/dev/null | grep -i doomsday | sed 's/^/    /'
    ((found++)) || true
  fi
  if cat "/proc/$pid/maps" 2>/dev/null | grep -qi 'doomsday'; then
    report "/proc/$pid/maps → doomsday"
  fi
done

shopt -s nullglob
for core in ./core.* /tmp/core.*; do
  if strings "$core" 2>/dev/null | grep -qi 'doomsday'; then
    report "strings в $core"
  fi
done

echo "{ Переименованные jar }"
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if file -b "$f" 2>/dev/null | grep -qi 'java archive\|zip archive'; then
    if unzip -l "$f" 2>/dev/null | grep -qi 'doomsday'; then
      report "jar под маской: $f"
    fi
  fi
done < <(find "$HOME/.minecraft" "$HOME/Загрузки" "$HOME/Downloads" /tmp "$HOME/.cache" \
  -maxdepth 3 -type f ! -name '*.jar' -size +10k 2>/dev/null)

echo "{ Сеть — IP чит-серверов (165.22 / 167.172 / …) }"
if command -v ss >/dev/null 2>&1; then
  out=$(ss -tuplna 2>/dev/null | grep -iE "$CHEAT_IP_RE" || true)
  if [[ -n "$out" ]]; then
    echo "[DETECT] ss -tuplna → чит-IP:"
    echo "$out" | sed 's/^/    /'
    ((found++)) || true
  fi
  out=$(ss -tn state established 2>/dev/null | grep -iE "$CHEAT_IP_RE" || true)
  if [[ -n "$out" ]]; then
    echo "[DETECT] ss ESTABLISHED → чит-IP:"
    echo "$out" | sed 's/^/    /'
    ((found++)) || true
  fi
  java_hit=$(ss -tuplna 2>/dev/null | grep '[j]ava' | grep -iE "$CHEAT_IP_RE" || true)
  if [[ -n "$java_hit" ]]; then
    echo "[DETECT] java → чит-сервер (Doomsday/Vape auth):"
    echo "$java_hit" | sed 's/^/    /'
    ((found++)) || true
  fi
elif command -v netstat >/dev/null 2>&1; then
  out=$(netstat -tulpn 2>/dev/null | grep -iE "$CHEAT_IP_RE" || true)
  if [[ -n "$out" ]]; then
    echo "[DETECT] netstat → чит-IP:"
    echo "$out" | sed 's/^/    /'
    ((found++)) || true
  fi
  java_hit=$(netstat -tulpn 2>/dev/null | grep '[j]ava' | grep -iE "$CHEAT_IP_RE" || true)
  if [[ -n "$java_hit" ]]; then
    echo "[DETECT] netstat java → чит-сервер:"
    echo "$java_hit" | sed 's/^/    /'
    ((found++)) || true
  fi
else
  echo "  ss/netstat не найдены — пропуск"
fi

echo
if [[ $found -eq 0 ]]; then
  echo "Doomsday не найден."
  exit 0
else
  echo "Найдено улик: $found → проверь вручную / бан"
  exit 2
fi
