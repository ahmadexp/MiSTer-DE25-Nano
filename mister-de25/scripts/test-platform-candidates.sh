#!/usr/bin/env bash
set -euo pipefail

platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/mister-de25-candidates-test.XXXXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

workspace=$test_root/workspace
fixture=$workspace/mister-de25
mkdir -p "$fixture/scripts" "$fixture/artifacts"
cp "$platform_root/scripts/build-platform-candidates.sh" "$fixture/scripts/"
chmod +x "$fixture/scripts/build-platform-candidates.sh"

target_hash=FDCDD4C99876BAE3D17BB5B0AF4A4C7B7D55B2CE17D05C535A5BF69DD7DE930B
printf 'partition\n' >"$workspace/platform.qdb"
printf '%s\n' "$target_hash" >"$workspace/platform.hps-io-hash"

for build_script in build-nes.sh build-pc110.sh build-pcxt.sh build-ao486.sh; do
    cat >"$fixture/scripts/$build_script" <<'FAKE_BUILD'
#!/usr/bin/env bash
set -euo pipefail
output=${DE25_NES_OUTPUT_RBF:-${DE25_PC110_OUTPUT_RBF:-${DE25_PCXT_OUTPUT_RBF:-${DE25_AO486_OUTPUT_RBF:-}}}}
[[ -n $output ]]
mkdir -p "$(dirname "$output")"
printf 'candidate %s\n' "$(basename "$0")" >"$output"
cp "$DE25_EXPECTED_HPS_IO_HASH_FILE" "$output.hps-io-hash"
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$output" | awk '{print $1}' >"$output.sha256"
else
    shasum -a 256 "$output" | awk '{print $1}' >"$output.sha256"
fi
FAKE_BUILD
    chmod +x "$fixture/scripts/$build_script"
done

candidate_builder=$fixture/scripts/build-platform-candidates.sh
"$candidate_builder" \
    --hps-qdb "$workspace/platform.qdb" \
    --hps-hash "$workspace/platform.hps-io-hash" \
    --tag FIXTURE NES PC110 PCXT AO486 >/dev/null

manifest=$fixture/artifacts/candidates/FIXTURE/manifest.tsv
grep -q $'^NES\tartifacts/nes/NES_FIXTURE.rbf\t' "$manifest"
grep -q $'^PC110\tartifacts/pc110/IBM_PC110_FIXTURE.rbf\t' "$manifest"
grep -q $'^PCXT\tartifacts/pcxt/PCXT_FIXTURE.rbf\t' "$manifest"
grep -q $'^AO486\tartifacts/ao486/AO486_FIXTURE.rbf\t' "$manifest"
[[ $(grep -vc '^#' "$manifest") -eq 4 ]]

# Valid candidates must be reusable without invoking their build wrappers.
for build_script in build-nes.sh build-pc110.sh build-pcxt.sh build-ao486.sh; do
    printf '%s\n' '#!/usr/bin/env bash' 'exit 91' \
        >"$fixture/scripts/$build_script"
    chmod +x "$fixture/scripts/$build_script"
done
"$candidate_builder" \
    --hps-qdb "$workspace/platform.qdb" \
    --hps-hash "$workspace/platform.hps-io-hash" \
    --tag FIXTURE --reuse-existing NES PC110 PCXT AO486 >/dev/null

printf 'outside\n' >"$test_root/outside.qdb"
if "$candidate_builder" \
    --hps-qdb "$test_root/outside.qdb" \
    --hps-hash "$workspace/platform.hps-io-hash" \
    --tag REJECT NES >/dev/null 2>&1; then
    echo "FAIL: candidate build accepted a QDB outside the workspace" >&2
    exit 1
fi

echo "PASS: compatibility-locked candidate builds and reuse"
