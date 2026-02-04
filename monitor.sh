#!/bin/bash
TARGET_DISK="${1:-ALL}"; INTERVAL="${2:-10}"; count=0; cached_output=""; script_name="monitor.sh"
EL=$(tput el); ED=$(tput ed); clear
while true; do
    cols=$(tput cols)
    if [ $count -le 0 ]; then
        raw_data=$(
            echo "=== NETWORK (Interface : IP) ==="; ip -4 -br addr show | grep -v "^lo" | awk '{printf "%-10s %s\n", $1, $3}'; echo
            
            # --- CPU修正箇所: Load Avg削除、コア数追加 ---
            echo "=== CPU STATUS (Total) ==="
            CPU_USE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
            CORES=$(nproc)
            echo "Usage: $CPU_USE (Used) | Cores: $CORES"; echo
            # ----------------------------------------

            echo "=== GPU STATUS ==="
            if command -v nvidia-smi &> /dev/null; then
                nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits | \
                awk -F', ' '{printf "#%s %-15s : %5sMiB / %5sMiB (Util: %3s%%)\n", $1, $2, $3, $4, $5}'
            else
                GPU_NAME=$(lspci 2>/dev/null | grep -E "VGA|3D" | cut -d: -f3 | head -1 | sed 's/^[ \t]*//')
                if [ -n "$GPU_NAME" ]; then echo "Detected: $GPU_NAME (nvidia-smi not found)"; else echo "No GPU Detected"; fi
            fi; echo

            if [ "$TARGET_DISK" = "ALL" ]; then echo "=== DISK USAGE (All Physical) ==="; df -hP | grep -vE '^tmpfs|^devtmpfs|^loop|^overlay|^none|^udev'; else echo "=== DISK USAGE ($TARGET_DISK) ==="; df -hP "$TARGET_DISK" 2>/dev/null | head -1; df -hP "$TARGET_DISK" 2>/dev/null | tail -1; fi; echo
            echo "=== POWER ==="; upower -i $(upower -e | grep BAT) 2>/dev/null | grep -E "energy-rate|percentage|state" || echo "No Battery Sensor"; echo
            echo "=== MEMORY & OOM CHECK ==="; free -h; echo
            echo "[OOM Risk Analysis]"; AVL=$(grep MemAvailable /proc/meminfo | awk '{print $2}'); SWP=$(grep SwapFree /proc/meminfo | awk '{print $2}'); PSI=$(grep "some" /proc/pressure/memory 2>/dev/null | awk -F"avg10=" '{print $2}' | awk '{print $1}' || echo "0.00")
            if [ "$AVL" -lt 500000 ]; then echo "🚨 DANGER: Memory Critical!"; elif [ "$SWP" -lt 500000 ] && [ "$SWP" -gt 0 ]; then echo "⚠️ WARNING: Swap filling up!"; else echo "✅ Capacity: Safe"; fi
            if [ -n "$PSI" ]; then echo "Memory Pressure (10s avg): $PSI%"; fi
        )
        cached_output=$(echo "$raw_data" | sed "s/$/${EL}/"); count=$INTERVAL
    fi
    tput cup 0 0
    printf '%*s\n' "$cols" '' | tr ' ' '='; left_info="$(date '+%H:%M:%S') | $(whoami)@$(hostname)"; right_info="Next Update: ${count}s "
    pad_len=$(( cols - ${#left_info} - ${#right_info} )); [ $pad_len -lt 1 ] && pad_len=1
    printf "%s%*s%s${EL}\n" "$left_info" "$pad_len" "" "$right_info"; printf '%*s\n' "$cols" '' | tr ' ' '='; echo "${EL}"; echo "$cached_output"; echo "${EL}"
    printf '%*s\n' "$cols" '' | tr ' ' '='; echo " Usage: ./$script_name [ALL|Path] [SEC] (e.g. ./$script_name ALL 5) | Ctrl+C to Exit${EL}"; printf '%*s' "$cols" '' | tr ' ' '='; tput ed
    count=$((count - 1)); sleep 1
done
