# Arch Linux ARM Mobile — Samsung Galaxy A32 (KDE Plasma Mobile, Halium)

Полноценная заготовка системы **Arch Linux ARM (aarch64) + KDE Plasma Mobile** для **Samsung Galaxy A32**:
- **SM-A325F** — 4G, Helio G80 (MT6768/MT6769), 6.4" 1080×2400 (~411 dpi)
- **SM-A326B** — 5G, Dimensity 720 (MT6853), 6.5" 720×1600 (~270 dpi)

Архитектура: **Halium** (ядро Android + LXC-контейнер с вендорными HAL) + GNU/Linux userspace Arch + Plasma Mobile (Wayland/KWin) + libhybris для доступа к железу.

> **Честный статус:** готового порта для A32 нет. Репозиторий содержит полную userspace-систему (rootfs, пакеты, конфиги, сервисы, сборка, профили устройств, kernel fragment, flash-инструкции). Для загрузки и работы на телефоне обязательны device-specific этапы: ядро Samsung OSS, halium-initramfs, `android-rootfs.img`/vendor, адаптация hwcomposer/аудио/RIL. Подробности — `docs/STATUS.md`, `docs/ARCHITECTURE.md`.

## Состав

```text
profiles/        Профили устройств (DPI, экран, разделы, пути Halium)
packages/        Списки пакетов: base, ui, connectivity, telephony-hybris
overlay/         Корневая ФС-конфигурация (etc, os-release, sddm, udev, NetworkManager, systemd, шаблоны)
scripts/         build-rootfs.sh — сборка rootfs.img (pacstrap + qemu-user-static + overlay)
kernel/          halium.fragment.config — флаги для ядра (cgroups/ns/binder/devtmpfs)
halium/          Шаблоны/заглушки для LXC, android-mounts, droid-конфигов
flash/           Прошивка: vbmeta, boot.img, размещение rootfs/android на /data/halium
docs/            Архитектура и статус bring-up
```

## Сборка rootfs (хост: x86_64 Arch Linux)

```bash
sudo pacman -S --needed \
  arch-install-scripts qemu-user-static qemu-user-static-binfmt \
  e2fsprogs parted rsync android-tools heimdall

sudo systemctl restart systemd-binfmt

chmod +x scripts/build-rootfs.sh
sudo ./scripts/build-rootfs.sh profiles/sm-a325f.env
# 5G: sudo ./scripts/build-rootfs.sh profiles/sm-a326b.env
```

Артефакт: `build/<device>/rootfs.img` (ext4, по умолчанию 8 GiB).  
По умолчанию: пользователь `alarm/1234`, `root/root` (сменить после первого запуска).  
Недоступные в подключённых бинарных репозиториях пакеты (часть мобильного стека, libhybris, droid-модули) пропускаются с предупреждением — ставятся из DanctNIX/AUR/внешних сборок в chroot на целевой системе.

## Конфигурация системы (входит в rootfs)

- **Сессия:** SDDM, автологин в `plasma-mobile` (Wayland), `PLASMA_PLATFORM=phone:handset`.
- **Окружение:** `QT_IM_MODULE=maliit`, HiDPI через `QT_FONT_DPI` из профиля, `PLASMA_INTEGRATION_USE_PORTAL=1`.
- **Bring-up fallback:** `QT_QPA_PLATFORM=wayland`, `QT_QUICK_BACKEND=software` (до настройки hwcomposer).
- **Сеть/звук:** NetworkManager, Bluetooth, PipeWire (+Pulse/ALSA) как user-сервисы.
- **Halium-шаблоны:** env для hwcomposer/hybris, udev-правила binder/input, шаблоны ofono-ril-binder и PulseAudio droid.
- **Идентификация ОС:** `/etc/os-release` (`Arch Linux ARM Mobile`, variant Plasma Mobile/Halium).

## Ядро

1. Скачать Kernel Source для точной модели/билда: https://opensource.samsung.com/ (`SM-A325F` / `SM-A326B`).
2. Применить `kernel/halium.fragment.config` к device defconfig:
   ```bash
   ./scripts/kconfig/merge_config.sh -m .config kernel/halium.fragment.config
   make olddefconfig
   ```
   Критично: `CONFIG_ANDROID_PARANOID_NETWORK=n`, включены cgroups/namespaces/binder/ashmem/devtmpfs_mount.
3. Собрать и упаковать `boot.img` (ядро + `halium-initramfs.cpio.gz`) с offsets/cmdline из стокового boot (`unpackbootimg`).

## Прошивка и запуск

См. `flash/flash-heimdall.md`:
1. OEM Unlock → Download Mode.
2. `vbmeta_disabled.img` (`avbtool --flag 2`) → `heimdall flash --VBMETA ...`
3. `heimdall flash --BOOT boot-halium.img`
4. Разместить `rootfs.img` и `android-rootfs.img` (Halium, device-specific) в `/data/halium/` на userdata.

## Аппаратное включение (device-specific, после bring-up)

- **Графика:** установить hybris/QPA-пакеты, включить `QT_QPA_PLATFORM=hwcomposer`, `EGL_PLATFORM=hwcomposer`, пути `/android/vendor/lib64`; запустить `lxc@android`.
- **Звук:** `pulseaudio-module-droid` / droid-модули, `callaudiod`.
- **Модем/звонки:** `ofono` + `ofono-ril-binder-plugin`, конфиг слотов binder.
- **Wi-Fi/BT/сенсоры:** адаптация под вендорные HAL/ядро устройства.

## Лицензия и ответственность

Конфиги/скрипты предоставляются как есть. Разблокировка/прошивка несут риск потери данных и нарушения гарантии (Knox 0x1). Проверяйте PIT, offsets и образы под вашу модель/прошивку перед записью.
