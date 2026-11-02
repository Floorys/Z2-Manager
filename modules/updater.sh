#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Updates & Package Management Module
# Handles update checks and upgrades for Zapret2 (1andrevich/zapret2-openwrt)
# and self-updates for Zapret2-Manager (Floorys/Z2-Manager)
# ==============================================================================

if [ -z "${Z2M_DIR:-}" ] || [ ! -d "${Z2M_DIR}/core" ]; then
    if [ -d "/opt/zapret2-manager/core" ]; then
        Z2M_DIR="/opt/zapret2-manager"
    elif [ -f "$(dirname "$0")/core/config.sh" ]; then
        Z2M_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
    elif [ -f "$(dirname "$0")/../core/config.sh" ]; then
        Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
    else
        Z2M_DIR="/opt/zapret2-manager"
    fi
fi
export Z2M_DIR
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"
[ -f "${Z2M_DIR}/core/tui.sh" ] && . "${Z2M_DIR}/core/tui.sh"
[ -f "${Z2M_DIR}/core/zapret_service.sh" ] && . "${Z2M_DIR}/core/zapret_service.sh"

# POSIX-compliant version comparison
# Returns:
#   0 : v1 == v2
#   1 : v1 > v2
#   2 : v1 < v2
vercmp() {
    local v1 v2 suffix1 suffix2
    # OpenWrt package revisions (-rN) do not change the upstream application
    # version and therefore compare equal to the corresponding release tag.
    v1=$(echo "$1" | sed 's/^v//; s/-r[0-9][0-9]*$//')
    v2=$(echo "$2" | sed 's/^v//; s/-r[0-9][0-9]*$//')
    [ "$v1" = "$v2" ] && return 0

    local i=1
    while [ "$i" -le 6 ]; do
        local p1 p2
        p1=$(echo "$v1" | cut -d. -f"$i")
        p2=$(echo "$v2" | cut -d. -f"$i")

        [ -z "$p1" ] && [ -z "$p2" ] && break
        [ -z "$p1" ] && p1=0
        [ -z "$p2" ] && p2=0

        p1=$(echo "$p1" | sed 's/[^0-9].*//')
        p2=$(echo "$p2" | sed 's/[^0-9].*//')
        [ -z "$p1" ] && p1=0
        [ -z "$p2" ] && p2=0

        if [ "$p1" -gt "$p2" ] 2>/dev/null; then
            return 1
        elif [ "$p1" -lt "$p2" ] 2>/dev/null; then
            return 2
        fi
        i=$(( i + 1 ))
    done
    suffix1=$(echo "${v1}" | sed 's/^[0-9.]*//')
    suffix2=$(echo "${v2}" | sed 's/^[0-9.]*//')
    [ "${suffix1}" = "${suffix2}" ] && return 0
    [ -z "${suffix1}" ] && return 1
    [ -z "${suffix2}" ] && return 2

    if [ "$(printf '%s\n%s\n' "${suffix1}" "${suffix2}" | LC_ALL=C sort | head -n1)" = "${suffix1}" ]; then
        return 2
    fi
    return 1
}

# Fetch latest Zapret2 release tag from GitHub (1andrevich/zapret2-openwrt)
zapret_get_latest_version() {
    local repo="${ZAPRET2_UPSTREAM_REPO:-1andrevich/zapret2-openwrt}"
    local tag=""

    # 1. Try redirect location from GitHub web releases/latest (avoids GitHub API 60 req/hr limits)
    if command -v curl >/dev/null 2>&1; then
        tag=$(curl -fsSI --proto '=https' --proto-redir '=https' --connect-timeout 5 -m 10 "https://github.com/${repo}/releases/latest" 2>/dev/null | grep -i "^location:" | sed 's/.*tag\///' | tr -d '\r\n ')
    fi
    if [ -z "${tag}" ] && command -v wget >/dev/null 2>&1; then
        tag=$(wget -S --spider --timeout=10 "https://github.com/${repo}/releases/latest" 2>&1 | grep -i "location:" | sed 's/.*tag\///' | tr -d '\r\n ')
    fi

    # 2. Fallback to GitHub REST API
    if [ -z "${tag}" ]; then
        if command -v curl >/dev/null 2>&1; then
            tag=$(curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 5 -m 10 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n1 | cut -d: -f2 | tr -d ' ",\r\n')
        elif command -v wget >/dev/null 2>&1; then
            tag=$(wget -qO- --timeout=10 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n1 | cut -d: -f2 | tr -d ' ",\r\n')
        fi
    fi

    echo "${tag}" | sed 's/^v//'
}

