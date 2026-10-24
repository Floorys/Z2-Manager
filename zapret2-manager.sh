#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Main Control Panel & Automation Suite for OpenWrt
# Based on Asterlike/zapret2UI and 1andrevich/zapret2-openwrt
# ==============================================================================

# Task 10: Root check for modifying network and system configuration
if [ "$1" != "--help" ] && [ "$1" != "-h" ] && [ "$(id -u 2>/dev/null)" -ne 0 ]; then
    printf "Ошибка: Zapret2-Manager требует прав root (суперпользователя)!\n" >&2
    printf "Запустите команду через sudo или войдите под учетной записью root.\n" >&2
    exit 1
fi

# Task 3: Robust determination of Z2M_DIR resolving symlinks (e.g. /usr/bin/z2m)
TARGET="$0"
while [ -L "${TARGET}" ]; do
    LINK="$(readlink "${TARGET}" 2>/dev/null)" || break
    case "${LINK}" in
        /*) TARGET="${LINK}" ;;
        *)  TARGET="$(dirname "${TARGET}")/${LINK}" ;;
    esac
done
SCRIPT_DIR="$(cd "$(dirname "${TARGET}")" >/dev/null 2>&1 && pwd)"

if [ -f "${SCRIPT_DIR}/core/config.sh" ]; then
    Z2M_DIR="${SCRIPT_DIR}"
elif [ -n "${Z2M_DIR:-}" ] && [ -f "${Z2M_DIR}/core/config.sh" ]; then
    : # Keep valid environment Z2M_DIR
elif [ -f "/opt/zapret2-manager/core/config.sh" ]; then
    Z2M_DIR="/opt/zapret2-manager"
else
    printf "Ошибка: Каталог установки Zapret2-Manager не найден!\n" >&2
    printf "Файл core/config.sh отсутствует по пути: %s/core/config.sh\n" "${SCRIPT_DIR}" >&2
    printf "Убедитесь, что файлы установлены в /opt/zapret2-manager или скрипт запускается из корня репозитория.\n" >&2
    exit 1
fi
export Z2M_DIR

# Task 3: Verify core/config.sh exists before sourcing
if [ ! -f "${Z2M_DIR}/core/config.sh" ]; then
    printf "Ошибка: критический файл конфигурации %s/core/config.sh не найден!\n" "${Z2M_DIR}" >&2
    exit 1
fi

# Task 3: Check existence of each module before sourcing
for _mod in \
    "${Z2M_DIR}/core/config.sh" \
    "${Z2M_DIR}/core/tui.sh" \
    "${Z2M_DIR}/core/zapret_service.sh" \
    "${Z2M_DIR}/core/probe.sh" \
    "${Z2M_DIR}/core/combo_builder.sh" \
    "${Z2M_DIR}/strategies/candidates.sh" \
    "${Z2M_DIR}/strategies/catalog.sh" \
    "${Z2M_DIR}/modules/autoselect.sh" \
    "${Z2M_DIR}/modules/generator.sh" \
    "${Z2M_DIR}/modules/diagnostics.sh" \
    "${Z2M_DIR}/modules/hostlists.sh" \
    "${Z2M_DIR}/modules/dns.sh" \
    "${Z2M_DIR}/modules/discord_fix.sh" \
    "${Z2M_DIR}/modules/ports.sh" \
    "${Z2M_DIR}/modules/updater.sh"
do
    if [ -f "${_mod}" ]; then
        # shellcheck disable=SC1090
        . "${_mod}"
    else
        printf "Ошибка: необходимый модуль %s не найден!\n" "${_mod}" >&2
        exit 1
    fi
done
unset _mod

# Task 2: Isolated bootstrap routine (repair config & sync blobs across whole fake/ directory)
z2m_bootstrap() {
    zapret_repair_config

    # Check all fake blobs from fake/ directory rather than just one single file
    local missing_blob=0
    if [ -d "${Z2M_DIR}/fake" ] && [ -d "${ZAPRET2_DIR}" ]; then
        for blob_file in "${Z2M_DIR}/fake/"*.bin; do
            [ -f "${blob_file}" ] || continue
            local blob_name
            blob_name="${blob_file##*/}"
            if [ ! -f "${ZAPRET2_FAKE_DIR}/${blob_name}" ]; then
                missing_blob=1
                break
            fi
        done
        if [ "${missing_blob}" -eq 1 ]; then
            zapret_sync_fake_blobs
            zapret_sync_hostlists
        fi
    fi
}

