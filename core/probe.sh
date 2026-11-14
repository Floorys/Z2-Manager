#!/bin/sh
# shellcheck disable=SC3043
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
        # BusyBox prints "Address 1: 1.2.3.4" while other implementations
        # commonly print "Address: 1.2.3.4". In both cases the IP is last.
        ip=$(nslookup "${host}" 2>/dev/null | awk '
            /^Name:/ { answer = 1; next }
            answer && /^Address/ { print $NF; exit }
        ')
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
    shift 3
    # Optional curl flags are separate arguments, never an eval/string split.
    if [ "$#" -gt 0 ] && [ -z "$1" ]; then shift; fi
    local max_t=$(( timeout + 1 ))

    z2m_prepare_runtime || return 1
    local hdr_file body_file
    hdr_file=$(mktemp "${Z2M_TMP}/curl_hdr.XXXXXX")
    body_file=$(mktemp "${Z2M_TMP}/curl_body.XXXXXX")
    if [ -z "${hdr_file}" ] || [ -z "${body_file}" ]; then
        rm -f "${hdr_file}" "${body_file}" 2>/dev/null
        return 1
    fi

    # Capture HTTP headers and status code
    local http_code
    PROBE_CURL_EXIT=0
    [ -z "${CURL_INTERFACE:-}" ] || set -- "$@" --interface "${CURL_INTERFACE}"
    http_code=$(curl -sS -L --proto '=https' --proto-redir '=https' \
        --connect-timeout "${timeout}" -m "${max_t}" -A "${BROWSER_UA}" \
        "$@" --range 0-8191 -D "${hdr_file}" -o "${body_file}" \
        -w "%{http_code}" "https://${host}:${port}/" 2>/dev/null)
    local curl_exit=$?
    if [ "${curl_exit}" -eq 2 ]; then
        # Minimal OpenWrt curl without --proto support: retry without proto restrictions
        http_code=$(curl -sS -L \
            --connect-timeout "${timeout}" -m "${max_t}" -A "${BROWSER_UA}" \
            "$@" --range 0-8191 -D "${hdr_file}" -o "${body_file}" \
            -w "%{http_code}" "https://${host}:${port}/" 2>/dev/null)
        curl_exit=$?
    fi
    PROBE_CURL_EXIT="${curl_exit}"

    # Separate curl exit code from HTTP code
    if [ "${curl_exit}" -ne 0 ]; then
        rm -f "${hdr_file}" "${body_file}" 2>/dev/null
        return 1
    fi

    # Check for Russian ISP block page redirects in headers
    if [ -s "${hdr_file}" ]; then
        local loc
        loc=$(grep -i "^Location:" "${hdr_file}" 2>/dev/null | tr -d '\r\n')
        if [ -n "${loc}" ]; then
            if echo "${loc}" | grep -q -i -E "${BLOCK_MARKERS}"; then
                rm -f "${hdr_file}" "${body_file}" 2>/dev/null
                return 1
            fi
        fi
    fi
    # Some ISP block pages return HTTP 200 and do not redirect.
    if [ -s "${body_file}" ] && grep -q -i -E "${BLOCK_MARKERS}" "${body_file}" 2>/dev/null; then
        rm -f "${hdr_file}" "${body_file}" 2>/dev/null
        return 1
    fi
    rm -f "${hdr_file}" "${body_file}" 2>/dev/null

    case "${http_code}" in
        2*|3*|400|401|403|404|405|409|429)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Fast TLS Handshake & HTTP Reachability Probe
# Uses a small ranged GET with strict timeouts so block-page bodies can be checked.
probe_fast_tls() {
    local host="$1"
    local port="${2:-443}"
    local timeout="${3:-${Z2M_PROBE_TIMEOUT:-2}}"

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
    local timeout="${3:-${Z2M_PROBE_TIMEOUT:-2}}"

    if command -v curl >/dev/null 2>&1; then
        probe_curl_request "${host}" "${port}" "${timeout}" --tlsv1.2 --tls-max 1.2
        return $?
    elif command -v openssl >/dev/null 2>&1; then
        printf "" | openssl s_client -servername "${host}" -connect "${host}:${port}" \
            -tls1_2 2>&1 | grep -q "CONNECTED" && return 0
    fi
    return 1
}

