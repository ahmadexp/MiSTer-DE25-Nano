#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/mister-de25-rbf-test.XXXXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

helper=$platform_root/sw/mister-de25-test-rbf
systemctl_mock=$test_root/systemctl
loader_mock=$test_root/loader
log=$test_root/actions.log
candidate=$test_root/candidate.rbf
rollback=$test_root/rollback.rbf
current_load=$test_root/fpga-load.current
marker=$test_root/selected-core
consumed_marker=$test_root/selected-core.consumed
content=$test_root/game.mgl
hash=078A3C543CF82A135C3914508B7426E499FBBB92A453C102F9D8F198BF3EFFF7

printf '<mistergamedescription/>\n' >"$content"

for rbf in "$candidate" "$rollback"; do
    printf 'rbf\n' >"$rbf"
    printf '%s\n' "$hash" >"$rbf.hps-io-hash"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$rbf" | awk '{print $1}' >"$rbf.sha256"
    else
        shasum -a 256 "$rbf" | awk '{print $1}' >"$rbf.sha256"
    fi
done

cat >"$systemctl_mock" <<EOF
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >>'$log'
case "\${FAIL_START:-}:\$1" in
    1:start) exit 1 ;;
esac
if [[ \$1 == start && -s '$marker' ]]; then
    cp '$marker' '$consumed_marker'
    rm -f '$marker'
fi
EOF
cat >"$loader_mock" <<EOF
#!/usr/bin/env bash
printf 'load %s\n' "\$1" >>'$log'
case "\${FAIL_CANDIDATE:-}:\$1" in
    1:'$candidate') exit 1 ;;
esac
loaded_path=\$(readlink -f "\$1" 2>/dev/null || printf '%s' "\$1")
loaded_digest=\$(tr -d '[:space:]' <"\$1.sha256" | tr '[:upper:]' '[:lower:]')
printf '%s\t%s\ttest-boot\n' "\$loaded_path" "\$loaded_digest" >'$current_load'
EOF
chmod +x "$systemctl_mock" "$loader_mock"

MISTER_DE25_SYSTEMCTL=$systemctl_mock \
MISTER_DE25_LOADER=$loader_mock \
MISTER_DE25_CURRENT_LOAD=$current_load \
MISTER_DE25_SELECTED_CORE_MARKER=$marker \
MISTER_DE25_TEST_SETTLE_SECONDS=0 \
    "$helper" "$candidate" "$rollback" "$content" >/dev/null
printf '%s\n%s\n' "$candidate" "$content" >"$test_root/expected-marker"
cmp "$test_root/expected-marker" "$consumed_marker"
grep -qx 'systemctl stop mister.service' "$log"
grep -qx "load $candidate" "$log"
grep -qx 'systemctl start mister.service' "$log"
grep -qx 'systemctl is-active --quiet mister.service' "$log"
if grep -qx "load $rollback" "$log"; then
    echo "FAIL: successful candidate test loaded rollback" >&2
    exit 1
fi

: >"$log"
if MISTER_DE25_SYSTEMCTL=$systemctl_mock \
   MISTER_DE25_LOADER=$loader_mock \
   MISTER_DE25_CURRENT_LOAD=$current_load \
   MISTER_DE25_SELECTED_CORE_MARKER=$marker \
   MISTER_DE25_TEST_SETTLE_SECONDS=0 \
       "$helper" "$candidate" "$rollback" "$test_root/missing.mgl" \
       >/dev/null 2>&1; then
    echo "FAIL: missing MGL content was accepted" >&2
    exit 1
fi
if [[ -s $log ]]; then
    echo "FAIL: invalid MGL content changed runtime state" >&2
    exit 1
fi

: >"$log"
if FAIL_CANDIDATE=1 \
   MISTER_DE25_SYSTEMCTL=$systemctl_mock \
   MISTER_DE25_LOADER=$loader_mock \
   MISTER_DE25_CURRENT_LOAD=$current_load \
   MISTER_DE25_SELECTED_CORE_MARKER=$marker \
   MISTER_DE25_TEST_SETTLE_SECONDS=0 \
       "$helper" "$candidate" "$rollback" >/dev/null 2>&1; then
    echo "FAIL: failed candidate test reported success" >&2
    exit 1
fi
expected=$test_root/expected.log
cat >"$expected" <<EOF
systemctl stop mister.service
load $candidate
load $rollback
systemctl start mister.service
EOF
cmp "$expected" "$log"

: >"$log"
if FAIL_START=1 \
   MISTER_DE25_SYSTEMCTL=$systemctl_mock \
   MISTER_DE25_LOADER=$loader_mock \
   MISTER_DE25_CURRENT_LOAD=$current_load \
   MISTER_DE25_SELECTED_CORE_MARKER=$marker \
   MISTER_DE25_TEST_SETTLE_SECONDS=0 \
       "$helper" "$candidate" "$rollback" >/dev/null 2>&1; then
    echo "FAIL: candidate Main start failure reported success" >&2
    exit 1
fi
cat >"$expected" <<EOF
systemctl stop mister.service
load $candidate
systemctl start mister.service
load $rollback
systemctl start mister.service
EOF
cmp "$expected" "$log"

echo "PASS: temporary FPGA test loads candidate and restores rollback on failure"
