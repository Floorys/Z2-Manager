#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Discord Voice Fix Module (STUN + IP Discovery)
# ==============================================================================
# Resolves "Infinite RTC Connecting" / "No Route" in Discord voice calls.
# Manages /opt/zapret2/init.d/openwrt/custom.d/50-script.sh (LuCI script #50)
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
. "${Z2M_DIR}/core/config.sh"
. "${Z2M_DIR}/core/tui.sh"
. "${Z2M_DIR}/core/probe.sh"
. "${Z2M_DIR}/core/zapret_service.sh"

CUSTOM_D_DIR="${ZAPRET2_DIR}/init.d/openwrt/custom.d"
CUSTOM_SCRIPT_50="${CUSTOM_D_DIR}/50-script.sh"

discord_fix_get_status() {
    local script_exists=0
    local has_media=0
    local has_stun=0
    local custom_enabled=0
    local zapret_up=0

    zapret_is_running && zapret_up=1

    if [ -f "${CUSTOM_SCRIPT_50}" ]; then
        script_exists=1
        grep -qi "discord_ip_discovery" "${CUSTOM_SCRIPT_50}" 2>/dev/null && has_media=1
        grep -qi "payload=stun" "${CUSTOM_SCRIPT_50}" 2>/dev/null && has_stun=1
    fi

    local dis_custom=""
    if command -v uci >/dev/null 2>&1; then
        dis_custom="$(uci -q get zapret2.config.DISABLE_CUSTOM)"
    fi
    if [ -z "${dis_custom}" ] && [ -f "${ZAPRET2_CONFIG}" ]; then
        dis_custom="$(grep "^DISABLE_CUSTOM=" "${ZAPRET2_CONFIG}" 2>/dev/null | cut -d'=' -f2 | tr -d '"')"
    fi
    [ "${dis_custom}" = "0" ] && custom_enabled=1

    if [ "${script_exists}" -eq 1 ] && [ "${has_media}" -eq 1 ] && [ "${has_stun}" -eq 1 ]; then
        if [ "${custom_enabled}" -eq 1 ]; then
            if [ "${zapret_up}" -eq 1 ]; then
                echo "ACTIVE"
            else
                echo "STOPPED"
            fi
        else
            echo "DISABLED_IN_CONFIG"
        fi
    elif [ "${script_exists}" -eq 1 ] && [ "${has_stun}" -eq 1 ] && [ "${has_media}" -eq 0 ]; then
        echo "STUN_ONLY"
    elif [ "${script_exists}" -eq 1 ] && [ "${has_media}" -eq 1 ] && [ "${has_stun}" -eq 0 ]; then
        echo "MEDIA_ONLY"
    elif [ "${script_exists}" -eq 1 ]; then
        echo "CUSTOM_UNKNOWN"
    else
        echo "NOT_INSTALLED"
    fi
}

