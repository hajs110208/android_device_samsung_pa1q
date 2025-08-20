#!/system/bin/sh

# USB Logger Script для TWRP
# Логирует все USB события при подключении OTG и к ПК

LOG_DIR="/tmp/usb_logs"
LOG_FILE="$LOG_DIR/usb_events.log"
DEBUG_LOG="$LOG_DIR/debug.log"

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
    if [ -f "/sys/bus/platform/devices/*ssusb*/mode" ]; then
        log_message "USB Controller Mode: $(cat /sys/bus/platform/devices/*ssusb*/mode 2>/dev/null)"
    fi
    
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
    
    # Логи ядра по USB
    dmesg | grep -i -e usb -e xhci -e dwc3 -e scsi -e otg | tail -n 50 >> $DEBUG_LOG
    
    # Логи ядра по Type-C
    dmesg | grep -i -e typec -e ccic -e pdic | tail -n 30 >> $DEBUG_LOG
    
    # Логи ядра по питанию
    dmesg | grep -i -e vbus -e power -e charger | tail -n 20 >> $DEBUG_LOG
}

# Функция логирования процессов
log_processes() {
    log_message "=== PROCESSES LOG ==="
    
    # USB-процессы
    ps -A | grep -i -e usb -e adb -e mtp >> $DEBUG_LOG
    
    # Модули ядра
    lsmod | grep -E 'dwc3|xhci|usb' >> $DEBUG_LOG
}

# Функция логирования файловых систем
log_filesystems() {
    log_message "=== FILESYSTEMS LOG ==="
    
    # Смонтированные ФС
    mount | grep -E "(usb|otg|vfat|exfat|ntfs)" >> $DEBUG_LOG
    
    # VOLD статус
    if [ -f "/dev/vold" ]; then
        log_message "VOLD device exists"
    fi
    
    # USB OTG точка монтирования
    if [ -d "/usb-otg" ]; then
        log_message "USB-OTG mount point exists"
        ls -la /usb-otg >> $DEBUG_LOG
    fi
}

# Функция мониторинга в реальном времени
monitor_usb_events() {
    log_message "=== STARTING USB MONITORING ==="
    
    # Мониторим изменения в /sys
    inotifywait -m -r /sys/bus/platform/devices/*ssusb* /sys/class/dual_role_usb/ /sys/class/host_notify/ 2>/dev/null | while read path action file; do
        log_message "SYSFS CHANGE: $action $path$file"
        log_usb_state
        log_kernel_events
    done &
    
    # Мониторим изменения в /dev/block
    inotifywait -m -e create,delete /dev/block 2>/dev/null | while read path action file; do
        if echo "$file" | grep -q "sd"; then
            log_message "BLOCK DEVICE CHANGE: $action $file"
            log_usb_state
            log_filesystems
        fi
    done &
    
    # Мониторим свойства системы
    while true; do
        old_config=$(getprop sys.usb.config)
        old_state=$(getprop sys.usb.state)
        
        sleep 2
        
        new_config=$(getprop sys.usb.config)
        new_state=$(getprop sys.usb.state)
        
        if [ "$old_config" != "$new_config" ] || [ "$old_state" != "$new_state" ]; then
            log_message "USB PROPERTY CHANGE: config=$old_config->$new_config, state=$old_state->$new_state"
            log_usb_state
            log_kernel_events
        fi
    done
}

# Основная функция
main() {
    log_message "=== USB LOGGER STARTED ==="
    log_message "Device: $(getprop ro.product.model)"
    log_message "Android: $(getprop ro.build.version.release)"
    log_message "TWRP: $(getprop ro.twrp.version)"
    
    # Начальное состояние
    log_usb_state
    log_kernel_events
    log_processes
    log_filesystems
    
    # Запускаем мониторинг
    monitor_usb_events
    
    # Ждем сигнала завершения
    trap 'log_message "=== USB LOGGER STOPPED ==="; exit 0' INT TERM
    wait
}

# Запуск скрипта
main "$@"
