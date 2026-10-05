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
    if pidof https-dns-proxy >/dev/null 2>&1 || pgrep https-dns-proxy >/dev/null 2>&1; then
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

        printf "  1. 🩺 Проверить DNS на подмену (DNS Poisoning / заглушка РКН)\n"
        printf "  2. 🌐 Настроить DNS-over-HTTPS (DoH: Google, Quad9, Xbox, DNS.ru...)\n"
        printf "  3. 🛡️ Установить безопасные DNS в dnsmasq (без шифрования)\n"
        printf "  4. ⏹️ Отключить DoH и сбросить DNS на стандартные провайдера\n"
        printf "  0. ↩️ Назад в главное меню\n\n"

        local choice
        choice=$(tui_prompt "Выберите действие" "0")

        case "${choice}" in
            1)
                _check_dns_poisoning
                ;;
            2)
                _setup_doh
                ;;
            3)
                _set_secure_dnsmasq
                ;;
            4)
                _disable_doh
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
    local ip=""

    if command -v nslookup >/dev/null 2>&1; then
        ip=$(nslookup "${test_domain}" 2>/dev/null | grep -A1 "Name:" | grep "Address" | awk '{print $2}' | head -n1)
    fi

    if [ -z "${ip}" ] && command -v getent >/dev/null 2>&1; then
        ip=$(getent hosts "${test_domain}" 2>/dev/null | awk '{print $1}')
    fi

    echo ""
    if [ -n "${ip}" ]; then
        printf "  Домен %s разрешен в IP: ${CYAN}%s${NC}\n" "${test_domain}" "${ip}"
        case "${ip}" in
            127.0.0.1|0.0.0.0|10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
                tui_error "ВНИМАНИЕ: Обнаружена подмена DNS провайдером (DNS Spoofing / Локальная заглушка)!"
                tui_warn "Рекомендуется включить DNS-over-HTTPS (DoH) для обхода перехвата DNS."
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

_setup_doh() {
    tui_banner
    tui_header "Выбор провайдера DNS-over-HTTPS (DoH)"
    printf "  ${BOLD}1.${NC} Google DNS      ${DGRAY}(https://dns.google/dns-query | 8.8.8.8)${NC}\n"
    printf "  ${BOLD}2.${NC} Quad9 DNS       ${DGRAY}(https://dns.quad9.net/dns-query | 9.9.9.9, без цензуры)${NC}\n"
    printf "  ${BOLD}3.${NC} Xbox / Comss    ${DGRAY}(https://dns.comss.one/dns-query | обход блокировок консолей)${NC}\n"
    printf "  ${BOLD}4.${NC} DNS.ru / Yandex ${DGRAY}(https://common.dot.dns.yandex.net/dns-query | быстрый RU)${NC}\n"
    printf "  ${BOLD}5.${NC} Cloudflare DNS  ${DGRAY}(https://cloudflare-dns.com/dns-query | 1.1.1.1)${NC}\n"
    printf "  ${BOLD}6.${NC} AdGuard DNS     ${DGRAY}(https://dns.adguard.com/dns-query | блокировка рекламы)${NC}\n"
    printf "  ${BOLD}7.${NC} Пользовательский DoH URL\n"
    printf "  ${BOLD}0.${NC} Отмена\n\n"

    local p_choice
    p_choice=$(tui_prompt "Выберите провайдера" "1")
    local doh_url=""
    local doh_name=""
    local bootstrap_ips=""

    case "${p_choice}" in
        1)
            doh_url="https://dns.google/dns-query"
            doh_name="Google DNS"
            bootstrap_ips="8.8.8.8,8.8.4.4"
            ;;
        2)
            doh_url="https://dns.quad9.net/dns-query"
            doh_name="Quad9 DNS"
            bootstrap_ips="9.9.9.9,149.112.112.112"
            ;;
        3)
            doh_url="https://dns.comss.one/dns-query"
            doh_name="Xbox DNS (Comss.one)"
            bootstrap_ips="95.216.208.204,188.138.8.199"
            ;;
        4)
            doh_url="https://common.dot.dns.yandex.net/dns-query"
            doh_name="DNS.ru / Yandex DNS"
            bootstrap_ips="77.88.8.8,77.88.8.1"
            ;;
        5)
            doh_url="https://cloudflare-dns.com/dns-query"
            doh_name="Cloudflare DNS"
            bootstrap_ips="1.1.1.1,1.0.0.1"
            ;;
        6)
            doh_url="https://dns.adguard.com/dns-query"
            doh_name="AdGuard DNS"
            bootstrap_ips="94.140.14.14,94.140.15.15"
            ;;
        7)
            doh_url=$(tui_prompt "Введите полный DoH URL" "https://dns.google/dns-query")
            doh_name="Custom DoH"
            bootstrap_ips="8.8.8.8,1.1.1.1"
            ;;
        0)
            return
            ;;
        *)
            tui_warn "Неверный выбор"
            sleep 1
            return
            ;;
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
        # Конфигурация https-dns-proxy
        uci -q delete https-dns-proxy.@https-dns-proxy[0] 2>/dev/null
        uci add https-dns-proxy https-dns-proxy >/dev/null 2>&1
        uci set https-dns-proxy.@https-dns-proxy[0].bootstrap_dns="${bootstrap_ips}" 2>/dev/null
        uci set https-dns-proxy.@https-dns-proxy[0].resolver_url="${doh_url}" 2>/dev/null
        uci set https-dns-proxy.@https-dns-proxy[0].url_prefix="${doh_url}" 2>/dev/null
        uci set https-dns-proxy.@https-dns-proxy[0].listen_addr="127.0.0.1" 2>/dev/null
        uci set https-dns-proxy.@https-dns-proxy[0].listen_port="5053" 2>/dev/null
        uci commit https-dns-proxy 2>/dev/null

        /etc/init.d/https-dns-proxy enable >/dev/null 2>&1
        /etc/init.d/https-dns-proxy restart >/dev/null 2>&1

        # Направляем dnsmasq на локальный DoH прокси (127.0.0.1#5053)
        uci -q delete dhcp.@dnsmasq[0].server 2>/dev/null
        uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5053"
        uci set dhcp.@dnsmasq[0].noresolv="1"
        uci commit dhcp
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
        tui_success "DoH (${doh_name}) успешно настроен и запущен через 127.0.0.1:5053!"
    else
        tui_warn "Пакет https-dns-proxy недоступен в репозиториях вашего роутера."
        tui_info "Настраиваем безопасные DNS напрямую в dnsmasq..."
        local ip1 ip2
        ip1=$(echo "${bootstrap_ips}" | cut -d',' -f1)
        ip2=$(echo "${bootstrap_ips}" | cut -d',' -f2)
        uci -q delete dhcp.@dnsmasq[0].server 2>/dev/null
        [ -n "${ip1}" ] && uci add_list dhcp.@dnsmasq[0].server="${ip1}"
        [ -n "${ip2}" ] && uci add_list dhcp.@dnsmasq[0].server="${ip2}"
        uci set dhcp.@dnsmasq[0].noresolv="1"
        uci commit dhcp
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
        tui_success "DNS (${doh_name}) успешно настроен в dnsmasq!"
    fi
    tui_pause
}

