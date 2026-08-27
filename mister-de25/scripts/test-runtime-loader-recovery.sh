#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/mister-de25-loader-test.XXXXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

bin=$test_root/bin
configfs=$test_root/configfs
overlay_root=$configfs/device-tree/overlays
overlay_dir=$overlay_root/mister-de25
state_dir=$test_root/state
region=$test_root/region0
manager_state=$test_root/manager-state
firmware=$test_root/firmware.rbf
overlay_source=$test_root/fpga-load.dtbo
watchdog=$test_root/watchdog
watchdog_timeout=$test_root/watchdog-timeout
watchdog_nowayout=$test_root/watchdog-nowayout
modprobe_log=$test_root/modprobe.log
compatibility_log=$test_root/compatibility.log
candidate=$test_root/candidate.rbf
menu=$test_root/menu.rbf
loader=$platform_root/sw/mister-de25-load

mkdir -p "$bin" "$overlay_root" "$state_dir" "$region"
printf operating >"$manager_state"
printf overlay >"$overlay_source"
printf candidate >"$candidate"
printf menu >"$menu"
: >"$watchdog"
: >"$watchdog_timeout"
printf '0\n' >"$watchdog_nowayout"

printf '#!/usr/bin/env bash\nexit 0\n' >"$bin/migration"
cat >"$bin/compatibility" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$COMPATIBILITY_LOG"
if [[ ${1:-} == --print-digest ]]; then
    shift
fi
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
else
    shasum -a 256 "$1" | awk '{print $1}'
fi
EOF
chmod +x "$bin/compatibility" "$bin/migration"
cat >"$bin/bridge" <<EOF
#!/usr/bin/env bash
if [[ \$1 == disable ]]; then
    printf applied >'$overlay_dir/status'
fi
EOF
cat >"$bin/modprobe" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >>'$modprobe_log'
exit 0
EOF
cat >"$bin/sync" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$bin/bridge" "$bin/modprobe" "$bin/sync"

run_loader() {
    rm -rf "$overlay_dir"
    PATH=$bin:$PATH \
    MISTER_DE25_FIRMWARE=$firmware \
    MISTER_DE25_FAT_ROOT=$test_root \
    MISTER_DE25_OVERLAY_SOURCE=$overlay_source \
    MISTER_DE25_CONFIGFS_ROOT=$configfs \
    MISTER_DE25_REGION_SYSFS=$region \
    MISTER_DE25_MANAGER_STATE=$manager_state \
    MISTER_DE25_BRIDGE_HELPER=$bin/bridge \
    MISTER_DE25_COMPATIBILITY_HELPER=$bin/compatibility \
    COMPATIBILITY_LOG=$compatibility_log \
    MISTER_DE25_MIGRATION_HELPER=$bin/migration \
    MISTER_DE25_WATCHDOG_HELPER=$platform_root/sw/mister-de25-watchdog-run \
    MISTER_DE25_WATCHDOG_DEVICE=$watchdog \
    MISTER_DE25_WATCHDOG_ALLOW_REGULAR=1 \
    MISTER_DE25_WATCHDOG_TIMEOUT_PATH=$watchdog_timeout \
    MISTER_DE25_WATCHDOG_NOWAYOUT_PATH=$watchdog_nowayout \
    MISTER_DE25_WATCHDOG_FAILURE_ACTION=return \
    MISTER_DE25_LOAD_STATE_DIR=$state_dir \
        "$loader" "$1"
}

run_loader "$candidate" >/dev/null
[[ $(wc -l <"$compatibility_log") -eq 1 ]]
cmp "$candidate" "$firmware"
[[ ! -e $state_dir/fpga-load.pending ]]
[[ $(od -An -tx1 -v "$watchdog" | tr -d ' \n') == 0056 ]]
printf '%s\n' stratix10_soc of-fpga-region >"$test_root/expected-modprobe.log"
cmp "$test_root/expected-modprobe.log" "$modprobe_log"

# Preload followed by Main asks for the same Menu twice. The second request
# must return successfully without touching the FPGA manager or watchdog.
run_loader "$candidate" >"$test_root/idempotent.out"
[[ $(wc -l <"$compatibility_log") -eq 2 ]]
grep -q 'FPGA already operates with candidate.rbf' "$test_root/idempotent.out"
[[ ! -e $overlay_dir ]]
[[ $(od -An -tx1 -v "$watchdog" | tr -d ' \n') == 0056 ]]
cmp "$test_root/expected-modprobe.log" "$modprobe_log"

# A later boot has a different boot ID but may find firmware and the cached
# Menu already hard-linked to the same inode. Reprogramming must not fail by
# attempting to move that inode onto itself.
IFS=$'\t' read -r cached_path cached_digest cached_boot \
    <"$state_dir/fpga-load.current"
printf '%s\t%s\told-boot\n' "$cached_path" "$cached_digest" \
    >"$state_dir/fpga-load.current"
run_loader "$candidate" >/dev/null
cmp "$candidate" "$firmware"
[[ $(wc -l <"$compatibility_log") -eq 3 ]]

# A watchdog-reset candidate is recorded, then the boot Menu is allowed to
# recover the fabric because it is a different image.
printf '%s\told-boot\n' "$candidate" >"$state_dir/fpga-load.pending"
run_loader "$menu" >/dev/null 2>"$test_root/recovery.err"
grep -q "Previous DE25-Nano FPGA load did not complete: $candidate" \
    "$test_root/recovery.err"
grep -q "^$candidate" "$state_dir/fpga-load.last-failed"
cmp "$menu" "$firmware"

# If Menu itself failed in the previous boot, skip it once so networking and
# JTAG remain available instead of creating an endless watchdog reboot loop.
printf '%s\told-boot\n' "$menu" >"$state_dir/fpga-load.pending"
if run_loader "$menu" >/dev/null 2>"$test_root/menu-loop.err"; then
    echo "FAIL: repeated failed Menu load was not blocked" >&2
    exit 1
fi
grep -q 'Skipping repeated failed Menu load' "$test_root/menu-loop.err"

echo "PASS: runtime loader records watchdog failures and restores Menu safely"
