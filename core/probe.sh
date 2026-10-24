#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Fast Network Connectivity & DPI Probe Engine
# Adapted from Asterlike/zapret2UI NetProbe.cs for high performance on OpenWrt
# ==============================================================================

[ -z "${Z2M_DIR:-}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"

probe_check_deps() {
    command -v curl >/dev/null 2>&1 && return 0
    command -v wget >/dev/null 2>&1 && return 0
    return 1
}

# Resolve human-readable category name for target hosts
probe_get_host_category() {
    local h="$1"
    case "${h}" in
        www.youtube.com)    echo "YouTube (Web)" ;;
        googlevideo.com)    echo "YouTube (Видео)" ;;
        i.ytimg.com)        echo "YouTube (Превью)" ;;
        discord.com)        echo "Discord (Web)" ;;
        gateway.discord.gg) echo "Discord (Голос/GW)" ;;
        cdn.discordapp.com) echo "Discord (Медиа)" ;;
        rutracker.org)      echo "РКН / RuTracker" ;;
        x.com)              echo "РКН / Twitter (X)" ;;
        instagram.com)      echo "РКН / Instagram" ;;
        vk.com)             echo "Контроль связи" ;;
        *)                  echo "Веб-сервис" ;;
    esac
}

# Check if resolved IP looks like an ISP spoofed stub or local redirect
probe_is_spoofed_ip() {
    local ip="$1"
    case "${ip}" in
        127.*|0.0.0.0) return 0 ;;
        10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0 ;;
        *) return 1 ;;
    esac
}

# DNS verification before probing
probe_dns_resolve() {
    local host="$1"
    local ip=""
    if command -v nslookup >/dev/null 2>&1; then
        ip=$(nslookup "${host}" 2>/dev/null | grep -A1 "Name:" | grep "Address" | awk '{print $2}' | head -n1)
    fi
    if [ -z "${ip}" ] && command -v getent >/dev/null 2>&1; then
        ip=$(getent hosts "${host}" 2>/dev/null | awk '{print $1}')
    fi
    echo "${ip}"
}

# Unified curl probe helper:
# Runs curl with strict timeouts, evaluates curl exit code vs HTTP status,
# checks redirect headers against ISP block stubs (warning.rt.ru, eais.rkn.gov.ru).
# Returns:
#   0 : Success (Reachable, bypass working)
#   1 : Failure (DPI block, timeout, RST, TLS fail, or ISP block stub)
probe_curl_request() {
    local host="$1"
    local port="${2:-443}"
    local timeout="${3:-2}"
    local extra_args="${4:-}"
    local max_t=$(( timeout + 1 ))

    local intf_opt=""
    if [ -n "${CURL_INTERFACE:-}" ]; then
        intf_opt="--interface ${CURL_INTERFACE}"
    fi

    local hdr_file
    hdr_file=$(mktemp "${Z2M_TMP}/curl_hdr.XXXXXX")

    # Capture HTTP headers and status code
    local http_code
    if [ -n "${CURL_INTERFACE:-}" ]; then
        if [ -n "${extra_args}" ]; then
            http_code=$(curl -s -k -I \
                --connect-timeout "${timeout}" \
                -m "${max_t}" \
                -A "${BROWSER_UA}" \
                --interface "${CURL_INTERFACE}" \
                "${extra_args}" \
                -D "${hdr_file}" \
                -o /dev/null \
                -w "%{http_code}" \
                "https://${host}:${port}/" 2>/dev/null)
        else
            http_code=$(curl -s -k -I \
                --connect-timeout "${timeout}" \
                -m "${max_t}" \
                -A "${BROWSER_UA}" \
                --interface "${CURL_INTERFACE}" \
                -D "${hdr_file}" \
                -o /dev/null \
                -w "%{http_code}" \
                "https://${host}:${port}/" 2>/dev/null)
        fi
    else
        if [ -n "${extra_args}" ]; then
            http_code=$(curl -s -k -I \
                --connect-timeout "${timeout}" \
                -m "${max_t}" \
                -A "${BROWSER_UA}" \
                "${extra_args}" \
                -D "${hdr_file}" \
                -o /dev/null \
                -w "%{http_code}" \
                "https://${host}:${port}/" 2>/dev/null)
        else
            http_code=$(curl -s -k -I \
                --connect-timeout "${timeout}" \
                -m "${max_t}" \
                -A "${BROWSER_UA}" \
                -D "${hdr_file}" \
                -o /dev/null \
                -w "%{http_code}" \
                "https://${host}:${port}/" 2>/dev/null)
        fi
    fi
    local curl_exit=$?

    # Separate curl exit code from HTTP code
    if [ "${curl_exit}" -ne 0 ]; then
        rm -f "${hdr_file}" 2>/dev/null
        return 1
    fi

    # Check for Russian ISP block page redirects in headers
    if [ -s "${hdr_file}" ]; then
        local loc
        loc=$(grep -i "^Location:" "${hdr_file}" 2>/dev/null | tr -d '\r\n')
        if [ -n "${loc}" ]; then
            if echo "${loc}" | grep -q -i -E "${BLOCK_MARKERS}"; then
                rm -f "${hdr_file}" 2>/dev/null
                return 1
            fi
        fi
    fi
    rm -f "${hdr_file}" 2>/dev/null

    case "${http_code}" in
        2*|3*|4*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Fast TLS Handshake & HTTP Reachability Probe
# Uses HEAD request (-I) with strict timeouts to eliminate router hangs
probe_fast_tls() {
    local host="$1"
    local port="${2:-443}"
    local timeout="${3:-2}"

    if command -v curl >/dev/null 2>&1; then
        probe_curl_request "${host}" "${port}" "${timeout}" ""
        return $?
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

    if command -v curl >/dev/null 2>&1; then
        probe_curl_request "${host}" "${port}" "${timeout}" "--tlsv1.2"
        return $?
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

    if command -v curl >/dev/null 2>&1; then
        probe_curl_request "${host}" "${port}" "${timeout}" "--tlsv1.3"
        return $?
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
    probe_fast_tls "${host}" 443 "${timeout}"
}

# 3-signal probe of a single host for scoring
probe_host() {
    local host="$1"
    local s_tls12=0
    local s_tls13=0

    if probe_fast_tls "${host}" 443 2; then
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

    # Check DNS spoofing first
    local ip
    ip=$(probe_dns_resolve "${host}")
    if [ -n "${ip}" ] && probe_is_spoofed_ip "${ip}"; then
        echo "DNSError"
        return 0
    fi

    local err_file
    err_file=$(mktemp "${Z2M_TMP}/curl_dpi_err.XXXXXX")

    local intf_opt=""
    if [ -n "${CURL_INTERFACE:-}" ]; then
        intf_opt="--interface ${CURL_INTERFACE}"
    fi

    # shellcheck disable=SC2086
    curl -s -k -o /dev/null -I --connect-timeout 2 -m 4 ${intf_opt} "https://${host}:${port}/" 2>"${err_file}"
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
