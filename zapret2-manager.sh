#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Main Control Panel & Automation Suite for OpenWrt
# Based on Asterlike/zapret2UI and 1andrevich/zapret2-openwrt
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
[ -z "${SCRIPT_DIR}" ] && SCRIPT_DIR="."
export Z2M_DIR="${SCRIPT_DIR}"

. "${SCRIPT_DIR}/core/config.sh"
. "${SCRIPT_DIR}/core/tui.sh"
. "${SCRIPT_DIR}/core/zapret_service.sh"
. "${SCRIPT_DIR}/modules/autoselect.sh"
. "${SCRIPT_DIR}/modules/generator.sh"
. "${SCRIPT_DIR}/modules/diagnostics.sh"
. "${SCRIPT_DIR}/modules/hostlists.sh"
. "${SCRIPT_DIR}/strategies/catalog.sh"

show_manual_catalog_menu() {
    tui_banner
    tui_header "🎯 Ручной выбор стратегии из каталога"

    local i=1
    while [ "${i}" -le "${CATALOG_COUNT}" ]; do
        local name
        local tagline
        name=$(catalog_get_name "${i}")
        tagline=$(catalog_get_tagline "${i}")
        printf "  %2s. %-36s ${DGRAY}%s${NC}\n" "${i}" "${name}" "${tagline}"
        i=$(( i + 1 ))
    done
    printf "   0. Назад\n\n"

    local sel
    sel=$(tui_prompt "Выберите номер стратегии для применения" "0")
    if [ "${sel}" -ge 1 ] && [ "${sel}" -le "${CATALOG_COUNT}" ] 2>/dev/null; then
        local chosen_name chosen_opt
        chosen_name=$(catalog_get_name "${sel}")
        chosen_opt=$(catalog_get_opt "${sel}")
        tui_info "Применяем стратегию: «${chosen_name}»..."
        zapret_set_opt "${chosen_opt}"
        tui_success "Стратегия успешно применена в /etc/config/zapret2!"
        tui_pause
    fi
}

main_menu() {
    while true; do
        tui_banner

        # Check Zapret2 status
        local status_str="${RED}Не установлена${NC}"
        if zapret_is_installed; then
            if zapret_is_running; then
                status_str="${GREEN}Активна (nfqws2 PID: $(pgrep nfqws2 | tr '\n' ' '))${NC}"
            else
                status_str="${YELLOW}Остановлена${NC}"
            fi
        fi

        printf "  ${BOLD}Статус Zapret2:${NC} %b\n" "${status_str}"
        printf "  ${DGRAY}───────────────────────────────────────────────────────────────────${NC}\n\n"

        printf "  ${BOLD}1.${NC} ⚡ ${CYAN}Автоподбор стратегии${NC}          ${DGRAY}(тест каталога и выбор лучшей)${NC}\n"
        printf "  ${BOLD}2.${NC} 🧬 ${MAGENTA}Генератор персональной стратегии${NC}  ${DGRAY}(Pass 1 + Pass 2 по Asterlike)${NC}\n"
        printf "  ${BOLD}3.${NC} 🎯 ${WHITE}Выбор стратегии из каталога${NC}       ${DGRAY}(Рекомендуемый, Flowseal, VK...)${NC}\n"
        printf "  ${BOLD}4.${NC} 🩺 ${GREEN}Диагностика сети и блокировок${NC}     ${DGRAY}(TLS, HTTP reach, сигнатуры ТСПУ)${NC}\n"
        printf "  ${BOLD}5.${NC} 📁 ${YELLOW}Управление списками доменов${NC}       ${DGRAY}(YouTube, Discord, Исключения)${NC}\n"
        printf "  ${BOLD}6.${NC} 🔄 Перезапустить службу Zapret2\n"
        printf "  ${BOLD}7.${NC} 📦 Синхронизировать фейковые блобы и хостлисты\n"
        printf "  ${BOLD}0.${NC} Выход\n\n"

        local choice
        choice=$(tui_prompt "Выберите пункт меню" "1")

        case "${choice}" in
            1)
                run_strategy_autoselect
                ;;
            2)
                run_strategy_generator
                ;;
            3)
                show_manual_catalog_menu
                ;;
            4)
                run_diagnostics
                ;;
            5)
                run_hostlists_menu
                ;;
            6)
                tui_info "Перезапуск zapret2..."
                zapret_restart
                tui_success "Служба перезапущена."
                tui_pause
                ;;
            7)
                tui_info "Синхронизация блобов и списков в /opt/zapret2..."
                zapret_sync_fake_blobs
                zapret_sync_hostlists
                tui_success "Готово!"
                tui_pause
                ;;
            0|q|Q)
                echo ""
                tui_info "Выход из Zapret2-Manager."
                exit 0
                ;;
            *)
                tui_warn "Неверный пункт меню."
                sleep 1
                ;;
        esac
    done
}

# Command-line flags handler
case "$1" in
    --autoselect|-a)
        run_strategy_autoselect
        exit 0
        ;;
    --generate|-g)
        run_strategy_generator
        exit 0
        ;;
    --diagnostics|-d)
        run_diagnostics
        exit 0
        ;;
    --restart|-r)
        zapret_restart
        exit 0
        ;;
    --status|-s)
        zapret_status
        exit 0
        ;;
    --help|-h)
        printf "Zapret2-Manager v%s\n\n" "${Z2M_VERSION}"
        printf "Использование:\n"
        printf "  zapret2-manager.sh              Интерактивное меню\n"
        printf "  zapret2-manager.sh --autoselect Автоподбор лучшей стратегии из каталога\n"
        printf "  zapret2-manager.sh --generate   Запуск двухпроходного генератора связок\n"
        printf "  zapret2-manager.sh --diagnostics Диагностика доступности сервисов\n"
        printf "  zapret2-manager.sh --restart    Перезапуск службы zapret2\n"
        printf "  zapret2-manager.sh --status     Вывод статуса службы\n"
        exit 0
        ;;
    *)
        main_menu
        ;;
esac
