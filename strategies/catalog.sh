#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Strategy Catalog
# Port of BuiltIns from Asterlike/zapret2UI PresetService.cs
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/combo_builder.sh" ] && . "${Z2M_DIR}/core/combo_builder.sh"

CATALOG_COUNT=9

catalog_get_name() {
    case "$1" in
        1) echo "Комбо (рекомендуемый)" ;;
        2) echo "Комбо — отечественный (VK, целевой)" ;;
        3) echo "Комбо — Flowseal ALT10 (двойной fake + ts)" ;;
        4) echo "Комбо — Flowseal ALT11 (fake+ts -> seqovl)" ;;
        5) echo "Комбо — Flowseal (multisplit seqovl)" ;;
        6) echo "Комбо — Flowseal ALT (fake+fakedsplit)" ;;
        7) echo "Комбо — окно (wssize)" ;;
        8) echo "Discord — голос (QUIC-фейк)" ;;
        9) echo "Discord — адаптивный (circular, эксперим.)" ;;
        *) echo "Unknown" ;;
    esac
}

catalog_get_tagline() {
    case "$1" in
        1) echo "Универсальная — начните с неё" ;;
        2) echo "Маскировка под VK" ;;
        3) echo "Когда не работают голос и медиа" ;;
        4) echo "Фейк + разрезка внахлёст" ;;
        5) echo "Разрезка запроса (без фейков)" ;;
        6) echo "Фейк + ложная разрезка" ;;
        7) echo "Дробит ответ сервера" ;;
        8) echo "Только голос Discord" ;;
        9) echo "Подбирает способ на ходу" ;;
        *) echo "" ;;
    esac
}

