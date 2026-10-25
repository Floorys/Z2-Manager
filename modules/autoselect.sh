#!/bin/sh
# shellcheck disable=SC3043
# ==============================================================================
# Zapret2-Manager: Strategy Auto-Selector Module
# Tests curated catalog presets against goal endpoints
# ==============================================================================

[ -z "${Z2M_DIR:-}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"
[ -f "${Z2M_DIR}/core/tui.sh" ] && . "${Z2M_DIR}/core/tui.sh"
[ -f "${Z2M_DIR}/core/probe.sh" ] && . "${Z2M_DIR}/core/probe.sh"
[ -f "${Z2M_DIR}/core/zapret_service.sh" ] && . "${Z2M_DIR}/core/zapret_service.sh"
[ -f "${Z2M_DIR}/strategies/catalog.sh" ] && . "${Z2M_DIR}/strategies/catalog.sh"

run_strategy_autoselect() {
    tui_banner
    tui_header "⚡ Автоподбор лучшей стратегии из каталога"

    tui_info "Этот режим последовательно проверяет ${CATALOG_COUNT} проверенных стратегий каталога,"
    tui_info "оценивает их работу на YouTube и Discord (с повторами) и выбирает лучшую."
    echo ""

    tui_info "Тестирование доступности выполняется напрямую с роутера (протоколы TCP/TLS)."
    if [ -n "${CURL_INTERFACE:-}" ]; then
        tui_info "Используется сетевой интерфейс: ${CURL_INTERFACE}"
    fi
    echo ""

    if ! zapret_is_installed; then
        tui_error "Пакет zapret2 не установлен в системе!"
        tui_pause
        return 1
    fi

    # Ensure required blobs and lists are in place
    zapret_sync_fake_blobs
    zapret_sync_hostlists

    # Backup current configuration BEFORE any modification
    local bak_file
    bak_file=$(zapret_backup_config)
    local interrupted=0

    cleanup_autoselect() {
        echo ""
        tui_warn "Прерывание! Восстанавливаем исходную конфигурацию..."
        zapret_restore_config "${bak_file}"
        rm -f "${bak_file}" 2>/dev/null
        trap - INT TERM HUP
        interrupted=1
    }
    trap cleanup_autoselect INT TERM HUP

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

        local name opt
        name=$(catalog_get_name "${i}")
        opt=$(catalog_get_opt "${i}")

        if [ -z "${opt}" ]; then
            i=$(( i + 1 ))
            continue
        fi

        local short_name
        short_name=$(printf "%.34s" "${name}")
        printf "%-36s %b%-10s%b %b%-10s%b %b⏳ Тест...%b\r" \
            "${short_name}" "${YELLOW}" "..." "${NC}" "${DGRAY}" "..." "${NC}" "${YELLOW}" "${NC}"

        # Apply candidate strategy (zapret_set_opt includes restart and 2s pause)
        zapret_set_opt "${opt}"

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        if ! zapret_is_running; then
            tui_print_result_row "${name}" "0" "5" "5"
            i=$(( i + 1 ))
            continue
        fi

        # Probe goal hosts with 2 repeats for stability
        local p_res1 p_res2
        p_res1=$(probe_host_list "${ALL_PROBE_HOSTS}")
        sleep 1
        p_res2=$(probe_host_list "${ALL_PROBE_HOSTS}")

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        local ok1 tot1 score1 ok2 score2
        ok1=$(echo "${p_res1}" | awk '{print $1}')
        tot1=$(echo "${p_res1}" | awk '{print $2}')
        score1=$(echo "${p_res1}" | awk '{print $3}')

        ok2=$(echo "${p_res2}" | awk '{print $1}')
        score2=$(echo "${p_res2}" | awk '{print $3}')

        # Combined average score
        local ok=$(( (ok1 + ok2) / 2 ))
        local score=$(( (score1 + score2) / 2 ))
        local tot="${tot1}"
        local fail=$(( tot - ok ))

        # Print table row replacing the temporary status
        tui_print_result_row "${name}" "${ok}" "${fail}" "${tot}"

        # Compare with best score
        if [ "${best_score}" -eq -1 ] || [ "${score}" -gt "${best_score}" ] || { [ "${score}" -eq "${best_score}" ] && [ "${fail}" -lt "${best_fail}" ]; }; then
            best_score="${score}"
            best_fail="${fail}"
            best_idx="${i}"
        fi

        # Early exit if candidate passed 100% of all checks on both repeats
        if [ "${fail}" -eq 0 ] && [ "${score}" -ge 25 ]; then
            tui_success "Стратегия #${i} («${name}») показала 100% результат! Ранний выход."
            break
        fi

        i=$(( i + 1 ))
    done

    if [ "${interrupted}" -eq 1 ]; then
        tui_pause
        return 0
    fi

    # If no strategy passed threshold (> 0), restore backup and inform user
    if [ "${best_score}" -le 0 ]; then
        echo ""
        tui_error "Ни одна стратегия из каталога не прошла проверки доступности!"
        tui_warn "Восстанавливаем исходную конфигурацию..."
        zapret_restore_config "${bak_file}"
        rm -f "${bak_file}" 2>/dev/null
        trap - INT TERM HUP
        tui_info "Рекомендация: проверьте DNS (DoH в меню 6) или запустите полный генератор (z2m -g)."
        tui_pause
        return 1
    fi

    # Apply the winning strategy
    local win_name win_opt win_tagline
    win_name=$(catalog_get_name "${best_idx}")
    win_tagline=$(catalog_get_tagline "${best_idx}")
    win_opt=$(catalog_get_opt "${best_idx}")

    zapret_set_opt "${win_opt}"

    # Remove temporary backup and clear trap
    rm -f "${bak_file}" 2>/dev/null
    trap - INT TERM HUP

    echo ""
    tui_header "🏆 Лучшая стратегия определена и применена!"
    tui_success "Название : ${win_name}"
    [ -n "${win_tagline}" ] && tui_info "Описание : ${win_tagline}"
    tui_info "Конфигурация успешно сохранена и работает."
    echo ""
    tui_info "Примечание: Проверка curl тестирует только TCP/TLS веб-трафик."
    tui_info "Для голосовых звонков Discord примените фикс: Главное меню -> Пункт 4."
    echo ""
    tui_pause
}

run_test_youtube_only() {
    tui_banner
    tui_header "▶️ Тестирование стратегий для YouTube"
    tui_info "Проверка стратегий каталога на доступность YouTube (с повторами)..."
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
        trap - INT TERM HUP
        interrupted=1
    }
    trap cleanup_yt INT TERM HUP

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
        printf "%-36s %b%-10s%b %b%-10s%b %b⏳ Тест...%b\r" \
            "${short_name}" "${YELLOW}" "..." "${NC}" "${DGRAY}" "..." "${NC}" "${YELLOW}" "${NC}"

        zapret_set_opt "${opt}"

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        if ! zapret_is_running; then
            tui_print_result_row "${name}" "0" "3" "3"
            i=$(( i + 1 ))
            continue
        fi

        local p_res1 p_res2
        p_res1=$(probe_host_list "${YOUTUBE_PROBE_HOSTS}")
        sleep 1
        p_res2=$(probe_host_list "${YOUTUBE_PROBE_HOSTS}")

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        local ok1 tot1 score1 ok2 score2
        ok1=$(echo "${p_res1}" | awk '{print $1}')
        tot1=$(echo "${p_res1}" | awk '{print $2}')
        score1=$(echo "${p_res1}" | awk '{print $3}')

        ok2=$(echo "${p_res2}" | awk '{print $1}')
        score2=$(echo "${p_res2}" | awk '{print $3}')

        local ok=$(( (ok1 + ok2) / 2 ))
        local score=$(( (score1 + score2) / 2 ))
        local tot="${tot1}"
        local fail=$(( tot - ok ))

        tui_print_result_row "${name}" "${ok}" "${fail}" "${tot}"

        if [ "${best_score}" -eq -1 ] || [ "${score}" -gt "${best_score}" ]; then
            best_score="${score}"
            best_idx="${i}"
        fi

        [ "${fail}" -eq 0 ] && [ "${score}" -ge 15 ] && break

        i=$(( i + 1 ))
    done

    if [ "${interrupted}" -eq 1 ]; then
        tui_pause
        return 0
    fi

    if [ "${best_score}" -le 0 ]; then
        tui_error "Ни одна стратегия для YouTube не сработала!"
        zapret_restore_config "${bak_file}"
        rm -f "${bak_file}" 2>/dev/null
        trap - INT TERM HUP
        tui_pause
        return 1
    fi

    local win_name win_opt
    win_name=$(catalog_get_name "${best_idx}")
    win_opt=$(catalog_get_opt "${best_idx}")
    zapret_set_opt "${win_opt}"
    rm -f "${bak_file}" 2>/dev/null
    trap - INT TERM HUP

    echo ""
    tui_success "Выбрана лучшая стратегия для YouTube: ${win_name}"
    tui_pause
}

