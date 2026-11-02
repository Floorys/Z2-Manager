#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Ports Configuration Module
# Manages NFQWS2_PORTS_TCP and NFQWS2_PORTS_UDP in UCI / OpenWrt
# ==============================================================================

[ -z "${Z2M_DIR:-}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"
[ -f "${Z2M_DIR}/core/tui.sh" ] && . "${Z2M_DIR}/core/tui.sh"
[ -f "${Z2M_DIR}/core/zapret_service.sh" ] && . "${Z2M_DIR}/core/zapret_service.sh"

run_ports_menu() {
    while true; do
        tui_banner
        tui_header "🌐 Настройка перехватываемых портов TCP и UDP"

        local cur_tcp cur_udp
        cur_tcp=$(zapret_get_ports_tcp)
        cur_udp=$(zapret_get_ports_udp)

        printf "  %bТекущие порты TCP:%b %b%s%b\n" "${BOLD}" "${NC}" "${CYAN}" "${cur_tcp}" "${NC}"
        printf "  %bТекущие порты UDP:%b %b%s%b\n" "${BOLD}" "${NC}" "${CYAN}" "${cur_udp}" "${NC}"
        printf "%b  ───────────────────────────────────────────────────────────────────%b\n\n" "${DGRAY}" "${NC}"

        printf "  1. 🚀 Установить рекомендуемые порты (Web + Discord Voice + Cloudflare)\n"
        printf "     %bTCP: %s%b\n" "${DGRAY}" "${DEFAULT_PORTS_TCP}" "${NC}"
        printf "     %bUDP: %s%b\n\n" "${DGRAY}" "${DEFAULT_PORTS_UDP}" "${NC}"

        printf "  2. 🎮 Установить расширенные порты для игр и медиа (Xtreme Gaming)\n"
        printf "     %bTCP: 80,443,2053,2083,2087,2096,8443,25565,27015-27030%b\n" "${DGRAY}" "${NC}"
        printf "     %bUDP: 443,19294-19344,27015-27030,50000-65535%b\n\n" "${DGRAY}" "${NC}"

        printf "  3. ✏️ Задать порты TCP вручную\n"
        printf "  4. ✏️ Задать порты UDP вручную\n"
        printf "  5. ↩️ Сбросить на минимальные стандартные порты (80,443 / 443)\n"
        printf "  0. ↩️ Назад в главное меню\n\n"

        local choice
        choice=$(tui_prompt "Выберите действие" "1")

        case "${choice}" in
            1)
                tui_info "Применение рекомендуемых портов..."
                if zapret_set_ports "${DEFAULT_PORTS_TCP}" "${DEFAULT_PORTS_UDP}"; then
                    tui_success "Рекомендуемые порты успешно установлены!"
                else
                    tui_error "Не удалось применить порты или перезапустить Zapret2."
                fi
                tui_pause
                ;;
            2)
                tui_info "Применение расширенных игровых портов..."
                if zapret_set_ports "80,443,2053,2083,2087,2096,8443,25565,27015-27030" "443,19294-19344,27015-27030,50000-65535"; then
                    tui_success "Расширенные игровые порты успешно установлены!"
                else
                    tui_error "Не удалось применить порты или перезапустить Zapret2."
                fi
                tui_pause
                ;;
            3)
                tui_banner
                tui_header "Ввод портов TCP"
                printf "Текущие порты TCP: %b%s%b\n\n" "${CYAN}" "${cur_tcp}" "${NC}"
                local new_tcp
                new_tcp=$(tui_prompt "Введите список портов TCP через запятую" "${cur_tcp}")
                if [ -n "${new_tcp}" ]; then
                    if zapret_set_ports "${new_tcp}" "${cur_udp}"; then
                        tui_success "Порты TCP обновлены!"
                    else
                        tui_error "Некорректный список портов или ошибка перезапуска Zapret2."
                    fi
                fi
                tui_pause
                ;;
            4)
                tui_banner
                tui_header "Ввод портов UDP"
                printf "Текущие порты UDP: %b%s%b\n\n" "${CYAN}" "${cur_udp}" "${NC}"
                local new_udp
                new_udp=$(tui_prompt "Введите список портов UDP через запятую" "${cur_udp}")
                if [ -n "${new_udp}" ]; then
                    if zapret_set_ports "${cur_tcp}" "${new_udp}"; then
                        tui_success "Порты UDP обновлены!"
                    else
                        tui_error "Некорректный список портов или ошибка перезапуска Zapret2."
                    fi
                fi
                tui_pause
                ;;
            5)
                tui_info "Сброс портов на стандартные минимальные (80,443 / 443)..."
                if zapret_set_ports "80,443" "443"; then
                    tui_success "Порты сброшены."
                else
                    tui_error "Не удалось сбросить порты."
                fi
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