catalog_get_opt() {
    case "$1" in
        1)
            # 1) RECOMMENDED: Discord hostfakesplit, YouTube fake+multidisorder
            local dc="--lua-desync=hostfakesplit:host=www.google.com:tcp_ts=-1000:tcp_md5:repeats=4"
            local yt="--lua-desync=fake:blob=tls_google:tcp_md5:tcp_seq=-10000:repeats=6 --lua-desync=multidisorder:pos=1,midsld"
            combo_build_args "${dc}" "${yt}" "${dc}"
            ;;
        2)
            # 2) TARGETED DOMESTIC (VK): mask as vk.com for Russian ISPs
            local dc="--lua-desync=hostfakesplit:host=vk.com:tcp_ts=-1000:tcp_md5:repeats=4"
            local yt="--lua-desync=fake:blob=tls_google:tcp_md5:tcp_seq=-10000:repeats=6 --lua-desync=multidisorder:pos=1,midsld"
            combo_build_args "${dc}" "${yt}" "${dc}"
            ;;
        3)
            # 3) Flowseal general (ALT10): dual fake + ts
            local dc="--lua-desync=fake:blob=tls_google:tcp_ts=-1000:repeats=6 --lua-desync=fake:blob=tls_vk:tcp_ts=-1000:repeats=6"
            local yt="--lua-desync=fake:blob=tls_google:tcp_ts=-1000:ip_id=zero:repeats=6"
            local voice="--lua-desync=fake:blob=quic_vk:repeats=6"
            combo_build_args "${dc}" "${yt}" "${dc}" "${voice}"
            ;;
        4)
            # 4) Flowseal general (ALT11): fake+ts -> seqovl 681
            local dc="--lua-desync=fake:blob=tls_google:tcp_ts=-1000:repeats=6 --lua-desync=multisplit:pos=1,midsld:seqovl=681:seqovl_pattern=tls_google:optional"
            local yt="--lua-desync=fake:blob=tls_google:tcp_ts=-1000:repeats=6 --lua-desync=multisplit:pos=1,midsld:seqovl=681:seqovl_pattern=tls_google:ip_id=zero:optional"
            local fb="--lua-desync=fake:blob=tls_google:tcp_ts=-1000:repeats=6 --lua-desync=multisplit:pos=1,midsld:seqovl=664:seqovl_pattern=tls_google:optional"
            local voice="--lua-desync=fake:blob=quic_vk:repeats=6"
            combo_build_args "${dc}" "${yt}" "${fb}" "${voice}"
            ;;
        5)
            # 5) Flowseal general: multisplit seqovl
            local dc="--lua-desync=multisplit:pos=2:seqovl=681:seqovl_pattern=tls_google:optional"
            local yt="--lua-desync=multisplit:pos=2:seqovl=681:seqovl_pattern=tls_google:ip_id=zero:optional"
            local fb="--lua-desync=multisplit:pos=2:seqovl=568:seqovl_pattern=tls_google:optional"
            combo_build_args "${dc}" "${yt}" "${fb}"
            ;;
        6)
            # 6) Flowseal ALT: fake+fakedsplit
            local dc="--lua-desync=fake:blob=tls_google:tcp_ts=-1000:repeats=6 --lua-desync=fakedsplit:tcp_ts=-1000"
            combo_build_args "${dc}" "${dc}" "${dc}"
            ;;
        7)
            # 7) wssize bundle: split + forced server window fragmentation
            local dc="--lua-desync=multisplit:pos=2,midsld-2:seqovl=1:seqovl_pattern=tls_google:optional --lua-desync=wssize:wsize=1:scale=6"
            local yt="--lua-desync=fake:blob=tls_google:tcp_md5:tcp_seq=-10000:repeats=6 --lua-desync=multidisorder:pos=1,midsld"
            combo_build_args "${dc}" "${yt}" "${dc}"
            ;;
        8)
            # 8) Standalone Discord Voice fix
            local hostlist_discord="${ZAPRET2_IPSET_DIR}/zapret-hosts-discord.txt"
            local filter_dc=""
            [ -f "${hostlist_discord}" ] && filter_dc="--hostlist=${hostlist_discord}"
            local opt="--ctrack-disable=0 --ipcache-lifetime=8400 --ipcache-hostname=1"
            [ -f "${ZAPRET2_FAKE_DIR}/tls_clienthello_www_google_com.bin" ] && \
                opt="${opt} --blob=tls_google:@${ZAPRET2_FAKE_DIR}/tls_clienthello_www_google_com.bin"
            [ -f "${ZAPRET2_FAKE_DIR}/quic_initial_www_google_com.bin" ] && \
                opt="${opt} --blob=quic_google:@${ZAPRET2_FAKE_DIR}/quic_initial_www_google_com.bin"
            opt="${opt} --filter-tcp=443-65535 --filter-l7=tls ${filter_dc} --out-range=-d10 --payload=tls_client_hello --lua-desync=multisplit:pos=2,midsld-2:seqovl=1:seqovl_pattern=tls_google:optional"
            opt="${opt} --new --filter-udp=19294-19344,50000-65535 --filter-l7=discord,stun --lua-desync=fake:blob=quic_google:repeats=6"
            echo "${opt}"
            ;;
        9)
            # 9) Standalone ADAPTIVE Discord (circular)
            local hostlist_discord="${ZAPRET2_IPSET_DIR}/zapret-hosts-discord.txt"
            local filter_dc=""
            [ -f "${hostlist_discord}" ] && filter_dc="--hostlist=${hostlist_discord}"
            local opt="--ctrack-disable=0 --ipcache-lifetime=8400 --ipcache-hostname=1"
            [ -f "${ZAPRET2_FAKE_DIR}/tls_clienthello_www_google_com.bin" ] && \
                opt="${opt} --blob=tls_google:@${ZAPRET2_FAKE_DIR}/tls_clienthello_www_google_com.bin"
            [ -f "${ZAPRET2_FAKE_DIR}/tls_clienthello_vk_com.bin" ] && \
                opt="${opt} --blob=tls_vk:@${ZAPRET2_FAKE_DIR}/tls_clienthello_vk_com.bin"
            [ -f "${ZAPRET2_FAKE_DIR}/quic_initial_www_google_com.bin" ] && \
                opt="${opt} --blob=quic_google:@${ZAPRET2_FAKE_DIR}/quic_initial_www_google_com.bin"
            [ -f "${ZAPRET2_FAKE_DIR}/quic_initial_vk_com.bin" ] && \
                opt="${opt} --blob=quic_vk:@${ZAPRET2_FAKE_DIR}/quic_initial_vk_com.bin"
            opt="${opt} --filter-tcp=443-65535 --filter-l7=tls ${filter_dc} --in-range=-s5556 --out-range=-d10 --payload=tls_client_hello --lua-desync=circular:fails=2:time=300 --lua-desync=hostfakesplit:host=www.google.com:tcp_ts=-1000:tcp_md5:repeats=4:strategy=1 --lua-desync=fake:blob=tls_google:tcp_ts=-1000:repeats=6:strategy=2 --lua-desync=fake:blob=tls_vk:tcp_ts=-1000:repeats=6:strategy=2 --lua-desync=fake:blob=tls_google:tcp_ts=-1000:repeats=6:strategy=3 --lua-desync=multisplit:pos=1,midsld:seqovl=681:seqovl_pattern=tls_google:strategy=3:optional"
            opt="${opt} --new --filter-udp=443-65535 --filter-l7=quic ${filter_dc} --payload=quic_initial --lua-desync=fake:blob=quic_google:repeats=11"
            opt="${opt} --new --filter-udp=19294-19344,50000-65535 --filter-l7=discord,stun --lua-desync=fake:blob=quic_vk:repeats=6"
            echo "${opt}"
            ;;
        *)
            echo ""
            ;;
    esac
}
