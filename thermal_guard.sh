#!/bin/bash

echo "Как просматривать записи журнала"
echo "Все записи скрипта через journalctl"
echo " journalctl -t docker-temp-guard "
echo "Следить за логами в реальном времени"
echo " journalctl -t docker-temp-guard -f"
echo " Поиск в текстовом файле /var/log/syslog"
echo "grep \"docker-temp-guard\" /var/log/syslog"

echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null

CONTAINER="32535c2a246a"
HIGH_TEMP=88    # Температура постановки на паузу (°C)
LOW_TEMP=70     # Температура возобновления работы (°C)
INTERVAL=4      # Интервал проверки в секундах
LOG_TAG="docker-temp-guard" # Имя тега в системном журнале

PAUSED=0

# Функция для одновременного вывода в консоль и системный журнал
log_event() {
    local level="$1" # info, warning, err
    local msg="$2"
    echo -e "\n[$(date +%H:%M:%S)] $msg"
    logger -t "$LOG_TAG" -p "user.$level" "$msg"
}

# При выходе по Ctrl+C снимаем контейнер с паузы, чтобы не забыть его замороженным
cleanup() {
    if [ "$PAUSED" -eq 1 ]; then
        log_event "info" "Завершение скрипта: возобновляем $CONTAINER..."
        docker unpause "$CONTAINER" >/dev/null 2>&1
    else
        log_event "info" "Скрипт контроля температуры остановлен."
    fi
    exit 0
}
trap cleanup SIGINT SIGTERM

log_event "info" "Запущен контроль температуры для контейнера '$CONTAINER' (Пауза >= ${HIGH_TEMP}°C, Старт <= ${LOW_TEMP}°C)"

while true; do
    # Получаем целое значение температуры Package id 0
    TEMP=$(sensors | awk '/Package id 0:/ {gsub(/\+|\..*/, "", $4); print $4}')
    
    # Получаем общую загрузку CPU в процентах
    LOAD=$(top -bn1 | awk '/Cpu\(s\)/ {printf "%.1f", 100 - $8}')

    if [ -z "$TEMP" ]; then
        log_event "err" "Ошибка: не удалось прочитать датчик Package id 0"
        sleep "$INTERVAL"
        continue
    fi

    STATUS="ACTIVE"
    [ "$PAUSED" -eq 1 ] && STATUS="PAUSED"

    # Обновляем строку состояния только в терминале (без записи в лог)
    printf "\r[%s] CPU: %5s%% | Temp: %s°C | Статус: %s   " "$(date +%H:%M:%S)" "$LOAD" "$TEMP" "$STATUS"

    if [ "$TEMP" -ge "$HIGH_TEMP" ] && [ "$PAUSED" -eq 0 ]; then
        log_event "warning" "Температура ${TEMP}°C >= ${HIGH_TEMP}°C (CPU: ${LOAD}%)! Ставим $CONTAINER на паузу..."
        if docker pause "$CONTAINER" >/dev/null; then
            PAUSED=1
        else
            log_event "err" "Не удалось поставить контейнер $CONTAINER на паузу!"
        fi
    elif [ "$TEMP" -le "$LOW_TEMP" ] && [ "$PAUSED" -eq 1 ]; then
        log_event "info" "Температура опустилась до ${TEMP}°C <= ${LOW_TEMP}°C (CPU: ${LOAD}%). Возобновляем $CONTAINER..."
        if docker unpause "$CONTAINER" >/dev/null; then
            PAUSED=0
        else
            log_event "err" "Не удалось возобновить работу контейнера $CONTAINER!"
        fi
    fi

    sleep "$INTERVAL"
done

