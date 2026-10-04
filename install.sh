#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Fast OpenWrt Router Installer
# ==============================================================================

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
NC="\033[0m"

INSTALL_DIR="/opt/zapret2-manager"
BIN_LINK="/usr/bin/z2m"

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}             Установка Zapret2-Manager на OpenWrt               ${NC}"
echo -e "${CYAN}================================================================${NC}"

# Check for OpenWrt
if [ ! -f /etc/openwrt_release ]; then
    echo -e "${RED}Ошибка: данный скрипт предназначен только для OpenWrt!${NC}"
    exit 1
fi

# Check package manager (opkg or apk)
if command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    PKG_INSTALL="apk add"
elif command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
    PKG_INSTALL="opkg install"
else
    echo -e "${RED}Ошибка: менеджер пакетов (opkg/apk) не найден!${NC}"
    exit 1
fi

# Ensure curl and unzip are available
if ! command -v curl >/dev/null 2>&1; then
    echo -e "${YELLOW}Устанавливаем curl...${NC}"
    $PKG_INSTALL curl >/dev/null 2>&1
fi

# Check if zapret2 is installed
if [ ! -f /opt/zapret2/sync_config.sh ]; then
    echo -e "${YELLOW}Внимание: Пакет zapret2 не обнаружен в /opt/zapret2.${NC}"
    echo -e "Для работы требуется установленный zapret2 (https://github.com/1andrevich/zapret2-openwrt)."
    echo -e "Установить zapret2 можно командой:"
    if [ "$PKG_MGR" = "apk" ]; then
        echo -e "  wget -O /tmp/zapret2.apk \"https://github.com/1andrevich/zapret2-openwrt/releases/latest/download/zapret2_\$(. /etc/os-release; echo \"\$OPENWRT_ARCH\").apk\""
        echo -e "  apk add --allow-untrusted /tmp/zapret2.apk"
    else
        echo -e "  wget -O /tmp/zapret2.ipk \"https://github.com/1andrevich/zapret2-openwrt/releases/latest/download/zapret2_\$(. /etc/os-release; echo \"\$OPENWRT_ARCH\").ipk\""
        echo -e "  opkg install /tmp/zapret2.ipk"
    fi
    echo ""
fi

# Local or remote deployment
SCRIPT_SOURCE_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
[ -z "${SCRIPT_SOURCE_DIR}" ] && SCRIPT_SOURCE_DIR="."

if [ -f "${SCRIPT_SOURCE_DIR}/zapret2-manager.sh" ]; then
    # Local install from repository directory
    echo -e "${CYAN}Копируем файлы в ${INSTALL_DIR}...${NC}"
    mkdir -p "${INSTALL_DIR}"
    cp -rf "${SCRIPT_SOURCE_DIR}/"* "${INSTALL_DIR}/"
else
    # Remote install via GitHub
    REPO_URL="https://github.com/FunnyDragon/Zapret2Manager/archive/refs/heads/main.tar.gz"
    echo -e "${CYAN}Загружаем Zapret2-Manager с GitHub...${NC}"
    mkdir -p "${INSTALL_DIR}"
    curl -fsSL "${REPO_URL}" | tar -xz -C "${INSTALL_DIR}" --strip-components=1 2>/dev/null
fi

# Set executable permissions
chmod +x "${INSTALL_DIR}/zapret2-manager.sh" 2>/dev/null
chmod +x "${INSTALL_DIR}/core/"*.sh 2>/dev/null
chmod +x "${INSTALL_DIR}/modules/"*.sh 2>/dev/null
chmod +x "${INSTALL_DIR}/strategies/"*.sh 2>/dev/null

# Create symlink
ln -sf "${INSTALL_DIR}/zapret2-manager.sh" "${BIN_LINK}"

# Sync fake blobs and hostlists
if [ -f "${INSTALL_DIR}/zapret2-manager.sh" ]; then
    sh "${INSTALL_DIR}/zapret2-manager.sh" --restart >/dev/null 2>&1
fi

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}       Zapret2-Manager успешно установлен!                     ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "Для запуска интерактивного меню введите команду:  ${BOLD}${YELLOW}z2m${NC}"
echo -e "Для автоподбора лучшей стратегии:                ${BOLD}${YELLOW}z2m -a${NC}"
echo -e "Для двухпроходной генерации:                    ${BOLD}${YELLOW}z2m -g${NC}"
echo ""
