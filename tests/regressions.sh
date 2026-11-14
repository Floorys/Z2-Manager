#!/bin/sh
# Sourced by run.sh. Every scenario runs in a subshell and only touches TMP_ROOT.
. "${ROOT}/modules/autoselect.sh"
. "${ROOT}/modules/generator.sh"
. "${ROOT}/modules/discord_fix.sh"
. "${ROOT}/modules/dns.sh"

fixture() {
    CASE_DIR=$(mktemp -d "${TMP_ROOT}/case.XXXXXX") || exit 1
    sh -c 'echo "$PPID"' > "${CASE_DIR}/pid"
    read -r CASE_PID < "${CASE_DIR}/pid"
    ZAPRET2_DIR="${CASE_DIR}/zapret2"
    ZAPRET2_CONFIG="${ZAPRET2_DIR}/config"
    ZAPRET2_IPSET_DIR="${ZAPRET2_DIR}/ipset"
    ZAPRET2_FAKE_DIR="${ZAPRET2_DIR}/files/fake"
    ZAPRET2_SYNC="${CASE_DIR}/no-sync"
    ZAPRET2_INIT="${CASE_DIR}/no-init"
    UCI_CONFIG="${CASE_DIR}/no-uci"
    CUSTOM_D_DIR="${ZAPRET2_DIR}/init.d/openwrt/custom.d"
    CUSTOM_SCRIPT_50="${CUSTOM_D_DIR}/50-script.sh"
    Z2M_TMP="${CASE_DIR}/runtime"
    Z2M_NONINTERACTIVE=1
    Z2M_GUARDED=0
    FAIL_RESTART=0 FAIL_AT=0 FAIL_RESTORE=0 SIGNAL_AT=0 SIGNAL_NAME=TERM
    mkdir -p "${CUSTOM_D_DIR}" "${Z2M_TMP}"
    printf 'NFQWS2_OPT="original"\nNFQWS2_PORTS_TCP="80,443"\nNFQWS2_PORTS_UDP="443"\nDISABLE_CUSTOM="1"\n' > "${ZAPRET2_CONFIG}"
    cp "${ZAPRET2_CONFIG}" "${CASE_DIR}/original"
    echo running > "${CASE_DIR}/status"
    echo 0 > "${CASE_DIR}/restarts"
    sleep() { :; }
    tui_banner() { :; }
    tui_header() { :; }
    tui_info() { :; }
    tui_warn() { :; }
    tui_error() { :; }
    tui_success() { :; }
    tui_pause() { :; }
    tui_print_result_table_header() { :; }
    tui_print_result_row() { :; }
    zapret_is_installed() { return 0; }
    zapret_is_running() { [ "$(cat "${CASE_DIR}/status")" = running ]; }
    zapret_stop() { echo stopped > "${CASE_DIR}/status"; }
    zapret_start() {
        [ "${FAIL_RESTORE}" -eq 0 ] || return 1
        echo running > "${CASE_DIR}/status"
    }
    zapret_restart() {
        local n
        n=$(( $(cat "${CASE_DIR}/restarts") + 1 ))
        echo "${n}" > "${CASE_DIR}/restarts"
        if [ "${SIGNAL_AT}" -eq "${n}" ]; then
            kill -"${SIGNAL_NAME}" "${CASE_PID}"
            # Keep the worker alive until the parent forwards the signal.
            command sleep 0.1
        fi
        if [ "${FAIL_RESTART}" -eq 1 ] || [ "${FAIL_AT}" -eq "${n}" ]; then
            echo stopped > "${CASE_DIR}/status"
            return 1
        fi
        echo running > "${CASE_DIR}/status"
    }
}

rollback_failed_apply() (
    fixture
    [ "${1:-running}" = running ] || echo stopped > "${CASE_DIR}/status"
    FAIL_RESTART=1
    ! zapret_set_opt candidate || return 1
    cmp -s "${ZAPRET2_CONFIG}" "${CASE_DIR}/original" &&
        [ "$(cat "${CASE_DIR}/status")" = "${1:-running}" ] &&
        [ ! -d "${Z2M_TMP}/operation.lock" ]
)
check "failed apply restores options, ports and running state" rollback_failed_apply running
check "failed apply restores originally stopped state" rollback_failed_apply stopped

