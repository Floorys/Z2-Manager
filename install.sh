#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Fast OpenWrt Router Installer
# Repository: Floorys/Z2-Manager
# ==============================================================================

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
BOLD="\033[1m"
NC="\033[0m"

INSTALL_DIR="/opt/zapret2-manager"
BIN_LINK_Z2M="/usr/bin/z2m"
BIN_LINK_ZSM="/usr/bin/zsm"

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}             Установка Zapret2-Manager на OpenWrt               ${NC}"
echo -e "${CYAN}================================================================${NC}"

# 1. Проверка OpenWrt
if [ ! -f /etc/openwrt_release ] && [ ! -f /etc/os-release ]; then
    echo -e "${RED}Ошибка: данный скрипт предназначен только для OpenWrt!${NC}"
    exit 1
fi

# 2. Определение менеджера пакетов (apk или opkg)
if command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    PKG_EXT="apk"
    PKG_INSTALL="apk add --allow-untrusted"
elif command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
    PKG_EXT="ipk"
    PKG_INSTALL="opkg install"
else
    echo -e "${RED}Ошибка: менеджер пакетов (opkg/apk) не найден!${NC}"
    exit 1
fi

# 3. Определение модели устройства, версии OpenWrt и архитектуры
ROUTER_MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"
[ -z "${ROUTER_MODEL}" ] && ROUTER_MODEL="$(grep -i 'machine' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//')"
[ -z "${ROUTER_MODEL}" ] && ROUTER_MODEL="$(grep -i 'Hardware' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//')"
[ -z "${ROUTER_MODEL}" ] && ROUTER_MODEL="OpenWrt Router"

OWRT_REL="$(grep '^DISTRIB_RELEASE=' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)"
[ -z "${OWRT_REL}" ] && [ -f /etc/os-release ] && OWRT_REL="$(. /etc/os-release 2>/dev/null; echo "$VERSION_ID")"
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
    . /etc/os-release 2>/dev/null
    ARCH="${OPENWRT_ARCH}"
fi
if [ -z "${ARCH}" ] && [ -f /etc/openwrt_release ]; then
    ARCH="$(grep '^DISTRIB_ARCH=' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)"
fi
[ -z "${ARCH}" ] && ARCH="unknown"

echo -e "  Устройство    : ${GREEN}${ROUTER_MODEL}${NC}"
echo -e "  Версия OpenWrt: ${GREEN}${OWRT_REL}${NC}"
echo -e "  Архитектура   : ${GREEN}${ARCH}${NC}"
echo -e "  Менеджер ПО   : ${GREEN}${PKG_MGR}${NC}"
echo -e "${CYAN}----------------------------------------------------------------${NC}"

# 4. Проверка и установка базовых утилит (curl, wget)
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo -e "${YELLOW}Обновляем списки пакетов и ставим curl...${NC}"
    [ "${PKG_MGR}" = "opkg" ] && opkg update >/dev/null 2>&1
    ${PKG_INSTALL} curl >/dev/null 2>&1
fi

# 5. Проверка наличия zapret2 (1andrevich)
if [ -f /opt/zapret2/sync_config.sh ] && [ -f /opt/zapret2/nfqws2 ]; then
    echo -e "  Статус Zapret2: ${GREEN}Установлен в /opt/zapret2${NC}"
else
    echo -e "${YELLOW}Zapret2 не обнаружен в /opt/zapret2.${NC}"
    echo -e "${CYAN}Автоматическая установка zapret2 под архитектуру ${ARCH}...${NC}"

    ZAPRET_BASE_URL="https://github.com/1andrevich/zapret2-openwrt/releases/latest/download"

    if [ "${PKG_MGR}" = "apk" ]; then
        mkdir -p /etc/apk/keys 2>/dev/null
        wget -q -O /etc/apk/keys/zapret2-1andrevich.pub "${ZAPRET_BASE_URL}/zapret2-1andrevich.pub" 2>/dev/null
        wget -q -O /tmp/zapret2.apk "${ZAPRET_BASE_URL}/zapret2_${ARCH}.apk" 2>/dev/null
        wget -q -O /tmp/luci-app-zapret2.apk "${ZAPRET_BASE_URL}/luci-app-zapret2.apk" 2>/dev/null

        if [ -s /tmp/zapret2.apk ]; then
            apk add --allow-untrusted /tmp/zapret2.apk /tmp/luci-app-zapret2.apk
        else
            echo -e "${RED}Пакет под ${ARCH} не найден в релизах zapret2-openwrt.${NC}"
        fi
        rm -f /tmp/zapret2.apk /tmp/luci-app-zapret2.apk 2>/dev/null
    else
        # opkg
        wget -q -O /tmp/zapret2.ipk "${ZAPRET_BASE_URL}/zapret2_${ARCH}.ipk" 2>/dev/null
        if [ ! -s /tmp/zapret2.ipk ]; then
            case "${ARCH}" in
                aarch64*) FALLBACK_ARCH="aarch64_generic" ;;
                mipsel*)  FALLBACK_ARCH="mipsel_24kc" ;;
                mips*)    FALLBACK_ARCH="mips_24kc" ;;
                x86_64*)  FALLBACK_ARCH="x86_64" ;;
                *)        FALLBACK_ARCH="" ;;
            esac
            if [ -n "${FALLBACK_ARCH}" ]; then
                echo -e "${YELLOW}Пробуем совместимую архитектуру ${FALLBACK_ARCH}...${NC}"
                wget -q -O /tmp/zapret2.ipk "${ZAPRET_BASE_URL}/zapret2_${FALLBACK_ARCH}.ipk" 2>/dev/null
            fi
        fi

        wget -q -O /tmp/luci-app-zapret2.ipk "${ZAPRET_BASE_URL}/luci-app-zapret2.ipk" 2>/dev/null

        if [ -s /tmp/zapret2.ipk ]; then
            opkg update >/dev/null 2>&1
            opkg install /tmp/zapret2.ipk /tmp/luci-app-zapret2.ipk
        else
            echo -e "${RED}Не удалось автоматически загрузить zapret2_${ARCH}.ipk${NC}"
        fi
        rm -f /tmp/zapret2.ipk /tmp/luci-app-zapret2.ipk 2>/dev/null
    fi

    if [ -f /opt/zapret2/sync_config.sh ]; then
        echo -e "${GREEN}Пакет zapret2 успешно установлен на роутер!${NC}"
        /etc/init.d/zapret2 enable 2>/dev/null
    else
        echo -e "${YELLOW}Предупреждение: zapret2 не найден. Установите пакет вручную при необходимости.${NC}"
    fi
    echo ""
