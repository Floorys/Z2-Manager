#!/bin/sh
# shellcheck disable=SC3043
# ==============================================================================
# Zapret2-Manager: Terminal UI & Formatting Helpers
# ==============================================================================

[ -z "${Z2M_DIR:-}" ] && Z2M_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)"
[ -f "${Z2M_DIR}/core/config.sh" ] && . "${Z2M_DIR}/core/config.sh"

tui_banner() {
    clear 2>/dev/null || printf "\033c"
    printf "%b" "${CYAN}"
    cat << "EOF"
  ███████╗ █████╗ ██████╗ ██████╗ ███████╗████████╗██████╗     ███╗   ███╗
  ╚══███╔╝██╔══██╗██╔══██╗██╔══██╗██╔════╝╚══██╔══╝╚════██╗    ████╗ ████║
    ███╔╝ ███████║██████╔╝██████╔╝█████╗     ██║    █████╔╝    ██╔████╔██║
   ███╔╝  ██╔══██║██╔═══╝ ██╔══██╗██╔══╝     ██║   ██╔═══╝     ██║╚██╔╝██║
  ███████╗██║  ██║██║     ██║  ██║███████╗   ██║   ███████╗    ██║ ╚═╝ ██║
  ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚══════╝    ╚═╝     ╚═╝
EOF
    printf "%b" "${NC}"
    printf "%b  Zapret2 Manager v%s | Asterlike & 1andrevich Architecture%b\n" "${DGRAY}" "${Z2M_VERSION}" "${NC}"
    printf "%b  ───────────────────────────────────────────────────────────────────%b\n\n" "${DGRAY}" "${NC}"
}

tui_header() {
    local title="$1"
    printf "%b%b%s%b\n" "${BOLD}" "${WHITE}" "${title}" "${NC}"
    printf "%b%s%b\n\n" "${DGRAY}" "───────────────────────────────────────────────────────────────────" "${NC}"
}

tui_info() {
    printf "%bℹ %s%b\n" "${CYAN}" "$1" "${NC}"
}

tui_success() {
    printf "%b✔ %s%b\n" "${GREEN}" "$1" "${NC}"
}

tui_warn() {
    printf "%b⚠ %s%b\n" "${YELLOW}" "$1" "${NC}"
}

tui_error() {
    printf "%b✖ %s%b\n" "${RED}" "$1" "${NC}" >&2
}

tui_step() {
    local current="$1"
    local total="$2"
    local msg="$3"
    printf "%b[%s/%s]%b %s\n" "${MAGENTA}" "${current}" "${total}" "${NC}" "${msg}"
}

tui_pause() {
    printf "\n%bНажмите [Enter] для продолжения...%b " "${DGRAY}" "${NC}" >&2
    # shellcheck disable=SC2034
    read -r dummy </dev/tty 2>/dev/null || read -r dummy
}

tui_prompt() {
    local prompt_text="$1"
    local default_val="$2"
    local user_val=""

    if [ -n "${default_val}" ]; then
        printf "%b %b[%s]%b: " "${prompt_text}" "${DGRAY}" "${default_val}" "${NC}" >&2
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
    printf "%b%-36s %-10s %-10s %-10s%b\n" "${BOLD}" "Стратегия / Бандл" "Успешно" "Ошибок" "Статус" "${NC}"
    printf "%b───────────────────────────────────────────────────────────────────%b\n" "${DGRAY}" "${NC}"
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
    printf "%-36s %b%-10s%b %b%-10s%b %b%s %s/%s%b\n" \
        "${short_name}" "${GREEN}" "${ok}" "${NC}" "${RED}" "${fail}" "${NC}" "${color}" "${glyph}" "${ok}" "${total}" "${NC}"
}
