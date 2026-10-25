#!/bin/sh
# shellcheck disable=SC3043
# ==============================================================================
# Zapret2-Manager: Zapret2 Service & UCI Integration Layer
# Interacts natively with 1andrevich/zapret2-openwrt and custom installations
# ==============================================================================

[ -z "${Z2M_DIR:-}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
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

# Detect installed Zapret2 package / binary version
zapret_get_installed_version() {
    local ver=""
    if command -v opkg >/dev/null 2>&1; then
        ver=$(opkg status zapret2 2>/dev/null | grep -i '^Version:' | awk '{print $2}')
        [ -z "${ver}" ] && ver=$(opkg list-installed zapret2 2>/dev/null | awk '{print $3}')
    fi
    if [ -z "${ver}" ] && command -v apk >/dev/null 2>&1; then
        ver=$(apk info -v zapret2 2>/dev/null | sed 's/^zapret2-//; s/-r[0-9]*$//')
        [ -z "${ver}" ] && ver=$(apk list -I zapret2 2>/dev/null | awk '{print $1}' | sed 's/^zapret2-//; s/-r[0-9]*$//')
    fi
    if [ -z "${ver}" ]; then
        local bin=""
        if [ -x "/opt/zapret2/nfq2/nfqws2" ]; then
            bin="/opt/zapret2/nfq2/nfqws2"
        elif [ -x "/opt/zapret2/nfqws2" ]; then
            bin="/opt/zapret2/nfqws2"
        elif command -v nfqws2 >/dev/null 2>&1; then
            bin="$(command -v nfqws2)"
        fi
        if [ -n "${bin}" ]; then
            ver=$("${bin}" --version 2>/dev/null | grep -i 'github version' | awk '{print $3}' | tr -d 'v')
        fi
    fi
    if [ -z "${ver}" ] && [ -f "${ZAPRET2_DIR}/version" ]; then
        ver=$(tr -d '\r\n ' < "${ZAPRET2_DIR}/version" 2>/dev/null)
    fi
    echo "${ver}" | sed 's/^v//'
}

zapret_start() {
    if [ -f "${ZAPRET2_SYNC}" ]; then
        chmod +x "${ZAPRET2_SYNC}" 2>/dev/null
        "${ZAPRET2_SYNC}" >/dev/null 2>&1
    fi

    local init_script=""
    if [ -x "${ZAPRET2_INIT}" ]; then
        init_script="${ZAPRET2_INIT}"
    elif [ -x "/etc/init.d/zapret" ]; then
        init_script="/etc/init.d/zapret"
    fi

    if [ -n "${init_script}" ]; then
        "${init_script}" start >/dev/null 2>&1
    fi

    # Poll for running status up to 5 seconds
    local i=0
    while [ "$i" -lt 5 ]; do
        if zapret_is_running; then
            return 0
        fi
        sleep 1
        i=$(( i + 1 ))
    done
    return 1
}

zapret_stop() {
    local init_script=""
    if [ -x "${ZAPRET2_INIT}" ]; then
        init_script="${ZAPRET2_INIT}"
    elif [ -x "/etc/init.d/zapret" ]; then
        init_script="/etc/init.d/zapret"
    fi

    if [ -n "${init_script}" ]; then
        "${init_script}" stop >/dev/null 2>&1
    fi

    # Poll for stopped status up to 5 seconds (success = process is gone)
    local i=0
    while [ "$i" -lt 5 ]; do
        if ! zapret_is_running; then
            return 0
        fi
        sleep 1
        i=$(( i + 1 ))
    done
    return 1
}

zapret_restart() {
    zapret_repair_config
    if [ -f "${ZAPRET2_SYNC}" ]; then
        chmod +x "${ZAPRET2_SYNC}" 2>/dev/null
        "${ZAPRET2_SYNC}" >/dev/null 2>&1
    fi

    local init_script=""
    if [ -x "${ZAPRET2_INIT}" ]; then
        init_script="${ZAPRET2_INIT}"
    elif [ -x "/etc/init.d/zapret" ]; then
        init_script="/etc/init.d/zapret"
    fi

    if [ -n "${init_script}" ]; then
        "${init_script}" restart >/dev/null 2>&1
    fi

    # Poll for running status up to 5 seconds
    local i=0
    while [ "$i" -lt 5 ]; do
        if zapret_is_running; then
            return 0
        fi
        sleep 1
        i=$(( i + 1 ))
    done
    return 1
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

# Write NFQWS2_OPT safely to /opt/zapret2/config
# - Handles multiline values by discarding continuation lines up to the closing quote
# - Passes replacement value via ENVIRON to prevent awk -v backslash unescaping
zapret_write_opt_to_config() {
    local opt_val="$1"
    [ -f "${ZAPRET2_CONFIG}" ] || return 0

    opt_val=$(echo "${opt_val}" | tr -d '"')
    local tmp_cfg
    tmp_cfg=$(mktemp "${Z2M_TMP}/cfg.XXXXXX") || return 1

    Z2M_NEW_OPT="${opt_val}" awk '
        BEGIN {
            found = 0
            in_q = 0
            q_char = ""
        }
        {
            if (in_q) {
                if (index($0, q_char) > 0) {
                    in_q = 0
                }
                next
            }
            if ($0 ~ /^[[:space:]]*(export[[:space:]]+)?NFQWS2_OPT=/) {
                found = 1
                prefix = ""
                if ($0 ~ /^[[:space:]]*export/) {
                    prefix = "export "
                }
                print prefix "NFQWS2_OPT=\"" ENVIRON["Z2M_NEW_OPT"] "\""
                rest = substr($0, index($0, "=") + 1)
                sub(/^[[:space:]]+/, "", rest)
                first_char = substr(rest, 1, 1)
                if (first_char == "\"" || first_char == "\x27") {
                    q_char = first_char
                    val = substr(rest, 2)
                    if (index(val, q_char) == 0) {
                        in_q = 1
                    }
                }
                next
            }
            print
        }
        END {
            if (!found) {
                print "NFQWS2_OPT=\"" ENVIRON["Z2M_NEW_OPT"] "\""
            }
        }
    ' "${ZAPRET2_CONFIG}" > "${tmp_cfg}" && cat "${tmp_cfg}" > "${ZAPRET2_CONFIG}"
    rm -f "${tmp_cfg}" 2>/dev/null
}

# Create a full UCI backup or config file backup
zapret_backup_config() {
    local backup_file
    backup_file=$(mktemp "${Z2M_TMP}/z2m_uci_backup.XXXXXX")
    if command -v uci >/dev/null 2>&1 && [ -f "${UCI_CONFIG}" ]; then
        uci export zapret2 > "${backup_file}" 2>/dev/null
    elif [ -f "${ZAPRET2_CONFIG}" ]; then
        cp -f "${ZAPRET2_CONFIG}" "${backup_file}" 2>/dev/null
    else
        zapret_get_opt > "${backup_file}"
    fi
    echo "${backup_file}"
}

# Restore full UCI configuration or config file from backup
zapret_restore_config() {
    local backup_file="$1"
    if [ -f "${backup_file}" ] && [ -s "${backup_file}" ]; then
        if command -v uci >/dev/null 2>&1 && grep -q "package zapret2" "${backup_file}" 2>/dev/null; then
            uci import zapret2 < "${backup_file}" 2>/dev/null
            uci commit zapret2 2>/dev/null
            if [ -f "${ZAPRET2_SYNC}" ]; then
                "${ZAPRET2_SYNC}" >/dev/null 2>&1
            fi
            # Write restored NFQWS2_OPT back to /opt/zapret2/config
            local restored_opt
            restored_opt="$(zapret_get_opt)"
            zapret_write_opt_to_config "${restored_opt}"
            zapret_restart
        elif [ -f "${ZAPRET2_CONFIG}" ] && grep -q "^NFQWS2_OPT=" "${backup_file}" 2>/dev/null; then
            cat "${backup_file}" > "${ZAPRET2_CONFIG}"
            zapret_restart
        else
            local saved_opt
            saved_opt=$(cat "${backup_file}")
            zapret_set_opt "${saved_opt}"
        fi
        rm -f "${backup_file}" 2>/dev/null
    fi
}

# Repair corrupted /opt/zapret2/config caused by unescaped nested double quotes
zapret_repair_config() {
    if [ -f "${ZAPRET2_CONFIG}" ]; then
        if ! sh -n "${ZAPRET2_CONFIG}" 2>/dev/null; then
            local raw_opt
            raw_opt=$(zapret_get_opt)
            [ -z "${raw_opt}" ] && raw_opt=$(grep "^NFQWS2_OPT=" "${ZAPRET2_CONFIG}" 2>/dev/null | sed 's/^NFQWS2_OPT=//' | tr -d '"')
            zapret_write_opt_to_config "${raw_opt}"
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
        local tmp_ports
        tmp_ports=$(mktemp "${Z2M_TMP}/ports.XXXXXX")
        Z2M_TCP="${tcp_ports}" Z2M_UDP="${udp_ports}" awk '
            BEGIN {
                tcp = "NFQWS2_PORTS_TCP=\"" ENVIRON["Z2M_TCP"] "\""
                udp = "NFQWS2_PORTS_UDP=\"" ENVIRON["Z2M_UDP"] "\""
                old_tcp = "NFQWS_PORTS_TCP=\"" ENVIRON["Z2M_TCP"] "\""
                old_udp = "NFQWS_PORTS_UDP=\"" ENVIRON["Z2M_UDP"] "\""
            }
            /^NFQWS2_PORTS_TCP=/ { print tcp; next }
            /^NFQWS2_PORTS_UDP=/ { print udp; next }
            /^NFQWS_PORTS_TCP=/ { print old_tcp; next }
            /^NFQWS_PORTS_UDP=/ { print old_udp; next }
            { print }
        ' "${ZAPRET2_CONFIG}" > "${tmp_ports}" && cat "${tmp_ports}" > "${ZAPRET2_CONFIG}"
        rm -f "${tmp_ports}" 2>/dev/null
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
            local tmp_ports
            tmp_ports=$(mktemp "${Z2M_TMP}/ports.XXXXXX")
            Z2M_TCP="${cur_tcp}" Z2M_UDP="${cur_udp}" awk '
                BEGIN {
                    tcp = "NFQWS2_PORTS_TCP=\"" ENVIRON["Z2M_TCP"] "\""
                    udp = "NFQWS2_PORTS_UDP=\"" ENVIRON["Z2M_UDP"] "\""
                    old_tcp = "NFQWS_PORTS_TCP=\"" ENVIRON["Z2M_TCP"] "\""
                    old_udp = "NFQWS_PORTS_UDP=\"" ENVIRON["Z2M_UDP"] "\""
                }
                /^NFQWS2_PORTS_TCP=/ { print tcp; next }
                /^NFQWS2_PORTS_UDP=/ { print udp; next }
                /^NFQWS_PORTS_TCP=/ { print old_tcp; next }
                /^NFQWS_PORTS_UDP=/ { print old_udp; next }
                { print }
            ' "${ZAPRET2_CONFIG}" > "${tmp_ports}" && cat "${tmp_ports}" > "${ZAPRET2_CONFIG}"
            rm -f "${tmp_ports}" 2>/dev/null
        fi
    fi
}

# Apply new NFQWS2_OPT to OpenWrt UCI and restart service
# Safely writes without sed corruption (&, quotes, slashes) and pauses for stabilization
zapret_set_opt() {
    local new_opt="$1"
    # Strictly strip surrounding double quotes to prevent syntax corruption
    new_opt=$(echo "${new_opt}" | tr -d '"')

    # Automatically ensure full ports are active so Discord and Web traffic are intercepted
    zapret_ensure_full_ports

    if command -v uci >/dev/null 2>&1; then
        uci set "${UCI_SECTION}.NFQWS2_ENABLE=1"
        uci set "${UCI_SECTION}.NFQWS2_OPT=${new_opt}"
        uci commit zapret2 2>/dev/null
    fi

    # Also update /opt/zapret2/config safely using zapret_write_opt_to_config
    zapret_write_opt_to_config "${new_opt}"

    # Restart service and wait for nfqws2 to stabilize (2 seconds)
    zapret_restart
    sleep 2
}

# Synchronize and install bundled fake blobs into /opt/zapret2/files/fake
zapret_sync_fake_blobs() {
    local src_dir="${Z2M_DIR}/fake"
    local dst_dir="${ZAPRET2_FAKE_DIR}"

    mkdir -p "${dst_dir}" 2>/dev/null

    if [ -d "${src_dir}" ]; then
        for f in "${src_dir}"/*.bin; do
            [ -f "${f}" ] || continue
            cp -f "${f}" "${dst_dir}/" 2>/dev/null
        done
        chmod 644 "${dst_dir}"/*.bin 2>/dev/null
    fi
}

# Synchronize bundled hostlists into /opt/zapret2/ipset
zapret_sync_hostlists() {
    local src_dir="${Z2M_DIR}/lists"
    local dst_dir="${ZAPRET2_IPSET_DIR}"

    mkdir -p "${dst_dir}" 2>/dev/null

    if [ -d "${src_dir}" ]; then
        for f in "${src_dir}"/*.txt; do
            [ -f "${f}" ] || continue
            cp -f "${f}" "${dst_dir}/" 2>/dev/null
        done
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
