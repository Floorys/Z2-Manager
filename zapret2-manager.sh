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
. "${Z2M_DIR}/modules/discord_fix.sh"
. "${Z2M_DIR}/modules/ports.sh"
. "${Z2M_DIR}/strategies/catalog.sh"

# 3. Авто-исправление конфигурации и первичная синхронизация при необходимости
zapret_repair_config
if [ -d "${ZAPRET2_DIR}" ] && [ ! -f "${ZAPRET2_FAKE_DIR}/tls_clienthello_www_google_com.bin" ]; then
    zapret_sync_fake_blobs
    zapret_sync_hostlists
fi

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
        printf "  7. 🎧 Починить голос Discord (Voice / звонки / custom.d #50)\n"
        printf "  8. 🌐 Порты перехвата TCP / UDP (текущие: %s / %s)\n" "$(zapret_get_ports_tcp | cut -c1-15)..." "$(zapret_get_ports_udp | cut -c1-15)..."
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
        printf "  5. 🔍 Проверить текущую стратегию   ${DGRAY}(быстрый отчет по доступности хостов)${NC}\n"
        printf "  6. 🎧 Исправление голоса Discord    ${DGRAY}(звонки, RTC, custom.d #50)${NC}\n"
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
manual_catalog_menu() {
    tui_banner
    tui_header "🎯 Каталог проверенных стратегий"

    local i=1
    while [ "${i}" -le "${CATALOG_COUNT}" ]; do
        local name tagline
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
        tui_success "Стратегия успешно применена!"
        tui_pause
    fi
}

