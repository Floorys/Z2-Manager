#!/bin/sh
# shellcheck disable=SC2034
# ==============================================================================
# Zapret2-Manager: Candidate TLS Desync Bundles for Strategy Generator
# Ordered by real-world bypass effectiveness across Russian ISPs
# ==============================================================================

CANDIDATES_COUNT=27

get_candidate_name() {
    case "$1" in
        1)  echo "Flowseal ALT10: dual fake + ts" ;;
        2)  echo "Flowseal ALT11: fake ts seqovl" ;;
        3)  echo "hostfakesplit google" ;;
        4)  echo "Фейк md5/seq + дизордер" ;;
        5)  echo "YT: fake dupsid + disorder" ;;
        6)  echo "hostfakesplit vk.com" ;;
        7)  echo "Окно wssize + seqovl" ;;
        8)  echo "Фейк md5 + сплит" ;;
        9)  echo "Фейк ts + дизордер" ;;
        10) echo "seqovl-перекрытие" ;;
        11) echo "badseq + ip_id=zero сплит" ;;
        12) echo "hostfakesplit + wssize" ;;
        13) echo "Отеч.: fake VK + дизордер" ;;
        14) echo "Отеч.: fake Sber + дизордер" ;;
        15) echo "hostfakesplit ozon.ru" ;;
        16) echo "hostfakesplit sberbank.ru" ;;
        17) echo "hostfakesplit gosuslugi.ru" ;;
        18) echo "hostfakesplit MS-host" ;;
        19) echo "hostfakesplit vk midhost" ;;
        20) echo "Фейк autottl + сплит" ;;
        21) echo "fakeddisorder badseq midsld" ;;
        22) echo "tcpseg seqovl 5 + drop" ;;
        23) echo "hostfakesplit md5 x6" ;;
        24) echo "Сплит по имени" ;;
        25) echo "Дизордер по имени" ;;
        26) echo "Дизордер 88x5" ;;
        27) echo "Дизордер host/sld/sni" ;;
        *)  echo "Unknown" ;;
    esac
}

get_candidate_tls() {
    case "$1" in
        1)  echo "--lua-desync=fake:blob=tls_google:tcp_ts=-1000:repeats=6 --lua-desync=fake:blob=tls_vk:tcp_ts=-1000:repeats=6" ;;
        2)  echo "--lua-desync=fake:blob=tls_google:tcp_ts=-1000:repeats=8 --lua-desync=multisplit:pos=1,midsld:seqovl=681:seqovl_pattern=tls_google:optional" ;;
        3)  echo "--lua-desync=hostfakesplit:host=www.google.com:tcp_ts=-1000:tcp_md5:repeats=4" ;;
        4)  echo "--lua-desync=fake:blob=tls_google:tcp_md5:tcp_seq=-10000:repeats=6 --lua-desync=multidisorder:pos=1,midsld" ;;
        5)  echo "--lua-desync=fake:blob=tls_google:tls_mod=rnd,dupsid:repeats=6 --lua-desync=multidisorder:pos=1,sniext+1,host+1,midsld-2,midsld,endhost-1" ;;
        6)  echo "--lua-desync=hostfakesplit:host=vk.com:tcp_ts=-1000:tcp_md5:repeats=4" ;;
        7)  echo "--lua-desync=multisplit:pos=2,midsld-2:seqovl=1:seqovl_pattern=tls_google:optional --lua-desync=wssize:wsize=1:scale=6" ;;
        8)  echo "--lua-desync=fake:blob=tls_google:tcp_md5:repeats=6 --lua-desync=multisplit:pos=1,midsld" ;;
        9)  echo "--lua-desync=fake:blob=tls_google:tcp_ts=-1000:repeats=6 --lua-desync=multidisorder:pos=1,midsld" ;;
        10) echo "--lua-desync=multisplit:pos=2,midsld-2:seqovl=681:seqovl_pattern=tls_google:optional" ;;
        11) echo "--lua-desync=fake:blob=tls_google:tcp_seq=-10000:ip_autottl=-2,3-20:repeats=6 --lua-desync=multisplit:pos=1,midsld:ip_id=zero" ;;
        12) echo "--lua-desync=hostfakesplit:host=www.google.com:tcp_ts=-1000:tcp_md5:repeats=4 --lua-desync=wssize:wsize=1:scale=6" ;;
        13) echo "--lua-desync=fake:blob=tls_vk:tcp_md5:ip_autottl=-2,3-20:repeats=6 --lua-desync=multidisorder:pos=1,midsld" ;;
        14) echo "--lua-desync=fake:blob=tls_sber:tcp_md5:ip_autottl=-2,3-20:repeats=6 --lua-desync=multidisorder:pos=1,midsld" ;;
        15) echo "--lua-desync=hostfakesplit:host=ozon.ru:tcp_md5:repeats=6" ;;
        16) echo "--lua-desync=hostfakesplit:host=sberbank.ru:tcp_ts=-1000:tcp_md5:repeats=4" ;;
        17) echo "--lua-desync=hostfakesplit:host=gosuslugi.ru:tcp_ts=-1000:tcp_md5:repeats=4" ;;
        18) echo "--lua-desync=hostfakesplit:host=www.microsoft.com:tcp_ts=-1000:tcp_md5:repeats=4" ;;
        19) echo "--lua-desync=hostfakesplit:host=vk.com:midhost=midsld:disorder_after:tcp_ts=-1000:tcp_md5:repeats=4" ;;
        20) echo "--lua-desync=fake:blob=tls_google:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:repeats=6 --lua-desync=multisplit:pos=1,midsld" ;;
        21) echo "--lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up:repeats=6" ;;
        22) echo "--lua-desync=tcpseg:pos=0,-1:seqovl=5:seqovl_pattern=tls_google --lua-desync=drop" ;;
        23) echo "--lua-desync=hostfakesplit:host=www.google.com:tcp_md5:repeats=6" ;;
        24) echo "--lua-desync=multisplit:pos=1,sniext,midsld,endhost" ;;
        25) echo "--lua-desync=multidisorder:pos=1,sniext,midsld,endhost" ;;
        26) echo "--lua-desync=multidisorder:pos=88,176,264,352,440" ;;
        27) echo "--lua-desync=multidisorder:pos=1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2" ;;
        *)  echo "" ;;
    esac
}

# Checks if a candidate is "Gateway-Friendly" for Discord (from StrategyGeneratorService.cs)
# Prevents Discord native client gateway/voice stall ("logs in but won't connect")
is_gateway_friendly() {
    local tls="$1"

    # A hostfakesplit or a fake:…tcp_ts prime carries even a big-seqovl split to the gateway (ALT10/11)
    if echo "${tls}" | grep -q "hostfakesplit"; then
        return 0
    fi
    if echo "${tls}" | grep -q -- "--lua-desync=fake:" && echo "${tls}" | grep -q "tcp_ts"; then
        return 0
    fi

    # Unprimed: large fixed seqovl >= 100 is NOT gateway-friendly
    if echo "${tls}" | grep -E -q "seqovl=[0-9]{3,}"; then
        return 1
    fi

    # Fixed absolute byte split positions pos >= 40 without prime
    if echo "${tls}" | grep -E -q "pos=([0-9]{2,})"; then
        local first_pos
        first_pos=$(echo "${tls}" | sed -n 's/.*pos=\([0-9]\+\).*/\1/p')
        if [ -n "${first_pos}" ] && [ "${first_pos}" -ge 40 ]; then
            return 1
        fi
    fi

    return 0
}
