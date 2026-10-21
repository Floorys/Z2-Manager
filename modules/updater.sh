#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Updates & Package Management Module
# Handles update checks and upgrades for Zapret2 (1andrevich/zapret2-openwrt)
# and self-updates for Zapret2-Manager (Floorys/Z2-Manager)
# ==============================================================================

if [ -z "${Z2M_DIR}" ] || [ ! -d "${Z2M_DIR}/core" ]; then
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
    local v1 v2
    v1=$(echo "$1" | sed 's/^v//')
    v2=$(echo "$2" | sed 's/^v//')
    [ "$v1" = "$v2" ] && return 0

    local i=1
    while [ "$i" -le 6 ]; do
        local p1 p2
        p1=$(echo "$v1" | cut -d. -f"$i")
        p2=$(echo "$v2" | cut -d. -f"$i")

        [ -z "$p1" ] && [ -z "$p2" ] && return 0
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
    return 0
}

# Fetch latest Zapret2 release tag from GitHub (1andrevich/zapret2-openwrt)
zapret_get_latest_version() {
    local repo="${ZAPRET2_UPSTREAM_REPO:-1andrevich/zapret2-openwrt}"
    local tag=""

    # 1. Try redirect location from GitHub web releases/latest (avoids GitHub API 60 req/hr limits)
    if command -v curl >/dev/null 2>&1; then
        tag=$(curl -sI -k --connect-timeout 5 -m 10 "https://github.com/${repo}/releases/latest" 2>/dev/null | grep -i "^location:" | sed 's/.*tag\///' | tr -d '\r\n ')
    fi
    if [ -z "${tag}" ] && command -v wget >/dev/null 2>&1; then
        tag=$(wget -S --spider --timeout=10 "https://github.com/${repo}/releases/latest" 2>&1 | grep -i "location:" | sed 's/.*tag\///' | tr -d '\r\n ')
    fi

    # 2. Fallback to GitHub REST API
    if [ -z "${tag}" ]; then
        if command -v curl >/dev/null 2>&1; then
            tag=$(curl -sSL -k --connect-timeout 5 -m 10 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n1 | cut -d: -f2 | tr -d ' ",\r\n')
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
        . /etc/os-release 2>/dev/null
        SYSTEM_ARCH="${OPENWRT_ARCH}"
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

    rm -f "${dest}" 2>/dev/null
    if command -v curl >/dev/null 2>&1; then
        curl -sSL -k --connect-timeout 8 -m 60 "${url}" -o "${dest}" 2>/dev/null
    fi
    if [ ! -s "${dest}" ] && command -v wget >/dev/null 2>&1; then
        wget -q --timeout=30 -O "${dest}" "${url}" 2>/dev/null
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
    printf "  ${BOLD}Текущая версия Zapret2 :${NC} ${CYAN}%s${NC}\n" "${cur_ver:-не установлена}"
    printf "  ${BOLD}Целевая версия Zapret2 :${NC} ${GREEN}v%s${NC}\n\n" "${target_ver}"

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
    tui_info "Архитектура устройства: ${GREEN}${SYSTEM_ARCH}${NC} | Менеджер: ${GREEN}${SYSTEM_PKG_MGR}${NC}"

    local tmp_dir="/tmp/zapret2_update_$$"
    rm -rf "${tmp_dir}" 2>/dev/null
    mkdir -p "${tmp_dir}" 2>/dev/null

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
                tui_success "Загружен пакет zapret2_${cand}.${SYSTEM_PKG_EXT} (${fsz} байт)"
                break
            fi
        fi
        rm -f "${target_file}" 2>/dev/null
    done

    if [ -z "${pkg_downloaded}" ] || [ ! -s "${pkg_downloaded}" ]; then
        tui_error "Не удалось скачать пакет Zapret2 для архитектуры ${SYSTEM_ARCH}."
        rm -rf "${tmp_dir}" 2>/dev/null
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
    zapret_stop

    tui_info "Установка пакета через ${SYSTEM_PKG_MGR}..."
    if [ "${SYSTEM_PKG_MGR}" = "apk" ]; then
        mkdir -p /etc/apk/keys 2>/dev/null
        local key_url="https://github.com/${repo}/releases/download/${tag_with_v}/zapret2-1andrevich.pub"
        updater_download "${key_url}" "/etc/apk/keys/zapret2-1andrevich.pub" 2>/dev/null

        if [ -s "${luci_pkg}" ]; then
            apk add --allow-untrusted --upgrade --force-non-repository "${pkg_downloaded}" "${luci_pkg}"
        else
            apk add --allow-untrusted --upgrade --force-non-repository "${pkg_downloaded}"
        fi
    else
        # opkg
        opkg update >/dev/null 2>&1
        if [ -s "${luci_pkg}" ]; then
            opkg install --force-reinstall "${pkg_downloaded}" "${luci_pkg}"
        else
            opkg install --force-reinstall "${pkg_downloaded}"
        fi
    fi

    # Восстановление интеграций Zapret2-Manager
    tui_info "Синхронизация компонентов и скриптов Zapret2-Manager..."
    zapret_sync_fake_blobs
    zapret_sync_hostlists
    zapret_sync_custom_scripts
    zapret_repair_config

    if [ -f "${ZAPRET2_SYNC}" ]; then
        "${ZAPRET2_SYNC}" >/dev/null 2>&1
    fi
    if [ -f "${ZAPRET2_INIT}" ]; then
        "${ZAPRET2_INIT}" enable >/dev/null 2>&1
    fi

    tui_info "Запуск обновленной службы Zapret2..."
    zapret_restart

    rm -rf "${tmp_dir}" 2>/dev/null

    local new_installed_ver
    new_installed_ver=$(zapret_get_installed_version)

    echo ""
    if zapret_is_running; then
        local new_pid
        new_pid=$(pidof nfqws2 2>/dev/null || pgrep nfqws2 2>/dev/null || pidof nfqws 2>/dev/null)
        tui_success "Zapret2 успешно обновлен до версии ${GREEN}v${new_installed_ver:-${target_ver}}${NC}!"
        tui_info "Служба запущена и перехватывает трафик (PID: ${new_pid})."
    else
        tui_warn "Пакет Zapret2 установлен (v${new_installed_ver:-${target_ver}}), но процесс nfqws2 еще не запущен."
        tui_info "Проверьте запуск через 'z2m -r' или '/etc/init.d/zapret2 restart'."
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

# Combined update: update Zapret2 and then update Zapret2-Manager
run_update_all() {
    tui_banner
    tui_header "🚀 Полное обновление: Zapret2 + Zapret2-Manager"
    tui_info "Шаг 1 из 2: Обновление пакета Zapret2..."
    zapret_run_update "" "0" "1"

    echo ""
    tui_info "Шаг 2 из 2: Обновление Zapret2-Manager..."
    sleep 1
    run_self_update
}

# CLI output for quick check command (z2m -cu / z2m --check-update)
run_check_updates_cli() {
    printf "${BOLD}=== Проверка обновлений Zapret2-Manager ===${NC}\n\n"

    local cur_zap latest_zap
    cur_zap=$(zapret_get_installed_version)
    latest_zap=$(zapret_get_latest_version)

    printf "  ${BOLD}Zapret2 (1andrevich/zapret2-openwrt):${NC}\n"
    printf "    Установлена : %s\n" "${cur_zap:-не установлена}"
    printf "    Актуальная  : %s\n" "${latest_zap:-не удалось получить}"

    if [ -n "${cur_zap}" ] && [ -n "${latest_zap}" ]; then
        vercmp "${cur_zap}" "${latest_zap}"
        local cmp=$?
        if [ "$cmp" -eq 2 ]; then
            printf "    Статус      : ${GREEN}${BOLD}Доступно обновление до v%s!${NC} (запустите: z2m -uz)\n" "${latest_zap}"
        elif [ "$cmp" -eq 0 ]; then
            printf "    Статус      : ${GREEN}Установлена актуальная версия ✔${NC}\n"
        else
            printf "    Статус      : ${YELLOW}Установлена тестовая версия (новее релиза)${NC}\n"
        fi
    elif [ -z "${cur_zap}" ] && [ -n "${latest_zap}" ]; then
        printf "    Статус      : ${RED}Пакет не установлен${NC} (запустите: z2m -uz для установки v%s)\n" "${latest_zap}"
    fi
    echo ""

    printf "  ${BOLD}Zapret2-Manager (Floorys/Z2-Manager):${NC}\n"
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

        printf "  ${BOLD}Устройство      :${NC} ${CYAN}%s${NC} (%s)\n" "${model}" "${owrt_ver}"
        printf "  ${BOLD}Архитектура     :${NC} ${GREEN}%s${NC} (${SYSTEM_PKG_MGR})\n" "${SYSTEM_ARCH}"

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

        printf "  ${BOLD}Zapret2         :${NC} %b\n" "${zap_status_badge}"
        printf "  ${BOLD}Zapret2-Manager :${NC} ${CYAN}v%s${NC} ${DGRAY}(Floorys/Z2-Manager)${NC}\n" "${Z2M_VERSION}"
        printf "  ${DGRAY}───────────────────────────────────────────────────────────────────${NC}\n\n"

        if [ "${can_update_zapret}" -eq 1 ]; then
            printf "  ${BOLD}1.${NC} 🛡️ ${GREEN}${BOLD}Обновить Zapret2 до v%s${NC}  ${DGRAY}(скачать и установить пакет от 1andrevich)${NC}\n" "${latest_zap:-latest}"
        else
            printf "  ${BOLD}1.${NC} 🛡️ Переустановить Zapret2 v%s     ${DGRAY}(принудительная переустановка пакета)${NC}\n" "${latest_zap:-latest}"
        fi
        printf "  ${BOLD}2.${NC} 🔄 Обновить Zapret2-Manager        ${DGRAY}(самообновление менеджера с GitHub)${NC}\n"
        printf "  ${BOLD}3.${NC} 🚀 Обновить всё                    ${DGRAY}(Zapret2 + Zapret2-Manager в один шаг)${NC}\n"
        printf "  ${BOLD}4.${NC} 🔍 Повторить проверку обновлений\n"
        printf "  ${BOLD}0.${NC} Назад в главное меню\n\n"

        local choice
        choice=$(tui_prompt "Выберите действие" "1")
        case "${choice}" in
            1)
                zapret_run_update "${latest_zap}" "1" "0"
                ;;
            2)
                run_self_update
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
