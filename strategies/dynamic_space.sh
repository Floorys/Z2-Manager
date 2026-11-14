#!/bin/sh
# shellcheck disable=SC3043
# ==============================================================================
# Zapret2-Manager: Dynamic Strategy Space (parameter axes for the generator)
#
# The real strategy generator: candidate desync bundles are CONSTRUCTED
# algorithmically from parameter axes (fake blobs, primes, repeats, split
# positions, seqovl, host masks, window tricks) instead of being picked from
# a fixed catalogue. Every generated string is a valid nfqws2 --lua-desync
# bundle using the same syntax as the classic Asterlike candidates.
# ==============================================================================

[ -z "${Z2M_DIR:-}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"

# Hard cap of generated stage-2 candidates (protects slow routers).
DYNGEN_STAGE2_MAX="${DYNGEN_STAGE2_MAX:-14}"

# --- Low-level bundle builders -----------------------------------------------

# dyn_fake <blob> <prime> <repeats>   prime: md5 | ts | seq | autottl
dyn_fake() {
    local s="fake:blob=$1"
    case "$2" in
        md5)     s="${s}:tcp_md5" ;;
        ts)      s="${s}:tcp_ts=-1000" ;;
        seq)     s="${s}:tcp_seq=-10000" ;;
        autottl) s="${s}:ip_autottl=-2,3-20:ip6_autottl=-2,3-20" ;;
    esac
    echo "--lua-desync=${s}:repeats=$3"
}

# dyn_split <mode> <positions> <seqovl> <extra>   mode: multisplit | multidisorder
dyn_split() {
    local s="$1:pos=$2"
    if [ -n "$3" ]; then
        s="${s}:seqovl=$3:seqovl_pattern=tls_google:optional"
    fi
    [ -z "$4" ] || s="${s}:$4"
    echo "--lua-desync=${s}"
}

# dyn_hfs <host> <prime> <repeats> <midhost>   prime: ts_md5 | md5
dyn_hfs() {
    local s="hostfakesplit:host=$1"
    case "$2" in
        md5) s="${s}:tcp_md5" ;;
        *)   s="${s}:tcp_ts=-1000:tcp_md5" ;;
    esac
    if [ -n "$4" ]; then
        s="${s}:midhost=$4:disorder_after"
    fi
    echo "--lua-desync=${s}:repeats=$3"
}

dyn_wssize()        { echo "--lua-desync=wssize:wsize=1:scale=6"; }
dyn_fakedsplit()    { echo "--lua-desync=fakedsplit:tcp_ts=-1000"; }
dyn_fakeddisorder() { echo "--lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up:repeats=6"; }

# --- Deduplication helper ------------------------------------------------------

# dyn_is_known <file> <tls>: exit 0 when the tls bundle is already listed.
dyn_is_known() {
    [ -f "$1" ] || return 1
    awk -F'|' -v t="$2" '$2 == t { f = 1; exit } END { exit f ? 0 : 1 }' "$1" 2>/dev/null
}

# dyn_try_add <outfile> <knownfile> <name> <tls>: append "name|tls" unless duplicate.
dyn_try_add() {
    local out="$1" known="$2" name="$3" tls="$4"
    case "${tls}" in *\"*) return 1 ;; esac
    [ -n "${tls}" ] || return 1
    dyn_is_known "${known}" "${tls}" && return 1
    dyn_is_known "${out}" "${tls}" && return 1
    printf '%s|%s\n' "${name}" "${tls}" >> "${out}"
    return 0
}

# --- Stage 1: one representative candidate per desync family ------------------

