#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Fast OpenWrt Router Installer
# Repository: Floorys/Z2-Manager
# ==============================================================================

if [ "$(id -u 2>/dev/null)" -ne 0 ]; then
    printf "\033[1;31mОшибка: скрипт установки должен быть запущен с правами администратора (root)!\033[0m\n" >&2
    exit 1
fi

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
BOLD="\033[1m"
NC="\033[0m"

INSTALL_DIR="/opt/zapret2-manager"
BIN_LINK_Z2M="/usr/bin/z2m"
BIN_LINK_ZSM="/usr/bin/zsm"

printf "%b\n" "${CYAN}================================================================${NC}"
printf "%b\n" "${CYAN}             Установка Zapret2-Manager на OpenWrt               ${NC}"
printf "%b\n" "${CYAN}================================================================${NC}"

# 1. Проверка OpenWrt
if [ ! -f /etc/openwrt_release ] && [ ! -f /etc/os-release ]; then
    printf "%b\n" "${RED}Ошибка: данный скрипт предназначен только для OpenWrt!${NC}" >&2
    exit 1
fi

# 2. Проверка наличия утилит загрузки (curl или wget)
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    printf "%b\n" "${RED}Ошибка: в системе не найдены ни curl, ни wget!${NC}" >&2
    printf "%b\n" "${YELLOW}Для работы инсталлятора требуется утилита загрузки по сети.${NC}" >&2
    printf "Установите необходимые пакеты командой:\n" >&2
    printf "  opkg update && opkg install curl ca-bundle libustream-mbedtls\n" >&2
    printf "или для OpenWrt с apk:\n" >&2
    printf "  apk add curl ca-certificates\n" >&2
    exit 1
fi

# 3. Определение менеджера пакетов (apk или opkg)
if command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    PKG_EXT="apk"
elif command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
    PKG_EXT="ipk"
else
    printf "%b\n" "${RED}Ошибка: менеджер пакетов (opkg/apk) не найден!${NC}" >&2
    exit 1
fi

# 4. Определение модели устройства, версии OpenWrt и архитектуры
ROUTER_MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"
[ -z "${ROUTER_MODEL}" ] && ROUTER_MODEL="$(grep -i 'machine' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//')"
[ -z "${ROUTER_MODEL}" ] && ROUTER_MODEL="$(grep -i 'Hardware' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//')"
[ -z "${ROUTER_MODEL}" ] && ROUTER_MODEL="OpenWrt Router"

OWRT_REL="$(grep '^DISTRIB_RELEASE=' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)"
if [ -z "${OWRT_REL}" ] && [ -f /etc/os-release ]; then
    OWRT_REL="$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID:-Unknown}")"
fi
[ -z "${OWRT_REL}" ] && OWRT_REL="Unknown"

# Определение целевой архитектуры процессора
ARCH=""
if [ "${PKG_MGR}" = "opkg" ]; then
    ARCH="$(opkg print-architecture 2>/dev/null | grep -v -E 'all|noarch' | sort -k3,3n | tail -n1 | awk '{print $2}')"
fi
if [ -z "${ARCH}" ] && [ "${PKG_MGR}" = "apk" ]; then
    ARCH="$(apk --print-arch 2>/dev/null)"
fi
if [ -z "${ARCH}" ] && [ -f /etc/os-release ]; then
    ARCH="$(. /etc/os-release 2>/dev/null; echo "${OPENWRT_ARCH:-}")"
fi
if [ -z "${ARCH}" ] && [ -f /etc/openwrt_release ]; then
    ARCH="$(grep '^DISTRIB_ARCH=' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)"
fi
if [ -z "${ARCH}" ]; then
    ARCH="$(uname -m 2>/dev/null)"
fi
[ -z "${ARCH}" ] && ARCH="unknown"

