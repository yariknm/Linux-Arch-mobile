#!/bin/sh
# Окружение сессии KDE Plasma Mobile
export PLASMA_PLATFORM="${PLASMA_PLATFORM:-phone:handset}"  # tablet — для планшетного UI
export QT_QUICK_CONTROLS_MOBILE=1
export QT_QUICK_CONTROLS_STYLE=Plasma
export QT_ENABLE_HIGHDPI_SCALING=1

# Виртуальная клавиатура (Maliit)
export MALIIT_KEYBOARD_LANGUAGES="${MALIIT_KEYBOARD_LANGUAGES:-en,ru}"

# Логи Qt (раскомментировать для отладки)
# export QT_LOGGING_RULES="qt.qpa.*=true;kwin*=true"
# export QT_DEBUG_PLUGINS=1
