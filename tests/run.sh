#!/bin/sh

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT="/tmp/z2m-tests.$$"
BIN_DIR="${TMP_ROOT}/bin"
PASS=0
FAIL=0

cleanup() {
    rm -rf "${TMP_ROOT}" 2>/dev/null
}
trap cleanup EXIT INT TERM

mkdir -p "${BIN_DIR}" "${TMP_ROOT}/runtime"

cat > "${BIN_DIR}/curl" <<'EOF'
#!/bin/sh
header_file=""
body_file=""
previous=""
for argument in "$@"; do
    case "${previous}" in
        header) header_file="${argument}"; previous=""; continue ;;
        body) body_file="${argument}"; previous=""; continue ;;
    esac
    case "${argument}" in
        -D) previous="header" ;;
        -o) previous="body" ;;
        -k|--insecure) exit 90 ;;
    esac
done
[ -n "${header_file}" ] && : > "${header_file}"
if [ -n "${body_file}" ]; then
    case "${FAKE_BODY:-clean}" in
        blocked) printf '%s\n' 'Доступ заблокирован. Ресурс внесён в единый реестр.' > "${body_file}" ;;
        *) printf '%s\n' 'normal service response' > "${body_file}" ;;
    esac
fi
printf '%s' "${FAKE_HTTP_CODE:-200}"
exit 0
EOF
chmod +x "${BIN_DIR}/curl"

cat > "${BIN_DIR}/nslookup" <<'EOF'
#!/bin/sh
cat <<'OUT'
Server:         127.0.0.1
Address:        127.0.0.1#53

Name:      example.org
Address 1: 104.21.32.1
OUT
EOF
chmod +x "${BIN_DIR}/nslookup"

PATH="${BIN_DIR}:${PATH}"
export PATH
Z2M_DIR="${ROOT}"
export Z2M_DIR

# The source paths are computed so the test works from any current directory.
# shellcheck disable=SC1090
. "${ROOT}/core/config.sh"
. "${ROOT}/core/probe.sh"
. "${ROOT}/core/zapret_service.sh"
. "${ROOT}/modules/updater.sh"

Z2M_TMP="${TMP_ROOT}/runtime"
export Z2M_TMP

check() {
    name="$1"
    shift
    if "$@"; then
        printf 'ok - %s\n' "${name}"
        PASS=$((PASS + 1))
    else
        printf 'not ok - %s\n' "${name}"
        FAIL=$((FAIL + 1))
    fi
}

probe_must_fail() {
    ! probe_curl_request example.org 443 1 ""
}

probe_must_pass() {
    probe_curl_request example.org 443 1 ""
}

FAKE_HTTP_CODE=451 FAKE_BODY=clean export FAKE_HTTP_CODE FAKE_BODY
check "HTTP 451 is blocked" probe_must_fail

FAKE_HTTP_CODE=200 FAKE_BODY=blocked export FAKE_HTTP_CODE FAKE_BODY
check "HTTP 200 block page is detected" probe_must_fail

FAKE_HTTP_CODE=404 FAKE_BODY=clean export FAKE_HTTP_CODE FAKE_BODY
check "service HTTP 404 still proves TLS reachability" probe_must_pass

check_dns_parser() {
    [ "$(probe_dns_resolve example.org)" = "104.21.32.1" ]
}
check "BusyBox nslookup address is parsed" check_dns_parser

check "valid port ranges are accepted" zapret_validate_ports "80,443,50000-65535"

invalid_ports_rejected() {
    ! zapret_validate_ports "80,70000,9000-8000"
}
check "invalid port ranges are rejected" invalid_ports_rejected

version_is_newer() {
    vercmp "1.0.10" "1.0.9"
    [ "$?" -eq 1 ]
}
check "numeric versions are compared correctly" version_is_newer

stable_is_newer_than_prerelease() {
    vercmp "1.0.6" "1.0.6-rc1"
    [ "$?" -eq 1 ]
}
check "stable release is newer than prerelease" stable_is_newer_than_prerelease

package_revision_matches_release() {
    vercmp "1.0.6-r2" "1.0.6"
}
check "OpenWrt package revision matches upstream release" package_revision_matches_release

secure_download_flags() {
    ! grep -R -E -- 'curl[^\n]*( -k|--insecure)|--allow-untrusted' \
        "${ROOT}/install.sh" "${ROOT}/core" "${ROOT}/modules" >/dev/null 2>&1
}
check "insecure download flags are absent" secure_download_flags

printf '\n%s passed, %s failed\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
