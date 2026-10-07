#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Zapret2 Service & UCI Integration Layer
# Interacts natively with 1andrevich/zapret2-openwrt and custom installations
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"

zapret_is_installed() {
    [ -f "${ZAPRET2_INIT}" ] && return 0
    [ -f "/etc/init.d/zapret" ] && return 0
    [ -f "${ZAPRET2_SYNC}" ] && return 0
    [ -f "${ZAPRET2_BIN}" ] && return 0
    [ -f "${UCI_CONFIG}" ] && return 0
    command -v nfqws2 >/dev/null 2>&1 && return 0
    command -v nfqws >/dev/null 2>&1 && return 0
    if command -v opkg >/dev/null 2>&1; then
        opkg list-installed 2>/dev/null | grep -qiE "^zapret2? " && return 0
    fi
    if command -v apk >/dev/null 2>&1; then
        apk info -e zapret2 2>/dev/null && return 0
    fi
    return 1
}

zapret_is_running() {
    pidof nfqws2 >/dev/null 2>&1 && return 0
    pgrep nfqws2 >/dev/null 2>&1 && return 0
    pidof nfqws >/dev/null 2>&1 && return 0
    pgrep nfqws >/dev/null 2>&1 && return 0
    return 1
}

zapret_status() {
    if zapret_is_running; then
        echo "running"
    else
        echo "stopped"
    fi
}

zapret_start() {
    if [ -f "${ZAPRET2_SYNC}" ]; then
        chmod +x "${ZAPRET2_SYNC}" 2>/dev/null
        "${ZAPRET2_SYNC}" >/dev/null 2>&1
    fi
    if [ -f "${ZAPRET2_INIT}" ]; then
        chmod +x "${ZAPRET2_INIT}" 2>/dev/null
        "${ZAPRET2_INIT}" start >/dev/null 2>&1
        sleep 1
    elif [ -f "/etc/init.d/zapret" ]; then
        /etc/init.d/zapret start >/dev/null 2>&1
        sleep 1
    fi
}

zapret_stop() {
    if [ -f "${ZAPRET2_INIT}" ]; then
        "${ZAPRET2_INIT}" stop >/dev/null 2>&1
        sleep 1
    elif [ -f "/etc/init.d/zapret" ]; then
        /etc/init.d/zapret stop >/dev/null 2>&1
        sleep 1
    fi
}

zapret_restart() {
    zapret_repair_config
    if [ -f "${ZAPRET2_SYNC}" ]; then
        chmod +x "${ZAPRET2_SYNC}" 2>/dev/null
        "${ZAPRET2_SYNC}" >/dev/null 2>&1
    fi
    if [ -f "${ZAPRET2_INIT}" ]; then
        chmod +x "${ZAPRET2_INIT}" 2>/dev/null
        "${ZAPRET2_INIT}" restart >/dev/null 2>&1
        sleep 1
    elif [ -f "/etc/init.d/zapret" ]; then
        /etc/init.d/zapret restart >/dev/null 2>&1
        sleep 1
    fi
    zapret_is_running
}

zapret_get_opt() {
    local val=""
    if command -v uci >/dev/null 2>&1; then
        val="$(uci -q get "${UCI_SECTION}.NFQWS2_OPT")"
    fi
    if [ -z "${val}" ] && [ -f "${ZAPRET2_CONFIG}" ]; then
        val="$(grep "^NFQWS2_OPT=" "${ZAPRET2_CONFIG}" 2>/dev/null | cut -d'=' -f2- | tr -d '"')"
    fi
    echo "${val}" | tr -d '"'
}

zapret_backup_config() {
    local backup_file="${Z2M_TMP}/zapret2_opt_backup_$$.txt"
    local current_opt
    current_opt=$(zapret_get_opt)
    echo "${current_opt}" > "${backup_file}"
    echo "${backup_file}"
}

zapret_restore_config() {
    local backup_file="$1"
    if [ -f "${backup_file}" ]; then
        local saved_opt
        saved_opt=$(cat "${backup_file}")
        zapret_set_opt "${saved_opt}"
        rm -f "${backup_file}" 2>/dev/null
    fi
}

# Repair corrupted /opt/zapret2/config caused by unescaped nested double quotes
zapret_repair_config() {
    if [ -f "${ZAPRET2_CONFIG}" ]; then
        if ! sh -n "${ZAPRET2_CONFIG}" 2>/dev/null; then
            local raw_opt
            raw_opt=$(grep "^NFQWS2_OPT=" "${ZAPRET2_CONFIG}" 2>/dev/null | sed 's/^NFQWS2_OPT=//' | tr -d '"')
            sed -i "s|^NFQWS2_OPT=.*|NFQWS2_OPT=\"${raw_opt}\"|" "${ZAPRET2_CONFIG}" 2>/dev/null
        fi
    fi
}