rollback_failed_ports() (
    fixture
    FAIL_RESTART=1
    ! zapret_set_ports "80,8443" "443,9000" || return 1
    cmp -s "${ZAPRET2_CONFIG}" "${CASE_DIR}/original"
)
check "failed port change restores full configuration" rollback_failed_ports

successful_ports() (
    fixture
    zapret_set_ports "80,8443" "443,9000" &&
        [ "$(zapret_get_ports_tcp)" = 80,8443 ] && [ "$(zapret_get_ports_udp)" = 443,9000 ]
)
check "successful manual port change commits the new values" successful_ports

invalid_apply_is_readonly() (
    fixture
    zapret_set_opt 'bad"quote'
    [ "$?" -eq 2 ] || return 1
    zapret_set_ports '70000' '443'
    [ "$?" -eq 2 ] && cmp -s "${ZAPRET2_CONFIG}" "${CASE_DIR}/original" &&
        [ "$(cat "${CASE_DIR}/restarts")" -eq 0 ]
)
check "invalid options/ports fail before service changes" invalid_apply_is_readonly

rollback_preserves_backup() (
    fixture
    FAIL_RESTART=1 FAIL_RESTORE=1
    ! zapret_set_opt candidate || return 1
    find "${Z2M_TMP}" -name recovery-failed | grep -q . &&
        find "${Z2M_TMP}" -name config | grep -q .
)
check "failed recovery retains snapshots for manual restoration" rollback_preserves_backup

snapshot_exact_config() (
    fixture
    printf 'export NFQWS2_OPT="first\nsecond"\nOTHER="literal \\$value"\n' > "${ZAPRET2_CONFIG}"
    cp "${ZAPRET2_CONFIG}" "${CASE_DIR}/original"
    local saved
    saved=$(zapret_backup_config) || return 1
    echo damaged > "${ZAPRET2_CONFIG}"
    zapret_restore_config "${saved}" && cmp -s "${ZAPRET2_CONFIG}" "${CASE_DIR}/original"
)
check "snapshot preserves multiline/exported flat config byte-for-byte" snapshot_exact_config

snapshot_uci_and_flat() (
    fixture
    UCI_CONFIG="${CASE_DIR}/uci"
    printf "package zapret2\nconfig zapret2 'config'\noption NFQWS2_OPT 'original'\n" > "${UCI_CONFIG}"
    cp "${UCI_CONFIG}" "${CASE_DIR}/original-uci"
    uci() {
        case "$1" in
            export) cat "${UCI_CONFIG}" ;;
            import) cat > "${UCI_CONFIG}" ;;
            commit) return 0 ;;
            *) return 1 ;;
        esac
    }
    local saved
    saved=$(zapret_backup_config) || return 1
    echo damaged > "${UCI_CONFIG}"
    echo damaged > "${ZAPRET2_CONFIG}"
    zapret_restore_config "${saved}" &&
        cmp -s "${UCI_CONFIG}" "${CASE_DIR}/original-uci" &&
        cmp -s "${ZAPRET2_CONFIG}" "${CASE_DIR}/original"
)
check "snapshot restores both UCI and flat config" snapshot_uci_and_flat

selector_fixture() {
    CATALOG_COUNT=1
    catalog_get_name() { echo candidate; }
    catalog_get_opt() { echo candidate; }
    probe_host_list() {
        if grep -q 'NFQWS2_OPT="original"' "${ZAPRET2_CONFIG}"; then
            echo '0 1 0 5'
        else
            echo '1 1 5 5'
        fi
    }
}

generator_fixture() {
    CANDIDATES_COUNT=1
    get_candidate_name() { echo candidate; }
    get_candidate_tls() { echo safe; }
    is_gateway_friendly() { return 0; }
    combo_build_single_test_args() { echo single; }
    combo_build_args() { echo "pair:$1:$2"; }
    probe_http_reach() { return 0; }
    probe_fast_tls() { return 0; }
    probe_host_list() {
        if grep -q 'NFQWS2_OPT="original"' "${ZAPRET2_CONFIG}"; then
            echo '0 3 0 15'
        else
            echo '3 3 15 15'
        fi
    }
}

