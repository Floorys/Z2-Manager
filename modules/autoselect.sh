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
        tui_error "Пакет zapret2 не установлен в системе!"
        tui_pause
        return 1
    fi

    # Ensure required blobs and lists are in place
    zapret_sync_fake_blobs
    zapret_sync_hostlists

    # Backup current configuration
    local bak_file
    bak_file=$(zapret_backup_config)
    local interrupted=0

    cleanup_autoselect() {
        echo ""
        tui_warn "Прерывание! Восстанавливаем исходную конфигурацию..."
        zapret_restore_config "${bak_file}"
        rm -f "${bak_file}" 2>/dev/null
        trap - INT TERM
        interrupted=1
    }
    trap cleanup_autoselect INT TERM

    tui_print_result_table_header

    local best_idx=1
    local best_score=-1
    local best_fail=999

    local i=1
    while [ "${i}" -le "${CATALOG_COUNT}" ]; do
        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        local name tagline opt
        name=$(catalog_get_name "${i}")
        tagline=$(catalog_get_tagline "${i}")
        opt=$(catalog_get_opt "${i}")

        if [ -z "${opt}" ]; then
            i=$(( i + 1 ))
            continue
        fi

        local short_name
        short_name=$(printf "%.34s" "${name}")
        printf "%-36s ${YELLOW}%-10s${NC} ${DGRAY}%-10s${NC} ${YELLOW}⏳ Тест...${NC}\r" "${short_name}" "..." "..."

        # Apply candidate strategy
        zapret_set_opt "${opt}"

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        if ! zapret_is_running; then
            tui_print_result_row "${name}" "0" "2" "2"
            i=$(( i + 1 ))
            continue
        fi

        # Fast probe of goal hosts
        local p_res
        p_res=$(probe_host_list "${ALL_PROBE_HOSTS}")

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        local ok tot score max_score
        ok=$(echo "${p_res}" | awk '{print $1}')
        tot=$(echo "${p_res}" | awk '{print $2}')
        score=$(echo "${p_res}" | awk '{print $3}')
        max_score=$(echo "${p_res}" | awk '{print $4}')

        local fail=$(( tot - ok ))

        # Print table row replacing the temporary status
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

    if [ "${interrupted}" -eq 1 ]; then
        tui_pause
        return 0
    fi

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
    tui_info "Конфигурация успешно сохранена и работает."
    tui_pause
}

run_test_youtube_only() {
    tui_banner
    tui_header "▶️ Тестирование стратегий для YouTube"
    tui_info "Проверка стратегий каталога на доступность YouTube..."
    echo ""

    if ! zapret_is_installed; then
        tui_error "Пакет zapret2 не установлен в системе!"
        tui_pause
        return 1
    fi

    local bak_file
    bak_file=$(zapret_backup_config)
    local interrupted=0

    cleanup_yt() {
        echo ""
        tui_warn "Прерывание! Восстанавливаем исходную конфигурацию..."
        zapret_restore_config "${bak_file}"
        rm -f "${bak_file}" 2>/dev/null
        trap - INT TERM
        interrupted=1
    }
    trap cleanup_yt INT TERM

    tui_print_result_table_header

    local best_idx=1
    local best_score=-1

    local i=1
    while [ "${i}" -le "${CATALOG_COUNT}" ]; do
        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        local name opt
        name=$(catalog_get_name "${i}")
        opt=$(catalog_get_opt "${i}")

        local short_name
        short_name=$(printf "%.34s" "${name}")
        printf "%-36s ${YELLOW}%-10s${NC} ${DGRAY}%-10s${NC} ${YELLOW}⏳ Тест...${NC}\r" "${short_name}" "..." "..."

        zapret_set_opt "${opt}"

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        if ! zapret_is_running; then
            tui_print_result_row "${name}" "0" "2" "2"
            i=$(( i + 1 ))
            continue
        fi

        local p_res ok tot score
        p_res=$(probe_host_list "${YOUTUBE_PROBE_HOSTS}")

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        ok=$(echo "${p_res}" | awk '{print $1}')
        tot=$(echo "${p_res}" | awk '{print $2}')
        score=$(echo "${p_res}" | awk '{print $3}')

        local fail=$(( tot - ok ))
        tui_print_result_row "${name}" "${ok}" "${fail}" "${tot}"

        if [ "${best_score}" -eq -1 ] || [ "${score}" -gt "${best_score}" ]; then
            best_score="${score}"
            best_idx="${i}"
        fi

        [ "${fail}" -eq 0 ] && break

        i=$(( i + 1 ))
    done

    if [ "${interrupted}" -eq 1 ]; then
        tui_pause
        return 0
    fi

    local win_name win_opt
    win_name=$(catalog_get_name "${best_idx}")
    win_opt=$(catalog_get_opt "${best_idx}")
    zapret_set_opt "${win_opt}"
    rm -f "${bak_file}" 2>/dev/null
    trap - INT TERM

    echo ""
    tui_success "Выбрана лучшая стратегия для YouTube: ${win_name}"
    tui_pause
}

