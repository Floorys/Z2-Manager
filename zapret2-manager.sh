#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Main Control Panel & Automation Suite for OpenWrt
# Based on Asterlike/zapret2UI and 1andrevich/zapret2-openwrt
# ==============================================================================

# 1. Надежное определение директории установки (разрешение путей /usr/bin/z2m и /usr/bin/zsm)
if [ -d "/opt/zapret2-manager/core" ]; then
    Z2M_DIR="/opt/zapret2-manager"
elif [ -f "$(dirname "$0")/core/config.sh" ]; then
    Z2M_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
elif [ -f "$(dirname "$0")/config.sh" ]; then
    Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
else
    Z2M_DIR="/opt/zapret2-manager"
fi
export Z2M_DIR

# 2. Подключение модулей ядра
. "${Z2M_DIR}/core/config.sh"
. "${Z2M_DIR}/core/tui.sh"
. "${Z2M_DIR}/core/zapret_service.sh"
. "${Z2M_DIR}/modules/autoselect.sh"
. "${Z2M_DIR}/modules/generator.sh"
. "${Z2M_DIR}/modules/diagnostics.sh"
. "${Z2M_DIR}/modules/hostlists.sh"
. "${Z2M_DIR}/modules/dns.sh"
. "${Z2M_DIR}/strategies/catalog.sh"

# 1. Меню управления службой Zapret2
service_menu() {
    while true; do
        tui_banner
        tui_header "🛡️ Управление службой Zapret2"

        local st="${RED}Остановлена${NC}"
        if zapret_is_running; then
            st="${GREEN}Запущена (PID: $(pgrep nfqws2 | tr '\n' ' '))${NC}"
        fi
        printf "  ${BOLD}Текущее состояние:${NC} %b\n" "${st}"

        local cur_opt
        cur_opt=$(zapret_get_opt)
        local short_opt
        short_opt=$(printf "%.55s" "${cur_opt}")
        [ ${#cur_opt} -gt 55 ] && short_opt="${short_opt}..."
        printf "  ${BOLD}Параметры NFQWS2 :${NC} ${CYAN}%s${NC}\n" "${short_opt:-по умолчанию}"
        printf "  ${DGRAY}───────────────────────────────────────────────────────────────────${NC}\n\n"

        printf "  1. Запустить службу\n"
        printf "  2. Остановить службу\n"
        printf "  3. Перезапустить службу\n"
        printf "  4. Показать полные параметры NFQWS2_OPT\n"
        printf "  5. Включить автозапуск при старте роутера\n"
        printf "  6. Отключить автозапуск\n"
        printf "  0. Назад в главное меню\n\n"

        local sc
        sc=$(tui_prompt "Выберите действие" "0")
        case "${sc}" in
            1)
                tui_info "Запуск..."
                zapret_start
                tui_success "Служба запущена."
                tui_pause
                ;;
            2)
                tui_info "Остановка..."
                zapret_stop
                tui_success "Служба остановлена."
                tui_pause
                ;;
            3)
                tui_info "Перезапуск..."
                zapret_restart
                tui_success "Служба перезапущена."
                tui_pause
                ;;
            4)
                tui_banner
                tui_header "Текущие параметры NFQWS2_OPT"
                echo "${cur_opt}"
                echo ""
                tui_pause
                ;;
            5)
                /etc/init.d/zapret2 enable >/dev/null 2>&1
                tui_success "Автозапуск включен."
                tui_pause
                ;;
            6)
                /etc/init.d/zapret2 disable >/dev/null 2>&1
                tui_warn "Автозапуск отключен."
                tui_pause
                ;;
            0)
                break
                ;;
        esac
    done
}

# 2. Меню подбора и тестирования стратегий
strategy_menu() {
    while true; do
        tui_banner
        tui_header "🧬 Подбор и тестирование стратегий"

        printf "  1. ⚡ Автоподбор из каталога        ${DGRAY}(быстрая проверка 9 проверенных стратегий)${NC}\n"
        printf "  2. 🧬 Двухпроходный генератор       ${DGRAY}(полный алгоритм Asterlike: Discord + YouTube)${NC}\n"
        printf "  3. ▶️ Тестирование только YouTube   ${DGRAY}(подбор стратегии для видео и googlevideo)${NC}\n"
        printf "  4. 💬 Тестирование только Discord   ${DGRAY}(подбор стратегии для Gateway и CDN)${NC}\n"
        printf "  5. 🔍 Проверить текущую стратегию   ${DGRAY}(детальный отчет по доступности хостов)${NC}\n"
        printf "  0. Назад в главное меню\n\n"

        local st_choice
        st_choice=$(tui_prompt "Выберите действие" "1")
        case "${st_choice}" in
            1)
                run_strategy_autoselect
                ;;
            2)
                run_strategy_generator
                ;;
            3)
                run_test_youtube_only
                ;;
            4)
                run_test_discord_only
                ;;
            5)
                run_test_current_strategy
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

