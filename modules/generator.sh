#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Strategy Generator Module
# Port of StrategyGeneratorService.cs from Asterlike/zapret2UI
# Two-Pass Tailored Strategy Generation (Discord vs YouTube)
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
. "${Z2M_DIR}/core/config.sh"
. "${Z2M_DIR}/core/tui.sh"
. "${Z2M_DIR}/core/probe.sh"
. "${Z2M_DIR}/core/combo_builder.sh"
. "${Z2M_DIR}/core/zapret_service.sh"
. "${Z2M_DIR}/strategies/candidates.sh"

run_strategy_generator() {
    tui_banner
    tui_header "🧬 Генератор персональной стратегии (Asterlike Two-Pass Generator)"

    tui_info "Этот режим подбирает уникальную связку десинка:"
    tui_info "1. Pass 1: перебор кандидатов раздельно для Discord и YouTube."
    tui_info "2. Pass 2: совместное тестирование лучших пар с учетом Gateway Discord."
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

    cleanup_generator() {
        echo ""
        tui_warn "Прерывание генератора! Восстанавливаем исходную конфигурацию..."
        zapret_restore_config "${bak_file}"
        rm -f "${bak_file}" 2>/dev/null
        trap - INT TERM
        interrupted=1
    }
    trap cleanup_generator INT TERM

    tui_info "Исходная конфигурация сохранена."
    tui_info "Запуск Pass 1: тестирование ${CANDIDATES_COUNT} десинк-бандлов..."
    echo ""
    tui_print_result_result_header() {
        printf "${BOLD}%-4s %-32s %-12s %-12s %-8s${NC}\n" "№" "Кандидат" "Discord" "YouTube" "GW-Safe"
        printf "${DGRAY}───────────────────────────────────────────────────────────────────${NC}\n"
    }
    tui_print_result_result_header

    local cand_scores_d=""
    local cand_scores_y=""
    local perfect_cand=0

    # ---- PASS 1: Fast TLS screening of each bundle for Discord & YouTube ----
    local i=1
    while [ "${i}" -le "${CANDIDATES_COUNT}" ]; do
        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        local c_name c_tls
        c_name=$(get_candidate_name "${i}")
        c_tls=$(get_candidate_tls "${i}")

        local gw_safe="Нет"
        if is_gateway_friendly "${c_tls}"; then
            gw_safe="${GREEN}Да${NC}"
        fi

        local short_name
        short_name=$(printf "%.30s" "${c_name}")

        printf "%-4s %-32s ${YELLOW}⏳ Тест...${NC}\r" "${i}" "${short_name}"

        # Apply candidate as standalone test rule
        local test_opt
        test_opt=$(combo_build_single_test_args "${c_tls}")
        zapret_set_opt "${test_opt}"

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        # If daemon crashed or failed to start, score 0 and move on immediately
        if ! zapret_is_running; then
            printf "%-4s %-32s ${RED}%-12s${NC} ${RED}%-12s${NC} %b\n" \
                "${i}" "${short_name}" "Сбой" "Сбой" "${gw_safe}"
            cand_scores_d="${cand_scores_d} ${i}:0"
            cand_scores_y="${cand_scores_y} ${i}:0"
            i=$(( i + 1 ))
            continue
        fi

        # Fast probes on key Discord endpoints (Web + Voice/GW + CDN)
        local d_score=0
        probe_http_reach "discord.com" 2 && d_score=$(( d_score + 1 ))
        probe_fast_tls "gateway.discord.gg" 443 2 && d_score=$(( d_score + 1 ))
        probe_fast_tls "cdn.discordapp.com" 443 2 && d_score=$(( d_score + 1 ))

        # Fast probes on key YouTube endpoints (Web + Video CDN + Preview CDN)
        local y_score=0
        probe_http_reach "www.youtube.com" 2 && y_score=$(( y_score + 1 ))
        probe_fast_tls "googlevideo.com" 443 2 && y_score=$(( y_score + 1 ))
        probe_fast_tls "i.ytimg.com" 443 2 && y_score=$(( y_score + 1 ))

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        local d_col="${RED}"
        [ "${d_score}" -gt 0 ] && d_col="${YELLOW}"
        [ "${d_score}" -eq 3 ] && d_col="${GREEN}"

        local y_col="${RED}"
        [ "${y_score}" -gt 0 ] && y_col="${YELLOW}"
        [ "${y_score}" -eq 3 ] && y_col="${GREEN}"

        printf "%-4s %-32s ${d_col}%s/3${NC}        ${y_col}%s/3${NC}        %b\n" \
            "${i}" "${short_name}" "${d_score}" "${y_score}" "${gw_safe}"

        # Save scores (format: "index:d_score" / "index:y_score")
        cand_scores_d="${cand_scores_d} ${i}:${d_score}"
        cand_scores_y="${cand_scores_y} ${i}:${y_score}"

        # Early exit check: 100% on everything and gateway-friendly
        if [ "${d_score}" -eq 3 ] && [ "${y_score}" -eq 3 ] && is_gateway_friendly "${c_tls}"; then
            tui_success "Найден отличный универсальный бандл #${i} (${c_name})! Переход к сборке."
            perfect_cand="${i}"
            break
        fi

        i=$(( i + 1 ))
    done

    if [ "${interrupted}" -eq 1 ]; then
        tui_pause
        return 0
    fi

    echo ""
    tui_header "Pass 2: Сборка и совместная проверка лучших сочетаний"

    # Select top candidates
    local top_d_list=""
    local top_y_list=""

    if [ "${perfect_cand}" -gt 0 ]; then
        top_d_list="${perfect_cand}"
        top_y_list="${perfect_cand}"
    else
        # Find top 3 Discord candidates (prioritizing gateway-friendly)
        local sorted_d
        sorted_d=$(echo "${cand_scores_d}" | tr ' ' '\n' | grep ":" | sort -t: -k2 -nr)

        local d_count=0
        for entry in ${sorted_d}; do
            local idx
            idx=$(echo "${entry}" | cut -d: -f1)
            local tls
            tls=$(get_candidate_tls "${idx}")
            if is_gateway_friendly "${tls}"; then
                top_d_list="${top_d_list} ${idx}"
                d_count=$(( d_count + 1 ))
                [ "${d_count}" -ge 3 ] && break
            fi
        done

        if [ "${d_count}" -eq 0 ]; then
            top_d_list=$(echo "${sorted_d}" | head -n3 | cut -d: -f1 | tr '\n' ' ')
        fi

        local sorted_y
        sorted_y=$(echo "${cand_scores_y}" | tr ' ' '\n' | grep ":" | sort -t: -k2 -nr)
        top_y_list=$(echo "${sorted_y}" | head -n3 | cut -d: -f1 | tr '\n' ' ')
    fi

    local best_min=-1
    local best_sum=-1
    local best_d_idx=1
    local best_y_idx=1
    local attempt=0
    local max_tests=5

    for d_idx in ${top_d_list}; do
        for y_idx in ${top_y_list}; do
            if [ "${interrupted}" -eq 1 ]; then
                tui_pause
                return 0
            fi

            attempt=$(( attempt + 1 ))
            [ "${attempt}" -gt "${max_tests}" ] && break

            local d_name y_name d_tls y_tls
            d_name=$(get_candidate_name "${d_idx}")
            y_name=$(get_candidate_name "${y_idx}")
            d_tls=$(get_candidate_tls "${d_idx}")
            y_tls=$(get_candidate_tls "${y_idx}")

            tui_info "Проверка сочетания [${attempt}]: Discord: «${d_name}» + YouTube: «${y_name}»..."

            local combo_args
            combo_args=$(combo_build_args "${d_tls}" "${y_tls}" "${d_tls}")
            zapret_set_opt "${combo_args}"

            if [ "${interrupted}" -eq 1 ]; then
                tui_pause
                return 0
            fi

            # Probe Discord & YouTube together
            local cd_res cy_res
            cd_res=$(probe_host_list "${DISCORD_PROBE_HOSTS}")
            cy_res=$(probe_host_list "${YOUTUBE_PROBE_HOSTS}")

            if [ "${interrupted}" -eq 1 ]; then
                tui_pause
                return 0
            fi

            local cd_score cy_score
            cd_score=$(echo "${cd_res}" | awk '{print $3}')
            cy_score=$(echo "${cy_res}" | awk '{print $3}')

            local cur_min
            if [ "${cd_score}" -le "${cy_score}" ]; then
                cur_min="${cd_score}"
            else
                cur_min="${cy_score}"
            fi
            local cur_sum=$(( cd_score + cy_score ))

            printf "  -> Результат: Discord: %s/15, YouTube: %s/15 (Min: %s, Sum: %s)\n" \
                "${cd_score}" "${cy_score}" "${cur_min}" "${cur_sum}"

            if [ "${cur_min}" -gt "${best_min}" ] || { [ "${cur_min}" -eq "${best_min}" ] && [ "${cur_sum}" -gt "${best_sum}" ]; }; then
                best_min="${cur_min}"
                best_sum="${cur_sum}"
                best_d_idx="${d_idx}"
                best_y_idx="${y_idx}"
            fi

            if [ "${cur_min}" -ge 15 ]; then
                break
            fi
        done
        [ "${attempt}" -gt "${max_tests}" ] && break
    done

    if [ "${interrupted}" -eq 1 ]; then
        tui_pause
        return 0
    fi

    # Build and permanently apply winning strategy
    local win_d_name win_y_name win_d_tls win_y_tls
    win_d_name=$(get_candidate_name "${best_d_idx}")
    win_y_name=$(get_candidate_name "${best_y_idx}")
    win_d_tls=$(get_candidate_tls "${best_d_idx}")
    win_y_tls=$(get_candidate_tls "${best_y_idx}")

    local final_opt
    final_opt=$(combo_build_args "${win_d_tls}" "${win_y_tls}" "${win_d_tls}")
    zapret_set_opt "${final_opt}"

    # Remove temporary backup
    rm -f "${bak_file}" 2>/dev/null
    trap - INT TERM

    echo ""
    tui_header "✨ Итоговая персональная стратегия сгенерирована!"
    tui_success "Discord профиль : ${win_d_name}"
    tui_success "YouTube профиль : ${win_y_name}"
    tui_success "Voice Discord   : QUIC-блок Flowseal (quic_vk:repeats=6)"
    tui_info "Конфигурация успешно сохранена и применена."
    tui_pause
}
