# Прошивка и размещение (Samsung Galaxy A32, Halium)

> Разблокировка загрузчика стирает данные, помечает Knox (0x1). Имена разделов и offsets boot.img — строго из `heimdall print-pit` и распаковки стокового `boot.img` для вашей модели/прошивки. `[DEVICE-SPECIFIC]`

## 1. Разблокировка
- OEM Unlock: Настройки → О телефоне → (7× номер сборки) → Параметры разработчика → «Заводская разблокировка».
- Download Mode: выкл. → удерживать **Vol+ и Vol-**, подключить USB → долго **Vol+** (подтверждение, wipe).
- Проверка: `FRP LOCK: OFF`, `OEM LOCK: OFF (U)`.

## 2. vbmeta (отключение AVB/dm-verity)
```bash
avbtool make_vbmeta_image --flag 2 --padding_size 4096 --output vbmeta_disabled.img
heimdall detect
heimdall print-pit | tee pit.txt
heimdall flash --VBMETA vbmeta_disabled.img
# при наличии раздела: heimdall flash --VBMETA_SYSTEM vbmeta_disabled.img
```

## 3. boot (ядро + halium-initramfs)
```bash
# offsets/base/cmdline/pagesize/header_version — из стокового boot.img
mkbootimg \
  --kernel arch/arm64/boot/Image.gz-dtb \
  --ramdisk halium-initramfs.cpio.gz \
  --base 0x40078000 --kernel_offset 0x00008000 \
  --ramdisk_offset 0x11088000 --tags_offset 0x07c08000 \
  --pagesize 2048 \
  --cmdline "bootopt=64S3,32N2,64N2 androidboot.hardware=mt6768 androidboot.selinux=permissive" \
  --header_version 2 --os_version 11.0.0 --os_patch_level 2023-00 \
  -o boot-halium.img

heimdall flash --BOOT boot-halium.img
```

## 4. rootfs и Android-контейнер (на userdata)
`userdata` не прошивать целиком образом rootfs. Копировать файлы:
```bash
adb push build/sm-a325f/rootfs.img /sdcard/
adb push halium-system.img /sdcard/   # [DEVICE-SPECIFIC]
adb shell
su
mkdir -p /data/halium
cp /sdcard/rootfs.img /data/halium/rootfs.img
cp /sdcard/halium-system.img /data/halium/android-rootfs.img
sync
```
Пути должны совпадать с тем, что ищет halium-initramfs.

## 5. Откат
```bash
adb shell su -c "dd if=/dev/block/by-name/boot of=/sdcard/backup_boot.img"
adb pull /sdcard/backup_boot.img
heimdall flash --BOOT boot_stock.img --VBMETA vbmeta_stock.img
```
При bootloop Download Mode обычно доступен для восстановления стокового `BOOT`/AP.