discord_fix_apply() {
    tui_banner
    tui_header "🎧 Установка исправления Discord Voice (звонки / RTC)"

    if ! zapret_is_installed; then
        tui_error "Пакет zapret2 не установлен в системе!"
        tui_pause
        return 1
    fi

    tui_info "1. Подготовка каталогов custom.d..."
    mkdir -p "${CUSTOM_D_DIR}" 2>/dev/null
    mkdir -p "${ZAPRET2_IPSET_DIR}" 2>/dev/null

    # Remove conflicting temporary scripts
    rm -f "${CUSTOM_D_DIR}/50-script.sh.bak" "${CUSTOM_D_DIR}/50-stun4all"* "${CUSTOM_D_DIR}/50-discord"* 2>/dev/null

    tui_info "2. Запись объединенного скрипта (STUN + IP Discovery) в custom.d script #50..."
    local tpl="${Z2M_DIR}/templates/50-script.sh"
    if [ -f "${tpl}" ]; then
        cp -f "${tpl}" "${CUSTOM_SCRIPT_50}"
    else
        cat << 'EOF' > "${CUSTOM_SCRIPT_50}"
# Discord Voice & Video Fix (STUN + Discord Media IP Discovery)
# This custom script desyncs both Discord IP Discovery and STUN packets
# Resolves "Infinite RTC Connecting" / "No Route" in Discord voice calls
# Compatible with LuCI "custom.d script #50" and OpenWrt 22, 23, 24+

# Can override in config:
NFQWS_OPT_DESYNC_STUN="${NFQWS_OPT_DESYNC_STUN:---payload=stun --lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2}"
NFQWS_OPT_DESYNC_DISCORD_MEDIA="${NFQWS_OPT_DESYNC_DISCORD_MEDIA:---payload=discord_ip_discovery --lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2}"
DISCORD_MEDIA_PORT_RANGE="${DISCORD_MEDIA_PORT_RANGE:-50000-65535,19294-19344}"

alloc_dnum DNUM_STUN4ALL
alloc_qnum QNUM_STUN4ALL
alloc_dnum DNUM_DISCORD_MEDIA
alloc_qnum QNUM_DISCORD_MEDIA

zapret_custom_daemons()
{
	# $1 - 1 - add, 0 - stop
	local opt_stun="--qnum=$QNUM_STUN4ALL $NFQWS_OPT_DESYNC_STUN"
	do_nfqws $1 $DNUM_STUN4ALL "$opt_stun"

	local opt_media="--qnum=$QNUM_DISCORD_MEDIA $NFQWS_OPT_DESYNC_DISCORD_MEDIA"
	do_nfqws $1 $DNUM_DISCORD_MEDIA "$opt_media"
}

zapret_custom_firewall()
{
	# $1 - 1 - run, 0 - stop
	local f_stun='-p udp -m u32 --u32'
	fw_nfqws_post $1 "$f_stun 0>>22&0x3C@4>>16=28:65535&&0>>22&0x3C@12=0x2112A442&&0>>22&0x3C@8&0xC0000003=0" "$f_stun 44>>16=28:65535&&52=0x2112A442&&48&0xC0000003=0" $QNUM_STUN4ALL

	local DISABLE_IPV6=1
	local port_range
	port_range=$(replace_char - : "$DISCORD_MEDIA_PORT_RANGE")
	local f_media="-p udp -m multiport --dports $port_range -m u32 --u32"
	fw_nfqws_post $1 "$f_media 0>>22&0x3C@4>>16=0x52&&0>>22&0x3C@8=0x00010046&&0>>22&0x3C@16=0&&0>>22&0x3C@76=0" '' $QNUM_DISCORD_MEDIA
}

zapret_custom_firewall_nft()
{
	# stop logic is not required
	local f_stun="udp length >= 28 @ih,32,32 0x2112A442 @ih,0,2 0 @ih,30,2 0"
	nft_fw_nfqws_post "$f_stun" "$f_stun" $QNUM_STUN4ALL

	local DISABLE_IPV6=1
	local f_media="udp dport {$DISCORD_MEDIA_PORT_RANGE} udp length == 82 @ih,0,32 0x00010046 @ih,64,128 0x00000000000000000000000000000000 @ih,192,128 0x00000000000000000000000000000000 @ih,320,128 0x00000000000000000000000000000000 @ih,448,128 0x00000000000000000000000000000000"
	nft_fw_nfqws_post "$f_media" '' $QNUM_DISCORD_MEDIA
}
EOF
    fi

    # Fix line endings and permissions
    sed -i 's/\r$//' "${CUSTOM_SCRIPT_50}" 2>/dev/null
    chmod 755 "${CUSTOM_SCRIPT_50}" 2>/dev/null

    tui_info "3. Включение поддержки custom.d, портов TCP и UDP в конфигурации OpenWrt..."
    if command -v uci >/dev/null 2>&1; then
        uci set zapret2.config.DISABLE_CUSTOM='0'
        uci set zapret2.config.NFQWS2_PORTS_TCP="${DEFAULT_PORTS_TCP}"
        uci set zapret2.config.NFQWS2_PORTS_UDP="${DEFAULT_PORTS_UDP}"
        uci commit zapret2 2>/dev/null
    fi

    if [ -f "${ZAPRET2_CONFIG}" ]; then
        sed -i 's/^DISABLE_CUSTOM=.*/DISABLE_CUSTOM=0/' "${ZAPRET2_CONFIG}" 2>/dev/null
        sed -i "s|^NFQWS2_PORTS_TCP=.*|NFQWS2_PORTS_TCP=\"${DEFAULT_PORTS_TCP}\"|" "${ZAPRET2_CONFIG}" 2>/dev/null
        sed -i "s|^NFQWS2_PORTS_UDP=.*|NFQWS2_PORTS_UDP=\"${DEFAULT_PORTS_UDP}\"|" "${ZAPRET2_CONFIG}" 2>/dev/null
    fi

    tui_info "4. Синхронизация списков доменов Discord..."
    zapret_sync_hostlists

    tui_info "5. Перезапуск службы zapret2..."
    zapret_restart

    sleep 1

    local new_st
    new_st=$(discord_fix_get_status)

    echo ""
    if [ "${new_st}" = "ACTIVE" ]; then
        tui_success "Исправление успешно установлено и активно!"
        tui_info "В LuCI Web UI скрипт отображается в разделе: Настройки -> custom.d -> custom.d script #50"
        tui_info "Теперь десинкятся как STUN пакеты, так и Discord IP Discovery (UDP 82)."
        tui_info "Голосовые каналы и звонки подключаются мгновенно!"
    else
        tui_warn "Скрипт установлен (${new_st}). Проверьте запуск службы zapret2 в меню 1."
    fi

    tui_pause
}

