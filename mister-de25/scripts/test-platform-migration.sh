#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/mister-de25-migration-test.XXXXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

source_hash=078A3C543CF82A135C3914508B7426E499FBBB92A453C102F9D8F198BF3EFFF7
target_hash=C600A54B0B4AC040B36C3C4024BC998E6DB61E5DF98DBE67BE99897E1F4B294E
fat=$test_root/fat
system=$test_root/system
boot_id=$test_root/boot-id
systemctl_log=$test_root/systemctl.log
systemctl_mock=$test_root/systemctl
target=$test_root/target-menu.rbf
pending=$system/var/lib/mister-de25/platform-migration/pending
boot_menu=$system/var/lib/mister-de25/boot/menu.rbf
helper=$platform_root/sw/mister-de25-platform-migration
checker=$platform_root/sw/mister-de25-check-rbf

write_digest() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}' >"$1.sha256"
    else
        shasum -a 256 "$1" | awk '{print $1}' >"$1.sha256"
    fi
}

mkdir -p "$fat" "$system/etc/mister-de25" "$(dirname "$boot_menu")"
printf 'boot-source\n' >"$boot_id"
printf 'old menu\n' >"$fat/menu.rbf"
write_digest "$fat/menu.rbf"
printf '%s\n' "$source_hash" >"$fat/menu.rbf.hps-io-hash"
cp "$fat/menu.rbf" "$boot_menu"
cp "$fat/menu.rbf.sha256" "$boot_menu.sha256"
cp "$fat/menu.rbf.hps-io-hash" "$boot_menu.hps-io-hash"
printf '%s\n' "$source_hash" >"$system/etc/mister-de25/hps-io-hash"
printf 'new menu\n' >"$target"
write_digest "$target"
printf '%s\n' "$target_hash" >"$target.hps-io-hash"

cat >"$systemctl_mock" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >>'$systemctl_log'
EOF
chmod +x "$systemctl_mock"

run_migration() {
    MISTER_DE25_FAT_ROOT=$fat \
    MISTER_DE25_SYS_ROOT=$system \
    MISTER_DE25_BOOT_ID_FILE=$boot_id \
    MISTER_DE25_SYSTEMCTL=$systemctl_mock \
        "$helper" "$@"
}

run_migration prepare "$target" >/dev/null
grep -qx 'state=prepared' "$pending"
grep -qx 'stop mister.service' "$systemctl_log"
if grep -Eq '^stop .*mister-de25-preload\.service' "$systemctl_log"; then
    echo "FAIL: migration stopped the non-stoppable watchdog keeper" >&2
    exit 1
fi
grep -qx 'old menu' "$system/var/lib/mister-de25/platform-migration/backup/menu.rbf"
grep -qx 'old menu' \
    "$system/var/lib/mister-de25/platform-migration/backup/boot-menu.rbf"
if MISTER_DE25_HPS_IO_HASH=$system/etc/mister-de25/hps-io-hash \
   MISTER_DE25_MIGRATION_PENDING=$pending \
   "$checker" "$fat/menu.rbf" >/dev/null 2>&1; then
    echo "FAIL: compatibility checker ignored a pending migration" >&2
    exit 1
fi
if run_migration finalize-boot >/dev/null 2>&1; then
    echo "FAIL: prepared migration finalized without a flash and reboot" >&2
    exit 1
fi
run_migration abort >/dev/null
[[ ! -e $pending ]]
grep -qx 'start mister-de25-preload.service' "$systemctl_log"
grep -qx 'start mister.service' "$systemctl_log"
grep -qx 'old menu' "$fat/menu.rbf"

: >"$systemctl_log"
run_migration prepare "$target" >/dev/null
if run_migration flashed --confirm WRONG >/dev/null 2>&1; then
    echo "FAIL: migration accepted an invalid flash confirmation" >&2
    exit 1
fi
run_migration flashed --confirm FLASH-VERIFIED >/dev/null
grep -qx 'state=flashed' "$pending"
grep -qx 'new menu' "$fat/menu.rbf"
grep -qx "$target_hash" "$fat/menu.rbf.hps-io-hash"
cmp "$target.sha256" "$fat/menu.rbf.sha256"
grep -qx "$target_hash" "$system/etc/mister-de25/hps-io-hash"
grep -qx 'new menu' "$boot_menu"
grep -qx "$target_hash" "$boot_menu.hps-io-hash"
cmp "$target.sha256" "$boot_menu.sha256"
if run_migration finalize-boot >/dev/null 2>&1; then
    echo "FAIL: flashed migration finalized in the pre-flash boot" >&2
    exit 1
fi
printf 'boot-target\n' >"$boot_id"
run_migration finalize-boot >/dev/null
[[ ! -e $pending ]]
MISTER_DE25_HPS_IO_HASH=$system/etc/mister-de25/hps-io-hash \
MISTER_DE25_MIGRATION_PENDING=$pending \
    "$checker" "$fat/menu.rbf" >/dev/null
MISTER_DE25_HPS_IO_HASH=$system/etc/mister-de25/hps-io-hash \
MISTER_DE25_MIGRATION_PENDING=$pending \
    "$checker" "$boot_menu" >/dev/null

# Exercise rollback after a verified target flash. The source JIC itself is
# restored by Quartus outside this helper; the explicit confirmation prevents
# source SD files from being restored against target QSPI by accident.
printf 'boot-source-2\n' >"$boot_id"
printf 'old menu\n' >"$fat/menu.rbf"
write_digest "$fat/menu.rbf"
printf '%s\n' "$source_hash" >"$fat/menu.rbf.hps-io-hash"
cp "$fat/menu.rbf" "$boot_menu"
cp "$fat/menu.rbf.sha256" "$boot_menu.sha256"
cp "$fat/menu.rbf.hps-io-hash" "$boot_menu.hps-io-hash"
printf '%s\n' "$source_hash" >"$system/etc/mister-de25/hps-io-hash"
run_migration prepare "$target" >/dev/null
run_migration flashed --confirm FLASH-VERIFIED >/dev/null
if run_migration restore-files --confirm WRONG >/dev/null 2>&1; then
    echo "FAIL: migration accepted an invalid rollback confirmation" >&2
    exit 1
fi
run_migration restore-files --confirm QSPI-ROLLED-BACK >/dev/null
[[ ! -e $pending ]]
grep -qx 'old menu' "$fat/menu.rbf"
grep -qx "$source_hash" "$fat/menu.rbf.hps-io-hash"
write_digest "$fat/menu.rbf"
cmp "$fat/menu.rbf.sha256" \
    "$system/var/lib/mister-de25/platform-migration/backup/menu.rbf.sha256"
grep -qx "$source_hash" "$system/etc/mister-de25/hps-io-hash"
grep -qx 'old menu' "$boot_menu"
grep -qx "$source_hash" "$boot_menu.hps-io-hash"

echo "PASS: platform migration interlock, reboot gate, abort, and rollback"
