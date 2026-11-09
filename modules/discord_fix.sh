#!/bin/sh
# shellcheck disable=SC3043
[ -z "${Z2M_DIR:-}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
. "${Z2M_DIR}/core/config.sh"
. "${Z2M_DIR}/core/tui.sh"
. "${Z2M_DIR}/core/probe.sh"
. "${Z2M_DIR}/core/zapret_service.sh"

CUSTOM_D_DIR="${ZAPRET2_DIR}/init.d/openwrt/custom.d"
CUSTOM_SCRIPT_50="${CUSTOM_D_DIR}/50-script.sh"

discord_fix_owned() {
    [ -f "${CUSTOM_SCRIPT_50}" ] && [ ! -L "${CUSTOM_SCRIPT_50}" ] || return 1
    if [ -f "${ZAPRET2_DIR}/.z2m-discord/installed" ]; then
        cmp -s "${CUSTOM_SCRIPT_50}" "${ZAPRET2_DIR}/.z2m-discord/installed"
    else
        # Recognize only an exact bundled template, including the legacy version.
        cmp -s "${CUSTOM_SCRIPT_50}" "${Z2M_DIR}/templates/50-script.sh" ||
            tail -n +2 "${Z2M_DIR}/templates/50-script.sh" | cmp -s - "${CUSTOM_SCRIPT_50}"
    fi
}

discord_fix_custom_value() {
    if command -v uci >/dev/null 2>&1 && [ -f "${UCI_CONFIG}" ]; then
        uci -q get "${UCI_SECTION}.DISABLE_CUSTOM" || :
    elif [ -f "${ZAPRET2_CONFIG}" ]; then
        sed -n 's/^DISABLE_CUSTOM=//p' "${ZAPRET2_CONFIG}" | tr -d '"'
    fi
}

discord_fix_set_custom() {
    local value="$1" tmp
    if command -v uci >/dev/null 2>&1 && [ -f "${UCI_CONFIG}" ]; then
        if [ -n "${value}" ]; then
            uci set "${UCI_SECTION}.DISABLE_CUSTOM=${value}" || return 1
        else
            uci -q delete "${UCI_SECTION}.DISABLE_CUSTOM" 2>/dev/null || :
        fi
        uci commit zapret2 || return 1
    fi
    if [ -f "${ZAPRET2_CONFIG}" ]; then
        tmp=$(mktemp "${Z2M_TMP}/custom_cfg.XXXXXX") || return 1
        awk '!/^DISABLE_CUSTOM=/' "${ZAPRET2_CONFIG}" > "${tmp}" || return 1
        [ -z "${value}" ] || printf 'DISABLE_CUSTOM="%s"\n' "${value}" >> "${tmp}"
        cat "${tmp}" > "${ZAPRET2_CONFIG}" || return 1
        rm -f "${tmp}"
    fi
}

discord_fix_get_status() {
    if [ ! -f "${CUSTOM_SCRIPT_50}" ]; then
        echo NOT_INSTALLED
    elif ! discord_fix_owned; then
        echo CUSTOM_UNKNOWN
    elif [ "$(discord_fix_custom_value)" != 0 ]; then
        echo DISABLED_IN_CONFIG
    elif zapret_is_running; then
        echo ACTIVE
    else
        echo STOPPED
    fi
}

discord_fix_apply() {
    z2m_run_guarded discord_fix_apply_worker
}

discord_fix_apply_worker() {
    tui_banner
    tui_header "Установка исправления Discord Voice"
    zapret_is_installed || { tui_error "Zapret2 не установлен."; return 1; }
    local tpl="${Z2M_DIR}/templates/50-script.sh" state="${ZAPRET2_DIR}/.z2m-discord" answer f
    [ -f "${tpl}" ] || { tui_error "Шаблон фикса отсутствует."; return 1; }
    [ ! -L "${CUSTOM_SCRIPT_50}" ] || {
        tui_error "Файл #50 — символическая ссылка; автоматическая замена запрещена."; return 1;
    }
    for f in "${CUSTOM_D_DIR}/50-stun4all"*.sh "${CUSTOM_D_DIR}/50-discord"*.sh; do
        [ -f "${f}" ] || continue
        tui_warn "Возможный конфликт: ${f}. Этот файл не будет удалён."
        answer=$(tui_prompt "Продолжить с этим скриптом? [y/N]" "N")
        case "${answer}" in y|Y|yes|YES) ;; *) return 1 ;; esac
    done
    if [ -e "${CUSTOM_SCRIPT_50}" ] && ! discord_fix_owned; then
        tui_warn "Скрипт #50 пользовательский или изменён после установки."
        answer=$(tui_prompt "Сохранить копию и заменить его? [y/N]" "N")
        case "${answer}" in y|Y|yes|YES) ;; *) return 1 ;; esac
        # Do not silently lose a previously saved script on a later overwrite.
        [ ! -f "${state}/previous-script" ] || {
            tui_error "Уже есть сохранённый скрипт: ${state}/previous-script. Сначала восстановите его."; return 1;
        }
    fi
    mkdir -p "${CUSTOM_D_DIR}" || return 1
    if [ ! -d "${state}" ]; then
        (umask 077; mkdir "${state}") || return 1
        discord_fix_custom_value > "${state}/previous-disable-custom"
    fi
    if [ -f "${CUSTOM_SCRIPT_50}" ] && ! discord_fix_owned; then
        cp -p "${CUSTOM_SCRIPT_50}" "${state}/previous-script" || return 1
    fi
    # Keep the old file in place until its firewall stop hooks have completed.
    zapret_stop || return 1
    cp "${tpl}" "${CUSTOM_SCRIPT_50}" && chmod 755 "${CUSTOM_SCRIPT_50}" || return 1
    cp "${CUSTOM_SCRIPT_50}" "${state}/installed" || return 1
    discord_fix_set_custom 0 || return 1
    # Voice interception lives in custom.d; do not reset the user's TCP/UDP ports.
    zapret_restart || return 1
    [ "$(discord_fix_get_status)" = ACTIVE ] || return 1
    z2m_transaction_commit
    tui_success "Фикс установлен. Пользовательские порты сохранены."
    tui_info "Проверьте звонок в Discord: TCP/TLS-пробы не проверяют голосовой UDP-поток."
    tui_pause
}