printf "  Устройство    : %b%s%b\n" "${GREEN}" "${ROUTER_MODEL}" "${NC}"
printf "  Версия OpenWrt: %b%s%b\n" "${GREEN}" "${OWRT_REL}" "${NC}"
printf "  Архитектура   : %b%s%b\n" "${GREEN}" "${ARCH}" "${NC}"
printf "  Менеджер ПО   : %b%s%b\n" "${GREEN}" "${PKG_MGR}" "${NC}"
printf "%b\n" "${CYAN}----------------------------------------------------------------${NC}"

# Подготовка изолированной временной папки для установки
TMP_WORK_DIR="$(mktemp -d /tmp/z2m_install.XXXXXX 2>/dev/null || echo "/tmp/z2m_install_$$")"
mkdir -p "${TMP_WORK_DIR}" 2>/dev/null
cleanup_install() {
    rm -rf "${TMP_WORK_DIR}" 2>/dev/null
}
trap cleanup_install EXIT INT TERM

# 5. Проверка наличия zapret2 (все возможные пути и менеджеры пакетов)
zapret_already_installed() {
    [ -f /etc/init.d/zapret2 ] && return 0
    [ -f /etc/init.d/zapret ] && return 0
    [ -f /opt/zapret2/sync_config.sh ] && return 0
    [ -f /opt/zapret2/nfqws2 ] && return 0
    [ -f /opt/zapret2/config ] && return 0
    [ -f /etc/config/zapret2 ] && return 0
    command -v nfqws2 >/dev/null 2>&1 && return 0
    command -v nfqws >/dev/null 2>&1 && return 0
    if command -v opkg >/dev/null 2>&1; then
        opkg list-installed 2>/dev/null | grep -qiE "^zapret2? " && return 0
    fi
    if command -v apk >/dev/null 2>&1; then
        apk info -e zapret2 2>/dev/null && return 0
    fi
    return 1
}

# Универсальный загрузчик файлов
install_download() {
    dl_url="$1"
    dl_dst="$2"
    rm -f "${dl_dst}" 2>/dev/null
    if command -v curl >/dev/null 2>&1; then
        curl -sSL -k --connect-timeout 8 -m 60 "${dl_url}" -o "${dl_dst}" 2>/dev/null
    fi
    if [ ! -s "${dl_dst}" ] && command -v wget >/dev/null 2>&1; then
        wget -q --timeout=30 -O "${dl_dst}" "${dl_url}" 2>/dev/null
    fi
    [ -s "${dl_dst}" ]
}

if zapret_already_installed; then
    printf "  Статус Zapret2: %bОбнаружен установленный Zapret2 в системе (пропуск)%b\n" "${GREEN}" "${NC}"
