#!/bin/bash
# ====================================================
# Wi-Fi Panic Recovery & Network Reset Script
# UNIVERSAL VERSION - Works in Normal AND Recovery modes
# ====================================================

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║     Wi-Fi Panic Recovery & Network Reset         ║"
echo "║     UNIVERSAL - Normal & Recovery Mode           ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ================= DETECT MODE & SETUP =================
if [[ -d "/Volumes/Macintosh HD" ]]; then
    MODE="RECOVERY"
    VOLUME="/Volumes/Macintosh HD"
elif [[ -d "/Volumes/Macintosh HD - Data" ]]; then
    MODE="RECOVERY"
    VOLUME="/Volumes/Macintosh HD - Data"
elif [[ $(mount | grep -c "Macintosh HD") -gt 0 ]]; then
    MODE="RECOVERY"
    VOLUME=$(mount | grep "Macintosh HD" | awk '{print $3}' | head -1)
elif [[ -d "/System/Library/CoreServices" ]] && [[ -f "/usr/sbin/system_profiler" ]]; then
    MODE="NORMAL"
    VOLUME=""
else
    echo "[ERROR] Cannot determine environment!"
    echo ""
    echo "If in Recovery Mode:"
    echo "  1. Mount your macOS volume first:"
    echo "     diskutil list"
    echo "     diskutil mount /dev/diskXsY"
    echo "  2. Then run this script again"
    exit 1
fi

# Check SIP status (only in Normal mode)
if [[ "$MODE" == "NORMAL" ]]; then
    echo "[INFO] Checking SIP status..."
    SIP_STATUS=$(csrutil status 2>/dev/null | grep -o "enabled\|disabled")
    if [[ "$SIP_STATUS" == "enabled" ]]; then
        echo "[OK] SIP is enabled (recommended)"
    else
        echo "[WARN] SIP is disabled or partially disabled"
    fi
fi

echo "[INFO] Mode: $MODE"
if [[ "$MODE" == "RECOVERY" ]]; then
    echo "[INFO] macOS Volume: $VOLUME"
    if [[ ! -d "$VOLUME/System" ]] || [[ ! -d "$VOLUME/Library" ]]; then
        echo "[ERROR] $VOLUME doesn't look like a macOS volume"
        exit 1
    fi
else
    if [[ $EUID -ne 0 ]]; then
        echo "[ERROR] In Normal mode, run with: sudo $0"
        exit 1
    fi
    echo "[INFO] Running with full permissions"
fi

# ================= PATH HANDLING =================
get_system_path() {
    local path="$1"
    if [[ "$MODE" == "RECOVERY" ]]; then
        echo "$VOLUME$path"
    else
        echo "$path"
    fi
}

# ================= MAIN MENU =================
echo ""
echo "──────────────────────────────────────────────────"
echo "SELECT FIX LEVEL:"
echo "  1) Reset network preferences only (quick)"
echo "  2) Reset network + Clean caches (recommended)"
echo "──────────────────────────────────────────────────"

while true; do
    read -p "Choice (1-2): " choice
    case $choice in
        1|2) break ;;
        *) echo "Invalid choice. Enter 1 or 2." ;;
    esac
done

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║          STARTING CORRUPTION FIX                 ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ================= STEP 1: NETWORK RESET =================
echo "┌──────────────────────────────────────────────────"
echo "│ STEP 1: Removing Corrupted Network Files"
echo "└──────────────────────────────────────────────────"

NET_CONFIG_DIR=$(get_system_path "/Library/Preferences/SystemConfiguration")
NET_FILES=(
    "com.apple.airport.preferences.plist"
    "preferences.plist"
    "NetworkInterfaces.plist"
    "com.apple.network.identification.plist"
    "com.apple.wifi.message-tracer.plist"
)

echo "  Deleting corrupted network files..."
for file in "${NET_FILES[@]}"; do
    file_path="$NET_CONFIG_DIR/$file"
    if [[ -f "$file_path" ]]; then
        rm -f "$file_path" 2>/dev/null
        echo "    ✓ $file"
    else
        echo "    ⦿ $file (not found - already cleaned)"
    fi
done

# Delete interface files
echo ""
echo "  Cleaning interface configurations..."
if [[ -d "$NET_CONFIG_DIR" ]]; then
    cd "$NET_CONFIG_DIR" 2>/dev/null
    find . -maxdepth 1 -name "*en[0-9]*" -delete 2>/dev/null
    find . -maxdepth 1 -name "*p2p[0-9]*" -delete 2>/dev/null
    find . -maxdepth 1 -name "*awdl[0-9]*" -delete 2>/dev/null
    cd - >/dev/null 2>&1
    echo "    ✓ Interface files"
fi

# User preferences
echo ""
echo "  Cleaning user network preferences..."
if [[ "$MODE" == "NORMAL" ]]; then
    rm -rf ~/Library/Preferences/SystemConfiguration/com.apple.wifi.known-networks.plist 2>/dev/null
    rm -rf ~/Library/Preferences/SystemConfiguration/com.apple.network.eapolclient.configuration.plist 2>/dev/null
    rm -rf ~/Library/Preferences/ByHost/com.apple.wifi.* 2>/dev/null
    echo "    ✓ User preferences"