# 1. Меню управления службой Zapret2
service_menu() {
    while true; do
        tui_banner
        tui_header "🛡️ Управление службой Zapret2"

        local st="${RED}Остановлена${NC}"
        if zapret_is_running; then
            local pids
            pids=$(pidof nfqws2 2>/dev/null || pgrep nfqws2 2>/dev/null || pidof nfqws 2>/dev/null)
            st="${GREEN}Запущена (PID: ${pids})${NC}"
        fi
        local cur_ver
        cur_ver=$(zapret_get_installed_version)

        printf "  %bТекущее состояние:%b %b\n" "${BOLD}" "${NC}" "${st}"
        printf "  %bВерсия Zapret2   :%b %b%s%b\n" "${BOLD}" "${NC}" "${CYAN}" "${cur_ver:-не установлена}" "${NC}"

        local cur_opt
        cur_opt=$(zapret_get_opt)
        local short_opt
        short_opt=$(printf "%.55s" "${cur_opt}")
        [ ${#cur_opt} -gt 55 ] && short_opt="${short_opt}..."
        printf "  %bПараметры NFQWS2 :%b %b%s%b\n" "${BOLD}" "${NC}" "${CYAN}" "${short_opt:-по умолчанию}" "${NC}"
        printf "%b  ───────────────────────────────────────────────────────────────────%b\n\n" "${DGRAY}" "${NC}"

        printf "  1. Запустить службу\n"
        printf "  2. Остановить службу\n"
        printf "  3. Перезапустить службу\n"
        printf "  4. Показать полные параметры NFQWS2_OPT\n"
        printf "  5. Включить автозапуск при старте роутера\n"
        printf "  6. Отключить автозапуск\n"
        printf "  7. 🎧 Починить голос Discord (Voice / звонки / custom.d #50)\n"
        printf "  8. 🌐 Порты перехвата TCP / UDP (текущие: %s / %s)\n" "$(zapret_get_ports_tcp | cut -c1-15)..." "$(zapret_get_ports_udp | cut -c1-15)..."
        printf "  9. 🔄 Проверить и обновить Zapret2 (1andrevich/zapret2-openwrt)\n"
        printf "  0. Назад в главное меню\n\n"

        local sc
        sc=$(tui_prompt "Выберите действие" "0")
        case "${sc}" in
            1)
                tui_info "Запуск службы zapret2..."
                if zapret_start; then
                    tui_success "Служба успешно запущена."
                else
                    tui_error "Не удалось запустить службу zapret2!"
                    tui_info "Для диагностики выполните: logread | grep -i nfqws"
                fi
                tui_pause
                ;;
            2)
                tui_info "Остановка службы zapret2..."
                if zapret_stop; then
                    tui_success "Служба успешно остановлена."
                else
                    tui_error "Не удалось остановить процесс nfqws2!"
                    tui_info "Для диагностики выполните: logread | grep -i nfqws"
                fi
                tui_pause
                ;;
            3)
                tui_info "Перезапуск службы zapret2..."
                if zapret_restart; then
                    tui_success "Служба успешно перезапущена."
                else
                    tui_error "Не удалось перезапустить службу zapret2!"
                    tui_info "Для диагностики выполните: logread | grep -i nfqws"
                fi
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
                [ -f /etc/init.d/zapret2 ] && /etc/init.d/zapret2 enable >/dev/null 2>&1
                [ -f /etc/init.d/zapret ] && /etc/init.d/zapret enable >/dev/null 2>&1
                tui_success "Автозапуск включен."
                tui_pause
                ;;
            6)
                [ -f /etc/init.d/zapret2 ] && /etc/init.d/zapret2 disable >/dev/null 2>&1
                [ -f /etc/init.d/zapret ] && /etc/init.d/zapret disable >/dev/null 2>&1
                tui_warn "Автозапуск отключен."
                tui_pause
                ;;
            7)
                run_discord_fix_menu
                ;;
            8)
                run_ports_menu
                ;;
            9)
                zapret_run_update "" "0" "0"
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