fi

# 6. Развертывание Zapret2-Manager
SCRIPT_SOURCE_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
[ -z "${SCRIPT_SOURCE_DIR}" ] && SCRIPT_SOURCE_DIR="."

if [ -f "${SCRIPT_SOURCE_DIR}/zapret2-manager.sh" ]; then
    # Локальная установка из папки репозитория
    echo -e "${CYAN}Копируем файлы в ${INSTALL_DIR}...${NC}"
    mkdir -p "${INSTALL_DIR}"
    cp -rf "${SCRIPT_SOURCE_DIR}/"* "${INSTALL_DIR}/"
else
    # Загрузка и распаковка с GitHub (Floorys/Z2-Manager)
    DOWNLOAD_TAR="/tmp/z2m_repo.tar.gz"
    TMP_UNPACK="/tmp/z2m_unpack"
    rm -rf "${DOWNLOAD_TAR}" "${TMP_UNPACK}" 2>/dev/null
    mkdir -p "${TMP_UNPACK}"

    echo -e "${CYAN}Загружаем Z2-Manager с GitHub (Floorys/Z2-Manager)...${NC}"
    REPO_URL="https://github.com/Floorys/Z2-Manager/archive/refs/heads/main.tar.gz"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${REPO_URL}" -o "${DOWNLOAD_TAR}" 2>/dev/null
    fi
    if [ ! -s "${DOWNLOAD_TAR}" ] && command -v wget >/dev/null 2>&1; then
        wget -qO "${DOWNLOAD_TAR}" "${REPO_URL}" 2>/dev/null
    fi

    # Fallback to ZIP если tar.gz не скачался
    if [ ! -s "${DOWNLOAD_TAR}" ]; then
        ZIP_URL="https://github.com/Floorys/Z2-Manager/archive/refs/heads/main.zip"
        DOWNLOAD_ZIP="/tmp/z2m_repo.zip"
        if command -v wget >/dev/null 2>&1; then
            wget -qO "${DOWNLOAD_ZIP}" "${ZIP_URL}" 2>/dev/null
        elif command -v curl >/dev/null 2>&1; then
            curl -fsSL "${ZIP_URL}" -o "${DOWNLOAD_ZIP}" 2>/dev/null
        fi

        if [ -s "${DOWNLOAD_ZIP}" ] && command -v unzip >/dev/null 2>&1; then
            unzip -q -o "${DOWNLOAD_ZIP}" -d "${TMP_UNPACK}" 2>/dev/null
            rm -f "${DOWNLOAD_ZIP}" 2>/dev/null
        fi
    else
        # Распаковка стандартным BusyBox tar
        tar -xzf "${DOWNLOAD_TAR}" -C "${TMP_UNPACK}" 2>/dev/null
    fi

    EXTRACTED_DIR="$(find "${TMP_UNPACK}" -maxdepth 1 -mindepth 1 -type d | head -n1)"
    if [ -z "${EXTRACTED_DIR}" ] || [ ! -f "${EXTRACTED_DIR}/zapret2-manager.sh" ]; then
        echo -e "${RED}Ошибка распаковки: zapret2-manager.sh не найден в архиве!${NC}"
        rm -rf "${DOWNLOAD_TAR}" "${TMP_UNPACK}" 2>/dev/null
        exit 1
    fi

    mkdir -p "${INSTALL_DIR}"
    cp -rf "${EXTRACTED_DIR}/"* "${INSTALL_DIR}/"
    rm -rf "${DOWNLOAD_TAR}" "${TMP_UNPACK}" 2>/dev/null
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

# 10. Первичная синхронизация блобов и хостлистов
if [ -d /opt/zapret2 ]; then
    sh "${INSTALL_DIR}/zapret2-manager.sh" --restart >/dev/null 2>&1
fi

# 11. Тестовый запуск для проверки
echo ""
if /bin/sh /opt/zapret2-manager/zapret2-manager.sh --help >/dev/null 2>&1; then
    echo -e "${GREEN}✔ Проверка запуска команды z2m: УСПЕШНО${NC}"
else
    echo -e "${RED}✖ Предупреждение: тестовый запуск завершился с ошибкой.${NC}"
fi

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}       Zapret2-Manager успешно установлен!                     ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "Для запуска интерактивного меню введите команду:  ${BOLD}${YELLOW}z2m${NC}  (или ${BOLD}${YELLOW}zsm${NC})"
echo -e "Для автоподбора лучшей стратегии:                ${BOLD}${YELLOW}z2m -a${NC}"
echo -e "Для двухпроходного генератора:                   ${BOLD}${YELLOW}z2m -g${NC}"
echo -e "Для проверки YouTube:                            ${BOLD}${YELLOW}z2m -yt${NC}"
echo -e "Для проверки Discord:                            ${BOLD}${YELLOW}z2m -dc${NC}"
echo ""