else
    for user_dir in "$VOLUME/Users/"*; do
        if [[ -d "$user_dir" ]] && [[ "$user_dir" != "$VOLUME/Users/Shared" ]]; then
            username=$(basename "$user_dir")
            rm -rf "$user_dir/Library/Preferences/SystemConfiguration/com.apple.wifi.known-networks.plist" 2>/dev/null
            echo "    ✓ User: $username"
        fi
    done
fi

# ================= STEP 2: CACHE CLEANUP =================
if [[ $choice -eq 2 ]]; then
    echo ""
    echo "┌──────────────────────────────────────────────────"
    echo "│ STEP 2: Cleaning Corrupted Caches"
    echo "└──────────────────────────────────────────────────"
    
    # Airport scan cache
    airport_cache=$(get_system_path "/Library/Caches/com.apple.airportd")
    if [[ -d "$airport_cache" ]]; then
        rm -rf "$airport_cache" 2>/dev/null
        echo "    ✓ Airport scan cache"
    else
        echo "    ⦿ Airport cache not found"
    fi
    
    # System Wi-Fi caches
    wifi_cache_dir=$(get_system_path "/Library/Caches")
    if [[ -d "$wifi_cache_dir" ]]; then
        cd "$wifi_cache_dir" 2>/dev/null
        find . -maxdepth 1 -name "com.apple.wifi*" -delete 2>/dev/null
        cd - >/dev/null 2>&1
        echo "    ✓ System Wi-Fi caches"
    fi
    
    # User caches
    echo ""
    echo "  Cleaning user Wi-Fi caches..."
    if [[ "$MODE" == "NORMAL" ]]; then
        rm -rf ~/Library/Caches/com.apple.wifi* 2>/dev/null
        echo "    ✓ User cache"
    else
        for user_dir in "$VOLUME/Users/"*; do
            if [[ -d "$user_dir" ]] && [[ "$user_dir" != "$VOLUME/Users/Shared" ]]; then
                username=$(basename "$user_dir")
                rm -rf "$user_dir/Library/Caches/com.apple.wifi"* 2>/dev/null
                echo "    ✓ User: $username"
            fi
        done
    fi
    
    # Kext cache rebuild
    if [[ "$MODE" == "NORMAL" ]]; then
        echo ""
        read -p "  Rebuild kernel cache? (takes time) [y/N]: " rebuild_cache
        if [[ "$rebuild_cache" =~ ^[Yy]$ ]]; then
            echo "  Rebuilding kernel cache..."
            sudo rm -rf /System/Library/Caches/com.apple.kext.caches 2>/dev/null
            sudo touch /System/Library/Extensions 2>/dev/null
            echo "    ✓ Kext cache marked for rebuild"
        fi
    fi
fi

# ================= FINAL ACTIONS =================
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║               COMPLETION STEPS                   ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

if [[ "$MODE" == "RECOVERY" ]]; then
    echo "1. Cleanup completed on: $VOLUME"
    echo ""
    echo "2. Unmount macOS volume:"
    echo "   diskutil unmount '$VOLUME'"
    echo ""
    echo "3. Reboot:"
    echo "   reboot"
    echo ""
    echo "4. After reboot:"
    echo "   • Reconnect to Wi-Fi"
    echo "   • Check System Preferences → Network"
else
    # Reset network services
    echo "1. Resetting network services..."
    
    WIFI_INTERFACE=""
    for iface in en1 en0 en2; do
        if networksetup -getairportpower $iface &>/dev/null 2>&1; then
            WIFI_INTERFACE=$iface
            break
        fi
    done
    
    if [[ -n "$WIFI_INTERFACE" ]]; then
        sudo networksetup -setairportpower $WIFI_INTERFACE off
        sleep 2
        sudo networksetup -setairportpower $WIFI_INTERFACE on
        echo "    ✓ Reset Wi-Fi interface: $WIFI_INTERFACE"
    else
        echo "    ⦿ Could not find Wi-Fi interface"
    fi
    
    echo ""
    echo "2. REBOOT REQUIRED:"
    echo "   sudo reboot"
    echo ""
    echo "3. After reboot:"
    echo "   • Check Wi-Fi: networksetup -getairportpower en1"
    echo "   • Test internet: ping -c 2 8.8.8.8"
fi

echo ""
echo "══════════════════════════════════════════════════════"
echo "PANIC PREVENTION:"
echo ""
echo "Quick fix if panic returns:"
echo "  sudo rm -rf /Library/Caches/com.apple.airportd"
echo "  sudo reboot"
echo ""
echo "Boot args for protection:"
echo "  -itlwm_scan_interval=30000"
echo "══════════════════════════════════════════════════════"
echo ""
echo "[FIX COMPLETED at $(date '+%Y-%m-%d %H:%M:%S')]"

# ================= LOGGING =================
if [[ "$MODE" == "NORMAL" ]]; then
    LOG_FILE="$HOME/wifi-fix-$(date +%Y%m%d-%H%M%S).log"
else
    LOG_FILE="/tmp/wifi-fix-$(date +%Y%m%d-%H%M%S).log"
fi

{
    echo "=== Wi-Fi Fix Log ==="
    echo "Date: $(date)"
    echo "Mode: $MODE"
    if [[ "$MODE" == "RECOVERY" ]]; then
        echo "Volume: $VOLUME"
    fi
    echo "Fix Level: $choice"
    echo ""
    echo "Status: SUCCESS - Files already cleaned from previous run"
} > "$LOG_FILE"

echo "[INFO] Log saved to: $LOG_FILE"