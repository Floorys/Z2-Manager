#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Hostlists & Exclusions Manager Module
# Manage domain lists and exclusions in /opt/zapret2/ipset
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
. "${Z2M_DIR}/core/config.sh"
. "${Z2M_DIR}/core/tui.sh"
. "${Z2M_DIR}/core/zapret_service.sh"

run_hostlists_menu() {
    while true; do
        tui_banner
        tui_header "📁 Управление списками доменов и исключений"

        local dc_count=0 yt_count=0 ex_count=0 usr_count=0
        [ -f "${ZAPRET2_IPSET_DIR}/zapret-hosts-discord.txt" ] && dc_count=$(grep -c "^[^#]" "${ZAPRET2_IPSET_DIR}/zapret-hosts-discord.txt" 2>/dev/null || echo 0)
        [ -f "${ZAPRET2_IPSET_DIR}/zapret-hosts-youtube.txt" ] && yt_count=$(grep -c "^[^#]" "${ZAPRET2_IPSET_DIR}/zapret-hosts-youtube.txt" 2>/dev/null || echo 0)
        [ -f "${ZAPRET2_IPSET_DIR}/zapret-hosts-user-exclude.txt" ] && ex_count=$(grep -c "^[^#]" "${ZAPRET2_IPSET_DIR}/zapret-hosts-user-exclude.txt" 2>/dev/null || echo 0)
        [ -f "${ZAPRET2_IPSET_DIR}/zapret-hosts-user.txt" ] && usr_count=$(grep -c "^[^#]" "${ZAPRET2_IPSET_DIR}/zapret-hosts-user.txt" 2>/dev/null || echo 0)

        printf "  1. Домены Discord      ${DGRAY}(активно: %s)${NC}\n" "${dc_count}"
        printf "  2. Домены YouTube      ${DGRAY}(активно: %s)${NC}\n" "${yt_count}"
        printf "  3. Исключения (RU)     ${DGRAY}(активно: %s)${NC}\n" "${ex_count}"
        printf "  4. Пользовательский    ${DGRAY}(активно: %s)${NC}\n" "${usr_count}"
        printf "  5. Добавить свой домен в список\n"
        printf "  6. Перезаписать стандартные списки из комплекта\n"
        printf "  0. Назад в главное меню\n\n"

        local choice
        choice=$(tui_prompt "Выберите действие" "0")

        case "${choice}" in
            1)
                _view_list "${ZAPRET2_IPSET_DIR}/zapret-hosts-discord.txt" "Discord"
                ;;
            2)
                _view_list "${ZAPRET2_IPSET_DIR}/zapret-hosts-youtube.txt" "YouTube"
                ;;
            3)
                _view_list "${ZAPRET2_IPSET_DIR}/zapret-hosts-user-exclude.txt" "Исключения"
                ;;
            4)
                _view_list "${ZAPRET2_IPSET_DIR}/zapret-hosts-user.txt" "Пользовательский"
                ;;
            5)
                _add_custom_domain
                ;;
            6)
                zapret_sync_hostlists
                tui_success "Списки успешно синхронизированы!"
                tui_pause
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

_view_list() {
    local file="$1"
    local title="$2"
    tui_banner
    tui_header "Список: ${title} (${file})"
    if [ -f "${file}" ]; then
        head -n 30 "${file}"
        local total
        total=$(wc -l < "${file}")
        if [ "${total}" -gt 30 ]; then
            printf "\n${DGRAY}... и еще %s строк${NC}\n" "$(( total - 30 ))"
        fi
    else
        tui_warn "Файл не найден."
    fi
    tui_pause
}

_add_custom_domain() {
    tui_banner
    tui_header "Добавление домена"
    local domain
    domain=$(tui_prompt "Введите домен (например, sub.domain.com)" "")
    [ -z "${domain}" ] && return

    printf "В какой список добавить?\n"
    printf "1. Discord\n2. YouTube\n3. Исключения (Exclude)\n4. Пользовательский (User)\n"
    local target
    target=$(tui_prompt "Выбор" "4")

    local file="${ZAPRET2_IPSET_DIR}/zapret-hosts-user.txt"
    case "${target}" in
        1) file="${ZAPRET2_IPSET_DIR}/zapret-hosts-discord.txt" ;;
        2) file="${ZAPRET2_IPSET_DIR}/zapret-hosts-youtube.txt" ;;
        3) file="${ZAPRET2_IPSET_DIR}/zapret-hosts-user-exclude.txt" ;;
        4) file="${ZAPRET2_IPSET_DIR}/zapret-hosts-user.txt" ;;
    esac

    mkdir -p "$(dirname "${file}")"
    echo "${domain}" >> "${file}"
    tui_success "Домен «${domain}» добавлен в ${file}!"
    zapret_restart
    tui_pause
}
