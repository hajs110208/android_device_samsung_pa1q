#!/system/bin/sh

# Автоматический USB Logger для TWRP
# Автоматически запускается и логирует USB события

LOG_DIR="/tmp/usb_logs"
LOG_FILE="$LOG_DIR/auto_usb_events.log"
DEBUG_LOG="$LOG_DIR/auto_debug.log"
PID_FILE="/tmp/usb_logger.pid"

# Создаем директорию для логов
mkdir -p $LOG_DIR
chmod 755 $LOG_DIR

# Функция логирования
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $DEBUG_LOG
}

# Функция логирования USB состояния
log_usb_state() {
    log_message "=== USB STATE LOG ==="
    
    # Режим USB-контроллера
    for mode_file in /sys/bus/platform/devices/*ssusb*/mode; do
        if [ -f "$mode_file" ]; then
            log_message "USB Controller Mode ($mode_file): $(cat $mode_file 2>/dev/null)"
        fi
    done
    
    # Type-C роли
    if [ -d "/sys/class/dual_role_usb/otg_default" ]; then
        log_message "Type-C Mode: $(cat /sys/class/dual_role_usb/otg_default/mode 2>/dev/null)"
        log_message "Type-C Data Role: $(cat /sys/class/dual_role_usb/otg_default/data_role 2>/dev/null)"
        log_message "Type-C Power Role: $(cat /sys/class/dual_role_usb/otg_default/power_role 2>/dev/null)"
    fi
    
    # USB уведомления
    if [ -d "/sys/class/host_notify/usb_otg" ]; then
        log_message "Host Notify State: $(cat /sys/class/host_notify/usb_otg/state 2>/dev/null)"
    fi
    
    # Блочные устройства
    log_message "Block Devices: $(ls /dev/block | grep sd 2>/dev/null)"
    
    # USB шины
    log_message "USB Buses: $(ls -d /sys/devices/platform/soc/*ssusb* 2>/dev/null)"
    log_message "xHCI Controllers: $(ls -d /sys/devices/platform/soc/*ssusb*/*dwc3/xhci-hcd* 2>/dev/null)"
    
    # Свойства системы
    log_message "sys.usb.config: $(getprop sys.usb.config)"
    log_message "sys.usb.state: $(getprop sys.usb.state)"
    log_message "sys.usb.controller: $(getprop sys.usb.controller)"
}

# Функция логирования ядра
log_kernel_events() {
    log_message "=== KERNEL EVENTS LOG ==="
    
            # Логи ядра по USB (с проверкой доступности dmesg)
        if command -v dmesg >/dev/null 2>&1; then
            # Логи ядра по USB (без tail для совместимости)
            dmesg | grep -i -e usb -e xhci -e dwc3 -e scsi -e otg 2>/dev/null >> $DEBUG_LOG 2>/dev/null || true
            
            # Логи ядра по Type-C
            dmesg | grep -i -e typec -e ccic -e pdic 2>/dev/null >> $DEBUG_LOG 2>/dev/null || true
            
            # Логи ядра по питанию
            dmesg | grep -i -e vbus -e power -e charger 2>/dev/null >> $DEBUG_LOG 2>/dev/null || true
        else
            log_message "dmesg not available"
        fi
}

# Функция логирования файловых систем
log_filesystems() {
    log_message "=== FILESYSTEMS LOG ==="
    
    # Смонтированные ФС
    mount | grep -E "(usb|otg|vfat|exfat|ntfs)" >> $DEBUG_LOG 2>/dev/null || true
    
    # VOLD статус
    if [ -f "/dev/vold" ]; then
        log_message "VOLD device exists"
    fi
    
    # USB OTG точка монтирования
    if [ -d "/usb-otg" ]; then
        log_message "USB-OTG mount point exists"
        ls -la /usb-otg >> $DEBUG_LOG 2>/dev/null || true
    fi
}

# Функция детекции событий
detect_usb_events() {
    local event_type="$1"
    
    case "$event_type" in
        "pc_connect")
            log_message "=== PC CONNECTED ==="
            log_usb_state
            log_kernel_events
            log_filesystems
            ;;
        "pc_disconnect")
            log_message "=== PC DISCONNECTED ==="
            log_usb_state
            log_kernel_events
            log_filesystems
            ;;
        "otg_connect")
            log_message "=== OTG DEVICE CONNECTED ==="
            log_usb_state
            log_kernel_events
            log_filesystems
            ;;
        "otg_disconnect")
            log_message "=== OTG DEVICE DISCONNECTED ==="
            log_usb_state
            log_kernel_events
            log_filesystems
            ;;
        "mode_change")
            log_message "=== USB MODE CHANGED ==="
            log_usb_state
            log_kernel_events
            ;;
        "block_change")
            log_message "=== BLOCK DEVICES CHANGED ==="
            log_usb_state
            log_filesystems
            ;;
    esac
}