# 3. Меню выбора стратегий из каталога
manual_catalog_menu() {
    tui_banner
    tui_header "🎯 Каталог проверенных стратегий"

    local i=1
    while [ "${i}" -le "${CATALOG_COUNT}" ]; do
        local name
        local tagline
        name=$(catalog_get_name "${i}")
        tagline=$(catalog_get_tagline "${i}")
        printf "  ${BOLD}%2s.${NC} %-36s ${DGRAY}%s${NC}\n" "${i}" "${name}" "${tagline}"
        i=$(( i + 1 ))
    done
    printf "   0. Назад в главное меню\n\n"

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

# Главное меню в стиле StressOzz Zapret-Manager
main_menu() {
    while true; do
        tui_banner

        # Сбор системной информации роутера
        local model
        model="$(cat /tmp/sysinfo/model 2>/dev/null || grep -i 'machine' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//')"
        [ -z "${model}" ] && model="OpenWrt"

        local owrt_ver
        owrt_ver="$(grep '^DISTRIB_RELEASE=' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)"
        [ -z "${owrt_ver}" ] && owrt_ver="OpenWrt"

        local zapret_stat="${RED}Остановлена${NC}"
        if zapret_is_installed; then
            if zapret_is_running; then
                zapret_stat="${GREEN}Запущена (PID: $(pgrep nfqws2 | tr '\n' ' '))${NC}"
            fi
        else
            zapret_stat="${RED}Не установлена${NC}"
        fi

        local doh_stat="${YELLOW}Обычный (без шифрования)${NC}"
        if is_doh_running; then
            doh_stat="${GREEN}DoH активен (https-dns-proxy)${NC}"
        fi

        printf "  ${BOLD}Устройство :${NC} ${CYAN}%s${NC} (%s)\n" "${model}" "${owrt_ver}"
        printf "  ${BOLD}Zapret2    :${NC} %b\n" "${zapret_stat}"
        printf "  ${BOLD}DNS / DoH  :${NC} %b\n" "${doh_stat}"
        printf "  ${DGRAY}───────────────────────────────────────────────────────────────────${NC}\n\n"

        printf "  ${BOLD}1.${NC} 🛡️ ${BLUE}Настройка и служба Zapret2${NC}    ${DGRAY}(статус, запуск, перезапуск, автозапуск)${NC}\n"
        printf "  ${BOLD}2.${NC} 🧬 ${MAGENTA}Подбор и генерация стратегий${NC}  ${DGRAY}(генератор Asterlike, автоподбор, тесты)${NC}\n"
        printf "  ${BOLD}3.${NC} 🎯 ${WHITE}Каталог готовых стратегий${NC}     ${DGRAY}(9 пресетов: General, Flowseal, VK...)${NC}\n"
        printf "  ${BOLD}4.${NC} 🔐 ${GREEN}Настройка DNS и DoH${NC}           ${DGRAY}(DoH, защита от подмены DNS, Cloudflare)${NC}\n"
        printf "  ${BOLD}5.${NC} 📁 ${YELLOW}Списки доменов и исключений${NC}   ${DGRAY}(YouTube, Discord, Исключения)${NC}\n"
        printf "  ${BOLD}6.${NC} 🩺 Диагностика сети и блокировок     ${DGRAY}(проверка DPI RST/Freeze, вердикты)${NC}\n"
        printf "  ${BOLD}7.${NC} 📦 Синхронизация и обновление        ${DGRAY}(синхронизация блобов /opt/zapret2)${NC}\n"
        printf "  ${BOLD}0.${NC} Выход\n\n"

        local choice
        choice=$(tui_prompt "Выберите пункт меню" "1")

        case "${choice}" in
            1)
                service_menu
                ;;
            2)
                strategy_menu
                ;;
            3)
                manual_catalog_menu
                ;;
            4)
                run_dns_menu
                ;;
            5)
                run_hostlists_menu
                ;;
            6)
                run_diagnostics
                ;;
            7)
                tui_info "Синхронизация блобов и списков в /opt/zapret2..."
                zapret_sync_fake_blobs
                zapret_sync_hostlists
                tui_success "Файлы успешно синхронизированы!"
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

# Обработка аргументов командной строки
case "$1" in
    --autoselect|-a)
        run_strategy_autoselect
        exit 0
        ;;
    --generate|-g)
        run_strategy_generator
        exit 0
        ;;
    --youtube|-yt)
        run_test_youtube_only
        exit 0
        ;;
    --discord|-dc)
        run_test_discord_only
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
        printf "  z2m | zsm                       Интерактивное меню\n"
        printf "  z2m -a | --autoselect          Автоподбор лучшей стратегии из каталога\n"
        printf "  z2m -g | --generate            Запуск двухпроходного генератора связок\n"
        printf "  z2m -yt | --youtube            Тестирование стратегий только для YouTube\n"
        printf "  z2m -dc | --discord            Тестирование стратегий только для Discord\n"
        printf "  z2m -d | --diagnostics         Диагностика доступности сервисов и DPI\n"
        printf "  z2m -r | --restart             Перезапуск службы zapret2\n"
        printf "  z2m -s | --status              Вывод статуса службы\n"
        exit 0
        ;;
    *)
        main_menu
        ;;
esac