# 2. Меню подбора и тестирования стратегий
strategy_menu() {
    while true; do
        tui_banner
        tui_header "🧬 Подбор и тестирование стратегий"

        printf "  1. ⚡ Автоподбор из каталога        %b(быстрая проверка 9 проверенных стратегий)%b\n" "${DGRAY}" "${NC}"
        printf "  2. 🧬 Двухпроходный генератор       %b(полный алгоритм Asterlike: Discord + YouTube)%b\n" "${DGRAY}" "${NC}"
        printf "  3. ▶️ Тестирование только YouTube   %b(подбор стратегии для видео и googlevideo)%b\n" "${DGRAY}" "${NC}"
        printf "  4. 💬 Тестирование только Discord   %b(подбор стратегии для Gateway и CDN)%b\n" "${DGRAY}" "${NC}"
        printf "  5. 🔍 Проверить текущую стратегию   %b(быстрый отчет по доступности хостов)%b\n" "${DGRAY}" "${NC}"
        printf "  6. 🎧 Исправление голоса Discord    %b(звонки, RTC, custom.d #50)%b\n" "${DGRAY}" "${NC}"
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
            6)
                run_discord_fix_menu
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
# Task 5: Check case for non-numeric input first to prevent ash "bad number" errors
manual_catalog_menu() {
    tui_banner
    tui_header "🎯 Каталог проверенных стратегий"

    local i=1
    while [ "${i}" -le "${CATALOG_COUNT}" ]; do
        local name tagline
        name=$(catalog_get_name "${i}")
        tagline=$(catalog_get_tagline "${i}")
        printf "  %b%2s.%b %-36s %b%s%b\n" "${BOLD}" "${i}" "${NC}" "${name}" "${DGRAY}" "${tagline}" "${NC}"
        i=$(( i + 1 ))
    done
    printf "   0. Назад в главное меню\n\n"

    local sel
    sel=$(tui_prompt "Выберите номер стратегии для применения (0 для отмены)" "0")
    case "${sel}" in
        0|q|Q)
            return 0
            ;;
        ''|*[!0-9]*)
            tui_warn "Неверный ввод: укажите число от 1 до ${CATALOG_COUNT}."
            sleep 1
            ;;
        *)
            if [ "${sel}" -ge 1 ] && [ "${sel}" -le "${CATALOG_COUNT}" ]; then
                local chosen_name chosen_opt
                chosen_name=$(catalog_get_name "${sel}")
                chosen_opt=$(catalog_get_opt "${sel}")
                tui_info "Применяем стратегию: «${chosen_name}»..."
                zapret_set_opt "${chosen_opt}"
                tui_success "Стратегия успешно применена!"
                tui_pause
            else
                tui_warn "Номер вне диапазона (1-${CATALOG_COUNT})."
                sleep 1
            fi
            ;;
    esac
}

