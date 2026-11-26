#!/bin/bash

# 1. Проверяем права суперпользователя
if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: скрипт требует прав суперпользователя для управления кэшем и cgroups."
    echo "Запустите так: sudo $0 $*"
    exit 1
fi

# 2. Проверяем аргумент с именем или ID контейнера
if [ -z "$1" ]; then
    echo "Ошибка: не указан ID или имя контейнера!"
    echo "Использование: sudo $0 <имя_или_ID_контейнера>"
    exit 1
fi

CONTAINER="$1"
LOG_TAG="docker-temp-guard"

log_event() {
    local level="$1"
    local msg="$2"
    echo -e "\n[$(date +%H:%M:%S)] $msg"
    logger -t "$LOG_TAG" -p "user.$level" "$msg"
}

# Получаем полный ID контейнера
FULL_ID=$(docker inspect --format '{{.Id}}' "$CONTAINER" 2>/dev/null)
if [ -z "$FULL_ID" ]; then
    echo "Ошибка: контейнер '$CONTAINER' не найден!"
    exit 1
fi

# Находим директорию cgroup v2 контейнера
CGROUP_DIR=$(find /sys/fs/cgroup -name "*${FULL_ID}*" -type d 2>/dev/null | head -n 1)

# Функция чтения и логирования лимитов cgroups контейнера при старте
log_cgroup_limits() {
    if [ -z "$CGROUP_DIR" ]; then
        log_event "warning" "Директория cgroup для $CONTAINER не найдена."
        return
    fi

    # Лимит RAM
    local mem_max_raw=$(cat "$CGROUP_DIR/memory.max" 2>/dev/null || echo "unknown")
    local mem_max_str="$mem_max_raw"
    [[ "$mem_max_raw" =~ ^[0-9]+$ ]] && mem_max_str="$(( mem_max_raw / 1024 / 1024 )) MB"

    # Лимит Swap
    local swap_max_raw=$(cat "$CGROUP_DIR/memory.swap.max" 2>/dev/null || echo "unknown")
    local swap_max_str="$swap_max_raw"
    [[ "$swap_max_raw" =~ ^[0-9]+$ ]] && swap_max_str="$(( swap_max_raw / 1024 / 1024 )) MB"

    # Лимит CPU (формат: quota period, например "350000 100000" -> 3.50 CPU)
    local cpu_max_raw=$(cat "$CGROUP_DIR/cpu.max" 2>/dev/null || echo "unknown")
    local cpu_max_str="$cpu_max_raw"
    if [[ "$cpu_max_raw" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
        cpu_max_str=$(awk -v q="${BASH_REMATCH[1]}" -v p="${BASH_REMATCH[2]}" 'BEGIN {printf "%.2f CPU", q/p}')
    fi

    log_event "info" "Лимиты cgroups для '$CONTAINER': CPU=${cpu_max_str} | Memory=${mem_max_str} | Swap=${swap_max_str}"
}

# Создаем CSV-файл и отдаем права пользователю, вызвавшему sudo
CSV_FILE="telemetry_${CONTAINER}_$(date +%Y-%m-%d_%H-%M-%S).csv"
echo "Timestamp,Status,Pause_Reason,CPU_Load_Pct,IO_Wait_Pct,Temp_C,Host_Free_RAM_MB,Host_Used_ZRAM_MB,PSI_Mem_Some_Pct,PSI_IO_Some_Pct,Container_RAM_MB,Container_Swap_MB" > "$CSV_FILE"
if [ -n "$SUDO_USER" ]; then
    chown "$SUDO_USER":"$SUDO_USER" "$CSV_FILE"
fi

echo "Телеметрия записывается в файл: $CSV_FILE"
echo "Просмотр системного журнала: journalctl -t docker-temp-guard -f"

# Отключаем Turbo Boost на время мониторинга
TURBO_FILE="/sys/devices/system/cpu/intel_pstate/no_turbo"
if [ -f "$TURBO_FILE" ]; then
    echo 1 > "$TURBO_FILE"
    log_event "info" "Intel Turbo Boost отключен на время работы скрипта."
fi

# Пороги срабатывания паузы
HIGH_TEMP=88          # Температура постановки на паузу (°C)
LOW_TEMP=70           # Температура возобновления работы (°C)
MIN_FREE_RAM_MB=1200  # Порог свободной ОЗУ для паузы (МБ)
SAFE_FREE_RAM_MB=2200 # Порог свободной ОЗУ для возобновления (МБ)
MAX_MEM_PSI=25        # Порог "задыхания" памяти/zram (PSI avg10, %)
MAX_IO_PSI=70         # Порог "задыхания" диска (PSI avg10, %)

INTERVAL=2            # Интервал опроса (сек)
PAUSED=0
PAUSE_REASON=""

# Единая функция корректного завершения работы
cleanup() {
    # Возвращаем Turbo Boost в исходное состояние
    if [ -f "$TURBO_FILE" ]; then
        echo 0 > "$TURBO_FILE"
        log_event "info" "Intel Turbo Boost включен обратно."
    fi

    # Если контейнер оставался на паузе и еще существует — снимаем с паузы
    if [ "$PAUSED" -eq 1 ]; then
        log_event "info" "Завершение скрипта: снимаем $CONTAINER с паузы..."
        docker unpause "$CONTAINER" >/dev/null 2>&1
    fi

    log_event "info" "Мониторинг завершен. CSV-лог сохранен: $CSV_FILE"
    exit 0
}
trap cleanup SIGINT SIGTERM

log_cgroup_limits
log_event "info" "Запущен мониторинг '$CONTAINER'. CSV-лог: $CSV_FILE"

while true; do
 # Проверяем состояние контейнера (запущен ли и на паузе ли реально)
    STATE_INFO=$(docker inspect --format '{{.State.Running}} {{.State.Paused}} {{.State.ExitCode}}' "$CONTAINER" 2>/dev/null)
    IS_RUNNING=$(echo "$STATE_INFO" | awk '{print $1}')
    IS_PAUSED=$(echo "$STATE_INFO" | awk '{print $2}')
    EXIT_CODE=$(echo "$STATE_INFO" | awk '{print $3}')

    if [ "$IS_RUNNING" != "true" ]; then
        log_event "info" "Контейнер '$CONTAINER' остановился (ExitCode: ${EXIT_CODE:-unknown})."
        PAUSED=0
        cleanup
    fi

    # Синхронизируем внутренний флаг PAUSED с реальным состоянием Docker
    if [ "$IS_PAUSED" = "true" ] && [ "$PAUSED" -eq 0 ]; then
        PAUSED=1
        PAUSE_REASON="external"
    elif [ "$IS_PAUSED" = "false" ] && [ "$PAUSED" -eq 1 ]; then
        log_event "info" "Контейнер '$CONTAINER' уже снят с паузы. Продолжаем мониторинг..."
        PAUSED=0
        PAUSE_REASON=""
    fi

    NOW_ISO=$(date +"%Y-%m-%d %H:%M:%S")
    NOW_TIME=$(date +"%H:%M:%S")

    # 1. Температура CPU
    TEMP=$(sensors | awk '/Package id 0:/ {gsub(/\+|\..*/, "", $4); print $4}')
    
    # 2. Общая загрузка CPU и iowait (wa)
    CPU_STATS=$(top -bn1 | awk '/Cpu\(s\)/ {printf "%.1f %.1f", 100 - $8, $10}')
    LOAD=$(echo "$CPU_STATS" | awk '{print $1}')
    IOWAIT=$(echo "$CPU_STATS" | awk '{print $2}')

    # 3. Свободная RAM и занятый Swap (zram) хоста в МБ
    MEM_STATS=$(awk '
        /MemAvailable:/ {avail=$2}
        /SwapTotal:/ {stotal=$2}
        /SwapFree:/ {sfree=$2}
        END {printf "%d %d", avail/1024, (stotal-sfree)/1024}
    ' /proc/meminfo)
    FREE_RAM_MB=$(echo "$MEM_STATS" | awk '{print $1}')
    USED_SWAP_MB=$(echo "$MEM_STATS" | awk '{print $2}')

    # 4. Показатели PSI (Memory и IO)
    MEM_PSI=$(awk -F'[= .]' '/^some/ {print $3}' /proc/pressure/memory 2>/dev/null)
    IO_PSI=$(awk -F'[= .]' '/^some/ {print $3}' /proc/pressure/io 2>/dev/null)
    MEM_PSI=${MEM_PSI:-0}
    IO_PSI=${IO_PSI:-0}

    # 5. Потребление RAM и Swap (zram) конкретно этим контейнером
    CONT_RAM_MB=0
    CONT_SWAP_MB=0
    if [ -n "$CGROUP_DIR" ] && [ -f "$CGROUP_DIR/memory.current" ]; then
        CONT_RAM_MB=$(( $(cat "$CGROUP_DIR/memory.current" 2>/dev/null || echo 0) / 1024 / 1024 ))
        if [ -f "$CGROUP_DIR/memory.swap.current" ]; then
            CONT_SWAP_MB=$(( $(cat "$CGROUP_DIR/memory.swap.current" 2>/dev/null || echo 0) / 1024 / 1024 ))
        fi
    fi

    if [ -z "$TEMP" ]; then
        log_event "err" "Ошибка: не удалось прочитать датчик Package id 0"
        sleep "$INTERVAL"
        continue
    fi

    STATUS="ACTIVE"
    [ "$PAUSED" -eq 1 ] && STATUS="PAUSED"

    # Записываем строку в CSV с немедленной сброской буфера
printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
    "$NOW_ISO" "$STATUS" "${PAUSE_REASON:-none}" "$LOAD" "$IOWAIT" "$TEMP" \
    "$FREE_RAM_MB" "$USED_SWAP_MB" "$MEM_PSI" "$IO_PSI" "$CONT_RAM_MB" "$CONT_SWAP_MB" >> "$CSV_FILE"

    DISPLAY_STATUS="$STATUS"
    [ "$PAUSED" -eq 1 ] && DISPLAY_STATUS="PAUSED($PAUSE_REASON)"

    printf "\r[%s] CPU:%5s%% (IOw:%4s%%) | T:%s°C | RAM:%sMB (Cont:%s+%sMB) | PSI(m/io):%s%%/%s%% | %s   " \
        "$NOW_TIME" "$LOAD" "$IOWAIT" "$TEMP" "$FREE_RAM_MB" "$CONT_RAM_MB" "$CONT_SWAP_MB" "$MEM_PSI" "$IO_PSI" "$DISPLAY_STATUS"

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
            log_event "warning" "$ALERT_MSG | CPU:${LOAD}% IOw:${IOWAIT}% HostRAM:${FREE_RAM_MB}MB Cont:${CONT_RAM_MB}MB+${CONT_SWAP_MB}MB(swap). Пауза..."
            if docker pause "$CONTAINER" >/dev/null; then
                PAUSED=1
                PAUSE_REASON="$REASON"
                if [ "$REASON" = "ram" ] || [ "$REASON" = "psi_mem" ]; then
                    sync && echo 1 > /proc/sys/vm/drop_caches
                fi
            else
                log_event "err" "Не удалось поставить контейнер $CONTAINER на паузу!"
            fi
        fi
    else
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

