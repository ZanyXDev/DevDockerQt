#!/bin/bash

# Проверяем, передан ли аргумент с именем или ID контейнера
if [ -z "$1" ]; then
    echo "Ошибка: не указан ID или имя контейнера!"
    echo "Использование: $0 <имя_или_ID_контейнера>"
    exit 1
fi

CONTAINER="$1"

# Получаем полный ID контейнера для чтения метрик cgroups v2
FULL_ID=$(docker inspect --format '{{.Id}}' "$CONTAINER" 2>/dev/null)
if [ -z "$FULL_ID" ]; then
    echo "Ошибка: контейнер '$CONTAINER' не найден!"
    exit 1
fi

echo "Как просматривать записи журнала:"
echo "  journalctl -t docker-temp-guard"
echo "  journalctl -t docker-temp-guard -f"

echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null

# Пороги срабатывания паузы
HIGH_TEMP=88          # Температура постановки на паузу (°C)
LOW_TEMP=70           # Температура возобновления работы (°C)
MIN_FREE_RAM_MB=1200  # Порог свободной ОЗУ для паузы (МБ)
SAFE_FREE_RAM_MB=2200 # Порог свободной ОЗУ для возобновления (МБ)
MAX_MEM_PSI=25        # Порог "задыхания" памяти/zram (PSI avg10, %)
MAX_IO_PSI=40         # Порог "задыхания" диска (PSI avg10, %)

INTERVAL=2            # Уменьшили интервал до 2 сек, чтобы успеть поймать скачок zram
LOG_TAG="docker-temp-guard"

PAUSED=0
PAUSE_REASON="" # Причина паузы: "temp", "ram", "psi_mem", "psi_io"

# Функция записи в консоль и системный журнал
log_event() {
    local level="$1"
    local msg="$2"
    echo -e "\n[$(date +%H:%M:%S)] $msg"
    logger -t "$LOG_TAG" -p "user.$level" "$msg"
}

# Функция сбора статистики cgroup контейнера (сколько он ест RAM и zram)
get_container_cgroup_stats() {
    local cgroup_dir
    cgroup_dir=$(find /sys/fs/cgroup -name "*${FULL_ID}*" -type d 2>/dev/null | head -n 1)
    if [ -n "$cgroup_dir" ] && [ -f "$cgroup_dir/memory.current" ]; then
        local mem_mb swap_mb
        mem_mb=$(( $(cat "$cgroup_dir/memory.current") / 1024 / 1024 ))
        swap_mb=0
        [ -f "$cgroup_dir/memory.swap.current" ] && swap_mb=$(( $(cat "$cgroup_dir/memory.swap.current") / 1024 / 1024 ))
        echo "Container RAM: ${mem_mb}MB, Swap(zram): ${swap_mb}MB"
    else
        echo "cgroup stats unavailable"
    fi
}

cleanup() {
    if [ "$PAUSED" -eq 1 ]; then
        log_event "info" "Завершение скрипта: возобновляем $CONTAINER..."
        docker unpause "$CONTAINER" >/dev/null 2>&1
    else
        log_event "info" "Скрипт мониторинга остановлен."
    fi
    exit 0
}
trap cleanup SIGINT SIGTERM

log_event "info" "Запущен мониторинг '$CONTAINER' (Temp >=${HIGH_TEMP}°C | RAM <${MIN_FREE_RAM_MB}MB | PSI Mem >${MAX_MEM_PSI}% | PSI IO >${MAX_IO_PSI}%)"

