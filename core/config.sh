#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Global Configuration & Environment Constants
# ==============================================================================

Z2M_VERSION="1.2.0"
Z2M_APP_NAME="Zapret2-Manager"

# ANSI Colors for TUI
NC="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"
DGRAY="\033[38;5;244m"
BG_BLUE="\033[44;37m"

# OpenWrt & Zapret2 System Paths
ZAPRET2_DIR="/opt/zapret2"
ZAPRET2_CONFIG="${ZAPRET2_DIR}/config"
ZAPRET2_CONFIG_DEF="${ZAPRET2_DIR}/config.default"
ZAPRET2_INIT="/etc/init.d/zapret2"
ZAPRET2_SYNC="${ZAPRET2_DIR}/sync_config.sh"
ZAPRET2_FAKE_DIR="${ZAPRET2_DIR}/files/fake"
ZAPRET2_IPSET_DIR="${ZAPRET2_DIR}/ipset"
ZAPRET2_BIN="${ZAPRET2_DIR}/nfqws2"

# OpenWrt UCI Configuration File
UCI_CONFIG="/etc/config/zapret2"
UCI_SECTION="zapret2.config"

# Recommended default ports for Zapret2 (Web, Discord Voice, CDN, Cloudflare)
DEFAULT_PORTS_TCP="80,443,2053,2083,2087,2096,8443"
DEFAULT_PORTS_UDP="443,19294-19344,50000-65535"

# Manager Runtime Directories
if [ -z "${Z2M_DIR}" ] || [ ! -d "${Z2M_DIR}/core" ]; then
    if [ -d "/opt/zapret2-manager/core" ]; then
        Z2M_DIR="/opt/zapret2-manager"
    elif [ -f "$(dirname "$0")/core/config.sh" ]; then
        Z2M_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
    elif [ -f "$(dirname "$0")/config.sh" ]; then
        Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
    else
        Z2M_DIR="/opt/zapret2-manager"
    fi
fi
export Z2M_DIR
Z2M_TMP="/tmp/zapret2-manager"
Z2M_BACKUP_DIR="${Z2M_DIR}/backups"
Z2M_LOG_FILE="${Z2M_TMP}/z2m.log"

# Probing target endpoints (Expanded suite inspired by StressOzz)
DISCORD_PROBE_HOSTS="discord.com gateway.discord.gg cdn.discordapp.com"
YOUTUBE_PROBE_HOSTS="www.youtube.com googlevideo.com i.ytimg.com"
BLOCKED_PROBE_HOSTS="rutracker.org x.com instagram.com"

# Benchmark domain suite for auto-selection (YouTube + Discord + RKN blocked)
ALL_PROBE_HOSTS="www.youtube.com googlevideo.com discord.com gateway.discord.gg rutracker.org"

# Full Diagnostic suite (10 domains across YouTube, Discord, RKN blocks & connection control)
DIAGNOSTIC_HOSTS="www.youtube.com googlevideo.com i.ytimg.com discord.com gateway.discord.gg cdn.discordapp.com rutracker.org x.com instagram.com vk.com"

# Chrome-like User-Agent for realistic probes
BROWSER_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

# Russian ISP Block Page Signatures (Russian TSPU/DPI stub-page fingerprints)
BLOCK_MARKERS="доступ ограничен|доступ заблокирован|ресурс заблокирован|единый реестр|запрещен на территории|warning.rt.ru|eais.rkn.gov.ru|blocked by"

# Setup temporary directory
mkdir -p "${Z2M_TMP}" 2>/dev/null
mkdir -p "${Z2M_BACKUP_DIR}" 2>/dev/null