# dyn_build_stage1 <outfile>: writes "name|tls" lines.
dyn_build_stage1() {
    local out="$1"
    : > "${out}"
    printf '%s|%s\n' "Сплит: 1,midsld"              "$(dyn_split multisplit "1,midsld" "" "")"                      >> "${out}"
    printf '%s|%s\n' "Сплит: SNI+SLD+хвост"         "$(dyn_split multisplit "1,sniext,midsld,endhost" "" "")"        >> "${out}"
    printf '%s|%s\n' "Дизордер: 1,midsld"           "$(dyn_split multidisorder "1,midsld" "" "")"                    >> "${out}"
    printf '%s|%s\n' "Дизордер: SNI-паттерн"        "$(dyn_split multidisorder "1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2" "" "")" >> "${out}"
    printf '%s|%s\n' "Дизордер: 88x5"               "$(dyn_split multidisorder "88,176,264,352,440" "" "")"          >> "${out}"
    printf '%s|%s\n' "Фейк Google: md5"             "$(dyn_fake tls_google md5 6)"                                  >> "${out}"
    printf '%s|%s\n' "Фейк Google: ts"              "$(dyn_fake tls_google ts 6)"                                   >> "${out}"
    printf '%s|%s\n' "Фейк Google: seq"             "$(dyn_fake tls_google seq 6)"                                  >> "${out}"
    printf '%s|%s\n' "Фейк Google: autottl"         "$(dyn_fake tls_google autottl 6)"                              >> "${out}"
    printf '%s|%s\n' "Фейк VK: autottl"             "$(dyn_fake tls_vk autottl 6)"                                  >> "${out}"
    printf '%s|%s\n' "hostfakesplit: google"        "$(dyn_hfs www.google.com ts_md5 4 "")"                         >> "${out}"
    printf '%s|%s\n' "hostfakesplit: vk.com"        "$(dyn_hfs vk.com ts_md5 4 "")"                                 >> "${out}"
    printf '%s|%s\n' "Двойной фейк: google+vk (ts)" "$(dyn_fake tls_google ts 6) $(dyn_fake tls_vk ts 6)"            >> "${out}"
    printf '%s|%s\n' "Комбо: фейк md5 + сплит"      "$(dyn_fake tls_google md5 6) $(dyn_split multisplit "1,midsld" "" "")" >> "${out}"
    printf '%s|%s\n' "Комбо: фейк ts + дизордер"    "$(dyn_fake tls_google ts 6) $(dyn_split multidisorder "1,midsld" "" "")" >> "${out}"
    printf '%s|%s\n' "fakedsplit: ts"               "$(dyn_fakedsplit)"                                             >> "${out}"
    printf '%s|%s\n' "fakeddisorder: midsld"        "$(dyn_fakeddisorder)"                                          >> "${out}"
    printf '%s|%s\n' "Сплит seqovl 681"             "$(dyn_split multisplit "2,midsld-2" 681 "")"                   >> "${out}"
    printf '%s|%s\n' "Сплит + окно wssize"          "$(dyn_split multisplit "2,midsld-2" 1 "") $(dyn_wssize)"       >> "${out}"
}

# --- Stage 2: parameter refinement of the surviving classes -------------------

