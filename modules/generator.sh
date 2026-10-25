#!/bin/sh
# shellcheck disable=SC3043
# ==============================================================================
# Zapret2-Manager: Strategy Generator Module
# Two-Pass Tailored Strategy Generation (Discord vs YouTube)
#
# Based on Asterlike/zapret2UI (https://github.com/Asterlike/zapret2UI)
# Licensed under the MIT License:
# Copyright (c) 2026 Zapret UI contributors
# ==============================================================================

[ -z "${Z2M_DIR:-}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"
[ -f "${Z2M_DIR}/core/tui.sh" ] && . "${Z2M_DIR}/core/tui.sh"
[ -f "${Z2M_DIR}/core/probe.sh" ] && . "${Z2M_DIR}/core/probe.sh"
[ -f "${Z2M_DIR}/core/combo_builder.sh" ] && . "${Z2M_DIR}/core/combo_builder.sh"
[ -f "${Z2M_DIR}/core/zapret_service.sh" ] && . "${Z2M_DIR}/core/zapret_service.sh"
[ -f "${Z2M_DIR}/strategies/candidates.sh" ] && . "${Z2M_DIR}/strategies/candidates.sh"

run_strategy_generator() {
    tui_banner
    tui_header "🧬 Генератор персональной стратегии (Asterlike Two-Pass Generator)"

    tui_info "Этот режим подбирает уникальную связку десинка:"
    tui_info "1. Замер baseline: проверка текущей стратегии тем же набором проб."
    tui_info "2. Pass 1: перебор кандидатов раздельно для Discord и YouTube (с повторами)."
    tui_info "3. Pass 2: совместное тестирование лучших пар с учетом Gateway Discord."
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

    # Synchronize required blobs and lists
    zapret_sync_fake_blobs
    zapret_sync_hostlists

    # Backup current configuration BEFORE any modification
    local bak_file
    bak_file=$(zapret_backup_config)
    local interrupted=0

    cleanup_generator() {
        echo ""
        tui_warn "Прерывание генератора! Восстанавливаем исходную конфигурацию..."
        zapret_restore_config "${bak_file}"
        rm -f "${bak_file}" 2>/dev/null
        trap - INT TERM HUP
        interrupted=1
    }
    trap cleanup_generator INT TERM HUP

    tui_info "Исходная конфигурация сохранена."

    # Baseline measurement of the current strategy using the exact same probe suite
    tui_info "Замер текущей конфигурации (baseline) перед поиском..."
    local base_d_score=0 base_y_score=0
    local base_min=0 base_sum=0
    local b_d_max=0 b_y_max=0

    if zapret_is_running; then
        local b_cd1 b_cd2 b_cy1 b_cy2
        b_cd1=$(probe_host_list "${DISCORD_PROBE_HOSTS}")
        b_cy1=$(probe_host_list "${YOUTUBE_PROBE_HOSTS}")
        sleep 1
        b_cd2=$(probe_host_list "${DISCORD_PROBE_HOSTS}")
        b_cy2=$(probe_host_list "${YOUTUBE_PROBE_HOSTS}")

        local b_cd_s1 b_cd_s2 b_cy_s1 b_cy_s2
        local b_cd_m1 b_cd_m2 b_cy_m1 b_cy_m2
        b_cd_s1=$(echo "${b_cd1}" | awk '{print $3}')
        b_cd_s2=$(echo "${b_cd2}" | awk '{print $3}')
        b_cy_s1=$(echo "${b_cy1}" | awk '{print $3}')
        b_cy_s2=$(echo "${b_cy2}" | awk '{print $3}')

        b_cd_m1=$(echo "${b_cd1}" | awk '{print $4}')
        b_cd_m2=$(echo "${b_cd2}" | awk '{print $4}')
        b_cy_m1=$(echo "${b_cy1}" | awk '{print $4}')
        b_cy_m2=$(echo "${b_cy2}" | awk '{print $4}')

        base_d_score=$(( b_cd_s1 + b_cd_s2 ))
        base_y_score=$(( b_cy_s1 + b_cy_s2 ))
        b_d_max=$(( b_cd_m1 + b_cd_m2 ))
        b_y_max=$(( b_cy_m1 + b_cy_m2 ))

        if [ "${base_d_score}" -le "${base_y_score}" ]; then
            base_min="${base_d_score}"
        else
            base_min="${base_y_score}"
        fi
        base_sum=$(( base_d_score + base_y_score ))
        tui_info "Baseline: Discord: ${base_d_score}/${b_d_max}, YouTube: ${base_y_score}/${b_y_max} (Min: ${base_min}, Sum: ${base_sum})"
    else
        tui_warn "Служба zapret2 не запущена. Baseline score: 0"
    fi
    echo ""

    if [ "${interrupted}" -eq 1 ]; then
        tui_pause
        return 0
    fi

    tui_info "Запуск Pass 1: тестирование ${CANDIDATES_COUNT} десинк-бандлов (по 2 повтора)..."
    echo ""

    printf "%b%-4s %-32s %-12s %-12s %-8s%b\n" "${BOLD}" "№" "Кандидат" "Discord" "YouTube" "GW-Safe" "${NC}"
    printf "%b───────────────────────────────────────────────────────────────────%b\n" "${DGRAY}" "${NC}"

    local cand_scores_d=""
    local cand_scores_y=""
    local perfect_cand=0

    # ---- PASS 1: Screening of each bundle for Discord & YouTube (2 repeats) ----
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

        printf "%-4s %-32s %b⏳ Тест...%b\r" "${i}" "${short_name}" "${YELLOW}" "${NC}"

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
            printf "%-4s %-32s %b%-12s%b %b%-12s%b %b\n" \
                "${i}" "${short_name}" "${RED}" "Сбой" "${NC}" "${RED}" "Сбой" "${NC}" "${gw_safe}"
            cand_scores_d="${cand_scores_d} ${i}:0"
            cand_scores_y="${cand_scores_y} ${i}:0"
            i=$(( i + 1 ))
            continue
        fi

        # Minimum 2 repeats per strategy to eliminate transient flukes
        local d_score_rep1=0 d_score_rep2=0
        local y_score_rep1=0 y_score_rep2=0

        # Repeat 1: Discord (Web, Gateway, CDN)
        probe_http_reach "discord.com" 2 && d_score_rep1=$(( d_score_rep1 + 1 ))
        probe_fast_tls "gateway.discord.gg" 443 2 && d_score_rep1=$(( d_score_rep1 + 1 ))
        probe_fast_tls "cdn.discordapp.com" 443 2 && d_score_rep1=$(( d_score_rep1 + 1 ))

        # Repeat 1: YouTube (Web, Video CDN, Preview CDN)
        probe_http_reach "www.youtube.com" 2 && y_score_rep1=$(( y_score_rep1 + 1 ))
        probe_fast_tls "googlevideo.com" 443 2 && y_score_rep1=$(( y_score_rep1 + 1 ))
        probe_fast_tls "i.ytimg.com" 443 2 && y_score_rep1=$(( y_score_rep1 + 1 ))

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        # Short pause between repeats
        sleep 1

        # Repeat 2: Discord
        probe_http_reach "discord.com" 2 && d_score_rep2=$(( d_score_rep2 + 1 ))
        probe_fast_tls "gateway.discord.gg" 443 2 && d_score_rep2=$(( d_score_rep2 + 1 ))
        probe_fast_tls "cdn.discordapp.com" 443 2 && d_score_rep2=$(( d_score_rep2 + 1 ))

        # Repeat 2: YouTube
        probe_http_reach "www.youtube.com" 2 && y_score_rep2=$(( y_score_rep2 + 1 ))
        probe_fast_tls "googlevideo.com" 443 2 && y_score_rep2=$(( y_score_rep2 + 1 ))
        probe_fast_tls "i.ytimg.com" 443 2 && y_score_rep2=$(( y_score_rep2 + 1 ))

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        # Store sum of two repeats instead of integer average
        local d_score=$(( d_score_rep1 + d_score_rep2 ))
        local y_score=$(( y_score_rep1 + y_score_rep2 ))

        local d_col="${RED}"
        [ "${d_score}" -gt 0 ] && d_col="${YELLOW}"
        [ "${d_score}" -eq 6 ] && d_col="${GREEN}"

        local y_col="${RED}"
        [ "${y_score}" -gt 0 ] && y_col="${YELLOW}"
        [ "${y_score}" -eq 6 ] && y_col="${GREEN}"

        printf "%-4s %-32s %b%s/6%b        %b%s/6%b        %b\n" \
            "${i}" "${short_name}" "${d_col}" "${d_score}" "${NC}" "${y_col}" "${y_score}" "${NC}" "${gw_safe}"

        cand_scores_d="${cand_scores_d} ${i}:${d_score}"
        cand_scores_y="${cand_scores_y} ${i}:${y_score}"

        # Early exit check: 100% (6/6) on both repeats and gateway-friendly
        if [ "${d_score}" -eq 6 ] && [ "${y_score}" -eq 6 ] && is_gateway_friendly "${c_tls}"; then
            tui_success "Найден надежный универсальный бандл #${i} (${c_name})! Переход к сборке."
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
        # Find top Discord candidates prioritizing gateway-friendly
        local sorted_d
        sorted_d=$(echo "${cand_scores_d}" | tr ' ' '\n' | grep ":" | sort -t: -k2,2nr -k1,1n)

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

        # Non-fatal fallback: if gateway-friendly shortlist is empty, take top by score with warning
        if [ "${d_count}" -eq 0 ]; then
            tui_warn "Gateway-friendly кандидаты не найдены. Используем лучшие бандлы по общему счету."
            top_d_list=$(echo "${sorted_d}" | head -n3 | cut -d: -f1 | tr '\n' ' ')
        fi

        local sorted_y
        sorted_y=$(echo "${cand_scores_y}" | tr ' ' '\n' | grep ":" | sort -t: -k2,2nr -k1,1n)
        top_y_list=$(echo "${sorted_y}" | head -n3 | cut -d: -f1 | tr '\n' ' ')
    fi

    local best_min=-1
    local best_sum=-1
    local best_len=99999
    local best_d_idx=1
    local best_y_idx=1
    local attempt=0
    local max_tests=6

    for d_idx in ${top_d_list}; do
        for y_idx in ${top_y_list}; do
            if [ "${interrupted}" -eq 1 ]; then
                tui_pause
                return 0
            fi

            attempt=$(( attempt + 1 ))
            [ "${attempt}" -gt "${max_tests}" ] && break 2

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

            # Probe Discord & YouTube with 2 repeats for stability
            local cd_res1 cd_res2 cy_res1 cy_res2
            cd_res1=$(probe_host_list "${DISCORD_PROBE_HOSTS}")
            cy_res1=$(probe_host_list "${YOUTUBE_PROBE_HOSTS}")
            sleep 1
            cd_res2=$(probe_host_list "${DISCORD_PROBE_HOSTS}")
            cy_res2=$(probe_host_list "${YOUTUBE_PROBE_HOSTS}")

            if [ "${interrupted}" -eq 1 ]; then
                tui_pause
                return 0
            fi

            local cd_s1 cd_s2 cy_s1 cy_s2
            local cd_m1 cd_m2 cy_m1 cy_m2
            cd_s1=$(echo "${cd_res1}" | awk '{print $3}')
            cd_s2=$(echo "${cd_res2}" | awk '{print $3}')
            cy_s1=$(echo "${cy_res1}" | awk '{print $3}')
            cy_s2=$(echo "${cy_res2}" | awk '{print $3}')

            cd_m1=$(echo "${cd_res1}" | awk '{print $4}')
            cd_m2=$(echo "${cd_res2}" | awk '{print $4}')
            cy_m1=$(echo "${cy_res1}" | awk '{print $4}')
            cy_m2=$(echo "${cy_res2}" | awk '{print $4}')

            # Sum of two repeats instead of integer average
            local cd_score=$(( cd_s1 + cd_s2 ))
            local cy_score=$(( cy_s1 + cy_s2 ))
            local cd_max_total=$(( cd_m1 + cd_m2 ))
            local cy_max_total=$(( cy_m1 + cy_m2 ))

            # Determine maximum score dynamically from probe suite
            local probe_max="${cd_max_total}"
            [ "${cy_max_total}" -lt "${probe_max}" ] && probe_max="${cy_max_total}"

            # Pass 2 score = min(score_D, score_Y)
            local cur_min
            if [ "${cd_score}" -le "${cy_score}" ]; then
                cur_min="${cd_score}"
            else
                cur_min="${cy_score}"
            fi
            local cur_sum=$(( cd_score + cy_score ))
            local cur_len=$(( ${#d_tls} + ${#y_tls} ))

            printf "  -> Результат: Discord: %s/%s, YouTube: %s/%s (Min: %s, Sum: %s)\n" \
                "${cd_score}" "${cd_max_total}" "${cy_score}" "${cy_max_total}" "${cur_min}" "${cur_sum}"

            # Compare: maximize cur_min, then cur_sum, tie-break on shorter/simpler options
            local is_better=0
            if [ "${cur_min}" -gt "${best_min}" ]; then
                is_better=1
            elif [ "${cur_min}" -eq "${best_min}" ]; then
                if [ "${cur_sum}" -gt "${best_sum}" ]; then
                    is_better=1
                elif [ "${cur_sum}" -eq "${best_sum}" ] && [ "${cur_len}" -lt "${best_len}" ]; then
                    is_better=1
                fi
            fi

            if [ "${is_better}" -eq 1 ]; then
                best_min="${cur_min}"
                best_sum="${cur_sum}"
                best_len="${cur_len}"
                best_d_idx="${d_idx}"
                best_y_idx="${y_idx}"
            fi

            # Early exit: break both loops if max score reached
            if [ "${probe_max}" -gt 0 ] && [ "${cur_min}" -ge "${probe_max}" ]; then
                tui_success "Достигнут максимальный результат (${cur_min}/${probe_max})! Досрочный выход."
                break 2
            fi
        done
        [ "${attempt}" -gt "${max_tests}" ] && break
    done

    if [ "${interrupted}" -eq 1 ]; then
        tui_pause
        return 0
    fi

    # If no strategy passed threshold (> 0), restore backup and inform user
    if [ "${best_min}" -le 0 ] && [ "${best_sum}" -le 0 ]; then
        echo ""
        tui_error "Ни одна стратегия не смогла обеспечить доступ к тестируемым ресурсам!"
        tui_warn "Восстанавливаем исходную конфигурацию роутера..."
        zapret_restore_config "${bak_file}"
        rm -f "${bak_file}" 2>/dev/null
        trap - INT TERM HUP
        tui_info "Рекомендация: проверьте блокировку провайдером DNS (DoH в меню 6)."
        tui_pause
        return 1
    fi

    # Check against baseline: apply winner only if best_min > baseline, else ask or rollback
    if [ "${best_min}" -le "${base_min}" ]; then
        echo ""
        tui_warn "Сгенерированная комбинация (Min: ${best_min}) не превосходит текущую конфигурацию (Baseline Min: ${base_min})."
        local ans
        ans=$(tui_prompt "Применить найденную комбинацию всё равно? [y/N]" "N")
        case "${ans}" in
            y|Y|yes|YES)
                tui_info "Применение подтверждено пользователем."
                ;;
            *)
                tui_info "Откатываемся к исходной конфигурации (baseline)..."
                zapret_restore_config "${bak_file}"
                rm -f "${bak_file}" 2>/dev/null
                trap - INT TERM HUP
                tui_pause
                return 0
                ;;
        esac
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

    # Remove temporary backup and clear trap
    rm -f "${bak_file}" 2>/dev/null
    trap - INT TERM HUP

    echo ""
    tui_header "✨ Итоговая персональная стратегия сгенерирована!"
    tui_success "Discord профиль : ${win_d_name}"
    tui_success "YouTube профиль : ${win_y_name}"
    if echo "${final_opt}" | grep -q "quic_vk"; then
        tui_success "Voice Discord   : QUIC-блок Flowseal (quic_vk:repeats=6)"
    fi
    tui_info "Конфигурация успешно сохранена и применена."
    echo ""

    # Mention that curl checks only TCP/TLS, UDP voice is not tested
    tui_info "Примечание: Проверка curl тестирует только протоколы TCP и TLS."
    tui_info "Голосовая связь Discord использует UDP (STUN / RTP)."
    tui_info "Для гарантированной работы голосовых звонков примените исправление:"
    tui_info "  Главное меню -> Пункт 4 (Исправление Discord Voice / custom.d #50)"
    echo ""
    tui_pause
}