while true; do
    # 1. Температура CPU
    TEMP=$(sensors | awk '/Package id 0:/ {gsub(/\+|\..*/, "", $4); print $4}')
    
    # 2. Общая загрузка CPU и iowait (wa) из top
    CPU_STATS=$(top -bn1 | awk '/Cpu\(s\)/ {printf "%.1f %.1f", 100 - $8, $10}')
    LOAD=$(echo "$CPU_STATS" | awk '{print $1}')
    IOWAIT=$(echo "$CPU_STATS" | awk '{print $2}')

    # 3. Свободная RAM и занятый Swap (zram) в МБ
    MEM_STATS=$(awk '
        /MemAvailable:/ {avail=$2}
        /SwapTotal:/ {stotal=$2}
        /SwapFree:/ {sfree=$2}
        END {printf "%d %d", avail/1024, (stotal-sfree)/1024}
    ' /proc/meminfo)
    FREE_RAM_MB=$(echo "$MEM_STATS" | awk '{print $1}')
    USED_SWAP_MB=$(echo "$MEM_STATS" | awk '{print $2}')

    # 4. Показатели PSI (Pressure Stall Information) - берем целую часть avg10 из строки "some"
    MEM_PSI=$(awk -F'[= .]' '/^some/ {print $3}' /proc/pressure/memory 2>/dev/null)
    IO_PSI=$(awk -F'[= .]' '/^some/ {print $3}' /proc/pressure/io 2>/dev/null)
    MEM_PSI=${MEM_PSI:-0}
    IO_PSI=${IO_PSI:-0}

    if [ -z "$TEMP" ]; then
        log_event "err" "Ошибка: не удалось прочитать датчик Package id 0"
        sleep "$INTERVAL"
        continue
    fi

    STATUS="ACTIVE"
    [ "$PAUSED" -eq 1 ] && STATUS="PAUSED($PAUSE_REASON)"

    # Компактная строка телеметрии в реальном времени
    printf "\r[%s] CPU:%5s%% (IOw:%4s%%) | T:%s°C | RAM:%sMB | zram:%sMB | PSI(m/io):%s%%/%s%% | %s   " \
        "$(date +%H:%M:%S)" "$LOAD" "$IOWAIT" "$TEMP" "$FREE_RAM_MB" "$USED_SWAP_MB" "$MEM_PSI" "$IO_PSI" "$STATUS"

    if [ "$PAUSED" -eq 0 ]; then
        REASON=""
        ALERT_MSG=""

        if [ "$TEMP" -ge "$HIGH_TEMP" ]; then
            REASON="temp"
            ALERT_MSG="Перегрев ${TEMP}°C >= ${HIGH_TEMP}°C"
        elif [ "$FREE_RAM_MB" -le "$MIN_FREE_RAM_MB" ]; then
            REASON="ram"
            ALERT_MSG="Мало свободной RAM: ${FREE_RAM_MB}MB <= ${MIN_FREE_RAM_MB}MB"
        elif [ "$MEM_PSI" -ge "$MAX_MEM_PSI" ]; then
            REASON="psi_mem"
            ALERT_MSG="Задыхается память/zram (Memory PSI: ${MEM_PSI}% >= ${MAX_MEM_PSI}%)"
        elif [ "$IO_PSI" -ge "$MAX_IO_PSI" ]; then
            REASON="psi_io"
            ALERT_MSG="Задыхается диск (IO PSI: ${IO_PSI}% >= ${MAX_IO_PSI}%)"
        fi

        if [ -n "$REASON" ]; then
            CGROUP_INFO=$(get_container_cgroup_stats)
            log_event "warning" "$ALERT_MSG | CPU:${LOAD}% IOw:${IOWAIT}% zram:${USED_SWAP_MB}MB | $CGROUP_INFO. Пауза..."
            if docker pause "$CONTAINER" >/dev/null; then
                PAUSED=1
                PAUSE_REASON="$REASON"
                # Если причина в памяти, сбрасываем файловый кэш хоста
                if [ "$REASON" = "ram" ] || [ "$REASON" = "psi_mem" ]; then
                    sync && echo 1 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1
                fi
            else
                log_event "err" "Не удалось поставить контейнер $CONTAINER на паузу!"
            fi
        fi
    else
        # Условия выхода из паузы
        UNPAUSE=0
        UNPAUSE_MSG=""

        if [ "$PAUSE_REASON" = "temp" ] && [ "$TEMP" -le "$LOW_TEMP" ]; then
            UNPAUSE=1
            UNPAUSE_MSG="Температура снизилась до ${TEMP}°C"
        elif [ "$PAUSE_REASON" = "ram" ] && [ "$FREE_RAM_MB" -ge "$SAFE_FREE_RAM_MB" ]; then
            UNPAUSE=1
            UNPAUSE_MSG="Свободная RAM восстановилась до ${FREE_RAM_MB}MB"
        elif [ "$PAUSE_REASON" = "psi_mem" ] && [ "$MEM_PSI" -lt 5 ] && [ "$FREE_RAM_MB" -ge "$MIN_FREE_RAM_MB" ]; then
            UNPAUSE=1
            UNPAUSE_MSG="Нагрузка на память/zram спала (PSI: ${MEM_PSI}%, RAM: ${FREE_RAM_MB}MB)"
        elif [ "$PAUSE_REASON" = "psi_io" ] && [ "$IO_PSI" -lt 10 ]; then
            UNPAUSE=1
            UNPAUSE_MSG="Очередь диска разгрузилась (IO PSI: ${IO_PSI}%)"
        fi

        if [ "$UNPAUSE" -eq 1 ]; then
            log_event "info" "$UNPAUSE_MSG. Возобновляем $CONTAINER..."
            if docker unpause "$CONTAINER" >/dev/null; then
                PAUSED=0
                PAUSE_REASON=""
            else
                log_event "err" "Не удалось возобновить работу контейнера $CONTAINER!"
            fi
        fi
    fi

    sleep "$INTERVAL"
done

