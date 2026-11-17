# Статус

| Компонент | Статус |
|---|---|
| Rootfs (Arch ARM aarch64, pacstrap, overlay, профили SM-A325F/A326B) | Готово (сборка на x86_64 хосте с qemu-user-static) |
| KDE Plasma Mobile + SDDM автологин + Maliit + PipeWire | Конфиги/пакеты в списках; фактическая доступность зависит от репозиториев (ALARM/danctnix/AUR) |
| Kernel config fragment (cgroups/ns/binder, без PARANOID_NETWORK) | Готово (применять к OSS defconfig устройства) |
| Halium initramfs / boot.img интеграция | Не входит (device-specific сборка) |
| Android container (system/vendor) | Не входит (нужен совместимый образ под устройство/прошивку) |
| Графика hwcomposer/libhybris | Шаблоны env; требует пакеты QPA/hybris и рабочий LXC |
| Звук (droid) / Модем (ofono-ril-binder) | Шаблоны конфигов; device-specific |
| Wi-Fi/BT/датчики/камера/вибрация | Device-specific адаптация |
| Протестировано на железе SM-A325F/A326B | Нет |

**Итог:** комплект представляет собой полнофункциональную заготовку ОС (userspace, конфигурация, сборка), но не является flash-and-boot прошивкой без завершения device-specific Halium bring-up.