# TLS 1.3 probe
probe_tls13() {
    local host="$1"
    local port="${2:-443}"
    local timeout="${3:-${Z2M_PROBE_TIMEOUT:-2}}"

    if command -v curl >/dev/null 2>&1; then
        probe_curl_request "${host}" "${port}" "${timeout}" "--tlsv1.3"
        return $?
    elif command -v openssl >/dev/null 2>&1; then
        printf "" | openssl s_client -servername "${host}" -connect "${host}:${port}" \
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

# ==============================================================================
# Concurrent probing engine
# Every host check is one curl process; they are spawned in parallel background
# jobs and aggregated afterwards, so a full host list costs one probe timeout
# instead of one timeout per host. Z2M_PROBE_PARALLEL=0 restores the strictly
# sequential behaviour for very weak routers.
# ==============================================================================

# Probe every host in $1 (timeout $2) and print "<host> <1|0>" lines.
# Optional $3 selects the probe type: "http" (default) or "tls12".
probe_hosts_map() {
    local hosts="$1"
    local timeout="${2:-${Z2M_PROBE_TIMEOUT:-2}}"
    local mode="${3:-http}"
    local h i=0 passed ok dir="" pids="" p

    if [ "${Z2M_PROBE_PARALLEL:-1}" = "1" ]; then
        z2m_prepare_runtime 2>/dev/null
        dir=$(mktemp -d "${Z2M_TMP}/probe.XXXXXX" 2>/dev/null) || dir=""
    fi

    if [ -n "${dir}" ]; then
        for h in ${hosts}; do
            i=$(( i + 1 ))
            (
                ok=0
                if [ "${mode}" = "tls12" ]; then
                    probe_tls12 "${h}" 443 "${timeout}" && ok=1
                else
                    probe_http_reach "${h}" "${timeout}" && ok=1
                fi
                printf '%s' "${ok}" > "${dir}/${i}"
            ) &
            pids="${pids} $!"
        done
        for p in ${pids}; do
            wait "${p}" 2>/dev/null
        done
        i=0
        for h in ${hosts}; do
            i=$(( i + 1 ))
            passed=0
            [ "$(cat "${dir}/${i}" 2>/dev/null)" = "1" ] && passed=1
            echo "${h} ${passed}"
        done
        rm -rf "${dir}"
    else
        for h in ${hosts}; do
            passed=0
            if [ "${mode}" = "tls12" ]; then
                probe_tls12 "${h}" 443 "${timeout}" && passed=1
            else
                probe_http_reach "${h}" "${timeout}" && passed=1
            fi
            echo "${h} ${passed}"
        done
    fi
    return 0
}

# Aggregate host map into "<passed> <total>" (1 point per reachable host).
probe_hosts_count() {
    probe_hosts_map "$@" | awk '{ if ($2 == 1) ok++; total++ } END { print ok + 0, total + 0 }'
}

# Probe list of hosts with instant response
# Returns: "<passed_checks> <total_checks> <weighted_score> <max_weighted_score>"
probe_host_list() {
    local res
    res=$(probe_hosts_count "$@")
    echo "${res} $(( ${res%% *} * 5 )) $(( ${res##* } * 5 ))"
}

# Probe two host lists concurrently; prints two "weighted" result lines
# (first line for list $1, second line for list $2).
probe_lists2() {
    local a="$1" b="$2" timeout="${3:-${Z2M_PROBE_TIMEOUT:-2}}"
    local dir pa pb
    z2m_prepare_runtime 2>/dev/null
    dir=$(mktemp -d "${Z2M_TMP}/probe2.XXXXXX" 2>/dev/null)
    if [ -z "${dir}" ]; then
        probe_host_list "${a}" "${timeout}"
        probe_host_list "${b}" "${timeout}"
        return 0
    fi
    probe_host_list "${a}" "${timeout}" > "${dir}/a" &
    pa=$!
    probe_host_list "${b}" "${timeout}" > "${dir}/b" &
    pb=$!
    wait "${pa}" 2>/dev/null
    wait "${pb}" 2>/dev/null
    cat "${dir}/a" "${dir}/b"
    rm -rf "${dir}"
    return 0
}

# Same as probe_lists2 but prints two "<passed> <total>" lines.
probe_counts2() {
    local a="$1" b="$2" timeout="${3:-${Z2M_PROBE_TIMEOUT:-2}}"
    local dir pa pb
    z2m_prepare_runtime 2>/dev/null
    dir=$(mktemp -d "${Z2M_TMP}/probe2.XXXXXX" 2>/dev/null)
    if [ -z "${dir}" ]; then
        probe_hosts_count "${a}" "${timeout}"
        probe_hosts_count "${b}" "${timeout}"
        return 0
    fi
    probe_hosts_count "${a}" "${timeout}" > "${dir}/a" &
    pa=$!
    probe_hosts_count "${b}" "${timeout}" > "${dir}/b" &
    pb=$!
    wait "${pa}" 2>/dev/null
    wait "${pb}" 2>/dev/null
    cat "${dir}/a" "${dir}/b"
    rm -rf "${dir}"
    return 0
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

    # Use the same GET/status/header/body policy as the selection probe.
    PROBE_CURL_EXIT=0
    if probe_curl_request "${host}" "${port}" 3; then
        echo "Clean"
        return 0
    fi
    case "${PROBE_CURL_EXIT}" in
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
            echo "Blocked"
            ;;
    esac
}