run_test_discord_only() {
    tui_banner
    tui_header "💬 Тестирование стратегий для Discord"
    tui_info "Проверка стратегий каталога на доступность Discord..."
    echo ""

    if ! zapret_is_installed; then
        tui_error "Пакет zapret2 не установлен в системе!"
        tui_pause
        return 1
    fi

    local bak_file
    bak_file=$(zapret_backup_config)
    local interrupted=0

    cleanup_dc() {
        echo ""
        tui_warn "Прерывание! Восстанавливаем исходную конфигурацию..."
        zapret_restore_config "${bak_file}"
        rm -f "${bak_file}" 2>/dev/null
        trap - INT TERM
        interrupted=1
    }
    trap cleanup_dc INT TERM

    tui_print_result_table_header

    local best_idx=1
    local best_score=-1

    local i=1
    while [ "${i}" -le "${CATALOG_COUNT}" ]; do
        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        local name opt
        name=$(catalog_get_name "${i}")
        opt=$(catalog_get_opt "${i}")

        local short_name
        short_name=$(printf "%.34s" "${name}")
        printf "%-36s ${YELLOW}%-10s${NC} ${DGRAY}%-10s${NC} ${YELLOW}⏳ Тест...${NC}\r" "${short_name}" "..." "..."

        zapret_set_opt "${opt}"

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        if ! zapret_is_running; then
            tui_print_result_row "${name}" "0" "2" "2"
            i=$(( i + 1 ))
            continue
        fi

        local p_res ok tot score
        p_res=$(probe_host_list "${DISCORD_PROBE_HOSTS}")

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        ok=$(echo "${p_res}" | awk '{print $1}')
        tot=$(echo "${p_res}" | awk '{print $2}')
        score=$(echo "${p_res}" | awk '{print $3}')

        local fail=$(( tot - ok ))
        tui_print_result_row "${name}" "${ok}" "${fail}" "${tot}"

        if [ "${best_score}" -eq -1 ] || [ "${score}" -gt "${best_score}" ]; then
            best_score="${score}"
            best_idx="${i}"
        fi

        [ "${fail}" -eq 0 ] && break

        i=$(( i + 1 ))
    done

    if [ "${interrupted}" -eq 1 ]; then
        tui_pause
        return 0
    fi

    local win_name win_opt
    win_name=$(catalog_get_name "${best_idx}")
    win_opt=$(catalog_get_opt "${best_idx}")
    zapret_set_opt "${win_opt}"
    rm -f "${bak_file}" 2>/dev/null
    trap - INT TERM

    echo ""
    tui_success "Выбрана лучшая стратегия для Discord: ${win_name}"
    tui_pause
}

run_test_current_strategy() {
    tui_banner
    tui_header "🔍 Проверка текущей активной стратегии"

    if ! zapret_is_running; then
        tui_warn "Служба zapret2 в данный момент остановлена!"
    fi

    local cur_opt
    cur_opt=$(zapret_get_opt)
    printf "  ${BOLD}Текущие параметры:${NC} ${CYAN}%s${NC}\n\n" "${cur_opt:-по умолчанию}"

    tui_header "Результаты проверки доступности:"
    printf "${BOLD}%-28s %-10s %-10s %-12s${NC}\n" "Хост" "TLS 1.2" "TLS 1.3" "HTTP Доступ"
    printf "${DGRAY}───────────────────────────────────────────────────────────────────${NC}\n"

    for h in ${ALL_PROBE_HOSTS}; do
        local s_t12="✗" c_t12="${RED}"
        local s_t13="✗" c_t13="${RED}"
        local s_http="✗" c_http="${RED}"

        probe_tls12 "${h}" && { s_t12="✓"; c_t12="${GREEN}"; }
        probe_tls13 "${h}" && { s_t13="✓"; c_t13="${GREEN}"; }
        probe_http_reach "${h}" && { s_http="✓"; c_http="${GREEN}"; }

        printf "%-28s ${c_t12}%-10s${NC} ${c_t13}%-10s${NC} ${c_http}%-12s${NC}\n" \
            "${h}" "${s_t12}" "${s_t13}" "${s_http}"
    done

    echo ""
    tui_pause
}