else
    printf "%b\n" "${YELLOW}Zapret2 не обнаружен в системе.${NC}"
    printf "%b\n" "${CYAN}Автоматическая загрузка zapret2 под архитектуру ${ARCH}...${NC}"

    ZAPRET_BASE_URL="https://github.com/1andrevich/zapret2-openwrt/releases/latest/download"

    # Определение списка совместимых резервных архитектур
    FALLBACK_ARCH=""
    case "${ARCH}" in
        aarch64*) FALLBACK_ARCH="aarch64_generic" ;;
        mipsel*)  FALLBACK_ARCH="mipsel_24kc" ;;
        mips*)    FALLBACK_ARCH="mips_24kc" ;;
        x86_64*)  FALLBACK_ARCH="x86_64" ;;
        arm*)     FALLBACK_ARCH="arm_cortex-a7_neon-vfpv4" ;;
        *)        FALLBACK_ARCH="" ;;
    esac

    PKG_FILE="${TMP_WORK_DIR}/zapret2.${PKG_EXT}"
    LUCI_FILE="${TMP_WORK_DIR}/luci-app-zapret2.${PKG_EXT}"

    if [ "${PKG_MGR}" = "apk" ]; then
        mkdir -p /etc/apk/keys 2>/dev/null
        install_download "${ZAPRET_BASE_URL}/zapret2-1andrevich.pub" "/etc/apk/keys/zapret2-1andrevich.pub"
        install_download "${ZAPRET_BASE_URL}/zapret2_${ARCH}.apk" "${PKG_FILE}"
        if [ ! -s "${PKG_FILE}" ] && [ -n "${FALLBACK_ARCH}" ]; then
            printf "%b\n" "${YELLOW}Пробуем совместимую архитектуру ${FALLBACK_ARCH}...${NC}"
            install_download "${ZAPRET_BASE_URL}/zapret2_${FALLBACK_ARCH}.apk" "${PKG_FILE}"
        fi
        install_download "${ZAPRET_BASE_URL}/luci-app-zapret2.apk" "${LUCI_FILE}"

        if [ -s "${PKG_FILE}" ]; then
            if [ -s "${LUCI_FILE}" ]; then
                apk add --allow-untrusted "${PKG_FILE}" "${LUCI_FILE}"
            else
                apk add --allow-untrusted "${PKG_FILE}"
            fi
        else
            printf "%b\n" "${RED}Пакет под ${ARCH} не найден в релизах zapret2-openwrt.${NC}" >&2
        fi
    else
        # opkg
        install_download "${ZAPRET_BASE_URL}/zapret2_${ARCH}.ipk" "${PKG_FILE}"
        if [ ! -s "${PKG_FILE}" ] && [ -n "${FALLBACK_ARCH}" ]; then
            printf "%b\n" "${YELLOW}Пробуем совместимую архитектуру ${FALLBACK_ARCH}...${NC}"
            install_download "${ZAPRET_BASE_URL}/zapret2_${FALLBACK_ARCH}.ipk" "${PKG_FILE}"
        fi
        install_download "${ZAPRET_BASE_URL}/luci-app-zapret2.ipk" "${LUCI_FILE}"

        if [ -s "${PKG_FILE}" ]; then
            opkg update >/dev/null 2>&1
            if [ -s "${LUCI_FILE}" ]; then
                opkg install "${PKG_FILE}" "${LUCI_FILE}"
            else
                opkg install "${PKG_FILE}"
            fi
        else
            printf "%b\n" "${RED}Не удалось автоматически загрузить zapret2_${ARCH}.ipk${NC}" >&2
        fi
    fi

    if zapret_already_installed; then
        printf "%b\n" "${GREEN}Пакет zapret2 успешно установлен на роутер!${NC}"
        /etc/init.d/zapret2 enable 2>/dev/null
    else
        printf "%b\n" "${YELLOW}Предупреждение: zapret2 не найден автоматически. При необходимости установите его вручную.${NC}"
    fi
    echo ""
fi

# 6. Развертывание Zapret2-Manager
SCRIPT_SOURCE_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
[ -z "${SCRIPT_SOURCE_DIR}" ] && SCRIPT_SOURCE_DIR="."

if [ -f "${SCRIPT_SOURCE_DIR}/zapret2-manager.sh" ]; then
    # Локальная установка из папки репозитория
    printf "%b\n" "${CYAN}Копируем файлы в ${INSTALL_DIR}...${NC}"
    mkdir -p "${INSTALL_DIR}"
    cp -rf "${SCRIPT_SOURCE_DIR}/"* "${INSTALL_DIR}/"
else
    # Загрузка и распаковка с GitHub (Floorys/Z2-Manager)
    DOWNLOAD_TAR="${TMP_WORK_DIR}/z2m_repo.tar.gz"
    TMP_UNPACK="${TMP_WORK_DIR}/unpack"
    mkdir -p "${TMP_UNPACK}" 2>/dev/null

    printf "%b\n" "${CYAN}Загружаем Z2-Manager с GitHub (Floorys/Z2-Manager)...${NC}"
    REPO_URL="https://github.com/Floorys/Z2-Manager/archive/refs/heads/main.tar.gz"

    if ! install_download "${REPO_URL}" "${DOWNLOAD_TAR}"; then
        ZIP_URL="https://github.com/Floorys/Z2-Manager/archive/refs/heads/main.zip"
        DOWNLOAD_ZIP="${TMP_WORK_DIR}/z2m_repo.zip"
        if install_download "${ZIP_URL}" "${DOWNLOAD_ZIP}" && command -v unzip >/dev/null 2>&1; then
            unzip -q -o "${DOWNLOAD_ZIP}" -d "${TMP_UNPACK}" 2>/dev/null
        fi
    else
        tar -xzf "${DOWNLOAD_TAR}" -C "${TMP_UNPACK}" 2>/dev/null
    fi

    EXTRACTED_DIR="$(find "${TMP_UNPACK}" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -n1)"
    if [ -z "${EXTRACTED_DIR}" ] || [ ! -f "${EXTRACTED_DIR}/zapret2-manager.sh" ]; then
        printf "%b\n" "${RED}Ошибка распаковки: zapret2-manager.sh не найден в архиве!${NC}" >&2
        exit 1
    fi

    mkdir -p "${INSTALL_DIR}"
    cp -rf "${EXTRACTED_DIR}/"* "${INSTALL_DIR}/"