_set_secure_dnsmasq() {
    tui_banner
    tui_header "Выбор безопасных DNS для dnsmasq"
    printf "  ${BOLD}1.${NC} Google DNS      ${DGRAY}(8.8.8.8, 8.8.4.4)${NC}\n"
    printf "  ${BOLD}2.${NC} Quad9 DNS       ${DGRAY}(9.9.9.9, 149.112.112.112)${NC}\n"
    printf "  ${BOLD}3.${NC} Xbox / Comss    ${DGRAY}(95.216.208.204, 188.138.8.199)${NC}\n"
    printf "  ${BOLD}4.${NC} DNS.ru / Yandex ${DGRAY}(77.88.8.8, 77.88.8.1)${NC}\n"
    printf "  ${BOLD}5.${NC} Cloudflare DNS  ${DGRAY}(1.1.1.1, 1.0.0.1)${NC}\n"
    printf "  ${BOLD}6.${NC} AdGuard DNS     ${DGRAY}(94.140.14.14, 94.140.15.15)${NC}\n"
    printf "  ${BOLD}0.${NC} Отмена\n\n"

    local s_choice
    s_choice=$(tui_prompt "Выберите DNS" "1")
    local d1="8.8.8.8" d2="8.8.4.4" d_name="Google DNS"

    case "${s_choice}" in
        1) d1="8.8.8.8"; d2="8.8.4.4"; d_name="Google DNS" ;;
        2) d1="9.9.9.9"; d2="149.112.112.112"; d_name="Quad9 DNS" ;;
        3) d1="95.216.208.204"; d2="188.138.8.199"; d_name="Xbox DNS (Comss)" ;;
        4) d1="77.88.8.8"; d2="77.88.8.1"; d_name="DNS.ru / Yandex DNS" ;;
        5) d1="1.1.1.1"; d2="1.0.0.1"; d_name="Cloudflare DNS" ;;
        6) d1="94.140.14.14"; d2="94.140.15.15"; d_name="AdGuard DNS" ;;
        0) return ;;
        *) tui_warn "Неверный выбор"; sleep 1; return ;;
    esac

    tui_info "Настройка ${d_name} (${d1}, ${d2}) в dnsmasq..."
    uci -q delete dhcp.@dnsmasq[0].server 2>/dev/null
    uci add_list dhcp.@dnsmasq[0].server="${d1}"
    uci add_list dhcp.@dnsmasq[0].server="${d2}"
    uci set dhcp.@dnsmasq[0].noresolv="1"
    uci commit dhcp
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    tui_success "${d_name} успешно установлен в dnsmasq!"
    tui_pause
}

_disable_doh() {
    tui_info "Отключение DoH и сброс DNS на стандартные провайдера (DHCP)..."
    if [ -f /etc/init.d/https-dns-proxy ]; then
        /etc/init.d/https-dns-proxy stop >/dev/null 2>&1
        /etc/init.d/https-dns-proxy disable >/dev/null 2>&1
    fi
    uci -q delete dhcp.@dnsmasq[0].server 2>/dev/null
    uci set dhcp.@dnsmasq[0].noresolv="0"
    uci commit dhcp
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    tui_success "DNS успешно сброшен на параметры провайдера."
    tui_pause
}
