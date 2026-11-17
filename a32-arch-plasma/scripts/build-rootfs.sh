#!/usr/bin/env bash
# Сборка Arch Linux ARM (aarch64) + KDE Plasma Mobile rootfs.img для Samsung Galaxy A32 (Halium)
# Хост: x86_64 Arch Linux. Запуск: sudo ./scripts/build-rootfs.sh [profiles/sm-a325f.env]
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROFILE="${1:-${PROJECT_DIR}/profiles/sm-a325f.env}"
[[ -f "$PROFILE" ]] || { echo "Нет профиля: $PROFILE"; exit 1; }
# shellcheck source=/dev/null
source "$PROFILE"

: "${DEVICE:?DEVICE не задан в профиле}"
: "${SCREEN_DPI:?SCREEN_DPI не задан в профиле}"
: "${ROOTFS_IMAGE_NAME:=rootfs.img}"

WORKDIR="${WORKDIR:-${PROJECT_DIR}/build/${DEVICE}}"
ROOTFS="${WORKDIR}/rootfs"
IMG="${WORKDIR}/${ROOTFS_IMAGE_NAME}"
IMG_SIZE_MB="${IMG_SIZE_MB:-8192}"
ALARM_MIRROR="${ALARM_MIRROR:-http://mirror.archlinuxarm.org}"
DANCTNIX_REPO="${DANCTNIX_REPO:-https://p64.arikawa-hi.me/danctnix/aarch64/}"
HOSTNAME="${HOSTNAME:-arch-a32}"
USERNAME="${USERNAME:-alarm}"
USERPASS="${USERPASS:-1234}"
ROOTPASS="${ROOTPASS:-root}"
LOCALE_LINE="${LOCALE_LINE:-en_US.UTF-8 UTF-8}"
LANG_DEFAULT="${LANG_DEFAULT:-en_US.UTF-8}"
TIMEZONE="${TIMEZONE:-UTC}"

[[ $EUID -eq 0 ]] || { echo "Запускать от root"; exit 1; }
for cmd in pacstrap arch-chroot qemu-aarch64-static mkfs.ext4 truncate rsync; do
  command -v "$cmd" >/dev/null || { echo "Нет команды: $cmd"; exit 1; }
done

read_pkglist() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  grep -vE '^\s*(#|$)' "$f" || true
}

mkdir -p "$WORKDIR" "$ROOTFS"
rm -f "$IMG"

echo "[*] Device=$DEVICE (${MODEL:-}) DPI=$SCREEN_DPI"
echo "[*] Создание образа $IMG (${IMG_SIZE_MB}M)"
truncate -s "${IMG_SIZE_MB}M" "$IMG"
mkfs.ext4 -F -L arch-root "$IMG"

MOUNTED=0
cleanup(){ set +e; sync; if [[ $MOUNTED -eq 1 ]]; then umount -R "$ROOTFS/dev" 2>/dev/null || true; umount -R "$ROOTFS/proc" 2>/dev/null || true; umount -R "$ROOTFS/sys" 2>/dev/null || true; umount -R "$ROOTFS" 2>/dev/null || true; fi; }
trap cleanup EXIT
mount -o loop "$IMG" "$ROOTFS"; MOUNTED=1

PACCONF="${WORKDIR}/pacman-aarch64.conf"
cat > "$PACCONF" <<EOF
[options]
Architecture = aarch64
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
[core]
Server = ${ALARM_MIRROR}/\$arch/\$repo
[extra]
Server = ${ALARM_MIRROR}/\$arch/\$repo
[alarm]
Server = ${ALARM_MIRROR}/\$arch/\$repo
EOF
if [[ -n "$DANCTNIX_REPO" ]]; then
cat >> "$PACCONF" <<EOF
[danctnix]
SigLevel = Optional TrustAll
Server = ${DANCTNIX_REPO}
EOF
echo "[!] [danctnix] добавлен с SigLevel=Optional TrustAll — для production настроить ключ."
fi