cancel_workflow() (
    fixture
    selector_fixture
    SIGNAL_AT="$2" SIGNAL_NAME="${3:-TERM}"
    [ "$1" != run_strategy_generator ] || generator_fixture
    "$1" >/dev/null 2>&1
    local rc=$?
    case "${SIGNAL_NAME}" in INT) [ "${rc}" -eq 130 ] ;; HUP) [ "${rc}" -eq 129 ] ;; *) [ "${rc}" -eq 143 ] ;; esac || return 1
    cmp -s "${ZAPRET2_CONFIG}" "${CASE_DIR}/original" &&
        [ "$(cat "${CASE_DIR}/status")" = running ] &&
        [ ! -d "${Z2M_TMP}/operation.lock" ]
)
for mode in run_strategy_autoselect run_test_youtube_only run_test_discord_only; do
    check "${mode}: signal during first apply rolls back and fails CLI" cancel_workflow "${mode}" 1
    check "${mode}: signal during final apply rolls back" cancel_workflow "${mode}" 2
done
check "generator: signal during first apply rolls back" cancel_workflow run_strategy_generator 1
check "generator: signal during final apply rolls back" cancel_workflow run_strategy_generator 3
check "Ctrl+C returns 130 after complete recovery" cancel_workflow run_strategy_autoselect 1 INT
check "SIGHUP returns 129 after complete recovery" cancel_workflow run_strategy_autoselect 2 HUP

failed_final_apply() (
    fixture
    selector_fixture
    FAIL_AT="$2"
    [ "$1" != run_strategy_generator ] || generator_fixture
    ! "$1" >/dev/null 2>&1 && cmp -s "${ZAPRET2_CONFIG}" "${CASE_DIR}/original"
)
check "selector final restart failure restores the workflow's original config" failed_final_apply run_strategy_autoselect 2
check "generator final restart failure restores the workflow's original config" failed_final_apply run_strategy_generator 3

selector_keeps_baseline() (
    fixture
    selector_fixture
    probe_host_list() {
        if grep -q 'NFQWS2_OPT="original"' "${ZAPRET2_CONFIG}"; then
            echo '2 3 10 15'
        else
            echo "1 3 ${CANDIDATE_SCORE:-5} 15"
        fi
    }
    CANDIDATE_SCORE="$1"
    "$2" >/dev/null 2>&1 && cmp -s "${ZAPRET2_CONFIG}" "${CASE_DIR}/original"
)
for mode in run_strategy_autoselect run_test_youtube_only run_test_discord_only; do
    check "${mode}: worse result keeps baseline by default" selector_keeps_baseline 5 "${mode}"
    check "${mode}: equal result keeps baseline by default" selector_keeps_baseline 10 "${mode}"
done

generator_fallback() (
    fixture
    generator_fixture
    CANDIDATES_COUNT=2
    get_candidate_tls() { if [ "$1" = 1 ]; then echo unsafe; else echo safe; fi; }
    is_gateway_friendly() { [ "$1" = safe ]; }
    probe_http_reach() { grep -q 'NFQWS2_OPT="unsafe"' "${ZAPRET2_CONFIG}"; }
    probe_fast_tls() { probe_http_reach; }
    combo_build_single_test_args() { echo "$1"; }
    probe_host_list() {
        case "$(zapret_get_opt)" in
            pair:unsafe:unsafe) echo '2 3 10 15' ;;
            *) echo '0 3 0 15' ;;
        esac
    }
    run_strategy_generator >/dev/null 2>&1 && [ "$(zapret_get_opt)" = pair:unsafe:unsafe ]
)
check "generator falls back to working non-GW candidate, ignoring zero scores" generator_fallback

generator_all_pairs() (
    fixture
    generator_fixture
    CANDIDATES_COUNT=3
    get_candidate_tls() { echo "c$1"; }
    combo_build_single_test_args() { echo "$1"; }
    # Do not allow Pass 1 to claim a perfect universal candidate.
    probe_fast_tls() { return 1; }
    probe_http_reach() {
        case "$1" in discord.com|www.youtube.com) return 0 ;; *) return 1 ;; esac
    }
    probe_host_list() {
        case "$(zapret_get_opt)" in
            pair:c3:c3) echo '2 3 10 15' ;;
            pair:*) echo '1 3 5 15' ;;
            *) echo '0 3 0 15' ;;
        esac
    }
    run_strategy_generator >/dev/null 2>&1 &&
        [ "$(zapret_get_opt)" = pair:c3:c3 ] &&
        [ "$(cat "${CASE_DIR}/restarts")" -eq 13 ]
)
check "generator tests all nine pairs including the third Discord candidate" generator_all_pairs

