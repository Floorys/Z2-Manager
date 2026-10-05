#!/bin/sh
# ==============================================================================
# Zapret2-Manager: Terminal UI & Formatting Helpers
# ==============================================================================

[ -z "${Z2M_DIR}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"

tui_banner() {
    clear
    printf "${CYAN}"
    cat << "EOF"
  ███████╗ █████╗ ██████╗ ██████╗ ███████╗████████╗██████╗     ███╗   ███╗
  ╚══███╔╝██╔══██╗██╔══██╗██╔══██╗██╔════╝╚══██╔══╝╚════██╗    ████╗ ████║
    ███╔╝ ███████║██████╔╝██████╔╝█████╗     ██║    █████╔╝    ██╔████╔██║
   ███╔╝  ██╔══██║██╔═══╝ ██╔══██╗██╔══╝     ██║   ██╔═══╝     ██║╚██╔╝██║
  ███████╗██║  ██║██║     ██║  ██║███████╗   ██║   ███████╗    ██║ ╚═╝ ██║
  ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚══════╝    ╚═╝     ╚═╝
EOF
    printf "${NC}"
    printf "${DGRAY}  Zapret2 Manager v%s | Asterlike & 1andrevich Architecture${NC}\n" "${Z2M_VERSION}"
    printf "${DGRAY}  ───────────────────────────────────────────────────────────────────${NC}\n\n"
}

tui_header() {
    local title="$1"
    printf "${BOLD}${WHITE}%s${NC}\n" "${title}"
    printf "${DGRAY}%s${NC}\n\n" "───────────────────────────────────────────────────────────────────"
}

tui_info() {
    printf "${CYAN}ℹ %s${NC}\n" "$1"
}

tui_success() {
    printf "${GREEN}✔ %s${NC}\n" "$1"
}

tui_warn() {
    printf "${YELLOW}⚠ %s${NC}\n" "$1"
}

tui_error() {
    printf "${RED}✖ %s${NC}\n" "$1"
}

tui_step() {
    local current="$1"
    local total="$2"
    local msg="$3"
    printf "${MAGENTA}[%s/%s]${NC} %s\n" "${current}" "${total}" "${msg}"
}

tui_pause() {
    printf "\n${DGRAY}Нажмите [Enter] для продолжения...${NC} " >&2
    # shellcheck disable=SC2034
    read -r dummy </dev/tty 2>/dev/null || read -r dummy
}

tui_prompt() {
    local prompt_text="$1"
    local default_val="$2"
    local user_val=""

    if [ -n "${default_val}" ]; then
        printf "%b ${DGRAY}[%s]${NC}: " "${prompt_text}" "${default_val}" >&2
    else
        printf "%b: " "${prompt_text}" >&2
    fi

    read -r user_val </dev/tty 2>/dev/null || read -r user_val
    user_val=$(echo "${user_val}" | tr -d '\r\n')

    if [ -z "${user_val}" ]; then
        echo "${default_val}"
    else
        echo "${user_val}"
    fi
}

tui_print_result_table_header() {
    printf "${BOLD}%-36s %-10s %-10s %-10s${NC}\n" "Стратегия / Бандл" "Успешно" "Ошибок" "Статус"
    printf "${DGRAY}───────────────────────────────────────────────────────────────────${NC}\n"
}

tui_print_result_row() {
    local name="$1"
    local ok="$2"
    local fail="$3"
    local total="$4"
    local glyph="≈"
    local color="${YELLOW}"

    if [ "${fail}" -eq 0 ] && [ "${ok}" -gt 0 ]; then
        glyph="✓"
        color="${GREEN}"
    elif [ "${ok}" -eq 0 ]; then
        glyph="✗"
        color="${RED}"
    fi

    # Trim name to fit table
    local short_name
    short_name=$(printf "%.34s" "${name}")
    printf "%-36s ${GREEN}%-10s${NC} ${RED}%-10s${NC} ${color}%s %s/%s${NC}\n" \
        "${short_name}" "${ok}" "${fail}" "${glyph}" "${ok}" "${total}"
}
