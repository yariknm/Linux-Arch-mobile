#!/usr/bin/env bash
# Сборка Arch Linux ARM aarch64 rootfs.img для Samsung Galaxy A32 (Halium)
set -euo pipefail

PROFILE="${1:-profiles/sm-a325f.env}"
[[ -f "$PROFILE" ]] || { echo "Нет профиля: $PROFILE"; exit 1; }
# shellcheck source=/dev/null
source "$PROFILE"

WORKDIR="${WORKDIR:-$(pwd)/build/${DEVICE}}"
ROOTFS="${WORKDIR}/rootfs"
IMG="${WORKDIR}/${ROOTFS_IMAGE_NAME}"
IMG_SIZE_MB="${IMG_SIZE_MB:-8192}"
ALARM_MIRROR="${ALARM_MIRROR:-http://mirror.archlinuxarm.org}"
DANCTNIX_REPO="${DANCTNIX_REPO:-https://p64.arikawa-hi.me/danctnix/aarch64/}"
HOSTNAME="${HOSTNAME:-arch-a32}"
USERNAME="${USERNAME:-alarm}"
USERPASS="${USERPASS:-1234}"
ROOTPASS="${ROOTPASS:-root}"

[[ $EUID -eq 0 ]] || { echo "Запускать от root"; exit 1; }
command -v qemu-aarch64-static >/dev/null || { echo "Установите qemu-user-static(+binfmt)"; exit 1; }

mkdir -p "$WORKDIR" "$ROOTFS"
rm -f "$IMG"

echo "[*] Создание образа $IMG (${IMG_SIZE_MB}M)"
truncate -s "${IMG_SIZE_MB}M" "$IMG"
mkfs.ext4 -F -L arch-root "$IMG"

MOUNTED=0
cleanup(){ set +e; sync; [[ $MOUNTED -eq 1 ]] && umount -R "$ROOTFS" || true; }
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
fi

install_set() {
  local name="$1"; shift
  local req=("$@") ok=() p
  for p in "${req[@]}"; do
    pacman --config "$PACCONF" -Si "$p" &>/dev/null && ok+=("$p") || echo "[!] отсутствует: $p"
  done
  [[ ${#ok[@]} -gt 0 ]] && { echo "[*] pacstrap: $name"; pacstrap -C "$PACCONF" -M "$ROOTFS" "${ok[@]}"; }
}

install_set "base" \
  base mkinitcpio openssh sudo nano vim less which \
  archlinuxarm-keyring ca-certificates lxc android-tools iproute2 dnsutils

install_set "graphics/plasma" \
  mesa wayland wayland-protocols xorg-xwayland qt6-wayland \
  kwin plasma-workspace plasma-mobile kirigami kirigami-addons qqc2-desktop-style \
  xdg-desktop-portal xdg-desktop-portal-kde polkit-kde-agent \
  plasma-pa powerdevil upower sddm qt6-declarative konsole \
  angelfish plasma-dialer spacebar

install_set "audio/net" \
  networkmanager bluez bluez-utils \
  pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils \
  modemmanager mobile-broadband-provider-info

install_set "input" maliit-framework maliit-keyboard

# hybris-компоненты (обычно нет в ALARM; ставить из AUR/внешнего репо после сборки):
# libhybris, android-headers, pulseaudio-module-droid, ofono-ril-binder и т.д.
install_set "hybris-if-present" libhybris

echo "[*] Базовые файлы"
echo "$HOSTNAME" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${HOSTNAME}.localdomain ${HOSTNAME}
EOF
mkdir -p "$ROOTFS/etc/sddm.conf.d" "$ROOTFS/etc/profile.d" "$ROOTFS/etc/xdg" \
         "$ROOTFS/etc/udev/rules.d" "$ROOTFS/android" "$ROOTFS/userdata"

cat > "$ROOTFS/etc/fstab" <<'EOF'
# / монтируется halium-initramfs. Bind-mount'ы Android настраиваются в initrd/device-адаптации.
EOF

echo "en_US.UTF-8 UTF-8" >> "$ROOTFS/etc/locale.gen"
echo "LANG=en_US.UTF-8" > "$ROOTFS/etc/locale.conf"

cat > "$ROOTFS/etc/environment" <<EOF
PLASMA_INTEGRATION_USE_PORTAL=1
QT_IM_MODULE=maliit
QT_FONT_DPI=${SCREEN_DPI}
QT_ENABLE_HIGHDPI_SCALING=1
QT_SCALE_FACTOR_ROUNDING_POLICY=RoundPreferFloor

# Bring-up fallback (пока нет рабочего hwcomposer):
QT_QPA_PLATFORM=wayland
QT_QUICK_BACKEND=software

# После установки hybris QPA/адаптации раскомментировать и проверить пути:
# QT_QPA_PLATFORM=hwcomposer
# EGL_PLATFORM=hwcomposer
# HYBRIS_LD_LIBRARY_PATH=/android/vendor/lib64:/android/vendor/lib64/hw:/android/system/lib64
# LD_LIBRARY_PATH=/usr/lib/libhybris:\$LD_LIBRARY_PATH
EOF

cat > "$ROOTFS/etc/profile.d/plasma-mobile.sh" <<'EOF'
#!/bin/sh
export PLASMA_PLATFORM=phone:handset
export QT_QUICK_CONTROLS_MOBILE=1
export QT_QUICK_CONTROLS_STYLE=Plasma
export MALIIT_KEYBOARD_LANGUAGES="en,ru"
EOF
chmod 755 "$ROOTFS/etc/profile.d/plasma-mobile.sh"

cat > "$ROOTFS/etc/sddm.conf.d/10-autologin.conf" <<EOF
[Autologin]
User=${USERNAME}
Session=plasma-mobile.desktop
Relogin=false
[General]
DisplayServer=wayland
EOF

cat > "$ROOTFS/etc/sddm.conf.d/20-wayland.conf" <<'EOF'
[General]
DisplayServer=wayland
[Wayland]
SessionDir=/usr/share/wayland-sessions
EOF

cat > "$ROOTFS/etc/udev/rules.d/70-halium-android.rules" <<'EOF'
# Базовые разрешения для binder/ashmem (уточнить под device/адаптацию)
KERNEL=="binder*|ashmem*|vndbinder*|hwbinder*", MODE="0666"
SUBSYSTEM=="graphics", MODE="0660", GROUP="video"
EOF

echo "[*] chroot-настройка"
arch-chroot "$ROOTFS" /bin/bash -euo pipefail <<CHROOT
locale-gen || true
echo "root:${ROOTPASS}" | chpasswd
id -u "${USERNAME}" >/dev/null 2>&1 || useradd -m -G wheel,video,audio,input,network,storage,power,render -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${USERPASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers || true

systemctl enable NetworkManager.service || true
systemctl enable bluetooth.service || true
systemctl enable sshd.service || true
systemctl enable sddm.service || true
systemctl enable upower.service || true
systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service || true
# после установки halium-адаптации: systemctl enable lxc@android.service
CHROOT

sync
umount "$ROOTFS"; MOUNTED=0; trap - EXIT
echo "[+] Готово: $IMG"
echo "    device=$DEVICE dpi=$SCREEN_DPI (${SCREEN_W}x${SCREEN_H}) user=${USERNAME}/${USERPASS}"
