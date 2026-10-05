#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Network Connectivity & DPI Probe Engine
# Adapted from Asterlike/zapret2UI NetProbe.cs
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"

# Check if curl is available
probe_check_deps() {
    if command -v curl >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# TLS 1.2 Handshake probe
# Returns 0 (OK) or 1 (FAIL)
probe_tls12() {
    local host="$1"
    local port="${2:-443}"
    local timeout=2

    if command -v curl >/dev/null 2>&1; then
        curl -s -k -o /dev/null -I --connect-timeout "${timeout}" -m "${timeout}" \
            --tlsv1.2 --tls-max 1.2 \
            "https://${host}:${port}/" >/dev/null 2>&1 && return 0
    elif command -v openssl >/dev/null 2>&1; then
        echo -n | openssl s_client -servername "${host}" -connect "${host}:${port}" \
            -tls1_2 2>&1 | grep -q "CONNECTED" && return 0
    fi
    return 1
}

# TLS 1.3 Handshake probe
# Returns 0 (OK) or 1 (FAIL)
probe_tls13() {
    local host="$1"
    local port="${2:-443}"
    local timeout=2

    if command -v curl >/dev/null 2>&1; then
        curl -s -k -o /dev/null -I --connect-timeout "${timeout}" -m "${timeout}" \
            --tlsv1.3 --tls-max 1.3 \
            "https://${host}:${port}/" >/dev/null 2>&1 && return 0
    elif command -v openssl >/dev/null 2>&1; then
        echo -n | openssl s_client -servername "${host}" -connect "${host}:${port}" \
            -tls1_3 2>&1 | grep -q "CONNECTED" && return 0
    fi
    return 1
}

# Fast TLS Handshake probe (checks TLS 1.3 then TLS 1.2)
probe_fast_tls() {
    local host="$1"
    local port="${2:-443}"
    probe_tls13 "${host}" "${port}" && return 0
    probe_tls12 "${host}" "${port}" && return 0
    return 1
}

# Recipe lookup for specific services (matches NetProbe.Recipe in Asterlike/zapret2UI)
probe_get_recipe() {
    local host="$1"
    case "${host}" in
        discord.com|*.discord.com)
            echo "https://discord.com/login discord"
            ;;
        www.youtube.com|youtube.com|*.youtube.com)
            echo "https://www.youtube.com/ ytcfg"
            ;;
        gateway.discord.gg)
            echo "https://gateway.discord.gg/ NONE"
            ;;
        cdn.discordapp.com)
            echo "https://cdn.discordapp.com/ NONE"
            ;;
        googlevideo.com|*.googlevideo.com)
            echo "https://googlevideo.com/ NONE"
            ;;
        i.ytimg.com)
            echo "https://i.ytimg.com/ NONE"
            ;;
        *)
            echo "https://${host}/ NONE"
            ;;
    esac
}

# HTTP Reachability & Response Body Validation (Browser-like)
# Returns 0 (OK) or 1 (FAIL)
probe_http_reach() {
    local host="$1"
    local recipe
    recipe=$(probe_get_recipe "${host}")
    local url
    url=$(echo "${recipe}" | awk '{print $1}')
    local marker
    marker=$(echo "${recipe}" | awk '{print $2}')

    local tmp_resp="${Z2M_TMP}/probe_resp_${host}_$$.tmp"
    rm -f "${tmp_resp}" 2>/dev/null

    # Perform browser-like HTTP request
    if command -v curl >/dev/null 2>&1; then
        # -k: ignore cert mismatch if any (identity is secondary, DPI block detection is primary)
        # -L: follow redirect (HTTP 3xx from origin is clean, DPI cannot forge valid TLS redirect)
        curl -sSL -k --connect-timeout 4 -m 6 \
            -A "${BROWSER_UA}" \
            -H "Accept: text/html,application/xhtml+xml,application/json,*/*" \
            -H "Accept-Language: ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7" \
            --range 0-65535 \
            "${url}" -o "${tmp_resp}" 2>/dev/null
    else
        wget -q --timeout=5 -O "${tmp_resp}" "${url}" 2>/dev/null
    fi

    # If response file is empty or missing, request failed (RST, drop or timeout)
    if [ ! -s "${tmp_resp}" ]; then
        rm -f "${tmp_resp}" 2>/dev/null
        return 1
    fi

    # Check for Russian ISP / TSPU block page indicators
    if grep -Eiq "${BLOCK_MARKERS}" "${tmp_resp}"; then
        rm -f "${tmp_resp}" 2>/dev/null
        return 1
    fi

    # Check for mandatory service content marker if specified
    if [ "${marker}" != "NONE" ] && [ -n "${marker}" ]; then
        if ! grep -iq "${marker}" "${tmp_resp}"; then
            rm -f "${tmp_resp}" 2>/dev/null
            return 1
        fi
    fi

    rm -f "${tmp_resp}" 2>/dev/null
    return 0
}

