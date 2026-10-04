#!/bin/sh
# ==============================================================================
# Zapret2-Manager: DNS & DoH Management Module
# DNS leak prevention and DNS-over-HTTPS configuration for OpenWrt
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="/opt/zapret2-manager"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"
[ -f "${Z2M_DIR}/core/tui.sh" ] && . "${Z2M_DIR}/core/tui.sh"

get_current_dns() {
    local dns_list=""
    if [ -f /tmp/resolv.conf.auto ]; then
        dns_list=$(grep "^nameserver" /tmp/resolv.conf.auto 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
    fi
    if [ -z "${dns_list}" ] && [ -f /etc/resolv.conf ]; then
        dns_list=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
    fi
    echo "${dns_list:-127.0.0.1}"
}

is_doh_running() {
    if pgrep https-dns-proxy >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

run_dns_menu() {
    while true; do
        tui_banner
        tui_header "🔐 Меню настройки DNS и DNS-over-HTTPS (DoH)"

        local cur_dns
        cur_dns=$(get_current_dns)
        printf "  ${BOLD}Текущие DNS:${NC} ${CYAN}%s${NC}\n" "${cur_dns}"

        local doh_status="${RED}Не активен${NC}"
        if is_doh_running; then
            doh_status="${GREEN}Работает (https-dns-proxy)${NC}"
        fi
        printf "  ${BOLD}Статус DoH :${NC} %b\n" "${doh_status}"
        printf "  ${DGRAY}───────────────────────────────────────────────────────────────────${NC}\n\n"

        printf "  1. Проверить DNS на подмену (DNS Poisoning / РКН)\n"
        printf "  2. Установить безопасные DNS в dnsmasq (1.1.1.1 / 8.8.8.8)\n"
        printf "  3. Настроить DoH (DNS over HTTPS через Cloudflare)\n"
        printf "  4. Сбросить DNS на стандартные провайдера (DHCP)\n"
        printf "  0. Назад в главное меню\n\n"

        local choice
        choice=$(tui_prompt "Выберите действие" "0")

        case "${choice}" in
            1)
                _check_dns_poisoning
                ;;
            2)
                _set_secure_dnsmasq
                ;;
            3)
                _setup_doh
                ;;
            4)
                _reset_dns
                ;;
            0)
                break
                ;;
            *)
                tui_warn "Неверный выбор"
                sleep 1
                ;;
        esac
    done
}

_check_dns_poisoning() {
    tui_banner
    tui_header "Проверка DNS на вмешательство провайдера"
    tui_info "Тестируем резолв заблокированных доменов через текущий DNS..."

    local test_domain="rutracker.org"
    local ip
    ip=$(nslookup "${test_domain}" 2>/dev/null | grep -A1 "Name:" | grep "Address" | awk '{print $2}' | head -n1)

    if [ -z "${ip}" ]; then
        ip=$(getent hosts "${test_domain}" 2>/dev/null | awk '{print $1}')
    fi

    echo ""
    if [ -n "${ip}" ]; then
        printf "  Домен %s разрешен в IP: ${CYAN}%s${NC}\n" "${test_domain}" "${ip}"
        case "${ip}" in
            127.0.0.1|0.0.0.0|10.*|192.168.*)
                tui_error "ВНИМАНИЕ: Обнаружена подмена DNS провайдером (DNS Spoofing / Заглушка)!"
                tui_warn "Рекомендуется включить безопасные DNS или DoH."
                ;;
            *)
                tui_success "DNS-ответ выглядит реальным. Прямая подмена не зафиксирована."
                ;;
        esac
    else
        tui_warn "Не удалось разрешить домен ${test_domain}."
    fi
    tui_pause
}

_set_secure_dnsmasq() {
    tui_info "Настройка DNS Cloudflare (1.1.1.1) и Google (8.8.8.8) в dnsmasq..."
    uci -q delete dhcp.@dnsmasq[0].server 2>/dev/null
    uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
    uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'
    uci set dhcp.@dnsmasq[0].noresolv='1'
    uci commit dhcp
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    tui_success "DNS успешно настроен на 1.1.1.1 и 8.8.8.8!"
    tui_pause
}

_setup_doh() {
    tui_banner
    tui_header "Выбор DoH провайдера"
    printf "  1. Cloudflare (https://cloudflare-dns.com/dns-query)\n"
    printf "  2. Google     (https://dns.google/dns-query)\n"
    printf "  3. Quad9      (https://dns.quad9.net/dns-query)\n"
    printf "  4. AdGuard    (https://dns.adguard.com/dns-query)\n"
    printf "  0. Отмена\n\n"

    local p_choice
    p_choice=$(tui_prompt "Выберите провайдера" "1")
    local doh_url="https://cloudflare-dns.com/dns-query"
    local doh_name="Cloudflare"

    case "${p_choice}" in
        1) doh_url="https://cloudflare-dns.com/dns-query"; doh_name="Cloudflare" ;;
        2) doh_url="https://dns.google/dns-query"; doh_name="Google" ;;
        3) doh_url="https://dns.quad9.net/dns-query"; doh_name="Quad9" ;;
        4) doh_url="https://dns.adguard.com/dns-query"; doh_name="AdGuard" ;;
        0) return ;;
    esac

    tui_info "Проверка пакета https-dns-proxy..."
    if ! command -v https-dns-proxy >/dev/null 2>&1; then
        tui_info "Устанавливаем https-dns-proxy..."
        if command -v apk >/dev/null 2>&1; then
            apk add https-dns-proxy >/dev/null 2>&1
        elif command -v opkg >/dev/null 2>&1; then
            opkg update >/dev/null 2>&1
            opkg install https-dns-proxy >/dev/null 2>&1
        fi
    fi

    if command -v https-dns-proxy >/dev/null 2>&1; then
        uci -q delete https-dns-proxy.@https-dns-proxy[0].url_prefix 2>/dev/null
        uci set https-dns-proxy.@https-dns-proxy[0].url_prefix="${doh_url}"
        uci commit https-dns-proxy 2>/dev/null
        /etc/init.d/https-dns-proxy enable >/dev/null 2>&1
        /etc/init.d/https-dns-proxy restart >/dev/null 2>&1

        # Направляем dnsmasq на локальный DoH прокси (порт 5053)
        uci -q delete dhcp.@dnsmasq[0].server 2>/dev/null
        uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5053'
        uci set dhcp.@dnsmasq[0].noresolv='1'
        uci commit dhcp
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
        tui_success "DoH (${doh_name}) успешно настроен и запущен!"
    else
        tui_warn "Пакет https-dns-proxy недоступен в репозиториях вашего роутера."
        tui_info "Применяем альтернативную защиту: защищенные DNS в dnsmasq..."
        _set_secure_dnsmasq
        return
    fi
    tui_pause
}

_reset_dns() {
    tui_info "Сброс DNS на настройки провайдера по умолчанию..."
    uci -q delete dhcp.@dnsmasq[0].server 2>/dev/null
    uci set dhcp.@dnsmasq[0].noresolv='0'
    uci commit dhcp
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    tui_success "Настройки DNS сброшены."
    tui_pause
}