discord_fix_remove() {
    z2m_run_guarded discord_fix_remove_worker
}

discord_fix_remove_worker() {
    local state="${ZAPRET2_DIR}/.z2m-discord" was_running=0
    discord_fix_owned || {
        tui_error "Скрипт #50 не принадлежит менеджеру или был изменён. Он не удалён."; return 1;
    }
    zapret_is_running && was_running=1
    zapret_stop || return 1
    rm -f "${CUSTOM_SCRIPT_50}" || return 1
    if [ -f "${state}/previous-script" ]; then
        cp -p "${state}/previous-script" "${CUSTOM_SCRIPT_50}" || return 1
    fi
    if [ -f "${state}/previous-disable-custom" ]; then
        discord_fix_set_custom "$(cat "${state}/previous-disable-custom")" || return 1
    fi
    [ "${was_running}" -ne 1 ] || zapret_start || return 1
    [ ! -d "${state}" ] || rm -r "${state}" || return 1
    z2m_transaction_commit
    tui_success "Фикс удалён; прежний скрипт и DISABLE_CUSTOM восстановлены."
    tui_pause
}

discord_fix_check_connection() {
    tui_banner
    tui_header "Проверка серверов Discord (TCP/TLS)"
    local h
    for h in discord.com gateway.discord.gg cdn.discordapp.com discord.media status.discord.com; do
        if probe_fast_tls "${h}" 443 2; then
            tui_success "${h}: доступен"
        else
            tui_warn "${h}: недоступен"
        fi
    done
    tui_info "Статус фикса: $(discord_fix_get_status). Голос проверяйте в приложении Discord."
    tui_pause
}

run_discord_fix_menu() {
    local choice
    while :; do
        tui_banner
        tui_header "Discord Voice: $(discord_fix_get_status)"
        printf '  1. Установить / обновить фикс\n  2. Проверить связь\n  3. Посмотреть скрипт #50\n  4. Удалить фикс и восстановить прежний скрипт\n  0. Назад\n'
        choice=$(tui_prompt "Выберите действие" "0")
        case "${choice}" in
            1) discord_fix_apply ;;
            2) discord_fix_check_connection ;;
            3) [ ! -f "${CUSTOM_SCRIPT_50}" ] || cat "${CUSTOM_SCRIPT_50}"; tui_pause ;;
            4) discord_fix_remove ;;
            0) return 0 ;;
            *) tui_warn "Неверный пункт меню." ;;
        esac
    done
}
