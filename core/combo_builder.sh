#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Combo Strategy Builder
# Port of PresetService.BuildComboArgs from Asterlike/zapret2UI
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"

# Build full NFQWS2_OPT argument string from components:
# $1: discord_tls_desync
# $2: youtube_tls_desync
# $3: fallback_tls_desync (optional, defaults to discord_tls)
# $4: voice_desync (optional, defaults to Flowseal domestic quic_vk)
combo_build_args() {
    local discord_tls="$1"
    local youtube_tls="$2"
    local fallback_tls="${3:-$1}"
    local voice_desync="${4:---lua-desync=fake:blob=quic_vk:repeats=6}"

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

    # Blob declarations
    local blobs=""
    [ -f "${ZAPRET2_FAKE_DIR}/tls_clienthello_www_google_com.bin" ] && \
        blobs="${blobs} --blob=tls_google:@${ZAPRET2_FAKE_DIR}/tls_clienthello_www_google_com.bin"
    [ -f "${ZAPRET2_FAKE_DIR}/quic_initial_www_google_com.bin" ] && \
        blobs="${blobs} --blob=quic_google:@${ZAPRET2_FAKE_DIR}/quic_initial_www_google_com.bin"
    [ -f "${ZAPRET2_FAKE_DIR}/tls_clienthello_vk_com.bin" ] && \
        blobs="${blobs} --blob=tls_vk:@${ZAPRET2_FAKE_DIR}/tls_clienthello_vk_com.bin"
    [ -f "${ZAPRET2_FAKE_DIR}/tls_clienthello_sberbank_ru.bin" ] && \
        blobs="${blobs} --blob=tls_sber:@${ZAPRET2_FAKE_DIR}/tls_clienthello_sberbank_ru.bin"
    [ -f "${ZAPRET2_FAKE_DIR}/tls_clienthello_gosuslugi_ru.bin" ] && \
        blobs="${blobs} --blob=tls_gos:@${ZAPRET2_FAKE_DIR}/tls_clienthello_gosuslugi_ru.bin"
    [ -f "${ZAPRET2_FAKE_DIR}/quic_initial_vk_com.bin" ] && \
        blobs="${blobs} --blob=quic_vk:@${ZAPRET2_FAKE_DIR}/quic_initial_vk_com.bin"

    # Base options
    local opt="--ctrack-disable=0 --ipcache-lifetime=8400 --ipcache-hostname=1 --lua-init=\"fake_default_tls = tls_mod(fake_default_tls,'rnd,rndsni')\" ${blobs}"

    # Profile 1: Discord TLS
    opt="${opt} --filter-tcp=443-65535 --filter-l7=tls ${filter_dc} --out-range=-d10 --payload=tls_client_hello ${discord_tls}"

    # Profile 2: YouTube TLS
    opt="${opt} --new --filter-tcp=443-65535 --filter-l7=tls ${filter_yt} --out-range=-d10 --payload=tls_client_hello ${youtube_tls}"

    # Profile 3: Catch-all Fallback TLS (excluding sensitive RU domains)
    opt="${opt} --new --filter-tcp=443-65535 --filter-l7=tls ${filter_ex} --out-range=-d10 --payload=tls_client_hello ${fallback_tls}"

    # Profile 4: QUIC YouTube
    opt="${opt} --new --filter-udp=443-65535 --filter-l7=quic ${filter_yt} --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=11"

    # Profile 5: QUIC Discord (media/cdn HTTP/3)
    opt="${opt} --new --filter-udp=443-65535 --filter-l7=quic ${filter_dc} --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=11"

    # Profile 6: QUIC Catch-all (excluding sensitive domains)
    opt="${opt} --new --filter-udp=443-65535 --filter-l7=quic ${filter_ex} --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6"

    # Profile 7: Discord Voice (STUN + RTP high UDP ports 50000-65535)
    opt="${opt} --new --filter-udp=19294-19344,50000-65535 --filter-l7=discord,stun ${voice_desync}"

    echo "${opt}"
}

# Build standalone test argument for probing a single candidate bundle on all traffic
# Used during Pass 1 of generation
combo_build_single_test_args() {
    local candidate_tls="$1"

    local blobs=""
    [ -f "${ZAPRET2_FAKE_DIR}/tls_clienthello_www_google_com.bin" ] && \
        blobs="${blobs} --blob=tls_google:@${ZAPRET2_FAKE_DIR}/tls_clienthello_www_google_com.bin"
    [ -f "${ZAPRET2_FAKE_DIR}/tls_clienthello_vk_com.bin" ] && \
        blobs="${blobs} --blob=tls_vk:@${ZAPRET2_FAKE_DIR}/tls_clienthello_vk_com.bin"
    [ -f "${ZAPRET2_FAKE_DIR}/tls_clienthello_sberbank_ru.bin" ] && \
        blobs="${blobs} --blob=tls_sber:@${ZAPRET2_FAKE_DIR}/tls_clienthello_sberbank_ru.bin"
    [ -f "${ZAPRET2_FAKE_DIR}/quic_initial_vk_com.bin" ] && \
        blobs="${blobs} --blob=quic_vk:@${ZAPRET2_FAKE_DIR}/quic_initial_vk_com.bin"

    local opt="--ctrack-disable=0 --ipcache-lifetime=8400 --ipcache-hostname=1 ${blobs}"
    opt="${opt} --filter-tcp=443-65535 --filter-l7=tls --out-range=-d10 --payload=tls_client_hello ${candidate_tls}"
    opt="${opt} --new --filter-udp=443-65535 --filter-l7=quic --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6"

    echo "${opt}"
}
