#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Strategy Auto-Selector Module
# Port of AutoSelectService.cs from Asterlike/zapret2UI
# Tests curated catalog presets against goal endpoints
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
. "${Z2M_DIR}/core/config.sh"
. "${Z2M_DIR}/core/tui.sh"
. "${Z2M_DIR}/core/probe.sh"
. "${Z2M_DIR}/core/zapret_service.sh"
. "${Z2M_DIR}/strategies/catalog.sh"

run_strategy_autoselect() {
    tui_banner
    tui_header "⚡ Автоподбор лучшей стратегии из каталога"

    tui_info "Этот режим последовательно проверяет ${CATALOG_COUNT} проверенных стратегий каталога,"
    tui_info "оценивает их работу на YouTube и Discord, и выбирает лучшую для вашего провайдера."
    echo ""

    if ! zapret_is_installed; then
        tui_error "Пакет zapret2 не установлен в /opt/zapret2!"
        tui_pause
        return 1
    fi

    # Ensure required blobs and lists are in place
    zapret_sync_fake_blobs
    zapret_sync_hostlists

    # Backup current configuration
    local bak_file
    bak_file=$(zapret_backup_config)

    # Trap Ctrl+C to safely restore configuration on abort
    trap 'echo ""; tui_warn "Прерывание! Восстанавливаем исходную конфигурацию..."; zapret_restore_config "'"${bak_file}"'"; exit 130' INT TERM

    tui_print_result_table_header

    local best_idx=1
    local best_score=-1
    local best_fail=999

    local i=1
    while [ "${i}" -le "${CATALOG_COUNT}" ]; do
        local name
        local tagline
        local opt
        name=$(catalog_get_name "${i}")
        tagline=$(catalog_get_tagline "${i}")
        opt=$(catalog_get_opt "${i}")

        if [ -z "${opt}" ]; then
            i=$(( i + 1 ))
            continue
        fi

        # Apply candidate strategy
        zapret_set_opt "${opt}"

        # Probe all goal hosts
        local p_res
        p_res=$(probe_host_list "${ALL_PROBE_HOSTS}")
        local ok tot score max_score
        ok=$(echo "${p_res}" | awk '{print $1}')
        tot=$(echo "${p_res}" | awk '{print $2}')
        score=$(echo "${p_res}" | awk '{print $3}')
        max_score=$(echo "${p_res}" | awk '{print $4}')

        local fail=$(( tot - ok ))

        # Print table row
        tui_print_result_row "${name}" "${ok}" "${fail}" "${tot}"

        # Compare with best score
        if [ "${best_score}" -eq -1 ] || [ "${score}" -gt "${best_score}" ] || { [ "${score}" -eq "${best_score}" ] && [ "${fail}" -lt "${best_fail}" ]; }; then
            best_score="${score}"
            best_fail="${fail}"
            best_idx="${i}"
        fi

        # Early exit if candidate passed 100% of all checks
        if [ "${fail}" -eq 0 ]; then
            tui_success "Стратегия #${i} («${name}») показала 100% результат! Ранний выход."
            break
        fi

        i=$(( i + 1 ))
    done

    # Apply the winning strategy
    local win_name win_opt win_tagline
    win_name=$(catalog_get_name "${best_idx}")
    win_tagline=$(catalog_get_tagline "${best_idx}")
    win_opt=$(catalog_get_opt "${best_idx}")

    zapret_set_opt "${win_opt}"

    # Remove temporary backup
    rm -f "${bak_file}" 2>/dev/null
    trap - INT TERM

    echo ""
    tui_header "🏆 Лучшая стратегия определена и применена!"
    tui_success "Название : ${win_name}"
    [ -n "${win_tagline}" ] && tui_info "Описание : ${win_tagline}"
    tui_info "Конфигурация успешно сохранена в /etc/config/zapret2."
    tui_pause
}
