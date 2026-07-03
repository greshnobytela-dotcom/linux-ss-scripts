#!/usr/bin/env bash
# Скан /tmp, cache, shm — jar и .so

set -euo pipefail

OUT="${1:-/tmp/linux-ss-scan.txt}"
MIN_KB="${2:-300}"

DIRS=(
  "/tmp"
  "$HOME/.cache"
  "/dev/shm"
  "$HOME/.minecraft"
  "$HOME/Загрузки"
  "$HOME/Downloads"
)

CHEAT_RE='doomsday|cheat|client|inject|hack|vape|meteor|liquidbounce|manthe|ghost'

echo "=== Common Directories Scan (Linux) ==="
echo "Вывод: $OUT"
echo "Мин. размер: ${MIN_KB} KB"
echo

: > "$OUT"
count=0

for dir in "${DIRS[@]}"; do
  [[ -d "$dir" ]] || continue
  echo "Скан: $dir"

  while IFS= read -r -d '' f; do
    size_kb=$(($(stat -c%s "$f" 2>/dev/null || echo 0) / 1024))
    [[ $size_kb -ge $MIN_KB ]] || continue

    base=$(basename "$f")
    [[ "$base" == ad_* ]] && continue
    [[ "$base" == xapp-tmp* ]] && continue

    ext="${f##*.}"
    ftype=$(file -b "$f" 2>/dev/null || echo "?")

    flag=""
    if echo "$f $base" | grep -qiE "$CHEAT_RE"; then
      flag="[NAME]"
    fi
    if echo "$ftype" | grep -qiE 'java archive|shared object|executable|ELF'; then
      if [[ "$ext" != "jar" && "$ext" != "so" ]] && echo "$ftype" | grep -qi 'java archive'; then
        flag="[FAKE-JAR]"
      fi
      if echo "$ftype" | grep -qi 'shared object' && [[ "$f" == /tmp/* || "$f" == *".cache"* ]]; then
        flag="[SO-TMP]"
      fi
    fi
    if strings "$f" 2>/dev/null | head -c 50000 | grep -qiE "$CHEAT_RE"; then
      flag="${flag}[STRINGS]"
    fi

    if [[ -n "$flag" ]] || [[ "$ext" == "jar" || "$ext" == "so" ]]; then
      if [[ "$ftype" != *"text"* ]]; then
        echo "$flag $size_kb KB $ftype :: $f" >> "$OUT"
        ((count++)) || true
      fi
    fi
  done < <(find "$dir" -maxdepth 4 -type f -size +"${MIN_KB}k" -print0 2>/dev/null)
done

echo
echo "Найдено: $count"
echo "Файл: $OUT"
if [[ $count -gt 0 ]]; then
  echo "--- первые 20 ---"
  head -20 "$OUT"
fi

[[ $count -gt 0 ]] && exit 2
exit 0
