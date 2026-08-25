#!/bin/sh
# Матрица достижимости TCP с ПОДКЛЮЧЁННОГО телефона (adb).
#
# Зачем: когда приложение «не работает в сети», первым делом надо отделить
# «наш сервис сломан» от «в этой сети вообще ничего не открывается».
# Без этого контроля можно построить целый эксперимент на сети, которая
# сама в ограниченном состоянии, и получить уверенный ложный вывод.
#
# Почему именно nc, а не /dev/tcp:
#   в Android sh (mksh/toybox) НЕТ /dev/tcp — конструкция exec 3<>/dev/tcp/...
#   молча падает, и ВСЕ цели показывают таймаут. Отказ инструмента при этом
#   выглядит ровно как результат «всё закрыто», то есть подтверждает любую
#   гипотезу о блокировке. Самая опасная форма ошибки.
#
# Почему echo x | nc, а не nc < /dev/null:
#   символ < в строке команды не переживает PowerShell (зарезервирован),
#   а $? не переживает adb shell. Поэтому вердикт печатает сам телефон
#   через && / ||, а не вычисляется по коду возврата на хосте.
#
#   net-reach.sh [порт]          порт по умолчанию 443
#   net-reach.sh 443 1.1.1.1 ya.ru
set -eu

PORT="${1:-443}"
shift 2>/dev/null || true

if [ "$#" -gt 0 ]; then
    TARGETS="$*"
else
    # Смысл набора: русские мажоры + крупные CDN + зарубежные мажоры.
    # Если открыты только русские — это операторский белый список,
    # и проверять на такой сети что-либо своё бессмысленно.
    TARGETS="5.255.255.242 87.240.132.72 104.16.132.229 172.67.74.226 17.253.39.131 23.55.52.129 142.250.150.100 1.1.1.1"
fi

NAMES="ya.ru(RU) vk.ru(RU) cloudflare-cdn cloudflare-cdn2 apple-cdn akamai google cloudflare-dns"

printf 'Достижимость TCP/%s с телефона\n' "$PORT"
printf 'ВАЖНО: снимать при ВЫКЛЮЧЕННОМ VPN, иначе меряешь туннель\n\n'

adb shell "dumpsys connectivity 2>/dev/null | grep -oE 'type: (WIFI|MOBILE|VPN)\[[A-Z]*\], state: [A-Z/]+' | head -4"
printf '\n'

open_ru=0
open_foreign=0
i=1
for ip in $TARGETS; do
    name=$(echo "$NAMES" | cut -d' ' -f"$i" 2>/dev/null)
    [ -n "$name" ] || name="цель-$i"
    verdict=$(adb shell "echo x | timeout 7 nc -w 5 $ip $PORT >/dev/null 2>&1 && echo OPEN || echo SHUT" 2>/dev/null | tr -d '\r\n ')
    printf '  %-18s %-17s %s\n' "$name" "$ip" "$verdict"
    if [ "$verdict" = "OPEN" ]; then
        case "$name" in
            *RU*) open_ru=$((open_ru + 1)) ;;
            *)    open_foreign=$((open_foreign + 1)) ;;
        esac
    fi
    i=$((i + 1))
done

printf '\n'
if [ "$open_foreign" = "0" ] && [ "$open_ru" -gt 0 ]; then
    printf 'ВЕРДИКТ: похоже на операторский БЕЛЫЙ СПИСОК — открыты только русские цели.\n'
    printf 'Проверять свой сервис на этой сети бессмысленно: результат ложноотрицательный.\n'
elif [ "$open_foreign" = "0" ] && [ "$open_ru" = "0" ]; then
    printf 'ВЕРДИКТ: не открывается НИЧЕГО — сеть нерабочая целиком.\n'
    printf 'Смотреть captive-портал: dumpsys connectivity, поле everCaptivePortalDetected.\n'
else
    printf 'ВЕРДИКТ: сеть в порядке, зарубежные цели доступны (%s из набора).\n' "$open_foreign"
    printf 'Значит отказ своего сервиса — действительно свой, можно копать дальше.\n'
fi