# ---------------------------------------------------------------------------
# Concurrent probing engine
# ---------------------------------------------------------------------------

probe_parallel_counts() (
    Z2M_TMP="${TMP_ROOT}/runtime"
    FAKE_HTTP_CODE=200 FAKE_BODY=clean
    export FAKE_HTTP_CODE FAKE_BODY
    [ "$(probe_host_list 'a.example.org b.example.org c.example.org')" = "3 3 15 15" ]
)
check "parallel probe host list aggregates every host" probe_parallel_counts

probe_parallel_fails_closed() (
    Z2M_TMP="${TMP_ROOT}/runtime"
    FAKE_HTTP_CODE=451 FAKE_BODY=clean
    export FAKE_HTTP_CODE FAKE_BODY
    [ "$(probe_host_list 'a.example.org b.example.org')" = "0 2 0 10" ]
)
check "parallel probe reports blocked hosts as failures" probe_parallel_fails_closed

probe_sequential_fallback() (
    Z2M_TMP="${TMP_ROOT}/runtime"
    Z2M_PROBE_PARALLEL=0
    FAKE_HTTP_CODE=200 FAKE_BODY=clean
    export FAKE_HTTP_CODE FAKE_BODY
    [ "$(probe_host_list 'a.example.org b.example.org')" = "2 2 10 10" ]
)
check "sequential probe fallback keeps the same output format" probe_sequential_fallback

probe_parallel_is_concurrent() (
    Z2M_TMP="${TMP_ROOT}/runtime"
    PROBE_SLEEP=1 FAKE_HTTP_CODE=200 FAKE_BODY=clean
    export PROBE_SLEEP FAKE_HTTP_CODE FAKE_BODY
    local start end
    start=$(date +%s)
    probe_host_list 'a.example.org b.example.org c.example.org' > /dev/null
    end=$(date +%s)
    [ $(( end - start )) -le 2 ]
)
check "parallel probes overlap instead of queueing" probe_parallel_is_concurrent

probe_lists_two_concurrent() (
    Z2M_TMP="${TMP_ROOT}/runtime"
    FAKE_HTTP_CODE=200 FAKE_BODY=clean
    export FAKE_HTTP_CODE FAKE_BODY
    local out
    out=$(probe_lists2 'a.example.org b.example.org' 'c.example.org')
    [ "$(echo "${out}" | sed -n 1p)" = "2 2 10 10" ] &&
        [ "$(echo "${out}" | sed -n 2p)" = "1 1 5 5" ]
)
check "probe_lists2 measures two host lists concurrently" probe_lists_two_concurrent

discord_does_not_delete_foreign() (
    fixture
    echo foreign > "${CUSTOM_SCRIPT_50}"
    echo stun-script > "${CUSTOM_D_DIR}/50-stun4all.sh"
    echo backup > "${CUSTOM_D_DIR}/50-script.sh.bak"
    ! discord_fix_apply >/dev/null 2>&1 || return 1
    ! discord_fix_remove >/dev/null 2>&1 || return 1
    [ "$(cat "${CUSTOM_SCRIPT_50}")" = foreign ] &&
        [ "$(cat "${CUSTOM_D_DIR}/50-stun4all.sh")" = stun-script ] &&
        [ "$(cat "${CUSTOM_D_DIR}/50-script.sh.bak")" = backup ]
)
check "Discord fix refuses foreign scripts and never deletes wildcard matches" discord_does_not_delete_foreign

discord_restores_foreign() (
    fixture
    echo foreign > "${CUSTOM_SCRIPT_50}"
    chmod 700 "${CUSTOM_SCRIPT_50}"
    tui_prompt() { echo y; }
    discord_fix_apply >/dev/null 2>&1 || return 1
    [ "$(zapret_get_ports_tcp)" = 80,443 ] && [ "$(zapret_get_ports_udp)" = 443 ] || return 1
    discord_fix_remove >/dev/null 2>&1 &&
        [ "$(cat "${CUSTOM_SCRIPT_50}")" = foreign ] &&
        [ "$(discord_fix_custom_value)" = 1 ]
)
check "Discord fix preserves ports and restores confirmed replacement on removal" discord_restores_foreign