# Detect system architecture, package manager, and generate candidate list
zapret_detect_system_arch() {
    # 1. Package manager
    if command -v apk >/dev/null 2>&1; then
        SYSTEM_PKG_MGR="apk"
        SYSTEM_PKG_EXT="apk"
    elif command -v opkg >/dev/null 2>&1; then
        SYSTEM_PKG_MGR="opkg"
        SYSTEM_PKG_EXT="ipk"
    else
        SYSTEM_PKG_MGR="opkg"
        SYSTEM_PKG_EXT="ipk"
    fi

    # 2. Architecture
    SYSTEM_ARCH=""
    if [ "${SYSTEM_PKG_MGR}" = "opkg" ]; then
        SYSTEM_ARCH="$(opkg print-architecture 2>/dev/null | grep -v -E 'all|noarch' | sort -k3,3n | tail -n1 | awk '{print $2}')"
    fi
    if [ -z "${SYSTEM_ARCH}" ] && [ "${SYSTEM_PKG_MGR}" = "apk" ]; then
        SYSTEM_ARCH="$(apk --print-arch 2>/dev/null)"
    fi
    if [ -z "${SYSTEM_ARCH}" ] && [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release 2>/dev/null
        SYSTEM_ARCH="${OPENWRT_ARCH:-}"
    fi
    if [ -z "${SYSTEM_ARCH}" ] && [ -f /etc/openwrt_release ]; then
        SYSTEM_ARCH="$(grep '^DISTRIB_ARCH=' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)"
    fi
    if [ -z "${SYSTEM_ARCH}" ]; then
        SYSTEM_ARCH="$(uname -m 2>/dev/null)"
    fi
    [ -z "${SYSTEM_ARCH}" ] && SYSTEM_ARCH="unknown"

    # 3. Candidates
    ARCH_CANDIDATES="${SYSTEM_ARCH}"
    case "${SYSTEM_ARCH}" in
        x86_64*)
            ARCH_CANDIDATES="x86_64"
            ;;
        i386*|i486*|i586*|i686*)
            ARCH_CANDIDATES="${SYSTEM_ARCH} i386_pentium4 i386_pentium-mmx"
            ;;
        aarch64*)
            [ "${SYSTEM_ARCH}" != "aarch64_generic" ] && ARCH_CANDIDATES="${SYSTEM_ARCH} aarch64_generic"
            ;;
        mipsel*)
            [ "${SYSTEM_ARCH}" != "mipsel_24kc" ] && ARCH_CANDIDATES="${SYSTEM_ARCH} mipsel_24kc mipsel_24kc_24kf mipsel_74kc mipsel_mips32"
            ;;
        mips*)
            [ "${SYSTEM_ARCH}" != "mips_24kc" ] && ARCH_CANDIDATES="${SYSTEM_ARCH} mips_24kc mips_4kec mips_mips32"
            ;;
        arm*cortex-a7*)
            ARCH_CANDIDATES="${SYSTEM_ARCH} arm_cortex-a7_neon-vfpv4 arm_cortex-a7_vfpv4 arm_cortex-a7"
            ;;
        arm*cortex-a9*)
            ARCH_CANDIDATES="${SYSTEM_ARCH} arm_cortex-a9_vfpv3-d16 arm_cortex-a9_neon arm_cortex-a9"
            ;;
        arm*cortex-a15*)
            ARCH_CANDIDATES="${SYSTEM_ARCH} arm_cortex-a15_neon-vfpv4"
            ;;
        arm*cortex-a53*)
            ARCH_CANDIDATES="${SYSTEM_ARCH} aarch64_cortex-a53 aarch64_generic"
            ;;
        arm*cortex-a8*)
            ARCH_CANDIDATES="${SYSTEM_ARCH} arm_cortex-a8_vfpv3 arm_cortex-a8"
            ;;
        arm*cortex-a5*)
            ARCH_CANDIDATES="${SYSTEM_ARCH} arm_cortex-a5_vfpv4 arm_cortex-a5"
            ;;
        arm*)
            ARCH_CANDIDATES="${SYSTEM_ARCH} arm_cortex-a7_neon-vfpv4 arm_cortex-a7 arm_arm1176jzf-s_vfp"
            ;;
        riscv64*)
            ARCH_CANDIDATES="${SYSTEM_ARCH} riscv64_riscv64"
            ;;
        powerpc*|ppc*)
            ARCH_CANDIDATES="${SYSTEM_ARCH} powerpc_8540 powerpc_464fp"
            ;;
    esac
}

