# Архитектура: Arch Linux ARM + Plasma Mobile на Samsung Galaxy A32 (Halium)

## Слои

1. **Загрузчик (Samsung BL / Download Mode)**  
   Прошивка `boot.img` (ядро + halium-initramfs), `vbmeta` (AVB отключён для разработки), при необходимости `dtbo`. Разблокировка OEM обязательна.

2. **Ядро**  
   Стоковое ядро Samsung (Linux 4.14, OSS) с конфигом для systemd/LXC/binder/devtmpfs и `CONFIG_ANDROID_PARANOID_NETWORK=n`. Аппаратная поддержка (дисплей, тач, GPU, модем) обеспечивается вендорными драйверами/модулями ядра.

3. **halium-initramfs**  
   Монтирует rootfs (Arch, `rootfs.img` в `/data/halium/`) и Android system/vendor (LXC-контейнер), поднимает binder/сервисы, выполняет switch-root в Arch userspace.

4. **Android-контейнер (LXC)**  
   Минимальная Android-среда для доступа к HAL (HWC/gralloc, audio, RIL, sensors) через binder.

5. **Arch Linux ARM userspace**  
   systemd, NetworkManager, PipeWire, SDDM, KDE Plasma Mobile (KWin/Wayland). Аппаратный доступ — через libhybris (`hwcomposer` QPA, droid audio/RIL) после адаптации.

## Режимы работы

- **Bring-up fallback:** `QT_QPA_PLATFORM=wayland`, `QT_QUICK_BACKEND=software` (llvmpipe) — для проверки UI без рабочего hwcomposer.
- **Halium/hardware:** `QT_QPA_PLATFORM=hwcomposer`, `EGL_PLATFORM=hwcomposer`, корректные `HYBRIS_LD_LIBRARY_PATH`/`LD_LIBRARY_PATH`, запущенный `lxc@android`.

## Device-specific компоненты (не входят в rootfs-автоматику)

- Ядро из Samsung OSS для точной модели/прошивки + упаковка `boot.img` со стоковыми offsets.
- halium-initramfs, собранный под устройство.
- `android-rootfs.img`/vendor, совместимые с прошивкой (Halium base 11 для A32).
- Адаптация: device manifest/config, udev/правила, mount-скрипты, ofono-ril-binder, audio HAL конфиг, сенсоры, вибрация.