install_set() {
  local name="$1"; shift
  local req=("$@") ok=() p
  [[ ${#req[@]} -eq 0 ]] && return 0
  for p in "${req[@]}"; do
    if pacman --config "$PACCONF" -Si "$p" &>/dev/null; then ok+=("$p"); else echo "[!] отсутствует в репо: $p"; fi
  done
  if [[ ${#ok[@]} -gt 0 ]]; then
    echo "[*] pacstrap: $name (${#ok[@]} пакетов)"
    pacstrap -C "$PACCONF" -M "$ROOTFS" "${ok[@]}"
  else
    echo "[!] набор '$name': нет доступных пакетов"
  fi
}

mapfile -t PKGS_BASE < <(read_pkglist "${PROJECT_DIR}/packages/base.txt")
mapfile -t PKGS_UI < <(read_pkglist "${PROJECT_DIR}/packages/ui.txt")
mapfile -t PKGS_CONN < <(read_pkglist "${PROJECT_DIR}/packages/connectivity.txt")
mapfile -t PKGS_TEL < <(read_pkglist "${PROJECT_DIR}/packages/telephony-hybris.txt")

install_set "base" "${PKGS_BASE[@]}"
install_set "ui/plasma-mobile" "${PKGS_UI[@]}"
install_set "connectivity/audio" "${PKGS_CONN[@]}"
install_set "telephony/hybris" "${PKGS_TEL[@]}"
install_set "hybris-if-present" libhybris

echo "[*] Применение overlay"
mkdir -p "$ROOTFS/etc" "$ROOTFS/usr/lib" "$ROOTFS/var/lib" "$ROOTFS/android" "$ROOTFS/userdata" "$ROOTFS/data"
rsync -a "${PROJECT_DIR}/overlay/" "$ROOTFS/"

# device-specific подстановки
echo "$HOSTNAME" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
EOF
echo "$LOCALE_LINE" >> "$ROOTFS/etc/locale.gen"
echo "LANG=${LANG_DEFAULT}" > "$ROOTFS/etc/locale.conf"
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "$ROOTFS/etc/localtime" 2>/dev/null || ln -sf /usr/share/zoneinfo/UTC "$ROOTFS/etc/localtime"

# DPI в /etc/environment
if [[ -f "$ROOTFS/etc/environment" ]]; then
  sed -i "s/^QT_FONT_DPI=.*/QT_FONT_DPI=${SCREEN_DPI}/" "$ROOTFS/etc/environment" || true
fi

# os-release: дополнить моделью устройства
if [[ -f "$ROOTFS/etc/os-release" ]]; then
  grep -q '^TARGET_DEVICE_MODEL=' "$ROOTFS/etc/os-release" || echo "TARGET_DEVICE_MODEL=\"${MODEL:-$DEVICE}\"" >> "$ROOTFS/etc/os-release"
  grep -q '^TARGET_DEVICE_CODENAME=' "$ROOTFS/etc/os-release" || echo "TARGET_DEVICE_CODENAME=\"${DEVICE}\"" >> "$ROOTFS/etc/os-release"
fi

cat > "$ROOTFS/etc/fstab" <<'EOF'
# / монтируется halium-initramfs. Bind-mount'ы Android настраиваются device-адаптацией/initrd.
# tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
EOF

chmod 755 "$ROOTFS/etc/profile.d/plasma-mobile.sh" 2>/dev/null || true
chmod 755 "$ROOTFS/usr/local/bin/arch-a32-firstboot" 2>/dev/null || true

echo "[*] chroot-настройка"
arch-chroot "$ROOTFS" /bin/bash -euo pipefail <<CHROOT
locale-gen || true
echo "root:${ROOTPASS}" | chpasswd
if ! id -u "${USERNAME}" >/dev/null 2>&1; then
  useradd -m -G wheel,video,audio,input,network,storage,power,render,scanner -s /bin/bash "${USERNAME}"
fi
echo "${USERNAME}:${USERPASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers || true

# Сервисы
systemctl enable NetworkManager.service || true
systemctl enable bluetooth.service || true
systemctl enable sshd.service || true
systemctl enable sddm.service || true
systemctl enable upower.service || true
systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service || true
# Halium (после установки адаптации): lxc@android, ofono, android-mounts

# Сессия plasma-mobile должна существовать
if [[ ! -f /usr/share/wayland-sessions/plasma-mobile.desktop ]]; then
  echo "[!] /usr/share/wayland-sessions/plasma-mobile.desktop не найден — проверьте пакет plasma-mobile"
fi
CHROOT

sync
umount -R "$ROOTFS" 2>/dev/null || true; MOUNTED=0; trap - EXIT
echo "[+] RootFS готов: $IMG"
echo "    Device: ${DEVICE} (${MODEL:-})  DPI: ${SCREEN_DPI}"
echo "    User: ${USERNAME}/${USERPASS}  Root: root/${ROOTPASS}"
echo "    Следующий шаг: halium-initramfs + android-rootfs.img + прошивка (см. flash/flash-heimdall.md)"