# Download a file using curl or wget with retries and timeout
updater_download() {
    local url="$1"
    local dest="$2"

    local part="${dest}.part.$$"
    rm -f "${dest}" "${part}" 2>/dev/null
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 8 -m 60 "${url}" -o "${part}" 2>/dev/null; then
            mv -f "${part}" "${dest}"
        else
            rm -f "${part}" 2>/dev/null
        fi
    fi
    if [ ! -s "${dest}" ] && command -v wget >/dev/null 2>&1; then
        if wget -q --timeout=30 -O "${part}" "${url}" 2>/dev/null; then
            mv -f "${part}" "${dest}"
        else
            rm -f "${part}" 2>/dev/null
        fi
    fi
    [ -s "${dest}" ]
}

# Run Zapret2 package upgrade
zapret_run_update() {
    local target_ver="$1"
    local force="$2"
    local non_interactive="$3"

    tui_banner
    tui_header "🛡️ Обновление пакета Zapret2 (1andrevich/zapret2-openwrt)"

    tui_info "Определение текущей и последней версии Zapret2..."
    local cur_ver
    cur_ver=$(zapret_get_installed_version)

    if [ -z "${target_ver}" ]; then
        target_ver=$(zapret_get_latest_version)
    fi

    if [ -z "${target_ver}" ]; then
        tui_error "Не удалось получить информацию о последней версии Zapret2 из GitHub."
        tui_warn "Проверьте подключение к интернету или укажите версию вручную."
        [ "${non_interactive}" != "1" ] && tui_pause
        return 1
    fi

    echo ""
    printf "  %bТекущая версия Zapret2 :%b %b%s%b\n" "${BOLD}" "${NC}" "${CYAN}" "${cur_ver:-не установлена}" "${NC}"
    printf "  %bЦелевая версия Zapret2 :%b %bv%s%b\n\n" "${BOLD}" "${NC}" "${GREEN}" "${target_ver}" "${NC}"

    if [ -n "${cur_ver}" ] && [ "${force}" != "1" ]; then
        vercmp "${cur_ver}" "${target_ver}"
        local cmp_res=$?
        if [ "${cmp_res}" -eq 0 ]; then
            tui_success "У вас уже установлена актуальная версия Zapret2 (v${cur_ver})!"
            if [ "${non_interactive}" = "1" ]; then
                return 0
            fi
            local ans
            ans=$(tui_prompt "Выполнить принудительную переустановку? (y/N)" "N")
            case "${ans}" in
                y|Y|yes|YES) ;;
                *) return 0 ;;
            esac
        elif [ "${cmp_res}" -eq 1 ]; then
            tui_warn "Установленная версия (v${cur_ver}) новее целевой версии (v${target_ver})!"
            if [ "${non_interactive}" = "1" ]; then
                return 0
            fi
            local ans
            ans=$(tui_prompt "Выполнить откат/переустановку? (y/N)" "N")
            case "${ans}" in
                y|Y|yes|YES) ;;
                *) return 0 ;;
            esac
        fi
    fi

    zapret_detect_system_arch
    printf "%bℹ Архитектура устройства: %b%s%b | Менеджер: %b%s%b%b\n" \
        "${CYAN}" "${GREEN}" "${SYSTEM_ARCH}" "${NC}" "${GREEN}" "${SYSTEM_PKG_MGR}" "${NC}" "${NC}"

    z2m_prepare_runtime || return 1
    local tmp_dir
    tmp_dir=$(mktemp -d "${Z2M_TMP}/zapret2_update.XXXXXX") || {
        tui_error "Не удалось создать временный каталог обновления."
        return 1
    }

    local service_was_running=0 service_was_enabled=0
    zapret_is_running && service_was_running=1
    [ -x "${ZAPRET2_INIT}" ] && "${ZAPRET2_INIT}" enabled >/dev/null 2>&1 && service_was_enabled=1
    cleanup_zapret_update() {
        rm -rf "${tmp_dir}" 2>/dev/null
    }
    abort_zapret_update() {
        cleanup_zapret_update
        [ "${service_was_running}" -eq 1 ] && zapret_start >/dev/null 2>&1
        trap - INT TERM
        exit 130
    }
    trap abort_zapret_update INT TERM

    local repo="${ZAPRET2_UPSTREAM_REPO:-1andrevich/zapret2-openwrt}"
    local tag_clean="${target_ver#v}"
    local tag_with_v="v${tag_clean}"
    local pkg_downloaded=""
    local matched_arch=""

    tui_info "Поиск подходящего пакета в релизе ${tag_with_v}..."
    for cand in ${ARCH_CANDIDATES}; do
        local url1="https://github.com/${repo}/releases/download/${tag_with_v}/zapret2_${cand}.${SYSTEM_PKG_EXT}"
        local url2="https://github.com/${repo}/releases/download/${tag_clean}/zapret2_${cand}.${SYSTEM_PKG_EXT}"
        local target_file="${tmp_dir}/zapret2.${SYSTEM_PKG_EXT}"

        if updater_download "${url1}" "${target_file}" || updater_download "${url2}" "${target_file}"; then
            local fsz
            fsz=$(wc -c < "${target_file}" 2>/dev/null || echo 0)
            if [ "${fsz}" -gt 20000 ]; then
                pkg_downloaded="${target_file}"
                matched_arch="${cand}"
                tui_success "Загружен пакет zapret2_${matched_arch}.${SYSTEM_PKG_EXT} (${fsz} байт)"
                break
            fi
        fi
        rm -f "${target_file}" 2>/dev/null
    done

    if [ -z "${pkg_downloaded}" ] || [ ! -s "${pkg_downloaded}" ]; then
        tui_error "Не удалось скачать пакет Zapret2 для архитектуры ${SYSTEM_ARCH}."
        cleanup_zapret_update
        trap - INT TERM
        [ "${non_interactive}" != "1" ] && tui_pause
        return 1
    fi

    # Загрузка luci-app-zapret2 (при наличии интерфейса LuCI)
    local luci_pkg="${tmp_dir}/luci-app-zapret2.${SYSTEM_PKG_EXT}"
    local luci_url1="https://github.com/${repo}/releases/download/${tag_with_v}/luci-app-zapret2.${SYSTEM_PKG_EXT}"
    local luci_url2="https://github.com/${repo}/releases/download/${tag_clean}/luci-app-zapret2.${SYSTEM_PKG_EXT}"
    if updater_download "${luci_url1}" "${luci_pkg}" || updater_download "${luci_url2}" "${luci_pkg}"; then
        tui_info "Загружен вспомогательный интерфейс luci-app-zapret2.${SYSTEM_PKG_EXT}"
    fi

    # Остановка текущей службы перед установкой
    tui_info "Остановка службы Zapret2 перед обновлением бинарных файлов..."
    if [ "${service_was_running}" -eq 1 ] && ! zapret_stop; then
        tui_error "Не удалось остановить Zapret2 перед обновлением."
        cleanup_zapret_update
        trap - INT TERM
        return 1
    fi

    tui_info "Установка пакета через ${SYSTEM_PKG_MGR}..."
    if [ "${SYSTEM_PKG_MGR}" = "apk" ]; then
        mkdir -p /etc/apk/keys 2>/dev/null
        local key_url="https://github.com/${repo}/releases/download/${tag_with_v}/zapret2-1andrevich.pub"
        local key_file="${tmp_dir}/zapret2-1andrevich.pub"
        if updater_download "${key_url}" "${key_file}"; then
            cp -f "${key_file}" /etc/apk/keys/zapret2-1andrevich.pub
            chmod 644 /etc/apk/keys/zapret2-1andrevich.pub 2>/dev/null
        elif [ ! -s /etc/apk/keys/zapret2-1andrevich.pub ]; then
            tui_error "Не удалось получить ключ подписи APK. Обновление отменено."
            [ "${service_was_running}" -eq 1 ] && zapret_start >/dev/null 2>&1
            cleanup_zapret_update
            trap - INT TERM
            return 1
        fi

        if [ -s "${luci_pkg}" ]; then
            if ! apk add --upgrade --force-non-repository "${pkg_downloaded}" "${luci_pkg}"; then
                tui_error "apk не смог установить пакет Zapret2."
                [ "${service_was_running}" -eq 1 ] && zapret_start >/dev/null 2>&1
                cleanup_zapret_update; trap - INT TERM; return 1
            fi
        else
            if ! apk add --upgrade --force-non-repository "${pkg_downloaded}"; then
                tui_error "apk не смог установить пакет Zapret2."
                [ "${service_was_running}" -eq 1 ] && zapret_start >/dev/null 2>&1
                cleanup_zapret_update; trap - INT TERM; return 1
            fi
        fi
    else
        # opkg
        opkg update >/dev/null 2>&1
        if [ -s "${luci_pkg}" ]; then
            if ! opkg install --force-reinstall "${pkg_downloaded}" "${luci_pkg}"; then
                tui_error "opkg не смог установить пакет Zapret2."
                [ "${service_was_running}" -eq 1 ] && zapret_start >/dev/null 2>&1
                cleanup_zapret_update; trap - INT TERM; return 1
            fi
        else
            if ! opkg install --force-reinstall "${pkg_downloaded}"; then
                tui_error "opkg не смог установить пакет Zapret2."
                [ "${service_was_running}" -eq 1 ] && zapret_start >/dev/null 2>&1
                cleanup_zapret_update; trap - INT TERM; return 1
            fi
        fi
    fi

    # Восстановление интеграций Zapret2-Manager
    tui_info "Синхронизация компонентов и скриптов Zapret2-Manager..."
    zapret_sync_fake_blobs
    zapret_sync_hostlists 0
    zapret_repair_config

    if [ -f "${ZAPRET2_SYNC}" ]; then
        "${ZAPRET2_SYNC}" >/dev/null 2>&1
    fi
    if [ -f "${ZAPRET2_INIT}" ]; then
        if [ "${service_was_enabled}" -eq 1 ]; then
            "${ZAPRET2_INIT}" enable >/dev/null 2>&1
        else
            "${ZAPRET2_INIT}" disable >/dev/null 2>&1
        fi
    fi

    if [ "${service_was_running}" -eq 1 ]; then
        tui_info "Запуск обновленной службы Zapret2..."
        if ! zapret_restart; then
            tui_error "Пакет установлен, но обновлённую службу не удалось запустить."
            cleanup_zapret_update
            trap - INT TERM
            return 1
        fi
    else
        if zapret_is_running && ! zapret_stop; then
            tui_error "Не удалось восстановить остановленное состояние службы после обновления."
            cleanup_zapret_update
            trap - INT TERM
            return 1
        fi
        tui_info "До обновления служба была остановлена; её состояние сохранено."
    fi

    cleanup_zapret_update
    trap - INT TERM

    local new_installed_ver
    new_installed_ver=$(zapret_get_installed_version)
    if [ -z "${new_installed_ver}" ]; then
        tui_error "Пакетный менеджер завершился без ошибки, но версия Zapret2 не определяется."
        return 1
    fi
    vercmp "${new_installed_ver}" "${target_ver}"
    local installed_cmp=$?
    if [ "${installed_cmp}" -ne 0 ]; then
        tui_error "После установки обнаружена версия v${new_installed_ver}, ожидалась v${target_ver}."
        return 1
    fi

    echo ""
    if [ "${service_was_running}" -eq 1 ] && zapret_is_running; then
        local new_pid
        new_pid=$(pidof nfqws2 2>/dev/null || pgrep nfqws2 2>/dev/null || pidof nfqws 2>/dev/null)
        printf "%b✔ Zapret2 успешно обновлен до версии %bv%s%b!%b\n" \
            "${GREEN}" "${GREEN}" "${new_installed_ver:-${target_ver}}" "${NC}" "${NC}"
        tui_info "Служба запущена и перехватывает трафик (PID: ${new_pid})."
    elif [ "${service_was_running}" -eq 0 ]; then
        tui_success "Zapret2 обновлён до v${new_installed_ver:-${target_ver}}; служба оставлена остановленной."
    else
        tui_error "Пакет установлен, но процесс nfqws2 не запущен."
        return 1
    fi

    [ "${non_interactive}" != "1" ] && tui_pause
    return 0
}

