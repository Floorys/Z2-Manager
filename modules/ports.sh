#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Ports Configuration Module
# Manages NFQWS2_PORTS_TCP and NFQWS2_PORTS_UDP in UCI / OpenWrt
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
. "${Z2M_DIR}/core/config.sh"
. "${Z2M_DIR}/core/tui.sh"
. "${Z2M_DIR}/core/zapret_service.sh"

run_ports_menu() {
    while true; do
        tui_banner
        tui_header "🌐 Настройка перехватываемых портов TCP и UDP"

        local cur_tcp cur_udp
        cur_tcp=$(zapret_get_ports_tcp)
        cur_udp=$(zapret_get_ports_udp)

        printf "  ${BOLD}Текущие порты TCP:${NC} ${CYAN}%s${NC}\n" "${cur_tcp}"
        printf "  ${BOLD}Текущие порты UDP:${NC} ${CYAN}%s${NC}\n" "${cur_udp}"
        printf "  ${DGRAY}───────────────────────────────────────────────────────────────────${NC}\n\n"

        printf "  1. 🚀 Установить рекомендуемые порты (Web + Discord Voice + Cloudflare)\n"
        printf "     ${DGRAY}TCP: %s${NC}\n" "${DEFAULT_PORTS_TCP}"
        printf "     ${DGRAY}UDP: %s${NC}\n\n" "${DEFAULT_PORTS_UDP}"

        printf "  2. 🎮 Установить расширенные порты для игр и медиа (Xtreme Gaming)\n"
        printf "     ${DGRAY}TCP: 80,443,2053,2083,2087,2096,8443,25565,27015-27030${NC}\n"
        printf "     ${DGRAY}UDP: 443,19294-19344,27015-27030,50000-65535${NC}\n\n"

        printf "  3. ✏️ Задать порты TCP вручную\n"
        printf "  4. ✏️ Задать порты UDP вручную\n"
        printf "  5. ↩️ Сбросить на минимальные стандартные порты (80,443 / 443)\n"
        printf "  0. ↩️ Назад в главное меню\n\n"

        local choice
        choice=$(tui_prompt "Выберите действие" "1")

        case "${choice}" in
            1)
                tui_info "Применение рекомендуемых портов..."
                zapret_set_ports "${DEFAULT_PORTS_TCP}" "${DEFAULT_PORTS_UDP}"
                tui_success "Рекомендуемые порты успешно установлены!"
                tui_pause
                ;;
            2)
                tui_info "Применение расширенных игровых портов..."
                zapret_set_ports "80,443,2053,2083,2087,2096,8443,25565,27015-27030" "443,19294-19344,27015-27030,50000-65535"
                tui_success "Расширенные игровые порты успешно установлены!"
                tui_pause
                ;;
            3)
                tui_banner
                tui_header "Ввод портов TCP"
                printf "Текущие порты TCP: ${CYAN}%s${NC}\n\n" "${cur_tcp}"
                local new_tcp
                new_tcp=$(tui_prompt "Введите список портов TCP через запятую" "${cur_tcp}")
                if [ -n "${new_tcp}" ]; then
                    zapret_set_ports "${new_tcp}" "${cur_udp}"
                    tui_success "Порты TCP обновлены!"
                fi
                tui_pause
                ;;
            4)
                tui_banner
                tui_header "Ввод портов UDP"
                printf "Текущие порты UDP: ${CYAN}%s${NC}\n\n" "${cur_udp}"
                local new_udp
                new_udp=$(tui_prompt "Введите список портов UDP через запятую" "${cur_udp}")
                if [ -n "${new_udp}" ]; then
                    zapret_set_ports "${cur_tcp}" "${new_udp}"
                    tui_success "Порты UDP обновлены!"
                fi
                tui_pause
                ;;
            5)
                tui_info "Сброс портов на стандартные минимальные (80,443 / 443)..."
                zapret_set_ports "80,443" "443"
                tui_success "Порты сброшены."
                tui_pause
                ;;
            0)
                break
                ;;
            *)
                tui_warn "Неверный пункт меню."
                sleep 1
                ;;
        esac
    done
}
