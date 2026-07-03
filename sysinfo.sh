#!/usr/bin/env bash
# Система: версия Linux, дата установки, VM или железо

set -uo pipefail

echo "=== System Info (Linux PC Check) ==="
echo

# --- Дистрибутив ---
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  echo "Дистрибутив:  ${PRETTY_NAME:-$NAME}"
  echo "Версия:       ${VERSION_ID:-?} (${VERSION_CODENAME:-—})"
else
  echo "Дистрибутив:  $(uname -s)"
fi

echo "Ядро:         $(uname -r)"
echo "Архитектура:  $(uname -m)"
echo "Hostname:     $(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo '?')"
echo

# --- Дата установки ---
install_date=""
install_src=""

if [[ -f /var/log/installer/syslog ]]; then
  install_date=$(grep -m1 ' finish' /var/log/installer/syslog 2>/dev/null | awk '{print $1,$2,$3}' || true)
  [[ -n "$install_date" ]] && install_src="Ubuntu/Debian installer log"
fi

if [[ -z "$install_date" && -f /etc/fedora-release ]]; then
  install_date=$(rpm -qa --qf '%{installtime:date}\n' 2>/dev/null | sort | head -1 || true)
  [[ -n "$install_date" ]] && install_src="rpm (первый пакет, приблизительно)"
fi

if [[ -z "$install_date" ]]; then
  birth=$(stat -c %w / 2>/dev/null || true)
  if [[ -n "$birth" && "$birth" != "-" ]]; then
    install_date="$birth"
    install_src="stat / (birth)"
  fi
fi

if [[ -z "$install_date" ]]; then
  root_dev=$(findmnt -n -o SOURCE / 2>/dev/null || df / 2>/dev/null | awk 'NR==2{print $1}')
  if [[ -n "$root_dev" ]]; then
    install_date=$(sudo tune2fs -l "$root_dev" 2>/dev/null | awk -F': ' '/Filesystem created/ {print $2; exit}' || true)
    [[ -n "$install_date" ]] && install_src="tune2fs (создание раздела /)"
  fi
fi

if [[ -z "$install_date" ]]; then
  install_date=$(stat -c %y /lost+found 2>/dev/null | cut -d. -f1 || true)
  [[ -n "$install_date" ]] && install_src="lost+found (грубо)"
fi

echo "--- Установка системы ---"
if [[ -n "$install_date" ]]; then
  echo "Дата:         $install_date"
  echo "Источник:     $install_src"
else
  echo "Дата:         не удалось определить"
  echo "              (sudo tune2fs -l \$(findmnt -n -o SOURCE /) — точнее)"
fi
echo "Uptime:       $(uptime -p 2>/dev/null || uptime)"
echo

# --- Виртуальная машина ---
virt="unknown"
virt_detail=""

if command -v systemd-detect-virt >/dev/null 2>&1; then
  v=$(systemd-detect-virt 2>/dev/null || echo "none")
  [[ "$v" == "none" ]] && virt="bare metal / container none" || virt="VM ($v)"
fi

read_dmi() {
  local f="$1"
  [[ -r "$f" ]] && cat "$f" 2>/dev/null | tr -d '\0' || true
}

vendor=$(read_dmi /sys/class/dmi/id/sys_vendor)
product=$(read_dmi /sys/class/dmi/id/product_name)
board=$(read_dmi /sys/class/dmi/id/board_name)

if [[ -n "$vendor" || -n "$product" ]]; then
  virt_detail="${vendor:-?} / ${product:-?}"
  case "${vendor}${product}${board}" in
    *[Vv][Mm]ware*|*VMware*)          virt="VM (VMware)" ;;
    *VirtualBox*|*innotek*)           virt="VM (VirtualBox)" ;;
    *QEMU*|*KVM*|*Bochs*)             virt="VM (QEMU/KVM)" ;;
    *Microsoft*Virtual*|*Hyper-V*)   virt="VM (Hyper-V)" ;;
    *Xen*)                            virt="VM (Xen)" ;;
    *Parallels*)                       virt="VM (Parallels)" ;;
  esac
fi

if grep -qi hypervisor /proc/cpuinfo 2>/dev/null; then
  [[ "$virt" == "unknown" || "$virt" == *bare* ]] && virt="VM (hypervisor в cpuinfo)"
fi

if [[ -d /proc/vz ]] || grep -q 'container=lxc' /proc/1/environ 2>/dev/null; then
  virt="Container/LXC"
fi

echo "--- Виртуализация ---"
echo "Вердикт:      $virt"
[[ -n "$virt_detail" ]] && echo "DMI:          $virt_detail"
[[ -n "$board" && "$board" != "$product" ]] && echo "Board:        $board"

if echo "$virt" | grep -qi '^VM'; then
  echo
  echo "[?] Виртуальная машина — не бан сам по себе."
  echo "    Свежая VM + чистая history = копать глубже."
elif echo "$virt" | grep -qi 'bare metal'; then
  echo
  echo "[OK] Похоже на физический ПК (не VM)."
else
  echo
  echo "[?] Неясно — проверь DMI выше."
fi

echo
echo "=== Конец ==="