# Главное меню в стиле StressOzz Zapret-Manager
main_menu() {
    # Task 2: Bootstrap config and blobs when entering interactive menu
    z2m_bootstrap

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
        local zap_ver
        zap_ver=$(zapret_get_installed_version)

        if zapret_is_installed; then
            if zapret_is_running; then
                local pids
                pids=$(pidof nfqws2 2>/dev/null || pgrep nfqws2 2>/dev/null || pidof nfqws 2>/dev/null)
                zapret_stat="${GREEN}Запущена (PID: ${pids})${NC}"
            fi
        else
            zapret_stat="${RED}Не установлена${NC}"
        fi

        local zap_display="${zapret_stat}"
        [ -n "${zap_ver}" ] && zap_display="${zapret_stat} ${CYAN}[v${zap_ver}]${NC}"

        local doh_stat="${YELLOW}Обычный (без шифрования)${NC}"
        if is_doh_running; then
            doh_stat="${GREEN}DoH активен (https-dns-proxy)${NC}"
        fi

        local cur_tcp cur_udp
        cur_tcp=$(zapret_get_ports_tcp)
        cur_udp=$(zapret_get_ports_udp)
        local short_tcp short_udp
        short_tcp=$(printf "%.40s" "${cur_tcp}")
        [ ${#cur_tcp} -gt 40 ] && short_tcp="${short_tcp}..."
        short_udp=$(printf "%.40s" "${cur_udp}")
        [ ${#cur_udp} -gt 40 ] && short_udp="${short_udp}..."

        printf "  %bУстройство :%b %b%s%b (%s)\n" "${BOLD}" "${NC}" "${CYAN}" "${model}" "${NC}" "${owrt_ver}"
        printf "  %bZapret2    :%b %b\n" "${BOLD}" "${NC}" "${zap_display}"
        printf "  %bПорты TCP  :%b %b%s%b\n" "${BOLD}" "${NC}" "${GREEN}" "${short_tcp}" "${NC}"
        printf "  %bПорты UDP  :%b %b%s%b\n" "${BOLD}" "${NC}" "${GREEN}" "${short_udp}" "${NC}"
        printf "  %bDNS / DoH  :%b %b\n" "${BOLD}" "${NC}" "${doh_stat}"
        printf "%b  ───────────────────────────────────────────────────────────────────%b\n\n" "${DGRAY}" "${NC}"

        printf "  %b1.%b 🛡️ %bНастройка и служба Zapret2%b    %b(статус, запуск, перезапуск, автозапуск)%b\n" "${BOLD}" "${NC}" "${BLUE}" "${NC}" "${DGRAY}" "${NC}"
        printf "  %b2.%b 🧬 %bПодбор и генерация стратегий%b  %b(генератор Asterlike, автоподбор, тесты)%b\n" "${BOLD}" "${NC}" "${MAGENTA}" "${NC}" "${DGRAY}" "${NC}"
        printf "  %b3.%b 🎯 %bКаталог готовых стратегий%b     %b(9 пресетов: General, Flowseal, VK...)%b\n" "${BOLD}" "${NC}" "${WHITE}" "${NC}" "${DGRAY}" "${NC}"
        printf "  %b4.%b 🎧 %bИсправление Discord Voice (звонки/RTC)%b %b(STUN + Media IP Discovery)%b\n" "${BOLD}" "${NC}" "${MAGENTA}" "${NC}" "${DGRAY}" "${NC}"
        printf "  %b5.%b 🌐 %bПорты перехвата TCP / UDP%b     %b(Cloudflare, Discord, игры: 80,443... / 443,50000...)%b\n" "${BOLD}" "${NC}" "${CYAN}" "${NC}" "${DGRAY}" "${NC}"
        printf "  %b6.%b 🔐 %bНастройка DNS и DoH%b           %b(Google, Quad9, Xbox, DNS.ru, Cloudflare)%b\n" "${BOLD}" "${NC}" "${GREEN}" "${NC}" "${DGRAY}" "${NC}"
        printf "  %b7.%b 📁 %bСписки доменов и исключений%b   %b(YouTube, Discord, Исключения)%b\n" "${BOLD}" "${NC}" "${YELLOW}" "${NC}" "${DGRAY}" "${NC}"
        printf "  %b8.%b 🩺 Диагностика сети и блокировок     %b(проверка DPI RST/Freeze, вердикты)%b\n" "${BOLD}" "${NC}" "${DGRAY}" "${NC}"
        printf "  %b9.%b 📦 Синхронизация файлов и блобов    %b(копирование fake-блобов в /opt/zapret2)%b\n" "${BOLD}" "${NC}" "${DGRAY}" "${NC}"
        printf "  %b10.%b 🔄 Центр обновлений             %b(проверка и обновление Zapret2 и Z2-Manager)%b\n" "${BOLD}" "${NC}" "${DGRAY}" "${NC}"
        printf "  %b0.%b Выход\n\n" "${BOLD}" "${NC}"

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
                run_discord_fix_menu
                ;;
            5)
                run_ports_menu
                ;;
            6)
                run_dns_menu
                ;;
            7)
                run_hostlists_menu
                ;;
            8)
                run_diagnostics
                ;;
            9)
                tui_info "Синхронизация блобов и списков в /opt/zapret2..."
                zapret_sync_fake_blobs
                zapret_sync_hostlists
                tui_success "Файлы успешно синхронизированы!"
                tui_pause
                ;;
            10|u|U)
                run_updates_menu
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
# Task 2: Mutating operations bootstrap when called; query/status operations have ZERO side-effects
case "$1" in
    --autoselect|-a)
        z2m_bootstrap
        run_strategy_autoselect
        exit 0
        ;;
    --generate|-g)
        z2m_bootstrap
        run_strategy_generator
        exit 0
        ;;
    --youtube|-yt)
        z2m_bootstrap
        run_test_youtube_only
        exit 0
        ;;
    --discord|-dc)
        z2m_bootstrap
        run_test_discord_only
        exit 0
        ;;
    --discord-voice|-dv|--voice)
        z2m_bootstrap
        discord_fix_apply
        exit 0
        ;;
    --ports|-p)
        z2m_bootstrap
        run_ports_menu
        exit 0
        ;;
    --diagnostics|-d)
        # Task 2: No bootstrap, zero side-effects
        run_diagnostics
        exit 0
        ;;
    --restart|-r)
        zapret_restart
        exit 0
        ;;
    --status|-s)
        # Task 2: No bootstrap, zero side-effects
        zapret_status
        exit 0
        ;;
    --update-zapret|-uz)
        z2m_bootstrap
        zapret_run_update "" "1" "1"
        exit 0
        ;;
    --check-update|-c|-cu)
        # Task 2: No bootstrap, zero side-effects
        run_check_updates_cli
        exit 0
        ;;
    --update-all|-ua)
        z2m_bootstrap
        run_update_all
        exit 0
        ;;
    --update|-u)
        z2m_bootstrap
        run_updates_menu
        exit 0
        ;;
    --help|-h)
        # Task 2 & 6: Aligned with README.md and all CLI flags
        printf "Zapret2-Manager v%s\n\n" "${Z2M_VERSION}"
        printf "Использование:\n"
        printf "  z2m | zsm                         Интерактивное меню\n"
        printf "  z2m -a  | --autoselect           Автоподбор лучшей стратегии из каталога\n"
        printf "  z2m -g  | --generate             Запуск двухпроходного генератора связок\n"
        printf "  z2m -yt | --youtube              Тестирование стратегий только для YouTube\n"
        printf "  z2m -dc | --discord              Тестирование стратегий только для Discord\n"
        printf "  z2m -dv | --discord-voice|--voice Установка исправления Discord Voice (звонки / RTC)\n"
        printf "  z2m -p  | --ports                Настройка перехватываемых портов TCP / UDP\n"
        printf "  z2m -d  | --diagnostics          Диагностика доступности сервисов и DPI\n"
        printf "  z2m -u  | --update               Центр обновлений (интерактивное меню)\n"
        printf "  z2m -uz | --update-zapret       Обновление пакета Zapret2 до актуальной версии\n"
        printf "  z2m -cu | -c | --check-update    Быстрая проверка доступных обновлений\n"
        printf "  z2m -ua | --update-all          Автоматическое обновление Zapret2 и Z2-Manager\n"
        printf "  z2m -r  | --restart              Перезапуск службы zapret2\n"
        printf "  z2m -s  | --status               Вывод статуса службы (running/stopped)\n"
        exit 0
        ;;
    *)
        main_menu
        ;;
esac
