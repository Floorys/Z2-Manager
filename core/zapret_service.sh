#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Zapret2 Service & UCI Integration Layer
# Interacts natively with 1andrevich/zapret2-openwrt
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"

zapret_is_installed() {
    if [ -f "${ZAPRET2_INIT}" ] && [ -f "${ZAPRET2_SYNC}" ]; then
        return 0
    fi
    return 1
}

zapret_is_running() {
    if pgrep nfqws2 >/dev/null 2>&1; then
        return 0
    fi
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
    fi
}

zapret_stop() {
    if [ -f "${ZAPRET2_INIT}" ]; then
        "${ZAPRET2_INIT}" stop >/dev/null 2>&1
        sleep 1
    fi
}

zapret_restart() {
    if [ -f "${ZAPRET2_SYNC}" ]; then
        chmod +x "${ZAPRET2_SYNC}" 2>/dev/null
        "${ZAPRET2_SYNC}" >/dev/null 2>&1
    fi
    if [ -f "${ZAPRET2_INIT}" ]; then
        "${ZAPRET2_INIT}" restart >/dev/null 2>&1
        sleep 2
    fi
}

zapret_get_opt() {
    if command -v uci >/dev/null 2>&1; then
        uci -q get "${UCI_SECTION}.NFQWS2_OPT"
    else
        grep "^NFQWS2_OPT=" "${ZAPRET2_CONFIG}" 2>/dev/null | cut -d'=' -f2- | tr -d '"'
    fi
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

# Apply new NFQWS2_OPT to OpenWrt UCI and restart service
zapret_set_opt() {
    local new_opt="$1"

    if command -v uci >/dev/null 2>&1; then
        uci set "${UCI_SECTION}.NFQWS2_ENABLE=1"
        uci set "${UCI_SECTION}.NFQWS2_OPT=${new_opt}"
        uci commit zapret2
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
