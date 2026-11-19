#!/bin/sh
. /opt/zapret2-manager/core/config.sh
. /opt/zapret2-manager/core/zapret_service.sh
. /opt/zapret2-manager/core/combo_builder.sh
. /opt/zapret2-manager/strategies/candidates.sh

orig_opt=$(zapret_get_opt)
trap 'zapret_set_opt "${orig_opt}"' EXIT INT TERM

CDN_HOST="rr4---sn-jvhnu5g-bvwl.googlevideo.com"

echo "Testing candidate bundles on REAL CDN host: ${CDN_HOST}"
echo "--------------------------------------------------------"

for idx in 3 5 8 9 10 11 12 15 16 19 20 21 24 25 26 27; do
    c_name=$(get_candidate_name "${idx}")
    c_tls=$(get_candidate_tls "${idx}")
    [ -n "${c_tls}" ] || continue
    
    test_opt=$(combo_build_single_test_args "${c_tls}") || continue
    if ! zapret_set_opt "${test_opt}"; then
        echo "[${idx}] ${c_name}: FAILED TO APPLY"
        continue
    fi
    sleep 1

    res=$(curl -4 -k -s -I --connect-timeout 2 -m 3 "https://${CDN_HOST}" 2>&1 | head -n 1 | tr -d '\r\n')
    if [ -n "${res}" ] && ! echo "${res}" | grep -q "curl:"; then
        echo ">>> [${idx}] ${c_name}: SUCCESS! Response: ${res} <<<"
    else
        echo "[${idx}] ${c_name}: FAIL (${res:-timeout})"
    fi
done