# Full 3-signal probe of a single host:
# Signal 1: TLS 1.2 (1 point)
# Signal 2: TLS 1.3 (1 point)
# Signal 3: HTTP Reachability with content validation (3 points)
# Outputs: "<tls12_ok:0/1> <tls13_ok:0/1> <http_ok:0/1> <weighted_score:0-5>"
probe_host() {
    local host="$1"
    local s_tls12=0
    local s_tls13=0
    local s_http=0

    probe_tls12 "${host}" && s_tls12=1
    probe_tls13 "${host}" && s_tls13=1
    probe_http_reach "${host}" && s_http=1

    # Weighted score calculation matching Asterlike/zapret2UI StrategyGeneratorService
    local score=$(( s_tls12 + s_tls13 + (s_http * 3) ))
    echo "${s_tls12} ${s_tls13} ${s_http} ${score}"
}

# Probe an entire group of hosts (e.g. Discord hosts or YouTube hosts)
# Returns: "<passed_checks> <total_checks> <weighted_score> <max_weighted_score>"
probe_host_list() {
    local hosts="$1"
    local total_checks=0
    local passed_checks=0
    local total_weighted=0
    local max_weighted=0

    for h in ${hosts}; do
        total_checks=$(( total_checks + 3 ))
        max_weighted=$(( max_weighted + 5 ))

        local res
        res=$(probe_host "${h}")
        local r_t12 r_t13 r_http r_weight
        r_t12=$(echo "${res}" | awk '{print $1}')
        r_t13=$(echo "${res}" | awk '{print $2}')
        r_http=$(echo "${res}" | awk '{print $3}')
        r_weight=$(echo "${res}" | awk '{print $4}')

        passed_checks=$(( passed_checks + r_t12 + r_t13 + r_http ))
        total_weighted=$(( total_weighted + r_weight ))
    done

    echo "${passed_checks} ${total_checks} ${total_weighted} ${max_weighted}"
}

# DPI Signature Probe: determines if DPI is actively blocking host by SNI
# Returns: "Clean", "Reset", "Freeze", "DNSError", or "NoConnection"
probe_dpi_verdict() {
    local host="$1"
    local port="${2:-443}"

    if ! command -v curl >/dev/null 2>&1; then
        echo "Unknown"
        return 0
    fi

    local err_file="${Z2M_TMP}/curl_dpi_err_$$.tmp"
    rm -f "${err_file}" 2>/dev/null

    # Fast connect with SNI
    curl -s -k -o /dev/null -I --connect-timeout 3 -m 5 "https://${host}:${port}/" 2>"${err_file}"
    local code=$?

    if [ ${code} -eq 0 ]; then
        rm -f "${err_file}" 2>/dev/null
        echo "Clean"
        return 0
    fi

    local err_msg=""
    [ -f "${err_file}" ] && err_msg="$(cat "${err_file}")"
    rm -f "${err_file}" 2>/dev/null

    case "${code}" in
        35|52|56)
            echo "Reset"
            ;;
        28)
            echo "Freeze"
            ;;
        6)
            echo "DNSError"
            ;;
        7)
            echo "NoConnection"
            ;;
        *)
            if echo "${err_msg}" | grep -qi "reset"; then
                echo "Reset"
            elif echo "${err_msg}" | grep -qi "timeout"; then
                echo "Freeze"
            else
                echo "Blocked"
            fi
            ;;
    esac
}