fi

# 7. Нормализация переводов строк (удаление Windows \r)
find "${INSTALL_DIR}" -name "*.sh" -exec sed -i 's/\r$//' {} + 2>/dev/null

# 8. Назначение прав на исполнение
chmod +x "${INSTALL_DIR}/zapret2-manager.sh" 2>/dev/null
chmod +x "${INSTALL_DIR}/core/"*.sh 2>/dev/null
chmod +x "${INSTALL_DIR}/modules/"*.sh 2>/dev/null
chmod +x "${INSTALL_DIR}/strategies/"*.sh 2>/dev/null

# 9. Создание команд z2m и zsm в /usr/bin
rm -f "${BIN_LINK_Z2M}" "${BIN_LINK_ZSM}" 2>/dev/null

cat << 'EOF' > "${BIN_LINK_Z2M}"
#!/bin/sh
exec /bin/sh /opt/zapret2-manager/zapret2-manager.sh "$@"
EOF
chmod +x "${BIN_LINK_Z2M}" 2>/dev/null

cat << 'EOF' > "${BIN_LINK_ZSM}"
#!/bin/sh
exec /bin/sh /opt/zapret2-manager/zapret2-manager.sh "$@"
EOF
chmod +x "${BIN_LINK_ZSM}" 2>/dev/null

# 10. Первичная синхронизация блобов, хостлистов и установка фикса Discord Voice
mkdir -p /opt/zapret2/files/fake /opt/zapret2/ipset /opt/zapret2/init.d/openwrt/custom.d 2>/dev/null
if [ -d "${INSTALL_DIR}/fake" ]; then
    printf "%b\n" "${CYAN}Копируем fake-блобы и списки доменов в /opt/zapret2...${NC}"
    cp -f "${INSTALL_DIR}/fake/"*.bin /opt/zapret2/files/fake/ 2>/dev/null
    chmod 644 /opt/zapret2/files/fake/*.bin 2>/dev/null
fi
if [ -d "${INSTALL_DIR}/lists" ]; then
    cp -f "${INSTALL_DIR}/lists/"*.txt /opt/zapret2/ipset/ 2>/dev/null
    chmod 644 /opt/zapret2/ipset/*.txt 2>/dev/null
fi

# Установка объединенного фикса Discord Voice (custom.d script #50)
if [ -f "${INSTALL_DIR}/templates/50-script.sh" ]; then
    printf "%b\n" "${CYAN}Устанавливаем исправление Discord Voice (custom.d script #50)...${NC}"
    cp -f "${INSTALL_DIR}/templates/50-script.sh" /opt/zapret2/init.d/openwrt/custom.d/50-script.sh 2>/dev/null
    chmod 755 /opt/zapret2/init.d/openwrt/custom.d/50-script.sh 2>/dev/null
    rm -f /opt/zapret2/init.d/openwrt/custom.d/50-stun4all* /opt/zapret2/init.d/openwrt/custom.d/50-discord* 2>/dev/null
fi

# Авто-исправление поврежденных двойных кавычек в конфигурации
if [ -f /opt/zapret2/config ]; then
    if ! sh -n /opt/zapret2/config 2>/dev/null; then
        raw_opt=$(grep "^NFQWS2_OPT=" /opt/zapret2/config 2>/dev/null | sed 's/^NFQWS2_OPT=//' | tr -d '"')
        sed -i "s|^NFQWS2_OPT=.*|NFQWS2_OPT=\"${raw_opt}\"|" /opt/zapret2/config 2>/dev/null
    fi
    sed -i 's/^DISABLE_CUSTOM=.*/DISABLE_CUSTOM=0/' /opt/zapret2/config 2>/dev/null
    sed -i 's|^NFQWS2_PORTS_TCP=.*|NFQWS2_PORTS_TCP="80,443,2053,2083,2087,2096,8443"|' /opt/zapret2/config 2>/dev/null
    sed -i 's|^NFQWS2_PORTS_UDP=.*|NFQWS2_PORTS_UDP="443,19294-19344,50000-65535"|' /opt/zapret2/config 2>/dev/null
