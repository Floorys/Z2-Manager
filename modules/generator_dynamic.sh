#!/bin/sh
# shellcheck disable=SC3043
# ==============================================================================
# Zapret2-Manager: Dynamic Strategy Generator (real parameter search)
#
# Unlike the classic Asterlike port (27 fixed bundles in candidates.sh), this
# generator BUILDS candidate strategies from parameter axes and tests every
# generated candidate with live internet probes:
#   Stage 1 (classes)    - screening of representative desync families;
#   Stage 2 (refinement) - parameter variants of the best families
#                          (blobs, primes, repeats, positions, seqovl, wssize);
#   Stage 3 (pairs)      - Discord x YouTube pairs with joint probing.
# Baseline comparison, the Gateway-friendly filter, transactional rollback and
# Ctrl+C safety are shared with the classic generator and the guard.
# ==============================================================================

[ -z "${Z2M_DIR:-}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"
[ -f "${Z2M_DIR}/core/tui.sh" ] && . "${Z2M_DIR}/core/tui.sh"
[ -f "${Z2M_DIR}/core/probe.sh" ] && . "${Z2M_DIR}/core/probe.sh"
[ -f "${Z2M_DIR}/core/combo_builder.sh" ] && . "${Z2M_DIR}/core/combo_builder.sh"
[ -f "${Z2M_DIR}/core/zapret_service.sh" ] && . "${Z2M_DIR}/core/zapret_service.sh"
[ -f "${Z2M_DIR}/strategies/candidates.sh" ] && . "${Z2M_DIR}/strategies/candidates.sh"
[ -f "${Z2M_DIR}/strategies/dynamic_space.sh" ] && . "${Z2M_DIR}/strategies/dynamic_space.sh"

run_strategy_generator_dynamic() {
    z2m_run_guarded strategy_generator_dynamic_worker
}

# dyn_measure <repeats>: probe Discord and YouTube lists (concurrently),
# repeat the measurement, and print "d_score y_score d_max y_max".
dyn_measure() {
    local reps="$1" d=0 y=0 dm=0 ym=0 r res
    for r in 1 2; do
        [ "${r}" -le "${reps}" ] || break
        [ "${r}" = "1" ] || sleep "${Z2M_PROBE_REPEAT_DELAY:-1}"
        res=$(probe_lists2 "${DISCORD_PROBE_HOSTS}" "${YOUTUBE_PROBE_HOSTS}")
        d=$(( d + $(echo "${res}" | sed -n 1p | awk '{print $3 + 0}') ))
        y=$(( y + $(echo "${res}" | sed -n 2p | awk '{print $3 + 0}') ))
        dm=$(( dm + $(echo "${res}" | sed -n 1p | awk '{print $4 + 0}') ))
        ym=$(( ym + $(echo "${res}" | sed -n 2p | awk '{print $4 + 0}') ))
    done
    echo "${d} ${y} ${dm} ${ym}"
}

strategy_generator_dynamic_worker() {
    tui_banner
    tui_header "🧬 Динамический генератор стратегий (реальный перебор параметров)"

    tui_info "Генератор строит стратегии из сетки параметров и проверяет доступ в интернет:"
    tui_info "  1. Baseline: замер текущей конфигурации теми же пробами."
    tui_info "  2. Этап 1: скрининг классов десинка (сплиты, фейки, маски, окна)."
    tui_info "  3. Этап 2: уточнение лучших классов (blob, prime, повторы, pos, seqovl)."
    tui_info "  4. Этап 3: связки Discord × YouTube с совместным тестом."
    echo ""
    tui_info "Каждый кандидат применяется к службе и проверяется живыми HTTP/TLS-пробами."
    if [ -n "${CURL_INTERFACE:-}" ]; then
        tui_info "Используется сетевой интерфейс: ${CURL_INTERFACE}"
    fi
    echo ""

    if ! zapret_is_installed; then
        tui_error "Пакет zapret2 не установлен в системе!"
        tui_pause
        return 1
    fi
    if ! probe_check_deps; then
        tui_error "Не найдены curl или wget — проверка доступа в интернет невозможна!"
        tui_pause
        return 1
    fi

    zapret_sync_fake_blobs || return 1
    zapret_sync_hostlists 0 || return 1

    tui_info "Исходная конфигурация сохранена."

    # ------------------------- Baseline -------------------------
    tui_info "Замер текущей конфигурации (baseline) перед поиском..."
    local base base_d base_y base_dm base_ym base_min base_sum
    base=$(dyn_measure 2)
    base_d=$(echo "${base}" | awk '{print $1 + 0}')
    base_y=$(echo "${base}" | awk '{print $2 + 0}')
    base_dm=$(echo "${base}" | awk '{print $3 + 0}')
    base_ym=$(echo "${base}" | awk '{print $4 + 0}')
    if [ "${base_d}" -le "${base_y}" ]; then base_min="${base_d}"; else base_min="${base_y}"; fi
    base_sum=$(( base_d + base_y ))
    tui_info "Baseline: Discord: ${base_d}/${base_dm}, YouTube: ${base_y}/${base_ym} (Min: ${base_min}, Sum: ${base_sum})"
    echo ""

    # A perfect baseline needs no search at all.
    local base_full=999999
    if [ "${base_dm}" -lt "${base_ym}" ]; then base_full="${base_dm}"; else base_full="${base_ym}"; fi
    if [ "${base_full}" -gt 0 ] && [ "${base_min}" -ge "${base_full}" ]; then
        tui_success "Текущая конфигурация уже обеспечивает полный доступ к обоим сервисам."
        tui_info "Генерация не требуется; исходная конфигурация сохранена."
        tui_pause
        return 0
    fi

    local t_start
    t_start=$(date +%s)

    # ------------------------- Stage 1 ---------------------------
    local stage1="${Z2M_TMP}/dyn_stage1"
    dyn_build_stage1 "${stage1}" || return 1
    local total1
    total1=$(wc -l < "${stage1}" | tr -d ' ')

    tui_header "Этап 1: скрининг ${total1} классов десинка (1 повтор)"
    printf "%b%-4s %-36s %-10s %-10s %-8s%b\n" "${BOLD}" "№" "Класс" "Discord" "YouTube" "GW-Safe" "${NC}"
    printf "%b───────────────────────────────────────────────────────────────────%b\n" "${DGRAY}" "${NC}"

    local scores1="" line i=1
    while IFS= read -r line; do
        [ -n "${line}" ] || continue
        local name tls short_name gw_flag=0 gw_safe="Нет" d_score=0 y_score=0 res test_opt
        name=${line%%|*}
        tls=${line#*|}
        short_name=$(printf "%.34s" "${name}")
        if is_gateway_friendly "${tls}"; then gw_flag=1; gw_safe="${GREEN}Да${NC}"; fi

        printf "%-4s %-36s %b⏳ [%s/%s, %ss]%b\r" "${i}" "${short_name}" "${YELLOW}" "${i}" "${total1}" "$(( $(date +%s) - t_start ))" "${NC}"

        test_opt=$(combo_build_single_test_args "${tls}")
        if [ -z "${test_opt}" ] || ! zapret_set_opt "${test_opt}" || ! zapret_is_running; then
            printf "%-4s %-36s %b%-10s%b %b%-10s%b %b\n" "${i}" "${short_name}" "${RED}" "Сбой" "${NC}" "${RED}" "Сбой" "${NC}" "${gw_safe}"
        else
            res=$(dyn_measure 1)
            d_score=$(echo "${res}" | awk '{print $1 + 0}')
            y_score=$(echo "${res}" | awk '{print $2 + 0}')
            local d_col="${RED}" y_col="${RED}"
            [ "${d_score}" -gt 0 ] && d_col="${YELLOW}"
            [ "${d_score}" -eq 15 ] && d_col="${GREEN}"
            [ "${y_score}" -gt 0 ] && y_col="${YELLOW}"
            [ "${y_score}" -eq 15 ] && y_col="${GREEN}"
            printf "%-4s %-36s %b%-7s/15%b %b%-7s/15%b %b\n" "${i}" "${short_name}" "${d_col}" "${d_score}" "${NC}" "${y_col}" "${y_score}" "${NC}" "${gw_safe}"
        fi
        scores1="${scores1} ${i}:${d_score}:${y_score}:${gw_flag}"
        i=$(( i + 1 ))
    done < "${stage1}"

    # Nothing works at all: fail fast and keep the original configuration.
    local any1
    any1=$(echo "${scores1}" | tr ' ' '\n' | awk -F: 'NF == 4 && ($2 + 0 > 0 || $3 + 0 > 0) { c++ } END { print c + 0 }')
    if [ "${any1}" -eq 0 ]; then
        echo ""
        tui_error "Ни один класс десинка не обеспечил доступ к тестируемым ресурсам!"
        tui_warn "Восстанавливаем исходную конфигурацию роутера..."
        tui_info "Рекомендация: проверьте блокировку провайдером DNS (DoH в меню 6)."
        tui_pause
        return 1
    fi

    # Top classes: Discord prefers gateway-friendly bundles.
    local top_d top_y
    top_d=$(echo "${scores1}" | tr ' ' '\n' | awk -F: 'NF == 4 { print ($4 + 0), ($2 + 0), ($3 + 0), $1 }' | sort -k1,1nr -k2,2nr -k3,3nr | head -n 2 | awk '{ print $4 }' | tr '\n' ' ')
    top_y=$(echo "${scores1}" | tr ' ' '\n' | awk -F: 'NF == 4 { print ($3 + 0), ($2 + 0), $1 }' | sort -k1,1nr -k2,2nr | head -n 2 | awk '{ print $3 }' | tr '\n' ' ')

    # ------------------------- Stage 2 ---------------------------
    echo ""
    tui_header "Этап 2: уточнение параметров лучших классов (2 повтора)"
    tui_info "Лучшие классы Discord (GW-приоритет): ${top_d}"
    tui_info "Лучшие классы YouTube: ${top_y}"

    local stage2="${Z2M_TMP}/dyn_stage2"
    local idx_list="" idx
    for idx in ${top_d} ${top_y}; do
        case " ${idx_list} " in *" ${idx} "*) ;; *) idx_list="${idx_list} ${idx}" ;; esac
    done
    # shellcheck disable=SC2086
    dyn_build_stage2 "${stage2}" "${stage1}" ${idx_list}
    local total2
    total2=$(wc -l < "${stage2}" | tr -d ' ')
    tui_info "Сгенерировано ${total2} уточнённых кандидатов (лимит: ${DYNGEN_STAGE2_MAX})."
    echo ""

    printf "%b%-4s %-36s %-10s %-10s %-8s%b\n" "${BOLD}" "№" "Кандидат" "Discord" "YouTube" "GW-Safe" "${NC}"
    printf "%b───────────────────────────────────────────────────────────────────%b\n" "${DGRAY}" "${NC}"

    local scores2="" perfect_cand=0 i2=1
    while IFS= read -r line; do
        [ -n "${line}" ] || continue
        local name tls short_name gw_flag=0 gw_safe="Нет" d_score=0 y_score=0 res test_opt
        name=${line%%|*}
        tls=${line#*|}
        short_name=$(printf "%.34s" "${name}")
        if is_gateway_friendly "${tls}"; then gw_flag=1; gw_safe="${GREEN}Да${NC}"; fi

        printf "%-4s %-36s %b⏳ [%s/%s, %ss]%b\r" "${i2}" "${short_name}" "${YELLOW}" "${i2}" "${total2}" "$(( $(date +%s) - t_start ))" "${NC}"

        test_opt=$(combo_build_single_test_args "${tls}")
        if [ -z "${test_opt}" ] || ! zapret_set_opt "${test_opt}" || ! zapret_is_running; then
            printf "%-4s %-36s %b%-10s%b %b%-10s%b %b\n" "${i2}" "${short_name}" "${RED}" "Сбой" "${NC}" "${RED}" "Сбой" "${NC}" "${gw_safe}"
        else
            res=$(dyn_measure 2)
            d_score=$(echo "${res}" | awk '{print $1 + 0}')
            y_score=$(echo "${res}" | awk '{print $2 + 0}')
            local d_col="${RED}" y_col="${RED}"
            [ "${d_score}" -gt 0 ] && d_col="${YELLOW}"
            [ "${d_score}" -eq 30 ] && d_col="${GREEN}"
            [ "${y_score}" -gt 0 ] && y_col="${YELLOW}"
            [ "${y_score}" -eq 30 ] && y_col="${GREEN}"
            printf "%-4s %-36s %b%-7s/30%b %b%-7s/30%b %b\n" "${i2}" "${short_name}" "${d_col}" "${d_score}" "${NC}" "${y_col}" "${y_score}" "${NC}" "${gw_safe}"
        fi
        scores2="${scores2} ${i2}:${d_score}:${y_score}:${gw_flag}"

        if [ "${d_score}" -eq 30 ] && [ "${y_score}" -eq 30 ] && [ "${gw_flag}" -eq 1 ]; then
            tui_success "Найден надёжный универсальный бандл #${i2} (${name})! Переход к сборке."
            perfect_cand="${i2}"
            break
        fi
        i2=$(( i2 + 1 ))
    done < "${stage2}"

    # ------------------------- Stage 3 ---------------------------
    echo ""
    tui_header "Этап 3: сборка и совместная проверка связок Discord × YouTube"

    local top2_d top2_y
    if [ "${perfect_cand}" -gt 0 ]; then
        top2_d="${perfect_cand}"
        top2_y="${perfect_cand}"
    else
        top2_d=$(echo "${scores2}" | tr ' ' '\n' | awk -F: 'NF == 4 && ($2 + 0 > 0) { print ($4 + 0), ($2 + 0), $1 }' | sort -k1,1nr -k2,2nr | head -n 3 | awk '{ print $3 }' | tr '\n' ' ')
        top2_y=$(echo "${scores2}" | tr ' ' '\n' | awk -F: 'NF == 4 && ($3 + 0 > 0) { print ($3 + 0), $1 }' | sort -k1,1nr | head -n 3 | awk '{ print $2 }' | tr '\n' ' ')
        if [ -z "${top2_d}" ]; then
            tui_warn "Gateway-friendly кандидаты не найдены. Используем лучшие бандлы по общему счёту."
            top2_d=$(echo "${scores2}" | tr ' ' '\n' | awk -F: 'NF == 4 { print ($2 + 0), $1 }' | sort -k1,1nr | head -n 3 | awk '{ print $2 }' | tr '\n' ' ')
        fi
        if [ -z "${top2_y}" ]; then
            top2_y=$(echo "${scores2}" | tr ' ' '\n' | awk -F: 'NF == 4 { print ($3 + 0), $1 }' | sort -k1,1nr | head -n 3 | awk '{ print $2 }' | tr '\n' ' ')
        fi
    fi

    local best_min=-1 best_sum=-1 best_len=99999 best_d_idx=0 best_y_idx=0
    local attempt=0 max_tests=9 d_idx y_idx
    for d_idx in ${top2_d}; do
        for y_idx in ${top2_y}; do
            attempt=$(( attempt + 1 ))
            [ "${attempt}" -gt "${max_tests}" ] && break 2

            local d_line y_line d_name y_name d_tls y_tls
            d_line=$(sed -n "${d_idx}p" "${stage2}")
            y_line=$(sed -n "${y_idx}p" "${stage2}")
            d_name=${d_line%%|*}; d_tls=${d_line#*|}
            y_name=${y_line%%|*}; y_tls=${y_line#*|}

            tui_info "Связка [${attempt}]: Discord «${d_name}» + YouTube «${y_name}»..."

            local combo_args
            combo_args=$(combo_build_args "${d_tls}" "${y_tls}" "${d_tls}")
            if ! zapret_set_opt "${combo_args}"; then
                tui_warn "Не удалось применить сочетание; пропускаем его."
                continue
            fi

            local res cd_score cy_score cd_max cy_max probe_max cur_min cur_sum cur_len
            res=$(dyn_measure 2)
            cd_score=$(echo "${res}" | awk '{print $1 + 0}')
            cy_score=$(echo "${res}" | awk '{print $2 + 0}')
            cd_max=$(echo "${res}" | awk '{print $3 + 0}')
            cy_max=$(echo "${res}" | awk '{print $4 + 0}')
            probe_max="${cd_max}"
            [ "${cy_max}" -lt "${probe_max}" ] && probe_max="${cy_max}"
            if [ "${cd_score}" -le "${cy_score}" ]; then cur_min="${cd_score}"; else cur_min="${cy_score}"; fi
            cur_sum=$(( cd_score + cy_score ))
            cur_len=$(( ${#d_tls} + ${#y_tls} ))

            printf "  -> Результат: Discord: %s/%s, YouTube: %s/%s (Min: %s, Sum: %s)\n" \
                "${cd_score}" "${cd_max}" "${cy_score}" "${cy_max}" "${cur_min}" "${cur_sum}"

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

            if [ "${probe_max}" -gt 0 ] && [ "${cur_min}" -ge "${probe_max}" ]; then
                tui_success "Достигнут максимальный результат (${cur_min}/${probe_max})! Досрочный выход."
                break 2
            fi
        done
        [ "${attempt}" -gt "${max_tests}" ] && break
    done

    if [ "${best_min}" -le 0 ] && [ "${best_sum}" -le 0 ]; then
        echo ""
        tui_error "Ни одна сгенерированная стратегия не обеспечила доступ к тестируемым ресурсам!"
        tui_warn "Восстанавливаем исходную конфигурацию роутера..."
        tui_info "Рекомендация: проверьте блокировку провайдером DNS (DoH в меню 6)."
        tui_pause
        return 1
    fi

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
                tui_pause
                return 0
                ;;
        esac
    fi

    # ------------------------- Final apply ------------------------
    local win_d_line win_y_line win_d_name win_y_name win_d_tls win_y_tls final_opt
    win_d_line=$(sed -n "${best_d_idx}p" "${stage2}")
    win_y_line=$(sed -n "${best_y_idx}p" "${stage2}")
    win_d_name=${win_d_line%%|*}; win_d_tls=${win_d_line#*|}
    win_y_name=${win_y_line%%|*}; win_y_tls=${win_y_line#*|}

    final_opt=$(combo_build_args "${win_d_tls}" "${win_y_tls}" "${win_d_tls}")
    if ! zapret_set_opt "${final_opt}"; then
        tui_error "Не удалось применить итоговую стратегию. Выполняется откат."
        tui_pause
        return 1
    fi

    z2m_transaction_commit

    echo ""
    tui_header "✨ Персональная стратегия сгенерирована и применена!"
    tui_success "Discord профиль : ${win_d_name}"
    tui_success "YouTube профиль : ${win_y_name}"
    tui_info "Сгенерированные десинк-бандлы:"
    printf "  Discord : %s\n" "${win_d_tls}"
    printf "  YouTube : %s\n" "${win_y_tls}"
    tui_info "Voice Discord   : STUN + IP Discovery (голос проверяется в приложении)"
    tui_info "Конфигурация успешно сохранена и применена."
    echo ""

    tui_info "Примечание: проверка curl тестирует только протоколы TCP и TLS."
    tui_info "Голосовая связь Discord использует UDP (STUN / RTP)."
    tui_info "Если звонки не подключаются, попробуйте исправление:"
    tui_info "  Главное меню -> Пункт 4 (Исправление Discord Voice / custom.d #50)"
    echo ""
    tui_info "Поиск завершён за $(( $(date +%s) - t_start )) секунд."
    tui_pause
}
