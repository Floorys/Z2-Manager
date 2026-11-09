#!/bin/sh
# shellcheck disable=SC3043
# Catalog selection shares one transaction and one scoring policy in every mode.
[ -z "${Z2M_DIR:-}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
. "${Z2M_DIR}/core/config.sh"
. "${Z2M_DIR}/core/tui.sh"
. "${Z2M_DIR}/core/probe.sh"
. "${Z2M_DIR}/core/zapret_service.sh"
. "${Z2M_DIR}/strategies/catalog.sh"

run_strategy_autoselect() {
    z2m_run_guarded catalog_autoselect "${ALL_PROBE_HOSTS}" "Автоподбор из каталога"
}

run_test_youtube_only() {
    z2m_run_guarded catalog_autoselect "${YOUTUBE_PROBE_HOSTS}" "Подбор для YouTube"
}

run_test_discord_only() {
    z2m_run_guarded catalog_autoselect "${DISCORD_PROBE_HOSTS}" "Подбор для Discord"
}

# Sum the two repeats, avoiding integer-average ties and false perfect results.
catalog_measure() {
    local first second
    first=$(probe_host_list "$1")
    sleep 1
    second=$(probe_host_list "$1")
    printf '%s\n%s\n' "${first}" "${second}" | awk '
        { ok += $1; total += $2; score += $3; maximum += $4 }
        END { print ok, total, score, maximum }
    '
}

catalog_autoselect() {
    local hosts="$1" title="$2"
    tui_banner
    tui_header "${title}"
    if ! zapret_is_installed; then
        tui_error "Пакет zapret2 не установлен!"
        return 1
    fi
    zapret_sync_fake_blobs || return 1
    zapret_sync_hostlists 0 || return 1

    local baseline result base_score base_fail
    tui_info "Замер текущей конфигурации теми же пробами (2 повтора)..."
    baseline=$(catalog_measure "${hosts}")
    base_score=$(echo "${baseline}" | awk '{print $3}')
    base_fail=$(echo "${baseline}" | awk '{print $2-$1}')
    tui_info "Baseline: ${base_score}, неуспешных проверок: ${base_fail}"
    tui_print_result_table_header

    local best_idx=0 best_score=-1 best_fail=999 i=1
    local name opt ok total score maximum fail
    while [ "${i}" -le "${CATALOG_COUNT}" ]; do
        name=$(catalog_get_name "${i}")
        opt=$(catalog_get_opt "${i}")
        if [ -z "${opt}" ] || ! zapret_set_opt "${opt}"; then
            tui_warn "${name}: не удалось применить; предыдущая конфигурация восстановлена."
            i=$((i + 1))
            continue
        fi
        result=$(catalog_measure "${hosts}")
        ok=$(echo "${result}" | awk '{print $1}')
        total=$(echo "${result}" | awk '{print $2}')
        score=$(echo "${result}" | awk '{print $3}')
        maximum=$(echo "${result}" | awk '{print $4}')
        fail=$((total - ok))
        tui_print_result_row "${name}" "${ok}" "${fail}" "${total}"
        if [ "${score}" -gt "${best_score}" ] || {
            [ "${score}" -eq "${best_score}" ] && [ "${fail}" -lt "${best_fail}" ];
        }; then
            best_idx="${i}"; best_score="${score}"; best_fail="${fail}"
        fi
        [ "${maximum}" -gt 0 ] && [ "${score}" -eq "${maximum}" ] && [ "${fail}" -eq 0 ] && break
        i=$((i + 1))
    done
    if [ "${best_score}" -le 0 ]; then
        tui_error "Ни одна стратегия не прошла проверки. Выполняется откат."
        return 1
    fi
    # Equal results also retain the user's configuration by default.
    if [ "${best_score}" -lt "${base_score}" ] || {
        [ "${best_score}" -eq "${base_score}" ] && [ "${best_fail}" -ge "${base_fail}" ];
    }; then
        local answer
        answer=$(tui_prompt "Результат не лучше baseline. Применить всё равно? [y/N]" "N")
        case "${answer}" in
            y|Y|yes|YES) ;;
            *) tui_info "Сохраняем исходную конфигурацию."; return 0 ;;
        esac
    fi
    opt=$(catalog_get_opt "${best_idx}")
    zapret_set_opt "${opt}" || return 1
    z2m_transaction_commit
    tui_success "Применена стратегия: $(catalog_get_name "${best_idx}")"
    tui_info "Проверены TCP/TLS; голосовой UDP-трафик проверяйте в Discord."
    tui_pause
}

run_test_current_strategy() {
    tui_banner
    tui_header "Проверка текущей стратегии"
    zapret_is_running || tui_warn "Служба zapret2 остановлена."
    tui_info "Параметры: $(zapret_get_opt)"
    printf '%-24s %-18s %-12s %-12s\n' "Хост" "Категория" "HTTP Доступ" "TLS"
    local h http tls
    for h in ${DIAGNOSTIC_HOSTS}; do
        http="Блок"; tls="Сбой"
        probe_http_reach "${h}" 2 && http="OK"
        probe_fast_tls "${h}" 443 2 && tls="OK"
        printf '%-24s %-18s %-12s %-12s\n' "${h}" "$(probe_get_host_category "${h}")" "${http}" "${tls}"
    done
    tui_pause
}