discord_failed_restart() (
    fixture
    echo foreign > "${CUSTOM_SCRIPT_50}"
    tui_prompt() { echo y; }
    FAIL_RESTART=1
    ! discord_fix_apply >/dev/null 2>&1 || return 1
    [ "$(cat "${CUSTOM_SCRIPT_50}")" = foreign ] &&
        cmp -s "${ZAPRET2_CONFIG}" "${CASE_DIR}/original" &&
        [ ! -d "${ZAPRET2_DIR}/.z2m-discord" ]
)
check "Discord failed restart restores original script and configuration" discord_failed_restart

discord_modified_owned() (
    fixture
    discord_fix_apply >/dev/null 2>&1 || return 1
    echo '# user edit' >> "${CUSTOM_SCRIPT_50}"
    cp "${CUSTOM_SCRIPT_50}" "${CASE_DIR}/edited"
    ! discord_fix_remove >/dev/null 2>&1 && cmp -s "${CUSTOM_SCRIPT_50}" "${CASE_DIR}/edited"
)
check "Discord removal refuses a user-edited managed script" discord_modified_owned

guard_restores_traps_and_stdin() (
    fixture
    local answer flag=0
    reader() { read -r answer; [ "${answer}" = yes ]; }
    trap 'flag=1' TERM
    z2m_run_guarded reader <<'INPUT' || return 1
yes
INPUT
    kill -TERM "${CASE_PID}"
    [ "${flag}" -eq 1 ]
)
check "guard preserves interactive stdin and restores caller signal traps" guard_restores_traps_and_stdin

guard_rejects_concurrent_operation() (
    fixture
    mkdir "${Z2M_TMP}/operation.lock"
    printf '%s\n' "$$" > "${Z2M_TMP}/operation.lock/pid"
    ! zapret_set_opt candidate >/dev/null 2>&1 && cmp -s "${ZAPRET2_CONFIG}" "${CASE_DIR}/original"
)
check "an existing operation lock prevents concurrent changes" guard_rejects_concurrent_operation

guard_removes_stale_lock() (
    fixture
    mkdir "${Z2M_TMP}/operation.lock"
    printf '999999\n' > "${Z2M_TMP}/operation.lock/pid"
    printf '1\n' > "${Z2M_TMP}/operation.lock/start"
    zapret_set_opt candidate >/dev/null 2>&1 &&
        [ "$(zapret_get_opt)" = candidate ] &&
        [ ! -e "${Z2M_TMP}/operation.lock" ]
)
check "a lock left by a dead process is removed and the operation proceeds" guard_removes_stale_lock

guard_removes_legacy_empty_lock() (
    fixture
    mkdir "${Z2M_TMP}/operation.lock"
    zapret_set_opt candidate >/dev/null 2>&1 &&
        [ "$(zapret_get_opt)" = candidate ] &&
        [ ! -e "${Z2M_TMP}/operation.lock" ]
)
check "a legacy lock without a PID is removed and the operation proceeds" guard_removes_legacy_empty_lock

# Keep the actual service functions for checks against failing executable hooks.
REAL_ZAPRET_START=$(sed -n '/^zapret_start() {/,/^}/p' "${ROOT}/core/zapret_service.sh")
REAL_ZAPRET_RESTART=$(sed -n '/^zapret_restart() {/,/^}/p' "${ROOT}/core/zapret_service.sh")
service_rejects_failed_hook() (
    fixture
    eval "${REAL_ZAPRET_START}"
    eval "${REAL_ZAPRET_RESTART}"
    ZAPRET2_INIT="${CASE_DIR}/init"
    printf '#!/bin/sh\nexit 1\n' > "${ZAPRET2_INIT}"
    chmod +x "${ZAPRET2_INIT}"
    # A leftover running process must not turn an init error into success.
    ! zapret_start && ! zapret_restart
)
check "start/restart reject failed init hooks even with a leftover process" service_rejects_failed_hook

service_rejects_failed_sync() (
    fixture
    eval "${REAL_ZAPRET_RESTART}"
    ZAPRET2_SYNC="${CASE_DIR}/sync"
    printf '#!/bin/sh\nexit 1\n' > "${ZAPRET2_SYNC}"
    chmod +x "${ZAPRET2_SYNC}"
    ! zapret_restart
)
check "restart reports sync_config failure rather than success" service_rejects_failed_sync

