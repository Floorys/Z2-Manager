#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Diagnostics Module
# Network reachability, DPI signature detection, and service status
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
. "${Z2M_DIR}/core/config.sh"
. "${Z2M_DIR}/core/tui.sh"
. "${Z2M_DIR}/core/probe.sh"
. "${Z2M_DIR}/core/zapret_service.sh"

run_diagnostics() {
    tui_banner
    tui_header "🩺 Диагностика сетевой доступности и DPI блокировок"

    printf "${BOLD}Статус службы Zapret2:${NC} "
    if zapret_is_running; then
        printf "${GREEN}Работает (nfqws2 PID: %s)${NC}\n" "$(pgrep nfqws2 | tr '\n' ' ')"
    else
        printf "${RED}Остановлена${NC}\n"
    fi
    echo ""

    tui_header "1. Проверка доступности ключевых сервисов"
    printf "${BOLD}%-28s %-10s %-10s %-12s %-12s${NC}\n" "Хост" "TLS 1.2" "TLS 1.3" "HTTP Reach" "DPI Вердикт"
    printf "${DGRAY}───────────────────────────────────────────────────────────────────${NC}\n"

    for host in ${ALL_PROBE_HOSTS}; do
        local t12_res="✗" t12_col="${RED}"
        local t13_res="✗" t13_col="${RED}"
        local http_res="✗" http_col="${RED}"

        probe_tls12 "${host}" && { t12_res="✓"; t12_col="${GREEN}"; }
        probe_tls13 "${host}" && { t13_res="✓"; t13_col="${GREEN}"; }
        probe_http_reach "${host}" && { http_res="✓"; http_col="${GREEN}"; }

        local dpi_verdict
        dpi_verdict=$(probe_dpi_verdict "${host}")
        local dpi_col="${YELLOW}"
        case "${dpi_verdict}" in
            Clean) dpi_col="${GREEN}" ;;
            Reset) dpi_col="${RED}" ;;
            Freeze) dpi_col="${MAGENTA}" ;;
            NoConnection) dpi_col="${DGRAY}" ;;
        esac

        printf "%-28s ${t12_col}%-10s${NC} ${t13_col}%-10s${NC} ${http_col}%-12s${NC} ${dpi_col}%-12s${NC}\n" \
            "${host}" "${t12_res}" "${t13_res}" "${http_res}" "${dpi_verdict}"
    done

    echo ""
    tui_header "2. Пояснение DPI вердиктов"
    printf "${GREEN}Clean${NC}        - соединение проходит без признаков вмешательства DPI.\n"
    printf "${RED}Reset${NC}        - провайдер отправляет поддельный TCP RST при отправке SNI.\n"
    printf "${MAGENTA}Freeze${NC}       - пакет с именем хоста (SNI) молча сбрасывается ТСПУ/DPI.\n"
    printf "${DGRAY}NoConnection${NC} - TCP-порт недоступен (блокировка по IP или сбой маршрутизации).\n"

    tui_pause
}
