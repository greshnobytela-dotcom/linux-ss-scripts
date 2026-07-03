#!/usr/bin/env bash
# BrowserHistory — IP и URL, связанные с читами (история браузера Linux)
# Chrome / Chromium / Brave / Edge / Opera / Firefox
# Только публичные домены и IP из PC-check баз

set -uo pipefail

HITS=()
WARN=()

add_hit() { HITS+=("$1"); }
add_warn() { WARN+=("$1"); }

MATCH_RE='vape\.gg|vapev4|vapelite|doomsday|meteorclient|meteor-client|meteordevelopment|liquidbounce|wurstclient|riseclient|aristois|fdpclient|fdpinfo|novoline|onetap|manthe|sigma5|moonclient|zeroday|thunderhack|bleachhack|impactclient|futureclient|phobos|komat|xulu|astolfo|exosware|grimclient|entropyclient|dreamclient|dripclient|sunsetclient|slinkyclient|karmaclient|skidfest|ghost-client|hackclient|cheat\.jar|javaagent|\.vape|165\.22\.|167\.172\.|144\.217\.|45\.142\.|185\.234\.'

have_sqlite() { command -v sqlite3 >/dev/null 2>&1; }

dedupe_hits() {
  local -A seen=() u=() h
  for h in "${HITS[@]}"; do
    [[ -n "${seen[$h]:-}" ]] && continue
    seen[$h]=1
    u+=("$h")
  done
  HITS=("${u[@]}")
}

filter_lines() {
  grep -iE "$MATCH_RE" || true
}

scan_chromium_db() {
  local db="$1" browser="$2"
  [[ -f "$db" ]] || return 0
  local tmp row url title

  tmp=$(mktemp)
  cp "$db" "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }

  if have_sqlite; then
    while IFS='|' read -r url title; do
      [[ -z "$url" ]] && continue
      add_hit "[$browser] $url"
      [[ -n "$title" && "$title" != "$url" ]] && add_hit "  title: $title"
    done < <(
      sqlite3 -separator '|' "$tmp" \
        "SELECT url, IFNULL(title,'') FROM urls;" 2>/dev/null | filter_lines | head -80
    )

    while IFS= read -r row; do
      [[ -z "$row" ]] && continue
      add_hit "[$browser download] $row"
    done < <(
      sqlite3 "$tmp" "SELECT target_path FROM downloads;" 2>/dev/null | filter_lines | head -30
    )
  else
    while IFS= read -r row; do
      [[ -z "$row" ]] && continue
      add_hit "[$browser strings] $row"
    done < <(strings "$tmp" 2>/dev/null | filter_lines | head -40)
  fi
  rm -f "$tmp"
}

scan_firefox_db() {
  local db="$1"
  [[ -f "$db" ]] || return 0
  local tmp

  tmp=$(mktemp)
  cp "$db" "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }

  if have_sqlite; then
    while IFS='|' read -r url title; do
      [[ -z "$url" ]] && continue
      add_hit "[Firefox] $url"
      [[ -n "$title" && "$title" != "$url" ]] && add_hit "  title: $title"
    done < <(
      sqlite3 -separator '|' "$tmp" \
        "SELECT p.url, IFNULL(p.title,'') FROM moz_places p;" 2>/dev/null | filter_lines | head -80
    )
  else
    while IFS= read -r row; do
      [[ -z "$row" ]] && continue
      add_hit "[Firefox strings] $row"
    done < <(strings "$tmp" 2>/dev/null | filter_lines | head -40)
  fi
  rm -f "$tmp"
}

scan_all_browsers() {
  local prof

  for prof in \
    "$HOME/.config/google-chrome"/*/History \
    "$HOME/.config/chromium"/*/History \
    "$HOME/.config/BraveSoftware/Brave-Browser"/*/History \
    "$HOME/.config/microsoft-edge"/*/History \
    "$HOME/.config/opera"/*/History \
    "$HOME/.config/vivaldi"/*/History; do
    [[ -f "$prof" ]] || continue
    scan_chromium_db "$prof" "$(basename "$(dirname "$prof")")"
  done

  for prof in "$HOME/.mozilla/firefox"/*.default*/places.sqlite \
              "$HOME/.mozilla/firefox"/*.default-release*/places.sqlite; do
    [[ -f "$prof" ]] || continue
    scan_firefox_db "$prof"
  done
}

scan_bash_history_urls() {
  local f line
  for f in "$HOME/.bash_history" "$HOME/.zsh_history"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      add_hit "[history] $line ($f)"
    done < <(grep -iE "$MATCH_RE" "$f" 2>/dev/null | tail -20 || true)
  done
}

echo "=== BrowserHistory — читы / IP / inject (Linux) ==="
echo

if ! have_sqlite; then
  add_warn "sqlite3 не установлен — fallback strings (слабее). apt install sqlite3"
fi

scan_all_browsers
scan_bash_history_urls
dedupe_hits

if [[ ${#WARN[@]} -gt 0 ]]; then
  for w in "${WARN[@]}"; do echo "[WARN] $w"; done
  echo
fi

if [[ ${#HITS[@]} -eq 0 ]]; then
  echo "[OK] Подозрительных URL/IP в истории браузера не найдено."
  echo "     (Пусто ≠ чисто, если историю чистили.)"
  exit 0
fi

echo "[DETECT] Найдено совпадений: ${#HITS[@]}"
for h in "${HITS[@]}"; do
  echo "  → $h"
done
exit 2
