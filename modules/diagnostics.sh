#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Diagnostics Module
# Comprehensive network reachability, DPI signature detection, and service status
# ==============================================================================

[ -z "${Z2M_DIR:-}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"
[ -f "${Z2M_DIR}/core/tui.sh" ] && . "${Z2M_DIR}/core/tui.sh"
[ -f "${Z2M_DIR}/core/probe.sh" ] && . "${Z2M_DIR}/core/probe.sh"
[ -f "${Z2M_DIR}/core/zapret_service.sh" ] && . "${Z2M_DIR}/core/zapret_service.sh"

get_host_category() {
    local h="$1"
    case "${h}" in
        www.youtube.com)    echo "YouTube (Web)" ;;
        googlevideo.com)    echo "YouTube (Видео)" ;;
        i.ytimg.com)        echo "YouTube (Превью)" ;;
        discord.com)        echo "Discord (Web)" ;;
        gateway.discord.gg) echo "Discord (Голос/GW)" ;;
        cdn.discordapp.com) echo "Discord (Медиа)" ;;
        rutracker.org)      echo "РКН / RuTracker" ;;
        x.com)              echo "РКН / Twitter (X)" ;;
        instagram.com)      echo "РКН / Instagram" ;;
        vk.com)             echo "Контроль связи" ;;
        *)                  echo "Веб-сервис" ;;
    esac
}

run_diagnostics() {
    tui_banner
    tui_header "Диагностика сетевой доступности и DPI блокировок"

    local interrupted=0
    cleanup_diag() {
        echo ""
        tui_warn "Диагностика прервана пользователем."
        trap - INT TERM
        interrupted=1
    }
    trap cleanup_diag INT TERM

    printf "%bСтатус службы Zapret2:%b " "${BOLD}" "${NC}"
    if zapret_is_running; then
        local pids
        pids=$(pidof nfqws2 2>/dev/null || pgrep nfqws2 2>/dev/null || pidof nfqws 2>/dev/null)
        printf "%bЗапущена (PID: %s)%b\n" "${GREEN}" "${pids}" "${NC}"
    else
        printf "%bОстановлена%b\n" "${RED}" "${NC}"
    fi

    local cur_opt
    cur_opt=$(zapret_get_opt)
    local short_opt
    short_opt=$(printf "%.50s" "${cur_opt}")
    [ ${#cur_opt} -gt 50 ] && short_opt="${short_opt}..."
    printf "%bАктивный NFQWS2_OPT :%b %b%s%b\n\n" "${BOLD}" "${NC}" "${CYAN}" "${short_opt:-по умолчанию}" "${NC}"

    tui_header "1. Проверка доступности доменов (набор как в Zapret-Manager)"
    printf "%b%-24s %-18s %-10s %-14s%b\n" "${BOLD}" "Хост" "Категория" "Статус" "DPI Вердикт" "${NC}"
    printf "%b───────────────────────────────────────────────────────────────────%b\n" "${DGRAY}" "${NC}"

    local total_hosts=0
    local ok_hosts=0

    for host in ${DIAGNOSTIC_HOSTS}; do
        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        total_hosts=$(( total_hosts + 1 ))
        local cat_name
        cat_name=$(get_host_category "${host}")

        # Live progress indicator
        printf "%-24s %-18s %b[...] Тест%b\r" "${host}" "${cat_name}" "${YELLOW}" "${NC}"

        local is_ok=0
        if probe_http_reach "${host}" 2; then
            is_ok=1
            ok_hosts=$(( ok_hosts + 1 ))
        fi

        if [ "${interrupted}" -eq 1 ]; then
            tui_pause
            return 0
        fi

        local dpi_verdict
        dpi_verdict=$(probe_dpi_verdict "${host}")
        local dpi_col="${YELLOW}"
        case "${dpi_verdict}" in
            Clean) dpi_col="${GREEN}" ;;
            Reset) dpi_col="${RED}" ;;
            Freeze) dpi_col="${MAGENTA}" ;;
            DNSError) dpi_col="${YELLOW}" ;;
            NoConnection) dpi_col="${DGRAY}" ;;
            *) dpi_col="${RED}" ;;
        esac

        printf "%-24s %-18s " "${host}" "${cat_name}"
        if [ "${is_ok}" -eq 1 ]; then
            printf "%b%-10s%b " "${GREEN}" "✓ Доступ" "${NC}"
        else
            printf "%b%-10s%b " "${RED}" "✗ Блок" "${NC}"
        fi
        printf "%b%-14s%b\n" "${dpi_col}" "${dpi_verdict}" "${NC}"
    done

    trap - INT TERM

    echo ""
    printf "  %bИтог проверки:%b доступно %b%s%b из %b%s%b сервисов.\n" \
        "${BOLD}" "${NC}" "${GREEN}" "${ok_hosts}" "${NC}" "${BOLD}" "${total_hosts}" "${NC}"

    if [ "${ok_hosts}" -eq "${total_hosts}" ]; then
        tui_success "Все сервисы доступны без признаков блокировок!"
    elif [ "${ok_hosts}" -ge 7 ]; then
        tui_info "Большинство сервисов доступно. Основные блокировки обойдены."
    else
        tui_warn "Обнаружены активные блокировки. Рекомендуется запустить автоподбор стратегии (z2m -a)."
    fi

    echo ""
    tui_header "2. Пояснение DPI вердиктов"
    printf "  %bClean%b        - соединение проходит без признаков вмешательства DPI.\n" "${GREEN}" "${NC}"
    printf "  %bReset%b        - провайдер отправляет поддельный TCP RST при отправке ClientHello SNI.\n" "${RED}" "${NC}"
    printf "  %bFreeze%b       - пакет с именем хоста (SNI) молча сбрасывается ТСПУ/DPI (Drop).\n" "${MAGENTA}" "${NC}"
    printf "  %bDNSError%b     - имя хоста не резолвится через DNS (включите DoH в меню 6).\n" "${YELLOW}" "${NC}"
    printf "  %bNoConnection%b - порт недоступен (блокировка по IP или сбой маршрутизации).\n" "${DGRAY}" "${NC}"

    tui_pause
}
