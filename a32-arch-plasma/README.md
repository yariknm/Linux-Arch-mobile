# Arch Linux ARM + KDE Plasma Mobile для Samsung Galaxy A32 (Halium bring-up kit)

Комплект для сборки rootfs и bring-up системы **Arch Linux ARM (aarch64) + KDE Plasma Mobile** на **Samsung Galaxy A32**:
- `SM-A325F` (4G, Helio G80, 1080×2400) — профиль по умолчанию
- `SM-A326B` (5G, Dimensity 720, 720×1600)

> **Статус:** готового порта для A32 нет. Это заготовка (rootfs, конфиги, kernel fragment, инструкции прошивки) для Halium-пути (Android-ядро + LXC-контейнер + libhybris). До рабочего UI/телефонии требуется device-specific работа: ядро из Samsung OSS, halium-initramfs, совместимый `halium-system.img` (vendor), адаптация hwcomposer/audio/RIL.

## Почему нет готового порта на GitHub

- SoC MediaTek (Helio G80 / Dimensity 720) без поддержки mainline (нет открытых драйверов GPU/дисплея/модема) → нужен Halium + libhybris с вендорными блобами.
- Порт требует: манифест Halium, сборку/патчинг ядра Samsung (4.14) под конкретный билд, initramfs, адаптацию HWC/audio/RIL, отладку на железе. Это месяцы работы и наличие устройства у мейнтейнера.
- Для этих моделей нет опубликованного завершённого порта в Halium/postmarketOS (по состоянию на подготовку комплекта).

## Состав

```text
profiles/        # параметры устройств (DPI, разделы, пути)
scripts/         # build-rootfs.sh (pacstrap + qemu-user-static)
kernel/          # halium.fragment.config (cgroups/namespaces/binder, без PARANOID_NETWORK)
flash/           # инструкции heimdall/vbmeta/boot/rootfs placement
```

## Сборка rootfs (хост: x86_64 Arch Linux)

```bash
sudo pacman -S --needed arch-install-scripts qemu-user-static qemu-user-static-binfmt \
  e2fsprogs dosfstools parted rsync android-tools heimdall
sudo systemctl restart systemd-binfmt

chmod +x scripts/build-rootfs.sh
sudo ./scripts/build-rootfs.sh profiles/sm-a325f.env
# или: sudo ./scripts/build-rootfs.sh profiles/sm-a326b.env
```

Результат: `build/<device>/rootfs.img`. Недостающие в бинарных репо пакеты (часть Plasma Mobile, `libhybris`, droid-модули) — из DanctNIX/AUR/внешних сборок (см. вывод скрипта).

## Ядро

1. Скачать Kernel Source для точной модели/прошивки: https://opensource.samsung.com/
2. Применить `kernel/halium.fragment.config` к device defconfig, собрать, упаковать в `boot.img` с halium-initramfs и offsets из стокового boot.
3. Критично: `CONFIG_ANDROID_PARANOID_NETWORK` выключен, включены binder/ashmem/cgroups/namespaces/devtmpfs_mount.

## Прошивка

См. `flash/flash-heimdall.md`: разблокировка OEM, `vbmeta_disabled.img`, `heimdall flash --BOOT boot-halium.img`, размещение `rootfs.img` и `android-rootfs.img` в `/data/halium/`.

## После bring-up (hybris)

- Графика: `QT_QPA_PLATFORM=hwcomposer`, `EGL_PLATFORM=hwcomposer`, пути `HYBRIS_LD_LIBRARY_PATH`/`LD_LIBRARY_PATH` к `/android/vendor/lib64` и `libhybris`.
- Звук: `pulseaudio-module-droid` (или pipewire-droid), `module-droid-card`.
- Модем/звонки: `ofono` + `ofono-ril-binder-plugin` (binder, device-specific).

Учётные данные по умолчанию (сменить): пользователь `alarm/1234`, `root/root`.