fi
if command -v uci >/dev/null 2>&1; then
    cur_opt="$(uci -q get zapret2.config.NFQWS2_OPT)"
    if [ -n "${cur_opt}" ]; then
        clean_opt="$(echo "${cur_opt}" | tr -d '"')"
        uci set zapret2.config.NFQWS2_OPT="${clean_opt}"
    fi
    uci set zapret2.config.DISABLE_CUSTOM='0'
    uci set zapret2.config.NFQWS2_PORTS_TCP='80,443,2053,2083,2087,2096,8443'
    uci set zapret2.config.NFQWS2_PORTS_UDP='443,19294-19344,50000-65535'
    uci commit zapret2 2>/dev/null
fi

# Перезапуск zapret2 с чистой конфигурацией если служба существует
if [ -f /opt/zapret2/sync_config.sh ]; then
    /opt/zapret2/sync_config.sh >/dev/null 2>&1
fi
if [ -f /etc/init.d/zapret2 ]; then
    /etc/init.d/zapret2 restart >/dev/null 2>&1
elif [ -f /etc/init.d/zapret ]; then
    /etc/init.d/zapret restart >/dev/null 2>&1
fi

# 11. Тестовый запуск для проверки
echo ""
if /bin/sh /opt/zapret2-manager/zapret2-manager.sh --help >/dev/null 2>&1; then
    printf "%b\n" "${GREEN}✔ Проверка запуска команды z2m: УСПЕШНО${NC}"
else
    printf "%b\n" "${RED}✖ Предупреждение: тестовый запуск завершился с ошибкой.${NC}"
fi

echo ""
printf "%b\n" "${GREEN}================================================================${NC}"
printf "%b\n" "${GREEN}       Zapret2-Manager успешно установлен!                     ${NC}"
printf "%b\n" "${GREEN}================================================================${NC}"
printf "Для запуска интерактивного меню введите команду:  %b%sz2m%b  (или %b%szsm%b)\n" "${BOLD}" "${YELLOW}" "${NC}" "${BOLD}" "${YELLOW}" "${NC}"
printf "Для автоподбора лучшей стратегии:                %b%sz2m -a%b\n" "${BOLD}" "${YELLOW}" "${NC}"
printf "Для двухпроходного генератора:                   %b%sz2m -g%b\n" "${BOLD}" "${YELLOW}" "${NC}"
printf "Для проверки YouTube:                            %b%sz2m -yt%b\n" "${BOLD}" "${YELLOW}" "${NC}"
printf "Для проверки Discord:                            %b%sz2m -dc%b\n" "${BOLD}" "${YELLOW}" "${NC}"
printf "Для центра обновлений (Zapret2 и Z2M):           %b%sz2m -u%b\n" "${BOLD}" "${YELLOW}" "${NC}"
printf "Для быстрого обновления пакета Zapret2:          %b%sz2m -uz%b\n" "${BOLD}" "${YELLOW}" "${NC}"
printf "Для проверки обновлений:                         %b%sz2m -cu%b\n" "${BOLD}" "${YELLOW}" "${NC}"
echo ""