# Основной цикл мониторинга
main_monitor() {
    log_message "=== AUTO USB LOGGER STARTED ==="
    log_message "Device: $(getprop ro.product.model)"
    log_message "Android: $(getprop ro.build.version.release)"
    log_message "TWRP: $(getprop ro.twrp.version)"
    
    # Инициализируем переменные
    local previous_config=""
    local previous_state=""
    local previous_blocks=""
    local pc_connected=false
    local otg_connected=false
    
    # Начальное состояние
    previous_config=$(getprop sys.usb.config)
    previous_state=$(getprop sys.usb.state)
    previous_blocks=$(ls /dev/block | grep sd 2>/dev/null | sort)
    
    log_message "Initial USB State:"
    log_usb_state
    log_kernel_events
    log_filesystems
    
    # Основной цикл мониторинга
    while true; do
        sleep 1
        
        # Проверяем изменения USB свойств
        local current_config=$(getprop sys.usb.config)
        local current_state=$(getprop sys.usb.state)
        
        if [ "$current_config" != "$previous_config" ] || [ "$current_state" != "$previous_state" ]; then
            log_message "USB PROPERTY CHANGE: config=$previous_config->$current_config, state=$previous_state->$current_state"
            
            # Детектируем тип события
            if [ "$current_config" = "none" ] && [ "$pc_connected" = true ]; then
                detect_usb_events "pc_disconnect"
                pc_connected=false
            elif [ "$current_config" != "none" ] && [ "$pc_connected" = false ]; then
                detect_usb_events "pc_connect"
                pc_connected=true
            fi
            
            detect_usb_events "mode_change"
            
            previous_config="$current_config"
            previous_state="$current_state"
        fi
        
        # Проверяем изменения в блочных устройствах
        local current_blocks=$(ls /dev/block | grep sd 2>/dev/null | sort)
        if [ "$current_blocks" != "$previous_blocks" ]; then
            log_message "BLOCK DEVICE CHANGE: $previous_blocks -> $current_blocks"
            
            # Детектируем OTG события (без использования comm)
            local new_devices=""
            local removed_devices=""
            
            # Проверяем новые устройства
            for device in $current_blocks; do
                if ! echo "$previous_blocks" | grep -q "$device"; then
                    new_devices="$new_devices $device"
                fi
            done
            
            # Проверяем удаленные устройства
            for device in $previous_blocks; do
                if ! echo "$current_blocks" | grep -q "$device"; then
                    removed_devices="$removed_devices $device"
                fi
            done
            
            if [ -n "$new_devices" ]; then
                log_message "New devices detected: $new_devices"
                detect_usb_events "otg_connect"
                otg_connected=true
            fi
            
            if [ -n "$removed_devices" ]; then
                log_message "Devices removed: $removed_devices"
                detect_usb_events "otg_disconnect"
                otg_connected=false
            fi
            
            detect_usb_events "block_change"
            previous_blocks="$current_blocks"
        fi
        
        # Проверяем изменения в Type-C ролях
        if [ -d "/sys/class/dual_role_usb/otg_default" ]; then
            local current_mode=$(cat /sys/class/dual_role_usb/otg_default/mode 2>/dev/null)
            local current_data_role=$(cat /sys/class/dual_role_usb/otg_default/data_role 2>/dev/null)
            local current_power_role=$(cat /sys/class/dual_role_usb/otg_default/power_role 2>/dev/null)
            
            if [ "$current_mode" = "dfp" ] && [ "$current_data_role" = "host" ] && [ "$otg_connected" = false ]; then
                log_message "Type-C switched to HOST mode - OTG device should be detected"
            fi
        fi
    done
}

# Функция запуска
start_logger() {
    if [ -f "$PID_FILE" ]; then
        local old_pid=$(cat $PID_FILE)
        if kill -0 $old_pid 2>/dev/null; then
            log_message "Logger already running with PID $old_pid"
            return
        else
            rm -f $PID_FILE
        fi
    fi
    
    # Запускаем основной мониторинг в фоне
    main_monitor &
    local logger_pid=$!
    
    # Сохраняем PID
    echo $logger_pid > $PID_FILE
    log_message "Auto USB Logger started with PID $logger_pid"
    
    # Ждем завершения
    wait $logger_pid
    rm -f $PID_FILE
}

# Функция остановки
stop_logger() {
    if [ -f "$PID_FILE" ]; then
        local logger_pid=$(cat $PID_FILE)
        if kill -0 $logger_pid 2>/dev/null; then
            kill $logger_pid
            log_message "Auto USB Logger stopped (PID $logger_pid)"
        fi
        rm -f $PID_FILE
    else
        log_message "No logger running"
    fi
}

# Обработка сигналов
trap 'log_message "=== AUTO USB LOGGER STOPPED ==="; stop_logger; exit 0' INT TERM

# Проверяем аргументы командной строки
case "$1" in
    "start")
        start_logger
        ;;
    "stop")
        stop_logger
        ;;
    "status")
        if [ -f "$PID_FILE" ]; then
            local logger_pid=$(cat $PID_FILE)
            if kill -0 $logger_pid 2>/dev/null; then
                echo "Logger running with PID $logger_pid"
            else
                echo "Logger not running (stale PID file)"
                rm -f $PID_FILE
            fi
        else
            echo "Logger not running"
        fi
        ;;
    "logs")
        echo "=== USB EVENTS LOG ==="
        cat $LOG_FILE 2>/dev/null || echo "No logs found"
        echo ""
        echo "=== DEBUG LOG ==="
        cat $DEBUG_LOG 2>/dev/null || echo "No debug logs found"
        ;;
    *)
        # По умолчанию запускаем
        start_logger
        ;;
esac