# dyn_build_stage2 <outfile> <stage1file> <index...>
# Variants are generated in a fixed priority order and capped at
# DYNGEN_STAGE2_MAX; exact duplicates of stage 1 are skipped.
dyn_build_stage2() {
    local out="$1" known="$2"
    shift 2
    : > "${out}"
    local made=0 idx line tls v v2 name
    local blob prime reps mode positions seqovl host sp
    for idx in "$@"; do
        [ "${made}" -ge "${DYNGEN_STAGE2_MAX}" ] && break
        line=$(sed -n "${idx}p" "${known}" 2>/dev/null)
        [ -n "${line}" ] || continue
        tls=${line#*|}
        case "${tls}" in
            *hostfakesplit*)
                for host in www.google.com vk.com www.microsoft.com sberbank.ru; do
                    for prime in ts_md5 md5; do
                        for reps in 4 6; do
                            [ "${made}" -ge "${DYNGEN_STAGE2_MAX}" ] && break 3
                            v="$(dyn_hfs "${host}" "${prime}" "${reps}" "")"
                            dyn_try_add "${out}" "${known}" "hfs: ${host} ${prime} x${reps}" "${v}" && made=$(( made + 1 ))
                            v="$(dyn_hfs "${host}" "${prime}" "${reps}" midsld)"
                            dyn_try_add "${out}" "${known}" "hfs: ${host} ${prime} x${reps} + midhost" "${v}" && made=$(( made + 1 ))
                            v="$(dyn_hfs "${host}" "${prime}" "${reps}" "") $(dyn_wssize)"
                            dyn_try_add "${out}" "${known}" "hfs: ${host} ${prime} x${reps} + окно" "${v}" && made=$(( made + 1 ))
                        done
                    done
                done
                ;;
            *fake:*multisplit:*|*fake:*multidisorder:*)
                # Combined bundle: vary the fake prime and the split shape.
                for blob in tls_google tls_vk; do
                    for prime in ts md5 seq; do
                        for reps in 6 8; do
                            for sp in "1,midsld" "2,midsld-2" "1,sniext,midsld,endhost"; do
                                [ "${made}" -ge "${DYNGEN_STAGE2_MAX}" ] && break 4
                                v="$(dyn_fake "${blob}" "${prime}" "${reps}") $(dyn_split multisplit "${sp}" "" "")"
                                dyn_try_add "${out}" "${known}" "комбо: ${blob} ${prime} x${reps} + ${sp}" "${v}" && made=$(( made + 1 ))
                            done
                        done
                    done
                done
                ;;
            *fake:*)
                # Pure fake: vary blob, prime and repeats, then prime+split bundles.
                for blob in tls_google tls_vk; do
                    for prime in ts md5 seq autottl; do
                        for reps in 4 6 8; do
                            [ "${made}" -ge "${DYNGEN_STAGE2_MAX}" ] && break 3
                            v="$(dyn_fake "${blob}" "${prime}" "${reps}")"
                            dyn_try_add "${out}" "${known}" "фейк: ${blob} ${prime} x${reps}" "${v}" && made=$(( made + 1 ))
                            v2="$(dyn_fake "${blob}" "${prime}" 6) $(dyn_split multisplit "1,midsld" "" "")"
                            dyn_try_add "${out}" "${known}" "комбо: ${blob} ${prime} x6 + сплит" "${v2}" && made=$(( made + 1 ))
                        done
                    done
                done
                ;;
            *multisplit:*|*multidisorder:*)
                mode=multisplit
                case "${tls}" in *multidisorder*) mode=multidisorder ;; esac
                for positions in "1,midsld" "2,midsld-2" "1,sniext,midsld,endhost" "1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2" "88,176,264,352,440" "1,midsld,endhost-2"; do
                    for seqovl in "" 1 681; do
                        [ "${made}" -ge "${DYNGEN_STAGE2_MAX}" ] && break 2
                        v="$(dyn_split "${mode}" "${positions}" "${seqovl}" "")"
                        if [ -n "${seqovl}" ]; then
                            name="${mode}: ${positions} ovl=${seqovl}"
                        else
                            name="${mode}: ${positions}"
                        fi
                        dyn_try_add "${out}" "${known}" "${name}" "${v}" && made=$(( made + 1 ))
                        v2="$(dyn_fake tls_google ts 6) ${v}"
                        dyn_try_add "${out}" "${known}" "комбо: fake ts + ${mode} ${positions}" "${v2}" && made=$(( made + 1 ))
                    done
                done
                v="$(dyn_split multisplit "2,midsld-2" 1 "") $(dyn_wssize)"
                dyn_try_add "${out}" "${known}" "сплит + окно wssize" "${v}" && made=$(( made + 1 ))
                ;;
            *fakedsplit:*)
                v="$(dyn_fake tls_google ts 6) $(dyn_fakedsplit)"
                dyn_try_add "${out}" "${known}" "комбо: fake ts + fakedsplit" "${v}" && made=$(( made + 1 ))
                v="$(dyn_fake tls_vk ts 6) $(dyn_fakedsplit)"
                dyn_try_add "${out}" "${known}" "комбо: fake vk ts + fakedsplit" "${v}" && made=$(( made + 1 ))
                ;;
            *fakeddisorder:*)
                v="$(dyn_fake tls_google md5 6) $(dyn_fakeddisorder)"
                dyn_try_add "${out}" "${known}" "комбо: fake md5 + fakeddisorder" "${v}" && made=$(( made + 1 ))
                ;;
        esac
    done
    # Enforce the hard cap exactly (a family may add several per iteration).
    local n
    n=$(wc -l < "${out}" | tr -d ' ')
    if [ "${n}" -gt "${DYNGEN_STAGE2_MAX}" ]; then
        head -n "${DYNGEN_STAGE2_MAX}" "${out}" > "${out}.cap" 2>/dev/null &&
            cat "${out}.cap" > "${out}" && rm -f "${out}.cap"
    fi
    return 0
}