run_test_discord_only() {
    tui_banner
    tui_header "💬 Тестирование стратегий для Discord"
    tui_info "Проверка стратегий каталога на доступность Discord (с повторами)..."
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
        trap - INT TERM HUP
        interrupted=1
    }
    trap cleanup_dc INT TERM HUP

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
        printf "%-36s %b%-10s%b %b%-10s%b %b⏳ Тест...%b\r" \
            "${short_name}" "${YELLOW}" "..." "${NC}" "${DGRAY}" "..." "${NC}" "${YELLOW}" "${NC}"

        zapret_set_opt "${opt}"

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        if ! zapret_is_running; then
            tui_print_result_row "${name}" "0" "3" "3"
            i=$(( i + 1 ))
            continue
        fi

        local p_res1 p_res2
        p_res1=$(probe_host_list "${DISCORD_PROBE_HOSTS}")
        sleep 1
        p_res2=$(probe_host_list "${DISCORD_PROBE_HOSTS}")

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        local ok1 tot1 score1 ok2 score2
        ok1=$(echo "${p_res1}" | awk '{print $1}')
        tot1=$(echo "${p_res1}" | awk '{print $2}')
        score1=$(echo "${p_res1}" | awk '{print $3}')

        ok2=$(echo "${p_res2}" | awk '{print $1}')
        score2=$(echo "${p_res2}" | awk '{print $3}')

        local ok=$(( (ok1 + ok2) / 2 ))
        local score=$(( (score1 + score2) / 2 ))
        local tot="${tot1}"
        local fail=$(( tot - ok ))

        tui_print_result_row "${name}" "${ok}" "${fail}" "${tot}"

        if [ "${best_score}" -eq -1 ] || [ "${score}" -gt "${best_score}" ]; then
            best_score="${score}"
            best_idx="${i}"
        fi

        [ "${fail}" -eq 0 ] && [ "${score}" -ge 15 ] && break

        i=$(( i + 1 ))
    done

    if [ "${interrupted}" -eq 1 ]; then
        tui_pause
        return 0
    fi

    if [ "${best_score}" -le 0 ]; then
        tui_error "Ни одна стратегия для Discord не сработала!"
        zapret_restore_config "${bak_file}"
        rm -f "${bak_file}" 2>/dev/null
        trap - INT TERM HUP
        tui_pause
        return 1
    fi

    local win_name win_opt
    win_name=$(catalog_get_name "${best_idx}")
    win_opt=$(catalog_get_opt "${best_idx}")
    zapret_set_opt "${win_opt}"
    rm -f "${bak_file}" 2>/dev/null
    trap - INT TERM HUP

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
    local short_opt
    short_opt=$(printf "%.50s" "${cur_opt}")
    [ ${#cur_opt} -gt 50 ] && short_opt="${short_opt}..."
    printf "  %bТекущие параметры:%b %b%s%b\n\n" "${BOLD}" "${NC}" "${CYAN}" "${short_opt:-по умолчанию}" "${NC}"

    tui_header "Результаты проверки доступности (набор сервисов):"
    printf "%b%-24s %-18s %-12s %-12s%b\n" "${BOLD}" "Хост" "Категория" "HTTP Доступ" "TLS Рукопожатие" "${NC}"
    printf "%b───────────────────────────────────────────────────────────────────%b\n" "${DGRAY}" "${NC}"

    for h in ${DIAGNOSTIC_HOSTS}; do
        local cat_name
        cat_name=$(probe_get_host_category "${h}")
        local ok_http=0 ok_tls=0
        probe_http_reach "${h}" 2 && ok_http=1
        probe_fast_tls "${h}" 443 2 && ok_tls=1

        printf "%-24s %-18s " "${h}" "${cat_name}"
        if [ "${ok_http}" -eq 1 ]; then
            printf "%b%-12s%b " "${GREEN}" "✓ OK" "${NC}"
        else
            printf "%b%-12s%b " "${RED}" "✗ Блок" "${NC}"
        fi
        if [ "${ok_tls}" -eq 1 ]; then
            printf "%b%-12s%b\n" "${GREEN}" "✓ OK" "${NC}"
        else
            printf "%b%-12s%b\n" "${RED}" "✗ Сбой" "${NC}"
        fi
    done

    echo ""
    tui_pause
}