# Функция самообновления из GitHub (в стиле StressOzz)
run_self_update() {
    tui_banner
    tui_header "🔄 Обновление Zapret2-Manager"
    tui_info "Загрузка актуальной версии из репозитория Floorys/Z2-Manager..."

    local update_url="https://github.com/Floorys/Z2-Manager/archive/refs/heads/main.tar.gz"
    local tmp_tar="/tmp/z2m_update.tar.gz"
    local tmp_dir="/tmp/z2m_update_extracted"

    rm -rf "${tmp_tar}" "${tmp_dir}" 2>/dev/null
    mkdir -p "${tmp_dir}" 2>/dev/null

    if command -v curl >/dev/null 2>&1; then
        curl -sSL -k --connect-timeout 8 -m 30 "${update_url}" -o "${tmp_tar}" 2>/dev/null
    fi
    if [ ! -s "${tmp_tar}" ] && command -v wget >/dev/null 2>&1; then
        wget -q --timeout=15 -O "${tmp_tar}" "${update_url}" 2>/dev/null
    fi

    if [ ! -s "${tmp_tar}" ]; then
        tui_error "Не удалось скачать архив обновления. Проверьте соединение с интернетом."
        rm -rf "${tmp_tar}" "${tmp_dir}" 2>/dev/null
        tui_pause
        return 1
    fi

    tui_info "Распаковка новой версии..."
    if ! tar -xzf "${tmp_tar}" -C "${tmp_dir}" 2>/dev/null; then
        tui_error "Ошибка распаковки архива обновления."
        rm -rf "${tmp_tar}" "${tmp_dir}" 2>/dev/null
        tui_pause
        return 1
    fi

    local src_folder
    src_folder=$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)
    if [ -z "${src_folder}" ] || [ ! -f "${src_folder}/zapret2-manager.sh" ]; then
        tui_error "Структура обновленного архива некорректна."
        rm -rf "${tmp_tar}" "${tmp_dir}" 2>/dev/null
        tui_pause
        return 1
    fi

    tui_info "Установка файлов в /opt/zapret2-manager..."
    mkdir -p /opt/zapret2-manager
    cp -rf "${src_folder}"/* /opt/zapret2-manager/
    find /opt/zapret2-manager -name "*.sh" -exec sed -i 's/\r$//' {} + 2>/dev/null
    chmod +x /opt/zapret2-manager/*.sh 2>/dev/null
    chmod +x /opt/zapret2-manager/core/*.sh 2>/dev/null
    chmod +x /opt/zapret2-manager/modules/*.sh 2>/dev/null
    chmod +x /opt/zapret2-manager/strategies/*.sh 2>/dev/null
    chmod +x /opt/zapret2-manager/templates/*.sh 2>/dev/null

    # Обновление команд z2m и zsm
    cat << 'EOF' > /usr/bin/z2m
#!/bin/sh
exec /bin/sh /opt/zapret2-manager/zapret2-manager.sh "$@"
EOF
    chmod +x /usr/bin/z2m 2>/dev/null

    cat << 'EOF' > /usr/bin/zsm
#!/bin/sh
exec /bin/sh /opt/zapret2-manager/zapret2-manager.sh "$@"
EOF
    chmod +x /usr/bin/zsm 2>/dev/null

    # Синхронизация блобов, списков и фикса Discord Voice
    zapret_sync_fake_blobs
    zapret_sync_hostlists
    if [ -f /opt/zapret2-manager/templates/50-script.sh ] && [ -d /opt/zapret2 ]; then
        mkdir -p /opt/zapret2/init.d/openwrt/custom.d 2>/dev/null
        cp -f /opt/zapret2-manager/templates/50-script.sh /opt/zapret2/init.d/openwrt/custom.d/50-script.sh 2>/dev/null
        chmod 755 /opt/zapret2/init.d/openwrt/custom.d/50-script.sh 2>/dev/null
        if command -v uci >/dev/null 2>&1; then
            uci set zapret2.config.DISABLE_CUSTOM='0'
            uci set zapret2.config.NFQWS2_PORTS_TCP="${DEFAULT_PORTS_TCP}"
            uci set zapret2.config.NFQWS2_PORTS_UDP="${DEFAULT_PORTS_UDP}"
            uci commit zapret2 2>/dev/null
        fi
    fi

    rm -rf "${tmp_tar}" "${tmp_dir}" 2>/dev/null
    tui_success "Zapret2-Manager успешно обновлен!"
    echo ""
    tui_info "Перезапуск интерфейса менеджера..."
    sleep 1
    exec /bin/sh /opt/zapret2-manager/zapret2-manager.sh "$@"
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
                local pids
                pids=$(pidof nfqws2 2>/dev/null || pgrep nfqws2 2>/dev/null || pidof nfqws 2>/dev/null)
                zapret_stat="${GREEN}Запущена (PID: ${pids})${NC}"
            fi
        else
            zapret_stat="${RED}Не установлена${NC}"
        fi

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

        printf "  ${BOLD}Устройство :${NC} ${CYAN}%s${NC} (%s)\n" "${model}" "${owrt_ver}"
        printf "  ${BOLD}Zapret2    :${NC} %b\n" "${zapret_stat}"
        printf "  ${BOLD}Порты TCP  :${NC} ${GREEN}%s${NC}\n" "${short_tcp}"
        printf "  ${BOLD}Порты UDP  :${NC} ${GREEN}%s${NC}\n" "${short_udp}"
        printf "  ${BOLD}DNS / DoH  :${NC} %b\n" "${doh_stat}"
        printf "  ${DGRAY}───────────────────────────────────────────────────────────────────${NC}\n\n"

        printf "  ${BOLD}1.${NC} 🛡️ ${BLUE}Настройка и служба Zapret2${NC}    ${DGRAY}(статус, запуск, перезапуск, автозапуск)${NC}\n"
        printf "  ${BOLD}2.${NC} 🧬 ${MAGENTA}Подбор и генерация стратегий${NC}  ${DGRAY}(генератор Asterlike, автоподбор, тесты)${NC}\n"
        printf "  ${BOLD}3.${NC} 🎯 ${WHITE}Каталог готовых стратегий${NC}     ${DGRAY}(9 пресетов: General, Flowseal, VK...)${NC}\n"
        printf "  ${BOLD}4.${NC} 🎧 ${MAGENTA}Исправление Discord Voice (звонки/RTC)${NC} ${DGRAY}(STUN + Media IP Discovery)${NC}\n"
        printf "  ${BOLD}5.${NC} 🌐 ${CYAN}Порты перехвата TCP / UDP${NC}     ${DGRAY}(Cloudflare, Discord, игры: 80,443... / 443,50000...)${NC}\n"
        printf "  ${BOLD}6.${NC} 🔐 ${GREEN}Настройка DNS и DoH${NC}           ${DGRAY}(Google, Quad9, Xbox, DNS.ru, Cloudflare)${NC}\n"
        printf "  ${BOLD}7.${NC} 📁 ${YELLOW}Списки доменов и исключений${NC}   ${DGRAY}(YouTube, Discord, Исключения)${NC}\n"
        printf "  ${BOLD}8.${NC} 🩺 Диагностика сети и блокировок     ${DGRAY}(проверка DPI RST/Freeze, вердикты)${NC}\n"
        printf "  ${BOLD}9.${NC} 📦 Синхронизация файлов и блобов    ${DGRAY}(копирование fake-блобов в /opt/zapret2)${NC}\n"
        printf "  ${BOLD}10.${NC} 🔄 Обновить Zapret2-Manager         ${DGRAY}(автоматическое обновление из GitHub)${NC}\n"
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
                run_self_update
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
    --discord-voice|-dv|--voice)
        discord_fix_apply
        exit 0
        ;;
    --ports|-p)
        run_ports_menu
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
    --update|-u)
        run_self_update
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
        printf "  z2m -dv | --discord-voice      Установка исправления Discord Voice (звонки / RTC)\n"
        printf "  z2m -p | --ports               Настройка перехватываемых портов TCP / UDP\n"
        printf "  z2m -d | --diagnostics         Диагностика доступности сервисов и DPI\n"
        printf "  z2m -u | --update              Автоматическое обновление программы\n"
        printf "  z2m -r | --restart             Перезапуск службы zapret2\n"
        printf "  z2m -s | --status              Вывод статуса службы\n"
        exit 0
        ;;
    *)
        main_menu
        ;;
esac
