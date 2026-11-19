#!/bin/sh
. /opt/zapret2-manager/core/config.sh
. /opt/zapret2-manager/core/zapret_service.sh
. /opt/zapret2-manager/strategies/catalog.sh

orig_opt=$(zapret_get_opt)
trap 'zapret_set_opt "${orig_opt}"' EXIT INT TERM

CDN_HOST="rr4---sn-jvhnu5g-bvwl.googlevideo.com"

echo "Testing all 7 combo catalog strategies on REAL video CDN host: ${CDN_HOST}"
echo "------------------------------------------------------------------------"

i=1
while [ "${i}" -le 7 ]; do
    name=$(catalog_get_name "${i}")
    opt=$(catalog_get_opt "${i}")
    
    if ! zapret_set_opt "${opt}"; then
        echo "[${i}] ${name}: FAILED TO APPLY"
        i=$((i + 1))
        continue
    fi
    sleep 1

    # Test TLS handshake + HEAD
    res=$(curl -4 -k -s -I --connect-timeout 3 -m 5 "https://${CDN_HOST}" | head -n 1 | tr -d '\r\n')
    echo "[${i}] ${name}: ${res:-TIMED OUT OR RESET}"
    
    i=$((i + 1))
done
