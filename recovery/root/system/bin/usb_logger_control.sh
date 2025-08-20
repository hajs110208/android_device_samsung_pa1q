#!/system/bin/sh

# Скрипт управления автоматическим USB логгером

PID_FILE="/tmp/usb_logger.pid"
LOG_DIR="/tmp/usb_logs"

echo "=== USB Logger Control ==="
echo ""

case "$1" in
    "start")
        echo "Starting USB Logger..."
        /system/bin/auto_usb_logger.sh start &
        echo "Logger started in background"
        ;;
    "stop")
        echo "Stopping USB Logger..."
        /system/bin/auto_usb_logger.sh stop
        echo "Logger stopped"
        ;;
    "status")
        echo "USB Logger Status:"
        /system/bin/auto_usb_logger.sh status
        ;;
    "logs")
        echo "Showing USB Logger logs:"
        /system/bin/auto_usb_logger.sh logs
        ;;
    "clear")
        echo "Clearing logs..."
        rm -rf $LOG_DIR/*
        echo "Logs cleared"
        ;;
    "tail")
        echo "Following logs in real-time (Ctrl+C to stop):"
        if command -v tail >/dev/null 2>&1; then
            tail -f $LOG_DIR/auto_usb_events.log
        else
            echo "tail command not available, showing last 20 lines:"
            # Простая альтернатива без tail
            if [ -f "$LOG_DIR/auto_usb_events.log" ]; then
                # Читаем файл и показываем последние строки
                local line_count=0
                while IFS= read -r line; do
                    line_count=$((line_count + 1))
                done < "$LOG_DIR/auto_usb_events.log"
                
                local start_line=$((line_count - 20))
                if [ $start_line -lt 1 ]; then
                    start_line=1
                fi
                
                local current_line=0
                while IFS= read -r line; do
                    current_line=$((current_line + 1))
                    if [ $current_line -ge $start_line ]; then
                        echo "$line"
                    fi
                done < "$LOG_DIR/auto_usb_events.log"
            else
                echo "No log file found"
            fi
        fi
        ;;
    "help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  start   - Start USB logger"
        echo "  stop    - Stop USB logger"
        echo "  status  - Show logger status"
        echo "  logs    - Show all logs"
        echo "  clear   - Clear all logs"
        echo "  tail    - Follow logs in real-time"
        echo "  help    - Show this help"
        echo ""
        echo "Log files location: $LOG_DIR"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        ;;
esac