zapret_get_ports_tcp() {
    local val=""
    if command -v uci >/dev/null 2>&1; then
        val="$(uci -q get "${UCI_SECTION}.NFQWS2_PORTS_TCP")"
        [ -z "${val}" ] && val="$(uci -q get zapret.config.NFQWS_PORTS_TCP)"
    fi
    if [ -z "${val}" ] && [ -f "${ZAPRET2_CONFIG}" ]; then
        val="$(grep "^NFQWS2_PORTS_TCP=" "${ZAPRET2_CONFIG}" 2>/dev/null | cut -d'=' -f2- | tr -d '"')"
        [ -z "${val}" ] && val="$(grep "^NFQWS_PORTS_TCP=" "${ZAPRET2_CONFIG}" 2>/dev/null | cut -d'=' -f2- | tr -d '"')"
    fi
    echo "${val:-80,443}"
}

zapret_get_ports_udp() {
    local val=""
    if command -v uci >/dev/null 2>&1; then
        val="$(uci -q get "${UCI_SECTION}.NFQWS2_PORTS_UDP")"
        [ -z "${val}" ] && val="$(uci -q get zapret.config.NFQWS_PORTS_UDP)"
    fi
    if [ -z "${val}" ] && [ -f "${ZAPRET2_CONFIG}" ]; then
        val="$(grep "^NFQWS2_PORTS_UDP=" "${ZAPRET2_CONFIG}" 2>/dev/null | cut -d'=' -f2- | tr -d '"')"
        [ -z "${val}" ] && val="$(grep "^NFQWS_PORTS_UDP=" "${ZAPRET2_CONFIG}" 2>/dev/null | cut -d'=' -f2- | tr -d '"')"
    fi
    echo "${val:-443}"
}

zapret_set_ports() {
    local tcp_ports="$1"
    local udp_ports="$2"

    [ -z "${tcp_ports}" ] && tcp_ports="${DEFAULT_PORTS_TCP}"
    [ -z "${udp_ports}" ] && udp_ports="${DEFAULT_PORTS_UDP}"

    if command -v uci >/dev/null 2>&1; then
        uci set "${UCI_SECTION}.NFQWS2_PORTS_TCP=${tcp_ports}"
        uci set "${UCI_SECTION}.NFQWS2_PORTS_UDP=${udp_ports}"
        if [ -f /etc/config/zapret ]; then
            uci set zapret.config.NFQWS_PORTS_TCP="${tcp_ports}" 2>/dev/null
            uci set zapret.config.NFQWS_PORTS_UDP="${udp_ports}" 2>/dev/null
            uci commit zapret 2>/dev/null
        fi
        uci commit zapret2 2>/dev/null
    fi

    if [ -f "${ZAPRET2_CONFIG}" ]; then
        sed -i "s|^NFQWS2_PORTS_TCP=.*|NFQWS2_PORTS_TCP=\"${tcp_ports}\"|" "${ZAPRET2_CONFIG}" 2>/dev/null
        sed -i "s|^NFQWS2_PORTS_UDP=.*|NFQWS2_PORTS_UDP=\"${udp_ports}\"|" "${ZAPRET2_CONFIG}" 2>/dev/null
        sed -i "s|^NFQWS_PORTS_TCP=.*|NFQWS_PORTS_TCP=\"${tcp_ports}\"|" "${ZAPRET2_CONFIG}" 2>/dev/null
        sed -i "s|^NFQWS_PORTS_UDP=.*|NFQWS_PORTS_UDP=\"${udp_ports}\"|" "${ZAPRET2_CONFIG}" 2>/dev/null
    fi

    zapret_restart
}

