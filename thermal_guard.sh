#!/bin/bash

echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo

CONTAINER="fec71d79cbb5"
HIGH_TEMP=90    # Температура постановки на паузу (°C)
LOW_TEMP=75     # Температура возобновления работы (°C)
INTERVAL=3      # Интервал проверки в секундах

PAUSED=0

# При выходе по Ctrl+C снимаем контейнер с паузы, чтобы не забыть его замороженным
cleanup() {
    if [ "$PAUSED" -eq 1 ]; then
        echo -e "\n[$(date +%H:%M:%S)] Завершение скрипта: возобновляем $CONTAINER..."
        docker unpause "$CONTAINER" >/dev/null 2>&1
    fi
    exit 0
}
trap cleanup SIGINT SIGTERM

echo "Запущен контроль температуры для контейнера '$CONTAINER' (Пауза >= ${HIGH_TEMP}°C, Старт <= ${LOW_TEMP}°C)"

while true; do
    # Получаем целое значение температуры Package id 0 (например, 94)
    TEMP=$(sensors | awk '/Package id 0:/ {gsub(/\+|\..*/, "", $4); print $4}')

    if [ -z "$TEMP" ]; then
        echo "[$(date +%H:%M:%S)] Ошибка: не удалось прочитать датчик Package id 0"
        sleep "$INTERVAL"
        continue
    fi

    if [ "$TEMP" -ge "$HIGH_TEMP" ] && [ "$PAUSED" -eq 0 ]; then
        echo "[$(date +%H:%M:%S)] Температура ${TEMP}°C >= ${HIGH_TEMP}°C! Ставим $CONTAINER на паузу..."
        if docker pause "$CONTAINER" >/dev/null; then
            PAUSED=1
        fi
    elif [ "$TEMP" -le "$LOW_TEMP" ] && [ "$PAUSED" -eq 1 ]; then
        echo "[$(date +%H:%M:%S)] Температура опустилась до ${TEMP}°C <= ${LOW_TEMP}°C. Возобновляем $CONTAINER..."
        if docker unpause "$CONTAINER" >/dev/null; then
            PAUSED=0
        fi
    fi

    sleep "$INTERVAL"
done