discord_fix_remove() {
    tui_banner
    tui_header "Отключение исправления Discord Voice"

    if [ -f "${CUSTOM_SCRIPT_50}" ]; then
        rm -f "${CUSTOM_SCRIPT_50}" 2>/dev/null
        tui_info "Скрипт ${CUSTOM_SCRIPT_50} удален."
    fi

    tui_info "Перезапуск zapret2..."
    zapret_restart
    tui_success "Исправление отключено."
    tui_pause
}

discord_fix_check_connection() {
    tui_banner
    tui_header "🧪 Проверка серверов Discord (Web, Gateway, Media, CDN)"

    printf "${BOLD}%-28s %-20s %-12s${NC}\n" "Домен" "Назначение" "Статус"
    printf "${DGRAY}───────────────────────────────────────────────────────────────────${NC}\n"

    local dc_hosts="discord.com gateway.discord.gg cdn.discordapp.com discord.media status.discord.com"

    for h in ${dc_hosts}; do
        local cat="Веб-интерфейс"
        case "${h}" in
            gateway.discord.gg) cat="Шлюз / Сигналинг" ;;
            cdn.discordapp.com) cat="Медиа / Аватары" ;;
            discord.media)      cat="Голосовые сервера" ;;
            status.discord.com) cat="Статус сервиса" ;;
        esac

        printf "%-28s %-20s ${YELLOW}[...] Тест${NC}\r" "${h}" "${cat}"

        if probe_fast_tls "${h}" 443 2; then
            printf "%-28s %-20s ${GREEN}✓ Доступен${NC}\n" "${h}" "${cat}"
        else
            printf "%-28s %-20s ${RED}✗ Недоступен${NC}\n" "${h}" "${cat}"
        fi
    done

    echo ""
    local st
    st=$(discord_fix_get_status)
    printf "  ${BOLD}Статус скрипта #50:${NC} %s\n" "${st}"
    echo ""
    tui_info "Примечание: голосовой поток проверяется в самом приложении Discord."
    tui_info "При входе в голосовой канал статус должен сразу меняться с «Подключение к RTC» на «Подключено» (зеленая иконка)."

    tui_pause
}

run_discord_fix_menu() {
    while true; do
        tui_banner
        tui_header "🎧 Управление голосовым чатом Discord (Voice / Звонки / RTC)"

        local st
        st=$(discord_fix_get_status)

        local st_text="${RED}Не установлен${NC}"
        case "${st}" in
            ACTIVE)
                st_text="${GREEN}Активен (STUN + Media IP Discovery)${NC}"
                ;;
            STOPPED)
                st_text="${YELLOW}Установлен, но zapret2 остановлен${NC}"
                ;;
            DISABLED_IN_CONFIG)
                st_text="${YELLOW}Установлен, но custom.d отключен в UCI (DISABLE_CUSTOM=1)${NC}"
                ;;
            STUN_ONLY)
                st_text="${RED}Частично (только STUN — звонки зависают в RTC Connecting!)${NC}"
                ;;
            MEDIA_ONLY)
                st_text="${YELLOW}Частично (только Media IP Discovery)${NC}"
                ;;
        esac

        printf "  ${BOLD}Текущее состояние:${NC} %b\n" "${st_text}"
        printf "  ${BOLD}Файл скрипта LuCI :${NC} ${CYAN}%s${NC}\n" "${CUSTOM_SCRIPT_50}"
        printf "  ${DGRAY}───────────────────────────────────────────────────────────────────${NC}\n\n"

        printf "  1. 🚀 Установить / Обновить исправление Discord Voice (RTC & Звонки)\n"
        printf "  2. 🧪 Проверить связь с серверами Discord\n"
        printf "  3. 📄 Посмотреть содержимое скрипта 50-script.sh\n"
        printf "  4. 🗑️ Удалить исправление\n"
        printf "  0. ↩️ Назад в главное меню\n\n"

        local choice
        choice=$(tui_prompt "Выберите действие" "1")

        case "${choice}" in
            1)
                discord_fix_apply
                ;;
            2)
                discord_fix_check_connection
                ;;
            3)
                tui_banner
                tui_header "Содержимое ${CUSTOM_SCRIPT_50}"
                if [ -f "${CUSTOM_SCRIPT_50}" ]; then
                    cat "${CUSTOM_SCRIPT_50}"
                else
                    tui_warn "Файл ${CUSTOM_SCRIPT_50} не существует."
                fi
                tui_pause
                ;;
            4)
                discord_fix_remove
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
