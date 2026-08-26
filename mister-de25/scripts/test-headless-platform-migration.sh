#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/mister-de25-headless-migration-test.XXXXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

fat=$test_root/fat
control=$fat/.mister-de25/headless-migration
source_rbf=$test_root/menu.rbf
helper=$test_root/migration-helper
systemctl_mock=$test_root/systemctl
helper_log=$test_root/helper.log
systemctl_log=$test_root/systemctl.log
target_hash=FDCDD4C99876BAE3D17BB5B0AF4A4C7B7D55B2CE17D05C535A5BF69DD7DE930B
client=$platform_root/sw/mister-de25-migrate
controller=$platform_root/sw/mister-de25-headless-migrate
bootstrap=$platform_root/sw/mister-de25-headless-bootstrap

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

mkdir -p "$fat"
printf 'scaler menu\n' >"$source_rbf"
printf '%s\n' "$target_hash" >"$source_rbf.hps-io-hash"
hash_file "$source_rbf" >"$source_rbf.sha256"

cat >"$helper" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >>'$helper_log'
EOF
cat >"$systemctl_mock" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >>'$systemctl_log'
EOF
chmod +x "$helper" "$systemctl_mock"

run_client() {
    MISTER_DE25_FAT_ROOT=$fat \
    MISTER_DE25_HEADLESS_ROOT=$control \
        "$client" "$@"
}

start_controller() {
    MISTER_DE25_FAT_ROOT=$fat \
    MISTER_DE25_HEADLESS_ROOT=$control \
    MISTER_DE25_MIGRATION_HELPER=$helper \
    MISTER_DE25_SYSTEMCTL=$systemctl_mock \
    MISTER_DE25_MIGRATION_WAIT_SECONDS=10 \
    MISTER_DE25_ALLOW_NON_ROOT=1 \
        "$controller" &
    controller_pid=$!
    for _ in {1..100}; do
        [[ -s $control/prepared ]] && return 0
        kill -0 "$controller_pid" 2>/dev/null || break
        sleep 0.01
    done
    echo "FAIL: headless migration controller did not prepare" >&2
    wait "$controller_pid" || true
    exit 1
}

run_client stage "$source_rbf" >/dev/null
grep -qx "$target_hash" "$control/request"
cmp "$source_rbf" "$control/menu.rbf"
start_controller
grep -qx 'state=waiting-for-qspi' "$control/status"
run_client verified --confirm FLASH-VERIFIED >/dev/null
wait "$controller_pid"
grep -qx "prepare $control/menu.rbf" "$helper_log"
grep -qx 'flashed --confirm FLASH-VERIFIED' "$helper_log"
grep -qx 'reboot' "$systemctl_log"
grep -qx 'state=rebooting' "$control/status"
[[ ! -e $control/request ]]

: >"$helper_log"
: >"$systemctl_log"
run_client stage "$source_rbf" >/dev/null
start_controller
run_client status | grep -qx 'state=waiting-for-qspi'
run_client cancel >/dev/null
if wait "$controller_pid"; then
    echo "FAIL: controller ignored a cancellation request" >&2
    exit 1
fi
grep -qx 'abort' "$helper_log"
grep -qx 'state=failed' "$control/status"
[[ ! -e $control/request ]]

: >"$helper_log"
: >"$systemctl_log"
run_client stage "$source_rbf" >/dev/null
start_controller
printf '%064d\n' 0 >"$control/qspi-verified"
if wait "$controller_pid"; then
    echo "FAIL: controller accepted the wrong QSPI verification hash" >&2
    exit 1
fi
grep -qx 'abort' "$helper_log"
grep -qx 'state=failed' "$control/status"
[[ ! -e $control/request ]]

# A temporary headless launcher occupies the configured MiSTer path while the
# real binary lives elsewhere.  It must identify that equivalent path to Main
# so Main does not continually re-exec the launcher.
launcher_log=$test_root/launcher.log
fake_main=$test_root/MiSTer.real
cat >"$fake_main" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$MISTER_DE25_LAUNCHER" >'$launcher_log'
EOF
chmod +x "$fake_main"
MISTER_DE25_FAT_ROOT=$fat \
MISTER_DE25_HEADLESS_ROOT=$control \
MISTER_DE25_REAL_MAIN=$fake_main \
    "$bootstrap"
grep -qx "$fat/MiSTer" "$launcher_log"

echo "PASS: headless migration staging, verification, cancellation, and abort"