doh_uses_correct_section() (
    fixture
    local existing="$1"
    uci() {
        [ "${1:-}" != -q ] || shift
        case "$1" in
            get) [ "${existing}" = yes ] ;;
            add) echo cfg123 ;;
            set) printf '%s\n' "$2" >> "${CASE_DIR}/uci-writes" ;;
            *) return 1 ;;
        esac
    }
    dns_configure_doh_section '8.8.8.8' 'https://dns.google/dns-query' || return 1
    local expected='https-dns-proxy.cfg123'
    [ "${existing}" != yes ] || expected='https-dns-proxy.@https-dns-proxy[0]'
    [ "$(wc -l < "${CASE_DIR}/uci-writes" | tr -d ' ')" -eq 5 ] &&
        grep -Fq "${expected}.resolver_url=https://dns.google/dns-query" "${CASE_DIR}/uci-writes"
)
check "DoH updates primary section without deleting or appending empty resolvers" doh_uses_correct_section yes
check "DoH uses UCI's returned section ID when creating a resolver" doh_uses_correct_section no

dpi_blocked() (
    Z2M_TMP="${TMP_ROOT}/runtime"
    FAKE_HTTP_CODE="$1" FAKE_BODY="$2"
    export FAKE_HTTP_CODE FAKE_BODY
    [ "$(probe_dpi_verdict example.org)" = Blocked ]
)
check "DPI verdict detects HTTP 451 rather than Clean" dpi_blocked 451 clean
check "DPI verdict detects HTTP 200 block pages" dpi_blocked 200 blocked

tls12_flags() (
    Z2M_TMP="${TMP_ROOT}/runtime"
    FAKE_HTTP_CODE=200 FAKE_BODY=clean
    CURL_ARGS="${TMP_ROOT}/tls12-args"
    export CURL_ARGS FAKE_HTTP_CODE FAKE_BODY
    probe_tls12 example.org 443 1 || return 1
    grep -qx -- --tlsv1.2 "${CURL_ARGS}" &&
        grep -qx -- --tls-max "${CURL_ARGS}" && grep -qx '1.2' "${CURL_ARGS}"
)
check "TLS 1.2 probe sets both minimum and maximum using separate arguments" tls12_flags

combo_http_profile() (
    fixture
    local args single
    args=$(combo_build_args safe safe) || return 1
    single=$(combo_build_single_test_args safe) || return 1
    echo "${args}" | grep -q -- '--filter-tcp=80 --filter-l7=http' &&
        echo "${single}" | grep -q -- '--filter-tcp=80 --filter-l7=http' &&
        echo "${single}" | grep -q -- '--blob=tls_sber:'
)
check "combo and standalone rules include HTTP 80 and all candidate blobs" combo_http_profile

service_enable_toggle() (
    fixture
    UCI_CONFIG="${CASE_DIR}/uci_cfg"
    : > "${UCI_CONFIG}"
    uci() {
        case "$1" in
            set)
                local key="${2%%=*}" val="${2#*=}"
                echo "${key}=${val}" >> "${UCI_CONFIG}"
                ;;
            -q)
                grep -E "^${3}=" "${UCI_CONFIG}" 2>/dev/null | tail -n1 | cut -d'=' -f2-
                ;;
            commit) ;;
        esac
    }
    zapret_set_enabled 0 || return 1
    ! zapret_is_enabled || return 1
    grep -q 'NFQWS2_ENABLE="0"' "${ZAPRET2_CONFIG}" || return 1
    zapret_set_enabled 1 || return 1
    zapret_is_enabled || return 1
    grep -q 'NFQWS2_ENABLE="1"' "${ZAPRET2_CONFIG}"
)
check "zapret_set_enabled updates UCI, config and is reflected in zapret_is_enabled" service_enable_toggle

test_current_strategy_renders_ok() (
    fixture
    DIAGNOSTIC_HOSTS="test.host"
    probe_check_deps() { return 0; }
    probe_hosts_map() { echo "test.host 1"; }
    local out
    out=$(Z2M_NONINTERACTIVE=1 run_test_current_strategy 2>&1)
    echo "${out}" | grep -q "test.host.*OK.*OK"
)
check "run_test_current_strategy correctly displays OK status for accessible hosts" test_current_strategy_renders_ok

shell_syntax() {
    find "${ROOT}" -name '*.sh' -exec sh -n {} \; > "${TMP_ROOT}/syntax-log" 2>&1
    [ ! -s "${TMP_ROOT}/syntax-log" ]
}
check "all shell files pass sh -n" shell_syntax