zapret_ensure_full_ports() {
    local cur_tcp cur_udp changed=0
    cur_tcp=$(zapret_get_ports_tcp)
    cur_udp=$(zapret_get_ports_udp)

    # If TCP is only standard 80,443, expand it to include Cloudflare/Alt HTTPS
    if [ "${cur_tcp}" = "80,443" ] || [ -z "${cur_tcp}" ]; then
        cur_tcp="${DEFAULT_PORTS_TCP}"
        changed=1
    fi

    # If UDP is only 443 or old partial range, expand it to include Discord voice and media
    if [ "${cur_udp}" = "443" ] || [ -z "${cur_udp}" ] || [ "${cur_udp}" = "443,19294-19344,50000-50100" ]; then
        cur_udp="${DEFAULT_PORTS_UDP}"
        changed=1
    fi

    if [ "${changed}" -eq 1 ]; then
        if command -v uci >/dev/null 2>&1; then
            uci set "${UCI_SECTION}.NFQWS2_PORTS_TCP=${cur_tcp}"
            uci set "${UCI_SECTION}.NFQWS2_PORTS_UDP=${cur_udp}"
            if [ -f /etc/config/zapret ]; then
                uci set zapret.config.NFQWS_PORTS_TCP="${cur_tcp}" 2>/dev/null
                uci set zapret.config.NFQWS_PORTS_UDP="${cur_udp}" 2>/dev/null
                uci commit zapret 2>/dev/null
            fi
            uci commit zapret2 2>/dev/null
        fi
        if [ -f "${ZAPRET2_CONFIG}" ]; then
            sed -i "s|^NFQWS2_PORTS_TCP=.*|NFQWS2_PORTS_TCP=\"${cur_tcp}\"|" "${ZAPRET2_CONFIG}" 2>/dev/null
            sed -i "s|^NFQWS2_PORTS_UDP=.*|NFQWS2_PORTS_UDP=\"${cur_udp}\"|" "${ZAPRET2_CONFIG}" 2>/dev/null
            sed -i "s|^NFQWS_PORTS_TCP=.*|NFQWS_PORTS_TCP=\"${cur_tcp}\"|" "${ZAPRET2_CONFIG}" 2>/dev/null
            sed -i "s|^NFQWS_PORTS_UDP=.*|NFQWS_PORTS_UDP=\"${cur_udp}\"|" "${ZAPRET2_CONFIG}" 2>/dev/null
        fi
    fi
}

# Apply new NFQWS2_OPT to OpenWrt UCI and restart service
zapret_set_opt() {
    local new_opt="$1"
    # Strictly strip all double quotes to prevent syntax corruption in /opt/zapret2/config
    new_opt=$(echo "${new_opt}" | tr -d '"')

    # Automatically ensure full ports are active so Discord and Web traffic are intercepted
    zapret_ensure_full_ports

    if command -v uci >/dev/null 2>&1; then
        uci set "${UCI_SECTION}.NFQWS2_ENABLE=1"
        uci set "${UCI_SECTION}.NFQWS2_OPT=${new_opt}"
        uci commit zapret2 2>/dev/null
    fi

    # Also update /opt/zapret2/config if present
    if [ -f "${ZAPRET2_CONFIG}" ]; then
        sed -i "s|^NFQWS2_OPT=.*|NFQWS2_OPT=\"${new_opt}\"|" "${ZAPRET2_CONFIG}" 2>/dev/null
    fi

    zapret_restart
}

# Synchronize and install bundled fake blobs into /opt/zapret2/files/fake
zapret_sync_fake_blobs() {
    local src_dir="${Z2M_DIR}/fake"
    local dst_dir="${ZAPRET2_FAKE_DIR}"

    mkdir -p "${dst_dir}" 2>/dev/null

    if [ -d "${src_dir}" ]; then
        cp -f "${src_dir}"/*.bin "${dst_dir}/" 2>/dev/null
        chmod 644 "${dst_dir}"/*.bin 2>/dev/null
    fi
}

# Synchronize bundled hostlists into /opt/zapret2/ipset
zapret_sync_hostlists() {
    local src_dir="${Z2M_DIR}/lists"
    local dst_dir="${ZAPRET2_IPSET_DIR}"

    mkdir -p "${dst_dir}" 2>/dev/null

    if [ -d "${src_dir}" ]; then
        cp -f "${src_dir}"/*.txt "${dst_dir}/" 2>/dev/null
        chmod 644 "${dst_dir}"/*.txt 2>/dev/null
    fi
}

# Synchronize bundled custom scripts into /opt/zapret2/init.d/openwrt/custom.d
zapret_sync_custom_scripts() {
    local src_file="${Z2M_DIR}/templates/50-script.sh"
    local dst_dir="${ZAPRET2_DIR}/init.d/openwrt/custom.d"

    mkdir -p "${dst_dir}" 2>/dev/null

    if [ -f "${src_file}" ]; then
        cp -f "${src_file}" "${dst_dir}/50-script.sh" 2>/dev/null
        chmod 755 "${dst_dir}/50-script.sh" 2>/dev/null
    fi
}