# Self-update Zapret2-Manager from GitHub repository (Floorys/Z2-Manager)
run_self_update() {
    tui_banner
    tui_header "🔄 Обновление Zapret2-Manager"
    tui_info "Загрузка актуальной версии из репозитория ${Z2M_GITHUB_REPO:-Floorys/Z2-Manager}..."

    local update_url="https://github.com/${Z2M_GITHUB_REPO:-Floorys/Z2-Manager}/archive/refs/heads/main.tar.gz"
    z2m_prepare_runtime || return 1
    local tmp_tar
    tmp_tar=$(mktemp "${Z2M_TMP}/z2m_update.XXXXXX.tar.gz")
    local tmp_dir
    tmp_dir=$(mktemp -d "${Z2M_TMP}/z2m_extracted.XXXXXX")
    if [ -z "${tmp_tar}" ] || [ -z "${tmp_dir}" ]; then
        tui_error "Не удалось создать временные файлы обновления."
        rm -rf "${tmp_tar}" "${tmp_dir}" 2>/dev/null
        return 1
    fi

    if ! updater_download "${update_url}" "${tmp_tar}"; then
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

    # Never replace the running installation with syntactically broken scripts.
    local script_list="${tmp_dir}/scripts.list" syntax_failed=0
    find "${src_folder}" -type f -name '*.sh' > "${script_list}" 2>/dev/null
    while IFS= read -r script_file; do
        if ! sh -n "${script_file}"; then
            tui_error "Загруженное обновление содержит ошибку синтаксиса: ${script_file##*/}"
            syntax_failed=1
            break
        fi
    done < "${script_list}"
    if [ "${syntax_failed}" -eq 1 ]; then
        rm -rf "${tmp_tar}" "${tmp_dir}" 2>/dev/null
        return 1
    fi

    tui_info "Установка файлов в /opt/zapret2-manager..."
    local stage_dir="/opt/zapret2-manager.new.$$"
    local old_dir="/opt/zapret2-manager.old.$$"
    local swap_complete=0
    rollback_self_update() {
        if [ -d "${old_dir}" ]; then
            rm -rf /opt/zapret2-manager 2>/dev/null
            mv "${old_dir}" /opt/zapret2-manager 2>/dev/null
        elif [ "${swap_complete}" -eq 1 ]; then
            rm -rf /opt/zapret2-manager 2>/dev/null
        fi
        rm -rf "${stage_dir}" "${tmp_tar}" "${tmp_dir}" 2>/dev/null
        trap - INT TERM
    }
    abort_self_update() {
        if [ "${swap_complete}" -eq 0 ]; then
            rollback_self_update
        else
            rm -rf "${old_dir}" "${stage_dir}" "${tmp_tar}" "${tmp_dir}" 2>/dev/null
            trap - INT TERM
        fi
        exit 130
    }
    trap abort_self_update INT TERM
    rm -rf "${stage_dir}" "${old_dir}" 2>/dev/null
    if ! mkdir -p "${stage_dir}"; then
        tui_error "Не удалось создать staging-каталог."
        trap - INT TERM
        rm -rf "${tmp_tar}" "${tmp_dir}" 2>/dev/null
        return 1
    fi
    if ! cp -rf "${src_folder}/." "${stage_dir}/"; then
        tui_error "Не удалось скопировать файлы обновления."
        rm -rf "${stage_dir}" "${tmp_tar}" "${tmp_dir}" 2>/dev/null
        trap - INT TERM
        return 1
    fi
    find "${stage_dir}" -name "*.sh" -exec sed -i 's/\r$//' {} + 2>/dev/null
    chmod +x "${stage_dir}"/*.sh "${stage_dir}"/core/*.sh "${stage_dir}"/modules/*.sh \
        "${stage_dir}"/strategies/*.sh "${stage_dir}"/templates/*.sh 2>/dev/null

    if [ -d /opt/zapret2-manager ]; then
        mv /opt/zapret2-manager "${old_dir}" || {
            tui_error "Не удалось подготовить текущую установку к замене."
            rm -rf "${stage_dir}" "${tmp_tar}" "${tmp_dir}" 2>/dev/null
            trap - INT TERM
            return 1
        }
    fi
    if ! mv "${stage_dir}" /opt/zapret2-manager; then
        tui_error "Не удалось активировать новую версию; выполняется откат."
        [ -d "${old_dir}" ] && mv "${old_dir}" /opt/zapret2-manager 2>/dev/null
        rm -rf "${stage_dir}" "${tmp_tar}" "${tmp_dir}" 2>/dev/null
        trap - INT TERM
        return 1
    fi
    swap_complete=1

    # Обновление команд z2m и zsm
    local z2m_wrapper="/usr/bin/.z2m.$$" zsm_wrapper="/usr/bin/.zsm.$$"
    if ! cat << 'EOF' > "${z2m_wrapper}"
#!/bin/sh
exec /bin/sh /opt/zapret2-manager/zapret2-manager.sh "$@"
EOF
    then
        tui_error "Не удалось обновить команду /usr/bin/z2m; выполняется откат."
        rollback_self_update
        return 1
    fi

    if ! cat << 'EOF' > "${zsm_wrapper}"
#!/bin/sh
exec /bin/sh /opt/zapret2-manager/zapret2-manager.sh "$@"
EOF
    then
        tui_error "Не удалось обновить команду /usr/bin/zsm; выполняется откат."
        rm -f "${z2m_wrapper}" "${zsm_wrapper}" 2>/dev/null
        rollback_self_update
        return 1
    fi
    if ! chmod +x "${z2m_wrapper}" "${zsm_wrapper}" 2>/dev/null || \
       ! mv -f "${z2m_wrapper}" /usr/bin/z2m || \
       ! mv -f "${zsm_wrapper}" /usr/bin/zsm; then
        tui_error "Не удалось атомарно обновить команды z2m/zsm; выполняется откат."
        rm -f "${z2m_wrapper}" "${zsm_wrapper}" 2>/dev/null
        rollback_self_update
        return 1
    fi

    # Self-update changes only manager files. User strategies, ports, hostlists
    # and custom.d scripts are deliberately left untouched.
    rm -rf "${old_dir}" "${tmp_tar}" "${tmp_dir}" 2>/dev/null
    trap - INT TERM
    tui_success "Zapret2-Manager успешно обновлен!"
    echo ""
    tui_info "Перезапуск интерфейса менеджера..."
    sleep 1
    exec /bin/sh /opt/zapret2-manager/zapret2-manager.sh "$@"
}

# Combined update: update Zapret2 and then update Zapret2-Manager
run_update_all() {
    tui_banner
    tui_header "🚀 Полное обновление: Zapret2 + Zapret2-Manager"
    tui_info "Шаг 1 из 2: Обновление пакета Zapret2..."
    if ! zapret_run_update "" "0" "1"; then
        tui_error "Обновление Zapret2 завершилось ошибкой; самообновление менеджера отменено."
        return 1
    fi

    echo ""
    tui_info "Шаг 2 из 2: Обновление Zapret2-Manager..."
    sleep 1
    run_self_update
}

# CLI output for quick check command (z2m -cu / z2m --check-update)
run_check_updates_cli() {
    printf "%b=== Проверка обновлений Zapret2-Manager ===%b\n\n" "${BOLD}" "${NC}"

    local cur_zap latest_zap
    cur_zap=$(zapret_get_installed_version)
    latest_zap=$(zapret_get_latest_version)

    printf "  %bZapret2 (1andrevich/zapret2-openwrt):%b\n" "${BOLD}" "${NC}"
    printf "    Установлена : %s\n" "${cur_zap:-не установлена}"
    printf "    Актуальная  : %s\n" "${latest_zap:-не удалось получить}"

    if [ -n "${cur_zap}" ] && [ -n "${latest_zap}" ]; then
        vercmp "${cur_zap}" "${latest_zap}"
        local cmp=$?
        if [ "$cmp" -eq 2 ]; then
            printf "    Статус      : %b%bДоступно обновление до v%s!%b (запустите: z2m -uz)\n" "${GREEN}" "${BOLD}" "${latest_zap}" "${NC}"
        elif [ "$cmp" -eq 0 ]; then
            printf "    Статус      : %bУстановлена актуальная версия ✔%b\n" "${GREEN}" "${NC}"
        else
            printf "    Статус      : %bУстановлена тестовая версия (новее релиза)%b\n" "${YELLOW}" "${NC}"
        fi
    elif [ -z "${cur_zap}" ] && [ -n "${latest_zap}" ]; then
        printf "    Статус      : %bПакет не установлен%b (запустите: z2m -uz для установки v%s)\n" "${RED}" "${NC}" "${latest_zap}"
    fi
    echo ""

    printf "  %bZapret2-Manager (Floorys/Z2-Manager):%b\n" "${BOLD}" "${NC}"
    printf "    Установлена : v%s\n" "${Z2M_VERSION}"
    printf "    Обновление  : выполните 'z2m -u' для открытия центра обновлений\n\n"
}

# Interactive Update Center Menu
run_updates_menu() {
    while true; do
        tui_banner
        tui_header "🔄 Центр обновлений (Zapret2 и Z2-Manager)"

        local model owrt_ver
        model="$(cat /tmp/sysinfo/model 2>/dev/null || grep -i 'machine' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//')"
        [ -z "${model}" ] && model="OpenWrt"
        owrt_ver="$(grep '^DISTRIB_RELEASE=' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)"
        [ -z "${owrt_ver}" ] && owrt_ver="OpenWrt"

        zapret_detect_system_arch

        local cur_zap latest_zap
        cur_zap=$(zapret_get_installed_version)
        tui_info "Проверка актуальной версии Zapret2 на GitHub..."
        latest_zap=$(zapret_get_latest_version)

        tui_banner
        tui_header "🔄 Центр обновлений (Zapret2 и Z2-Manager)"

        printf "  %bУстройство      :%b %b%s%b (%s)\n" "${BOLD}" "${NC}" "${CYAN}" "${model}" "${NC}" "${owrt_ver}"
        printf "  %bАрхитектура     :%b %b%s%b (%s)\n" "${BOLD}" "${NC}" "${GREEN}" "${SYSTEM_ARCH}" "${NC}" "${SYSTEM_PKG_MGR}"

        local zap_status_badge=""
        local can_update_zapret=0
        if [ -z "${cur_zap}" ]; then
            zap_status_badge="${RED}Не установлена${NC}"
            can_update_zapret=1
        elif [ -z "${latest_zap}" ]; then
            zap_status_badge="${CYAN}v${cur_zap}${NC} ${DGRAY}(проверка сети не удалась)${NC}"
        else
            vercmp "${cur_zap}" "${latest_zap}"
            local c=$?
            if [ "$c" -eq 2 ]; then
                zap_status_badge="${YELLOW}v${cur_zap}${NC}  ➔  ${GREEN}${BOLD}[Доступно обновление v${latest_zap}]${NC} 🚀"
                can_update_zapret=1
            elif [ "$c" -eq 0 ]; then
                zap_status_badge="${GREEN}v${cur_zap}${NC} ${GREEN}(Актуальная версия ✔)${NC}"
            else
                zap_status_badge="${CYAN}v${cur_zap}${NC} ${YELLOW}(Тестовая / новее релиза)${NC}"
            fi
        fi

        printf "  %bZapret2         :%b %b\n" "${BOLD}" "${NC}" "${zap_status_badge}"
        printf "  %bZapret2-Manager :%b %bv%s%b %b(Floorys/Z2-Manager)%b\n" "${BOLD}" "${NC}" "${CYAN}" "${Z2M_VERSION}" "${NC}" "${DGRAY}" "${NC}"
        printf "%b  ───────────────────────────────────────────────────────────────────%b\n\n" "${DGRAY}" "${NC}"

        if [ "${can_update_zapret}" -eq 1 ]; then
            printf "  %b1.%b 🛡️ %b%bОбновить Zapret2 до v%s%b  %b(скачать и установить пакет от 1andrevich)%b\n" \
                "${BOLD}" "${NC}" "${GREEN}" "${BOLD}" "${latest_zap:-latest}" "${NC}" "${DGRAY}" "${NC}"
        else
            printf "  %b1.%b 🛡️ Переустановить Zapret2 v%s     %b(принудительная переустановка пакета)%b\n" \
                "${BOLD}" "${NC}" "${latest_zap:-latest}" "${DGRAY}" "${NC}"
        fi
        printf "  %b2.%b 🔄 Обновить Zapret2-Manager        %b(самообновление менеджера с GitHub)%b\n" "${BOLD}" "${NC}" "${DGRAY}" "${NC}"
        printf "  %b3.%b 🚀 Обновить всё                    %b(Zapret2 + Zapret2-Manager в один шаг)%b\n" "${BOLD}" "${NC}" "${DGRAY}" "${NC}"
        printf "  %b4.%b 🔍 Повторить проверку обновлений\n" "${BOLD}" "${NC}"
        printf "  %b0.%b Назад в главное меню\n\n" "${BOLD}" "${NC}"

        local choice
        choice=$(tui_prompt "Выберите действие" "1")
        case "${choice}" in
            1)
                zapret_run_update "${latest_zap}" "1" "0"
                ;;
            2)
                run_self_update "$@"
                ;;
            3)
                run_update_all
                ;;
            4)
                continue
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
