#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Combo Strategy Builder
# Port of PresetService.BuildComboArgs from Asterlike/zapret2UI
# ==============================================================================

[ -z "${Z2M_DIR:-}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"

combo_blob_args() {
    local entry alias file src
    for entry in tls_google:tls_clienthello_www_google_com.bin tls_vk:tls_clienthello_vk_com.bin tls_sber:tls_clienthello_sberbank_ru.bin tls_gos:tls_clienthello_gosuslugi_ru.bin quic_generic:quic_initial_generic.bin; do
        alias="${entry%%:*}"; file="${entry#*:}"
        src="${ZAPRET2_FAKE_DIR}/${file}"
        [ -f "${src}" ] || src="${Z2M_DIR}/fake/${file}"
        [ -f "${src}" ] || return 1
        printf ' --blob=%s:@%s' "${alias}" "${src}"
    done
}

# Build full NFQWS2_OPT argument string from components:
# $1: discord_tls_desync
# $2: youtube_tls_desync
# $3: fallback_tls_desync (optional, defaults to discord_tls)
# $4: voice_desync (optional, defaults to Asterlike standard QUIC fake)
combo_build_args() {
    local discord_tls="$1"
    local youtube_tls="$2"
    local fallback_tls="${3:-$1}"
    local voice_desync="${4:---payload=discord_ip_discovery,stun --lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2}"

    local hostlist_discord="${ZAPRET2_IPSET_DIR}/zapret-hosts-discord.txt"
    local hostlist_youtube="${ZAPRET2_IPSET_DIR}/zapret-hosts-youtube.txt"
    local hostlist_exclude="${ZAPRET2_IPSET_DIR}/zapret-hosts-user-exclude.txt"

    # Filter arguments
    local filter_dc=""
    local filter_yt=""
    local filter_ex=""

    if [ -f "${hostlist_discord}" ]; then
        filter_dc="--hostlist=${hostlist_discord}"
    fi
    if [ -f "${hostlist_youtube}" ]; then
        filter_yt="--hostlist=${hostlist_youtube}"
    fi
    if [ -f "${hostlist_exclude}" ]; then
        filter_ex="--hostlist-exclude=${hostlist_exclude}"
    fi

    local blobs
    blobs=$(combo_blob_args) || return 1

    # Base options (no double quotes to prevent syntax corruption in /opt/zapret2/config)
    local opt="--ctrack-disable=0 --ipcache-lifetime=8400 --ipcache-hostname=1${blobs}"

    # HTTP must be profiled as well as intercepted; TLS-only rules ignore port 80.
    opt="${opt} --filter-tcp=80 --filter-l7=http ${filter_ex} --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2"

    # Profile 1: Discord TLS
    opt="${opt} --new --filter-tcp=443-65535 --filter-l7=tls ${filter_dc} --out-range=-d10 --payload=tls_client_hello ${discord_tls}"

    # Profile 2: YouTube TLS
    opt="${opt} --new --filter-tcp=443-65535 --filter-l7=tls ${filter_yt} --out-range=-d10 --payload=tls_client_hello ${youtube_tls}"

    # Profile 3: Catch-all Fallback TLS (excluding sensitive RU domains)
    opt="${opt} --new --filter-tcp=443-65535 --filter-l7=tls ${filter_ex} --out-range=-d10 --payload=tls_client_hello ${fallback_tls}"

    # Profile 4: QUIC YouTube
    opt="${opt} --new --filter-udp=443-65535 --filter-l7=quic ${filter_yt} --payload=quic_initial --lua-desync=fake:blob=quic_generic:repeats=11"

    # Profile 5: QUIC Discord (media/cdn HTTP/3)
    opt="${opt} --new --filter-udp=443-65535 --filter-l7=quic ${filter_dc} --payload=quic_initial --lua-desync=fake:blob=quic_generic:repeats=11"

    # Profile 6: QUIC Catch-all (excluding sensitive domains)
    opt="${opt} --new --filter-udp=443-65535 --filter-l7=quic ${filter_ex} --payload=quic_initial --lua-desync=fake:blob=quic_generic:repeats=6"

    # Profile 7: Discord Voice (STUN + RTP high UDP ports 50000-65535)
    opt="${opt} --new --filter-udp=19294-19344,50000-65535 --filter-l7=discord,stun ${voice_desync}"

    echo "${opt}"
}

# Build standalone test argument for probing a single candidate bundle on all traffic
# Used during Pass 1 of generation
combo_build_single_test_args() {
    local candidate_tls="$1"

    local blobs
    blobs=$(combo_blob_args) || return 1

    local opt="--ctrack-disable=0 --ipcache-lifetime=8400 --ipcache-hostname=1${blobs}"
    opt="${opt} --filter-tcp=80 --filter-l7=http --payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5 --lua-desync=multisplit:pos=method+2"
    opt="${opt} --new --filter-tcp=443-65535 --filter-l7=tls --out-range=-d10 --payload=tls_client_hello ${candidate_tls}"
    opt="${opt} --new --filter-udp=443-65535 --filter-l7=quic --payload=quic_initial --lua-desync=fake:blob=quic_generic:repeats=6"

    echo "${opt}"
}
