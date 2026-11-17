#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Ports Configuration Module
# Manages NFQWS2_PORTS_TCP and NFQWS2_PORTS_UDP in UCI / OpenWrt
# ==============================================================================

[ -z "${Z2M_DIR:-}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"
[ -f "${Z2M_DIR}/core/tui.sh" ] && . "${Z2M_DIR}/core/tui.sh"
[ -f "${Z2M_DIR}/core/zapret_service.sh" ] && . "${Z2M_DIR}/core/zapret_service.sh"

quic_is_blocked() {
    command -v uci >/dev/null 2>&1 || return 1
    local tgt
    tgt=$(uci -q get firewall.block_quic.target)
    if [ "${tgt}" = "REJECT" ] || [ "${tgt}" = "DROP" ]; then
        [ "$(uci -q get firewall.block_quic.enabled)" != "0" ] && return 0
    fi
    local i=0 name
    while [ "${i}" -lt 50 ]; do
        name=$(uci -q get "firewall.@rule[${i}].name") || break
        [ -z "${name}" ] && break
        if [ "${name}" = "Block-QUIC" ]; then
            tgt=$(uci -q get "firewall.@rule[${i}].target")
            if [ "${tgt}" = "REJECT" ] || [ "${tgt}" = "DROP" ]; then
                [ "$(uci -q get "firewall.@rule[${i}].enabled")" != "0" ] && return 0
            fi
        fi
        i=$((i + 1))
    done
    return 1
}

quic_block_enable() {
    command -v uci >/dev/null 2>&1 || return 1
    uci set firewall.block_quic=rule
    uci set firewall.block_quic.name='Block-QUIC'
    uci set firewall.block_quic.src='lan'
    uci set firewall.block_quic.dest='wan'
    uci set firewall.block_quic.proto='udp'
    uci set firewall.block_quic.dest_port='443'
    uci set firewall.block_quic.target='REJECT'
    uci set firewall.block_quic.enabled='1'
    uci commit firewall || return 1
    if [ -x /etc/init.d/firewall ]; then
        /etc/init.d/firewall reload >/dev/null 2>&1
    fi
    return 0
}

quic_block_disable() {
    command -v uci >/dev/null 2>&1 || return 1
    local changed=0
    if [ -n "$(uci -q get firewall.block_quic)" ]; then
        uci delete firewall.block_quic
        changed=1
    fi
    local i=0 name
    while [ "${i}" -lt 50 ]; do
        name=$(uci -q get "firewall.@rule[${i}].name") || break
        [ -z "${name}" ] && break
        if [ "${name}" = "Block-QUIC" ]; then
            uci delete "firewall.@rule[${i}]"
            changed=1
            continue
        fi
        i=$((i + 1))
    done
    if [ "${changed}" -eq 1 ]; then
        uci commit firewall || return 1
        if [ -x /etc/init.d/firewall ]; then
            /etc/init.d/firewall reload >/dev/null 2>&1
        fi
    fi
    return 0
}

quic_block_toggle() {
    if quic_is_blocked; then
        tui_info "Отключаем блокировку QUIC..."
        if quic_block_disable; then
            tui_success "Блокировка QUIC отключена."
        else
            tui_error "Не удалось отключить блокировку QUIC в firewall."
        fi
    else
        tui_info "Включаем блокировку QUIC (REJECT UDP 443)..."
        if quic_block_enable; then
            tui_success "Блокировка QUIC включена! YouTube в браузерах теперь мгновенно работает по TCP без буферизации."
        else
            tui_error "Не удалось включить блокировку QUIC в firewall."
        fi
    fi
    tui_pause
}

run_ports_menu() {
    while true; do
        tui_banner
        tui_header "Настройка перехватываемых портов TCP и UDP"

        local cur_tcp cur_udp
        cur_tcp=$(zapret_get_ports_tcp)
        cur_udp=$(zapret_get_ports_udp)

        local quic_stat="${YELLOW}Разрешен (может замедлять YouTube)${NC}"
        if quic_is_blocked; then
            quic_stat="${GREEN}Заблокирован (быстрый YouTube по TCP)${NC}"
        fi

        printf "  %bТекущие порты TCP:%b %b%s%b\n" "${BOLD}" "${NC}" "${CYAN}" "${cur_tcp}" "${NC}"
        printf "  %bТекущие порты UDP:%b %b%s%b\n" "${BOLD}" "${NC}" "${CYAN}" "${cur_udp}" "${NC}"
        printf "  %bБлокировка QUIC  :%b %b\n" "${BOLD}" "${NC}" "${quic_stat}"
        printf "%b  -------------------------------------------------------------------%b\n\n" "${DGRAY}" "${NC}"

        printf "  1. Установить рекомендуемые порты (Web + Discord Voice + Cloudflare)\n"
        printf "     %bTCP: %s%b\n" "${DGRAY}" "${DEFAULT_PORTS_TCP}" "${NC}"
        printf "     %bUDP: %s%b\n\n" "${DGRAY}" "${DEFAULT_PORTS_UDP}" "${NC}"

        printf "  2. Установить расширенные порты для игр и медиа (Xtreme Gaming)\n"
        printf "     %bTCP: 80,443,2053,2083,2087,2096,8443,25565,27015-27030%b\n" "${DGRAY}" "${NC}"
        printf "     %bUDP: 443,19294-19344,27015-27030,50000-65535%b\n\n" "${DGRAY}" "${NC}"

        printf "  3. Задать порты TCP вручную\n"
        printf "  4. Задать порты UDP вручную\n"
        printf "  5. Сбросить на минимальные стандартные порты (80,443 / 443)\n"
        printf "  6. Переключить блокировку QUIC (ускорение YouTube без задержек)\n"
        printf "  0. Назад в главное меню\n\n"

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
            6)
                quic_block_toggle
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
