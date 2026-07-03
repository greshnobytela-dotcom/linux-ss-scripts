#!/usr/bin/env bash
# Анализ ~/.minecraft/mods

set -euo pipefail

MODS="${1:-$HOME/.minecraft/mods}"
CHEAT_STRINGS='AimAssist|AutoCrystal|AutoTotem|TriggerBot|KillAura|SelfDestruct|Velocity|Hitboxes|FastPlace'

echo "=== Mod Analyzer (Linux) ==="
echo "Папка: $MODS"
echo

if [[ ! -d "$MODS" ]]; then
  echo "[!] Папка mods не найдена: $MODS"
  exit 1
fi

if pgrep -af 'KnotClient|net.minecraft.client.main.Main' >/dev/null 2>&1; then
  echo "{ Minecraft запущен }"
  ps aux | grep -E 'KnotClient|Main.*minecraft' | grep -v grep | head -3
  echo
fi

verified=0
unknown=0
cheat=0

shopt -s nullglob
for jar in "$MODS"/*.jar; do
  name=$(basename "$jar")
  hash=$(sha1sum "$jar" | awk '{print $1}')

  modrinth=$(curl -fsS "https://api.modrinth.com/v2/version_file/$hash" 2>/dev/null || true)
  if echo "$modrinth" | grep -q '"project_id"'; then
    pid=$(echo "$modrinth" | grep -o '"project_id":"[^"]*"' | head -1 | cut -d'"' -f4)
    title=$(curl -fsS "https://api.modrinth.com/v2/project/$pid" 2>/dev/null | grep -o '"title":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "?")
    printf "\033[32m[OK]\033[0m %-30s %s (Modrinth: %s)\n" "$name" "$hash" "$title"
    ((verified++)) || true
    continue
  fi

  if unzip -p "$jar" 2>/dev/null | strings 2>/dev/null | grep -qiE "$CHEAT_STRINGS"; then
    hits=$(unzip -l "$jar" 2>/dev/null | grep -iE 'combat|killaura|clickgui|module|hack' | head -5)
    printf "\033[31m[CHEAT]\033[0m %s\n" "$name"
    echo "$hits" | sed 's/^/    /'
    ((cheat++)) || true
    continue
  fi

  if unzip -l "$jar" 2>/dev/null | grep -qiE 'killaura|clickgui|modulemanager|/hack/|/combat/'; then
    printf "\033[31m[CHEAT]\033[0m %s (пути в jar)\n" "$name"
    unzip -l "$jar" 2>/dev/null | grep -iE 'killaura|clickgui|module|combat|hack' | head -8 | sed 's/^/    /'
    ((cheat++)) || true
    continue
  fi

  ftype=$(file -b "$jar")
  if [[ "$name" != *.jar ]] && echo "$ftype" | grep -qi 'java archive\|zip'; then
    printf "\033[31m[FAKE]\033[0m %s — %s\n" "$name" "$ftype"
    ((cheat++)) || true
    continue
  fi

  printf "\033[33m[?]\033[0m %s  SHA1: %s\n" "$name" "$hash"
  ((unknown++)) || true
done

echo
echo "--- Итог: OK=$verified  неизвестно=$unknown  чит=$cheat ---"
[[ $cheat -gt 0 ]] && exit 2
exit 0
