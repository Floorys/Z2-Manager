#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Fast Network Connectivity & DPI Probe Engine
# Adapted from Asterlike/zapret2UI NetProbe.cs for high performance on OpenWrt
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"

probe_check_deps() {
    command -v curl >/dev/null 2>&1 && return 0
    command -v wget >/dev/null 2>&1 && return 0
    return 1
}

# Fast TLS Handshake & HTTP Reachability Probe
# Uses HEAD request (-I) with strict timeouts to eliminate router hangs
# Returns 0 (Reachable/Bypassed) or 1 (Blocked/Timeout/RST)
probe_fast_tls() {
    local host="$1"
    local port="${2:-443}"
    local timeout="${3:-2}"
    local max_t=$(( timeout + 1 ))

    if command -v curl >/dev/null 2>&1; then
        local code
        code=$(curl -s -k -o /dev/null -w "%{http_code}" -I \
            --connect-timeout "${timeout}" -m "${max_t}" \
            -A "${BROWSER_UA}" "https://${host}:${port}/" 2>/dev/null)
        case "${code}" in
            2*|3*|4*) return 0 ;;
            *) return 1 ;;
        esac
    elif command -v wget >/dev/null 2>&1; then
        wget -q --spider --timeout="${timeout}" "https://${host}:${port}/" >/dev/null 2>&1 && return 0
    fi
    return 1
}

# TLS 1.2 probe (compatible with mbedTLS, wolfSSL, and OpenSSL curl)
probe_tls12() {
    local host="$1"
    local port="${2:-443}"
    local timeout="${3:-2}"
    local max_t=$(( timeout + 1 ))

    if command -v curl >/dev/null 2>&1; then
        local code
        code=$(curl -s -k -o /dev/null -w "%{http_code}" -I --tlsv1.2 \
            --connect-timeout "${timeout}" -m "${max_t}" \
            -A "${BROWSER_UA}" "https://${host}:${port}/" 2>/dev/null)
        case "${code}" in
            2*|3*|4*) return 0 ;;
            *) return 1 ;;
        esac
    elif command -v openssl >/dev/null 2>&1; then
        echo -n | openssl s_client -servername "${host}" -connect "${host}:${port}" \
            -tls1_2 2>&1 | grep -q "CONNECTED" && return 0
    fi
    return 1
}

# TLS 1.3 probe
probe_tls13() {
    local host="$1"
    local port="${2:-443}"
    local timeout="${3:-2}"
    local max_t=$(( timeout + 1 ))

    if command -v curl >/dev/null 2>&1; then
        local code
        code=$(curl -s -k -o /dev/null -w "%{http_code}" -I --tlsv1.3 \
            --connect-timeout "${timeout}" -m "${max_t}" \
            -A "${BROWSER_UA}" "https://${host}:${port}/" 2>/dev/null)
        case "${code}" in
            2*|3*|4*) return 0 ;;
            *) return 1 ;;
        esac
    elif command -v openssl >/dev/null 2>&1; then
        echo -n | openssl s_client -servername "${host}" -connect "${host}:${port}" \
            -tls1_3 2>&1 | grep -q "CONNECTED" && return 0
    fi
    return 1
}

# Primary HTTP Reachability Check
probe_http_reach() {
    local host="$1"
    local timeout="${2:-2}"
    probe_fast_tls "${host}" "443" "${timeout}"
}

# 3-signal probe of a single host for scoring
probe_host() {
    local host="$1"
    local s_tls12=0
    local s_tls13=0
    local s_http=0

    probe_fast_tls "${host}" 443 2 && s_http=1
    if [ "${s_http}" -eq 1 ]; then
        s_tls12=1
        s_tls13=1
        echo "1 1 1 5"
    else
        probe_tls13 "${host}" 443 2 && s_tls13=1
        probe_tls12 "${host}" 443 2 && s_tls12=1
        local score=$(( s_tls12 + s_tls13 ))
        echo "${s_tls12} ${s_tls13} 0 ${score}"
    fi
}

# Probe list of hosts with instant response
# Returns: "<passed_checks> <total_checks> <weighted_score> <max_weighted_score>"
probe_host_list() {
    local hosts="$1"
    local total_checks=0
    local passed_checks=0
    local total_weighted=0
    local max_weighted=0

    for h in ${hosts}; do
        total_checks=$(( total_checks + 1 ))
        max_weighted=$(( max_weighted + 5 ))

        if probe_http_reach "${h}" 2; then
            passed_checks=$(( passed_checks + 1 ))
            total_weighted=$(( total_weighted + 5 ))
        fi
    done

    echo "${passed_checks} ${total_checks} ${total_weighted} ${max_weighted}"
}

# DPI Signature Probe: determines if DPI is actively blocking host by SNI
# Returns: "Clean", "Reset", "Freeze", "DNSError", or "NoConnection"
probe_dpi_verdict() {
    local host="$1"
    local port="${2:-443}"

    if ! command -v curl >/dev/null 2>&1; then
        if probe_fast_tls "${host}" "${port}" 3; then
            echo "Clean"
        else
            echo "Blocked"
        fi
        return 0
    fi

    local err_file="${Z2M_TMP}/curl_dpi_err_$$.tmp"
    rm -f "${err_file}" 2>/dev/null

    curl -s -k -o /dev/null -I --connect-timeout 2 -m 4 "https://${host}:${port}/" 2>"${err_file}"
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
