#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: prepare-sd-image.sh BASE.img OUTPUT.img

Creates a new DE25-Nano MiSTer image without modifying BASE.img. The image
contains Menu, every core marked packaged in the locked build matrix, ARM64
Main, memory reservations, and the runtime FPGA-region loader.

Optional environment:
  MISTER_DE25_MENU_RBF           Alternate validated Menu RBF
  MISTER_DE25_PLATFORM_HASH_FILE Matching QSPI HPS I/O hash metadata
EOF
}

if [[ $# -ne 2 ]]; then
    usage >&2
    exit 2
fi

base_image=$1
output_image=$2
platform_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu_rbf=${MISTER_DE25_MENU_RBF:-$platform_root/artifacts/menu/menu.rbf}
platform_hash_file=${MISTER_DE25_PLATFORM_HASH_FILE:-$(dirname "$menu_rbf")/qspi.hps-io-hash}
core_categories=()
core_rbfs=()
while IFS=$'\t' read -r category artifact; do
    core_categories+=("$category")
    core_rbfs+=("$platform_root/$artifact")
done < <("$platform_root/scripts/list-packaged-artifacts.sh")
managed_core_categories=()
managed_core_rbfs=()
while IFS=$'\t' read -r category artifact; do
    managed_core_categories+=("$category")
    managed_core_rbfs+=("$platform_root/$artifact")
done < <("$platform_root/scripts/list-packaged-artifacts.sh" --managed)
main_binary=${MISTER_DE25_MAIN_BINARY:-$platform_root/artifacts/main/MiSTer}
kernel_image=${MISTER_DE25_KERNEL_IMAGE:-$platform_root/artifacts/kernel/Image}
kernel_dtb=${MISTER_DE25_KERNEL_DTB:-$platform_root/artifacts/kernel/socfpga_agilex5_de25_nano.dtb}
kernel_module=${MISTER_DE25_KERNEL_MODULE:-$platform_root/artifacts/kernel/stratix10-soc.ko}
kernel_release=${MISTER_DE25_KERNEL_RELEASE:-6.12.11-gd7d192a9ddd9}
kernel_modules=${MISTER_DE25_KERNEL_MODULES:-$platform_root/artifacts/kernel/modules-$kernel_release.tar.gz}
fat_offset=1048576

for tool in dtc fdtoverlay mcopy mdel mdir mmd docker curl tar; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required tool is missing: $tool" >&2
        exit 1
    fi
done

for input in "$base_image" "$menu_rbf" "${core_rbfs[@]}" \
    "$main_binary" "$main_binary.sha256" \
    "$kernel_image" "$kernel_image.sha256" \
    "$kernel_dtb" "$kernel_dtb.sha256" \
    "$kernel_module" "$kernel_module.sha256" \
    "$kernel_modules" "$kernel_modules.sha256" \
    "$platform_hash_file"; do
    if [[ ! -f $input ]]; then
        echo "Input file not found: $input" >&2
        exit 1
    fi
done

if [[ ! $kernel_release =~ ^[0-9A-Za-z._+-]+$ ]]; then
    echo "Invalid kernel release: $kernel_release" >&2
    exit 1
fi

verify_sha256_sidecar() {
    local input=$1 metadata=$2 expected actual
    expected=$(tr -d '[:space:]' <"$metadata" | tr '[:upper:]' '[:lower:]')
    if [[ ! $expected =~ ^[0-9a-f]{64}$ ]]; then
        echo "Invalid SHA-256 metadata: $metadata" >&2
        exit 1
    fi
    actual=$(sha256sum "$input" 2>/dev/null | awk '{print $1}' || \
        shasum -a 256 "$input" | awk '{print $1}')
    if [[ $actual != "$expected" ]]; then
        echo "SHA-256 metadata does not match: $input" >&2
        exit 1
    fi
}

verify_sha256_sidecar "$kernel_image" "$kernel_image.sha256"
verify_sha256_sidecar "$kernel_dtb" "$kernel_dtb.sha256"
verify_sha256_sidecar "$kernel_module" "$kernel_module.sha256"
verify_sha256_sidecar "$kernel_modules" "$kernel_modules.sha256"
if ! LC_ALL=C grep -aFq "vermagic=$kernel_release " "$kernel_module"; then
    echo "FPGA manager module does not match kernel release $kernel_release" >&2
    exit 1
fi
module_prefix=lib/modules/$kernel_release/
module_count=0
while IFS= read -r member; do
    case $member in
        "$module_prefix"*) ;;
        *)
            echo "Unsafe or mismatched kernel module archive member: $member" >&2
            exit 1
            ;;
    esac
    case $member in
        /*|../*|*/../*|*/..) 
            echo "Unsafe kernel module archive member: $member" >&2
            exit 1
            ;;
        *.ko) module_count=$((module_count + 1)) ;;
    esac
done < <(tar -tzf "$kernel_modules")
if [[ $module_count -ne 1334 ]]; then
    echo "Expected 1334 matching kernel modules, found $module_count" >&2
    exit 1
fi

main_digest=$(tr -d '[:space:]' <"$main_binary.sha256" | \
    tr '[:upper:]' '[:lower:]')
if [[ ! $main_digest =~ ^[0-9a-f]{64}$ ]]; then
    echo "Invalid ARM64 Main SHA-256 metadata: $main_binary.sha256" >&2
    exit 1
fi
main_actual_digest=$(sha256sum "$main_binary" 2>/dev/null | awk '{print $1}' || \
    shasum -a 256 "$main_binary" | awk '{print $1}')
if [[ $main_actual_digest != "$main_digest" ]]; then
    echo "ARM64 Main SHA-256 metadata does not match: $main_binary" >&2
    exit 1
fi
for rbf in "$menu_rbf" "${core_rbfs[@]}"; do
    if [[ ! -s $rbf.hps-io-hash ]]; then
        echo "HPS I/O compatibility metadata not found: $rbf.hps-io-hash" >&2
        exit 1
    fi
    if [[ ! -s $rbf.sha256 ]]; then
        echo "RBF SHA-256 metadata not found: $rbf.sha256" >&2
        exit 1
    fi
done

read_hps_hash() {
    local hash
    hash=$(tr -d '[:space:]' <"$1" | tr '[:lower:]' '[:upper:]')
    if [[ ! $hash =~ ^[0-9A-F]{64}$ ]]; then
        echo "Invalid HPS I/O compatibility metadata: $1" >&2
        exit 1
    fi
    printf '%s' "$hash"
}

platform_hash=$(read_hps_hash "$platform_hash_file")
for rbf in "$menu_rbf" "${core_rbfs[@]}"; do
    rbf_hash=$(read_hps_hash "$rbf.hps-io-hash")
    if [[ $rbf_hash != "$platform_hash" ]]; then
        echo "Refusing mixed HPS I/O hashes in the SD image:" >&2
        echo "  QSPI platform: $platform_hash" >&2
        echo "  $(basename "$rbf"): $rbf_hash" >&2
        exit 1
    fi
    rbf_digest=$(tr -d '[:space:]' <"$rbf.sha256" | \
        tr '[:upper:]' '[:lower:]')
    if [[ ! $rbf_digest =~ ^[0-9a-f]{64}$ ]]; then
        echo "Invalid RBF SHA-256 metadata: $rbf.sha256" >&2
        exit 1
    fi
    actual_digest=$(sha256sum "$rbf" 2>/dev/null | awk '{print $1}' || \
        shasum -a 256 "$rbf" | awk '{print $1}')
    if [[ $actual_digest != "$rbf_digest" ]]; then
        echo "RBF SHA-256 metadata does not match: $rbf" >&2
        exit 1
    fi
done

if [[ $base_image == "$output_image" ]]; then
    echo "OUTPUT.img must be different from BASE.img" >&2
    exit 1
fi
if [[ -e $output_image ]]; then
    echo "Refusing to overwrite existing output: $output_image" >&2
    exit 1
fi

# Docker Desktop and remote Docker contexts cannot necessarily bind macOS's
# private TMPDIR. Keep temporary payloads beside the image, whose parent is
# already required to be visible to the Docker engine.
output_parent=$(cd "$(dirname "$output_image")" && pwd)
work_dir=$(mktemp -d "$output_parent/.mister-de25-sd.XXXXXXXX")
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT
runtime_catalog=$work_dir/cores.tsv
"$platform_root/scripts/make-runtime-core-catalog.sh" "$runtime_catalog"

echo "Copying the Terasic base image..."
if cp --reflink=auto --sparse=always "$base_image" "$output_image" 2>/dev/null; then
    :
else
    cp "$base_image" "$output_image"
fi

image_spec="$output_image@@$fat_offset"
mtools_run() {
    # Homebrew mtools may ask for an interactive override when a Terasic FAT
    # image has a legacy geometry field that does not match the image size.
    # The filesystem is valid, so make image creation deterministic in CI.
    MTOOLS_SKIP_CHECK=1 "$@"
}

normalize_core_stem() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' _-'
}

prune_superseded_fat_family() {
    local category=$1 active_filename=$2 without_extension stem
    local normalized_stem candidate candidate_filename candidate_stem

    without_extension=${active_filename%.rbf}
    case $without_extension in
        *_20[0-9][0-9][0-9][0-9][0-9][0-9]*)
            stem=${without_extension%%_20[0-9][0-9][0-9][0-9][0-9][0-9]*}
            ;;
        *_v2)
            # A promoted V2 artifact supersedes the older dated release of
            # the same family, for example NES_v2 replacing
            # NES_20260814_FDCD. Compare the family name without the V2 tag.
            stem=${without_extension%_v2}
            ;;
        *) return ;;
    esac
    normalized_stem=$(normalize_core_stem "$stem")

    while IFS= read -r candidate; do
        [[ -n $candidate ]] || continue
        candidate_filename=${candidate##*/}
        [[ $candidate_filename != "$active_filename" ]] || continue
        case $candidate_filename in
            *_20[0-9][0-9][0-9][0-9][0-9][0-9]*) ;;
            *) continue ;;
        esac
        candidate_stem=${candidate_filename%%_20[0-9][0-9][0-9][0-9][0-9][0-9]*}
        [[ $(normalize_core_stem "$candidate_stem") == "$normalized_stem" ]] || \
            continue
        mtools_run mdel -i "$image_spec" "$candidate" 2>/dev/null || true
        mtools_run mdel -i "$image_spec" "$candidate.hps-io-hash" \
            2>/dev/null || true
        mtools_run mdel -i "$image_spec" "$candidate.sha256" \
            2>/dev/null || true
    done < <(mtools_run mdir -b -i "$image_spec" "::/$category/*.rbf" \
        2>/dev/null || true)
}

# A base image may have been produced by an earlier catalog revision. Remove
# only exact DE25-managed artifact paths, then repopulate the packaged set
# below. This prevents a demoted or incompatible core from surviving merely
# because it was already present in the base image.
for index in "${!managed_core_rbfs[@]}"; do
    rbf=${managed_core_rbfs[$index]}
    category=${managed_core_categories[$index]}
    filename=${rbf##*/}
    mtools_run mdel -i "$image_spec" "::/$category/$filename" \
        2>/dev/null || true
    mtools_run mdel -i "$image_spec" "::/$category/$filename.hps-io-hash" \
        2>/dev/null || true
    mtools_run mdel -i "$image_spec" "::/$category/$filename.sha256" \
        2>/dev/null || true
done

# The build matrix records only the active artifact name. Remove older dated
# versions of the same managed families as well, while leaving unrelated user
# cores untouched. Tagged releases such as YYYYMMDD_FDCD are handled by
# matching the family stem before the first date component.
for index in "${!core_rbfs[@]}"; do
    rbf=${core_rbfs[$index]}
    category=${core_categories[$index]}
    prune_superseded_fat_family "$category" "${rbf##*/}"
done

cp "$kernel_dtb" "$work_dir/base.dtb"

dtc -q -@ -I dts -O dtb \
    -o "$work_dir/mister-memory.dtbo" \
    "$platform_root/boot/mister-memory-overlay.dts"
fdtoverlay \
    -i "$work_dir/base.dtb" \
    -o "$work_dir/socfpga_agilex5_de25_nano.dtb" \
    "$work_dir/mister-memory.dtbo"

dtc -q -@ -I dts -O dtb \
    -o "$work_dir/fpga-load.dtbo" \
    "$platform_root/boot/mister-fpga-load-overlay.dts"
if command -v mkimage >/dev/null 2>&1; then
    mkimage \
        -A arm64 -O linux -T script -C none \
        -n "DE25-Nano MiSTer boot" \
        -d "$platform_root/boot/boot-mister.cmd" \
        "$work_dir/boot.scr.uimg"
else
    echo "Host mkimage is unavailable; creating the boot script in Ubuntu..."
    docker run --rm \
        -v "$platform_root/boot:/input:ro" \
        -v "$work_dir:/output" \
        ubuntu:22.04 bash -c '
            set -e
            export DEBIAN_FRONTEND=noninteractive
            apt-get -qq update
            apt-get -qq install -y u-boot-tools
            mkimage -A arm64 -O linux -T script -C none \
                -n "DE25-Nano MiSTer boot" \
                -d /input/boot-mister.cmd /output/boot.scr.uimg
        '
fi
grep -a -q 'mem=512M' "$work_dir/boot.scr.uimg"

mtools_run mcopy -o -i "$image_spec" \
    "$work_dir/socfpga_agilex5_de25_nano.dtb" \
    ::/socfpga_agilex5_de25_nano.dtb
mtools_run mcopy -o -i "$image_spec" "$kernel_image" ::/Image
mtools_run mcopy -o -i "$image_spec" "$work_dir/boot.scr.uimg" ::/boot.scr.uimg
mtools_run mcopy -o -i "$image_spec" "$menu_rbf" ::/menu.rbf
mtools_run mcopy -o -i "$image_spec" "$menu_rbf.hps-io-hash" ::/menu.rbf.hps-io-hash
mtools_run mcopy -o -i "$image_spec" "$menu_rbf.sha256" ::/menu.rbf.sha256
for index in "${!core_rbfs[@]}"; do
    rbf=${core_rbfs[$index]}
    category=${core_categories[$index]}
    filename=${rbf##*/}
    mtools_run mmd -i "$image_spec" "::/$category" 2>/dev/null || true
    mtools_run mcopy -o -i "$image_spec" "$rbf" "::/$category/$filename"
    mtools_run mcopy -o -i "$image_spec" "$rbf.hps-io-hash" \
        "::/$category/$filename.hps-io-hash"
    mtools_run mcopy -o -i "$image_spec" "$rbf.sha256" \
        "::/$category/$filename.sha256"
done
mtools_run mmd -i "$image_spec" ::/Scripts 2>/dev/null || true
mtools_run mcopy -o -i "$image_spec" "$platform_root/sw/update_de25.sh" ::/Scripts/update_de25.sh
mtools_run mcopy -o -i "$image_spec" "$main_binary" ::/MiSTer
mtools_run mcopy -o -i "$image_spec" \
    "$platform_root/upstream/Main_MiSTer/MiSTer.ini" ::/MiSTer.ini
mtools_run mdel -i "$image_spec" ::/pc110_bios.bin 2>/dev/null || true
mtools_run mdel -i "$image_spec" ::/pc110_font.bin 2>/dev/null || true

mkdir -p "$work_dir/rootfs/usr/lib/mister-de25"
mkdir -p "$work_dir/rootfs/usr/libexec"
mkdir -p "$work_dir/rootfs/usr/bin"
mkdir -p "$work_dir/rootfs/etc/systemd/system"
mkdir -p "$work_dir/rootfs/etc/mister-de25"
mkdir -p "$work_dir/rootfs/usr/lib/tmpfiles.d"
mkdir -p "$work_dir/runtime-debs"

download_runtime_deb() {
    local filename=$1
    local expected_sha256=$2
    local url=$3
    local destination=$work_dir/runtime-debs/$filename

    curl --fail --location --proto '=https' --tlsv1.2 \
        --retry 3 --output "$destination" "$url"
    local actual_sha256
    actual_sha256=$(sha256sum "$destination" 2>/dev/null | awk '{print $1}' || \
        shasum -a 256 "$destination" | awk '{print $1}')
    if [[ $actual_sha256 != "$expected_sha256" ]]; then
        echo "Runtime package SHA-256 mismatch: $filename" >&2
        exit 1
    fi
}

# Main links to Imlib2, while the GIF and ID3 libraries are loaded by Imlib2
# format modules. Vendor the exact Ubuntu 22.04 ARM64 packages into the image
# so first boot does not depend on network access.
download_runtime_deb \
    libimlib2_1.7.4-1build1_arm64.deb \
    1ea03f311ea441f959dd704e1c2a20744b9bf114f066cc958a5a58d63bd26633 \
    https://ports.ubuntu.com/pool/universe/i/imlib2/libimlib2_1.7.4-1build1_arm64.deb
download_runtime_deb \
    libgif7_5.1.9-2ubuntu0.3_arm64.deb \
    34ea6839a6c04bfca9574f90c7f9a50c273756cbbd3c0701ba595acc60bce7f9 \
    https://ports.ubuntu.com/pool/main/g/giflib/libgif7_5.1.9-2ubuntu0.3_arm64.deb
download_runtime_deb \
    libid3tag0_0.15.1b-14_arm64.deb \
    8aa715d9de10159b8e64127ad1431777f35376465f85ede04f6be14d8fe2a7d7 \
    https://ports.ubuntu.com/pool/universe/libi/libid3tag/libid3tag0_0.15.1b-14_arm64.deb
install -m 0644 "$work_dir/fpga-load.dtbo" \
    "$work_dir/rootfs/usr/lib/mister-de25/fpga-load.dtbo"
install -m 0755 "$platform_root/sw/mister-de25-load" \
    "$work_dir/rootfs/usr/libexec/mister-de25-load"
install -m 0755 "$platform_root/sw/mister-de25-watchdog-run" \
    "$work_dir/rootfs/usr/libexec/mister-de25-watchdog-run"
install -m 0755 "$platform_root/sw/mister-de25-bridge" \
    "$work_dir/rootfs/usr/libexec/mister-de25-bridge"
install -m 0755 "$platform_root/sw/mister-de25-check-rbf" \
    "$work_dir/rootfs/usr/libexec/mister-de25-check-rbf"
install -m 0755 "$platform_root/sw/mister-de25-prune-cores" \
    "$work_dir/rootfs/usr/libexec/mister-de25-prune-cores"
install -m 0755 "$platform_root/sw/mister-de25-platform-migration" \
    "$work_dir/rootfs/usr/libexec/mister-de25-platform-migration"
install -m 0755 "$platform_root/sw/mister-de25-headless-migrate" \
    "$work_dir/rootfs/usr/libexec/mister-de25-headless-migrate"
install -m 0755 "$platform_root/sw/mister-de25-test-rbf" \
    "$work_dir/rootfs/usr/libexec/mister-de25-test-rbf"
install -m 0755 "$platform_root/sw/mister-de25-select-core" \
    "$work_dir/rootfs/usr/libexec/mister-de25-select-core"
install -m 0755 "$platform_root/sw/mister-de25-process-core-request" \
    "$work_dir/rootfs/usr/libexec/mister-de25-process-core-request"
install -m 0755 "$platform_root/sw/mister-de25-core" \
    "$work_dir/rootfs/usr/bin/mister-de25-core"
install -m 0755 "$platform_root/sw/mister-de25-screenshot" \
    "$work_dir/rootfs/usr/bin/mister-de25-screenshot"
install -m 0755 "$platform_root/sw/mister-de25-migrate" \
    "$work_dir/rootfs/usr/bin/mister-de25-migrate"
install -m 0644 "$platform_hash_file" \
    "$work_dir/rootfs/etc/mister-de25/hps-io-hash"
install -m 0644 "$runtime_catalog" \
    "$work_dir/rootfs/etc/mister-de25/cores.tsv"
install -m 0644 "$platform_root/systemd/mister-de25-core-request.path" \
    "$work_dir/rootfs/etc/systemd/system/mister-de25-core-request.path"
install -m 0644 "$platform_root/systemd/mister-de25-core-request.service" \
    "$work_dir/rootfs/etc/systemd/system/mister-de25-core-request.service"
install -m 0644 "$platform_root/systemd/mister-de25-watchdog-keeper.service" \
    "$work_dir/rootfs/etc/systemd/system/mister-de25-watchdog-keeper.service"
install -m 0644 "$platform_root/systemd/mister-de25-platform-migration.path" \
    "$work_dir/rootfs/etc/systemd/system/mister-de25-platform-migration.path"
install -m 0644 "$platform_root/systemd/mister-de25-platform-migration-request.service" \
    "$work_dir/rootfs/etc/systemd/system/mister-de25-platform-migration-request.service"
install -m 0644 "$platform_root/systemd/mister-de25-tmpfiles.conf" \
    "$work_dir/rootfs/usr/lib/tmpfiles.d/mister-de25.conf"
install -m 0644 "$platform_root/systemd/mister-de25-preload.service" \
    "$work_dir/rootfs/etc/systemd/system/mister-de25-preload.service"
install -m 0644 "$platform_root/systemd/mister.service" \
    "$work_dir/rootfs/etc/systemd/system/mister.service"
install -m 0644 "$kernel_modules" \
    "$work_dir/rootfs/usr/lib/mister-de25/kernel-modules.tar.gz"

# Read the second MBR entry's little-endian start LBA at byte 470.
root_lba=$(od -An -tu4 -j 470 -N 4 "$output_image" | tr -d ' ')
if [[ ! $root_lba =~ ^[1-9][0-9]*$ ]]; then
    echo "Could not determine the root partition start LBA" >&2
    exit 1
fi
root_offset=$((root_lba * 512))
output_abs=$(cd "$(dirname "$output_image")" && pwd)/$(basename "$output_image")
payload_abs=$(cd "$work_dir/rootfs" && pwd)

docker run --rm --privileged -i \
    -v "$output_abs:/image.img" \
    -v "$payload_abs:/payload:ro" \
    -v "$work_dir/runtime-debs:/runtime-debs:ro" \
    ubuntu:22.04 bash -s -- "$root_offset" "$kernel_release" <<'ROOTFS_INSTALL'
set -euo pipefail
root_offset=$1
kernel_release=$2
mkdir -p /mnt/root
mount -o loop,offset="$root_offset" /image.img /mnt/root
cleanup() {
    sync
    umount /mnt/root
}
trap cleanup EXIT

install -d /mnt/root/media/fat
install -d /mnt/root/usr/lib/mister-de25
install -d /mnt/root/usr/libexec
install -d /mnt/root/usr/bin
install -d /mnt/root/usr/lib/tmpfiles.d
install -d /mnt/root/etc/systemd/system/multi-user.target.wants
install -d /mnt/root/etc/mister-de25
install -m 0644 /payload/usr/lib/mister-de25/fpga-load.dtbo \
    /mnt/root/usr/lib/mister-de25/fpga-load.dtbo
install -m 0755 /payload/usr/libexec/mister-de25-load \
    /mnt/root/usr/libexec/mister-de25-load
install -m 0755 /payload/usr/libexec/mister-de25-watchdog-run \
    /mnt/root/usr/libexec/mister-de25-watchdog-run
install -m 0755 /payload/usr/libexec/mister-de25-bridge \
    /mnt/root/usr/libexec/mister-de25-bridge
install -m 0755 /payload/usr/libexec/mister-de25-check-rbf \
    /mnt/root/usr/libexec/mister-de25-check-rbf
install -m 0755 /payload/usr/libexec/mister-de25-prune-cores \
    /mnt/root/usr/libexec/mister-de25-prune-cores
install -m 0755 /payload/usr/libexec/mister-de25-platform-migration \
    /mnt/root/usr/libexec/mister-de25-platform-migration
install -m 0755 /payload/usr/libexec/mister-de25-headless-migrate \
    /mnt/root/usr/libexec/mister-de25-headless-migrate
install -m 0755 /payload/usr/libexec/mister-de25-test-rbf \
    /mnt/root/usr/libexec/mister-de25-test-rbf
install -m 0755 /payload/usr/libexec/mister-de25-select-core \
    /mnt/root/usr/libexec/mister-de25-select-core
install -m 0755 /payload/usr/libexec/mister-de25-process-core-request \
    /mnt/root/usr/libexec/mister-de25-process-core-request
install -m 0755 /payload/usr/bin/mister-de25-core \
    /mnt/root/usr/bin/mister-de25-core
install -m 0755 /payload/usr/bin/mister-de25-screenshot \
    /mnt/root/usr/bin/mister-de25-screenshot
install -m 0755 /payload/usr/bin/mister-de25-migrate \
    /mnt/root/usr/bin/mister-de25-migrate
install -m 0644 /payload/etc/mister-de25/hps-io-hash \
    /mnt/root/etc/mister-de25/hps-io-hash
install -m 0644 /payload/etc/mister-de25/cores.tsv \
    /mnt/root/etc/mister-de25/cores.tsv
install -m 0644 /payload/etc/systemd/system/mister-de25-core-request.path \
    /mnt/root/etc/systemd/system/mister-de25-core-request.path
install -m 0644 /payload/etc/systemd/system/mister-de25-core-request.service \
    /mnt/root/etc/systemd/system/mister-de25-core-request.service
install -m 0644 /payload/etc/systemd/system/mister-de25-watchdog-keeper.service \
    /mnt/root/etc/systemd/system/mister-de25-watchdog-keeper.service
install -m 0644 /payload/etc/systemd/system/mister-de25-platform-migration.path \
    /mnt/root/etc/systemd/system/mister-de25-platform-migration.path
install -m 0644 /payload/etc/systemd/system/mister-de25-platform-migration-request.service \
    /mnt/root/etc/systemd/system/mister-de25-platform-migration-request.service
install -m 0644 /payload/usr/lib/tmpfiles.d/mister-de25.conf \
    /mnt/root/usr/lib/tmpfiles.d/mister-de25.conf
install -m 0644 /payload/etc/systemd/system/mister-de25-preload.service \
    /mnt/root/etc/systemd/system/mister-de25-preload.service
install -m 0644 /payload/etc/systemd/system/mister.service \
    /mnt/root/etc/systemd/system/mister.service
module_relative=kernel/drivers/fpga/stratix10-soc.ko
module_dir=/mnt/root/lib/modules/$kernel_release
rm -rf -- "$module_dir"
tar -xzf /payload/usr/lib/mister-de25/kernel-modules.tar.gz -C /mnt/root
if command -v depmod >/dev/null 2>&1; then
    depmod -b /mnt/root "$kernel_release"
fi
for package in /runtime-debs/*.deb; do
    dpkg-deb -x "$package" /mnt/root
done

if ! grep -qE '^[^#]+[[:space:]]+/media/fat[[:space:]]' /mnt/root/etc/fstab; then
    printf '%s\n' '/dev/mmcblk0p1 /media/fat vfat rw,sync,umask=0000,nofail,x-systemd.device-timeout=30 0 0' \
        >>/mnt/root/etc/fstab
fi

ln -sfn ../mister.service \
    /mnt/root/etc/systemd/system/multi-user.target.wants/mister.service
ln -sfn ../mister-de25-core-request.path \
    /mnt/root/etc/systemd/system/multi-user.target.wants/mister-de25-core-request.path
ln -sfn ../mister-de25-watchdog-keeper.service \
    /mnt/root/etc/systemd/system/multi-user.target.wants/mister-de25-watchdog-keeper.service
ln -sfn ../mister-de25-platform-migration.path \
    /mnt/root/etc/systemd/system/multi-user.target.wants/mister-de25-platform-migration.path

test -x /mnt/root/usr/libexec/mister-de25-load
test -x /mnt/root/usr/libexec/mister-de25-watchdog-run
test -x /mnt/root/usr/libexec/mister-de25-bridge
test -x /mnt/root/usr/libexec/mister-de25-check-rbf
test -x /mnt/root/usr/libexec/mister-de25-prune-cores
test -x /mnt/root/usr/libexec/mister-de25-platform-migration
test -x /mnt/root/usr/libexec/mister-de25-headless-migrate
test -x /mnt/root/usr/libexec/mister-de25-test-rbf
test -x /mnt/root/usr/libexec/mister-de25-select-core
test -x /mnt/root/usr/libexec/mister-de25-process-core-request
test -x /mnt/root/usr/bin/mister-de25-core
test -x /mnt/root/usr/bin/mister-de25-screenshot
test -x /mnt/root/usr/bin/mister-de25-migrate
test -s /mnt/root/etc/mister-de25/hps-io-hash
test -s /mnt/root/etc/mister-de25/cores.tsv
test -s /mnt/root/usr/lib/mister-de25/fpga-load.dtbo
test -s "$module_dir/$module_relative"
grep -qF "$module_relative:" "$module_dir/modules.dep"
test "$(find "$module_dir" -type f -name '*.ko' | wc -l)" -eq 1334
LC_ALL=C grep -aFq "vermagic=$kernel_release " "$module_dir/$module_relative"
test -e /mnt/root/usr/lib/aarch64-linux-gnu/libImlib2.so.1
test -L /mnt/root/etc/systemd/system/multi-user.target.wants/mister.service
test -L /mnt/root/etc/systemd/system/multi-user.target.wants/mister-de25-core-request.path
test -L /mnt/root/etc/systemd/system/multi-user.target.wants/mister-de25-watchdog-keeper.service
test -L /mnt/root/etc/systemd/system/multi-user.target.wants/mister-de25-platform-migration.path
grep -qE '^[^#]+[[:space:]]+/media/fat[[:space:]]' /mnt/root/etc/fstab
ROOTFS_INSTALL

mtools_run mcopy -n -i "$image_spec" ::/socfpga_agilex5_de25_nano.dtb "$work_dir/check.dtb"
mtools_run mcopy -n -i "$image_spec" ::/Image "$work_dir/check-Image"
cmp "$kernel_image" "$work_dir/check-Image"
mtools_run mcopy -n -i "$image_spec" ::/menu.rbf "$work_dir/check-menu.rbf"
cmp "$menu_rbf" "$work_dir/check-menu.rbf"
mtools_run mcopy -n -i "$image_spec" ::/menu.rbf.hps-io-hash "$work_dir/check-menu.rbf.hps-io-hash"
cmp "$menu_rbf.hps-io-hash" "$work_dir/check-menu.rbf.hps-io-hash"
mtools_run mcopy -n -i "$image_spec" ::/menu.rbf.sha256 "$work_dir/check-menu.rbf.sha256"
cmp "$menu_rbf.sha256" "$work_dir/check-menu.rbf.sha256"
for index in "${!core_rbfs[@]}"; do
    rbf=${core_rbfs[$index]}
    category=${core_categories[$index]}
    filename=${rbf##*/}
    check_rbf=$work_dir/check-core-$index.rbf
    mtools_run mcopy -n -i "$image_spec" "::/$category/$filename" "$check_rbf"
    cmp "$rbf" "$check_rbf"
    mtools_run mcopy -n -i "$image_spec" \
        "::/$category/$filename.hps-io-hash" "$check_rbf.hps-io-hash"
    cmp "$rbf.hps-io-hash" "$check_rbf.hps-io-hash"
    mtools_run mcopy -n -i "$image_spec" \
        "::/$category/$filename.sha256" "$check_rbf.sha256"
    cmp "$rbf.sha256" "$check_rbf.sha256"
done
for managed_index in "${!managed_core_rbfs[@]}"; do
    managed_rbf=${managed_core_rbfs[$managed_index]}
    managed_category=${managed_core_categories[$managed_index]}
    managed_filename=${managed_rbf##*/}
    is_packaged=false
    for packaged_index in "${!core_rbfs[@]}"; do
        if [[ ${core_categories[$packaged_index]} == "$managed_category" &&
              ${core_rbfs[$packaged_index]##*/} == "$managed_filename" ]]; then
            is_packaged=true
            break
        fi
    done
    if [[ $is_packaged == false ]] &&
       mtools_run mdir -i "$image_spec" \
           "::/$managed_category/$managed_filename" >/dev/null 2>&1; then
        echo "Non-packaged DE25 artifact survived in SD image: $managed_filename" >&2
        exit 1
    fi
done
for index in "${!core_rbfs[@]}"; do
    rbf=${core_rbfs[$index]}
    category=${core_categories[$index]}
    active_filename=${rbf##*/}
    active_without_extension=${active_filename%.rbf}
    case $active_without_extension in
        *_20[0-9][0-9][0-9][0-9][0-9][0-9]*)
            active_stem=${active_without_extension%%_20[0-9][0-9][0-9][0-9][0-9][0-9]*}
            ;;
        *_v2)
            active_stem=${active_without_extension%_v2}
            ;;
        *) continue ;;
    esac
    active_normalized_stem=$(normalize_core_stem "$active_stem")
    while IFS= read -r candidate; do
        [[ -n $candidate ]] || continue
        candidate_filename=${candidate##*/}
        [[ $candidate_filename != "$active_filename" ]] || continue
        case $candidate_filename in
            *_20[0-9][0-9][0-9][0-9][0-9][0-9]*) ;;
            *) continue ;;
        esac
        candidate_stem=${candidate_filename%%_20[0-9][0-9][0-9][0-9][0-9][0-9]*}
        if [[ $(normalize_core_stem "$candidate_stem") == \
              "$active_normalized_stem" ]]; then
            echo "Superseded managed DE25 artifact survived in SD image: $candidate_filename" >&2
            exit 1
        fi
    done < <(mtools_run mdir -b -i "$image_spec" "::/$category/*.rbf" \
        2>/dev/null || true)
done
mtools_run mcopy -n -i "$image_spec" ::/Scripts/update_de25.sh "$work_dir/check-updater.sh"
cmp "$platform_root/sw/update_de25.sh" "$work_dir/check-updater.sh"
mtools_run mcopy -n -i "$image_spec" ::/boot.scr.uimg "$work_dir/check-boot.scr.uimg"
cmp "$work_dir/boot.scr.uimg" "$work_dir/check-boot.scr.uimg"
grep -a -q 'mem=512M' "$work_dir/check-boot.scr.uimg"
dtc -q -I dtb -O dts -o "$work_dir/check.dts" "$work_dir/check.dtb"
grep -q 'reg = <0x00 0x80000000 0x00 0x40000000>' "$work_dir/check.dts"
grep -q 'mister_env@9ffff000' "$work_dir/check.dts"
grep -q 'mister_ddram@a0000000' "$work_dir/check.dts"
if grep -A4 'mister_ddram@a0000000' "$work_dir/check.dts" | grep -q 'no-map;'; then
    echo "MiSTer LPDDR reservation was incorrectly marked no-map" >&2
    exit 1
fi
[[ $(grep -c 'iommus = ' "$work_dir/check.dts") -eq 1 ]]
[[ $(grep -c 'dma-coherent;' "$work_dir/check.dts") -eq 1 ]]
grep -A8 'compatible = "intel,agilex5-svc"' "$work_dir/check.dts" | \
    grep -q 'iommus = '
if grep -q 'sdm-remapper' "$work_dir/check.dts"; then
    echo "Obsolete SDM remapper survived in the release device tree" >&2
    exit 1
fi

echo
echo "DE25-Nano MiSTer image ready: $output_image"
echo "Menu RBF SHA-256: $(sha256sum "$menu_rbf" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$menu_rbf" | awk '{print $1}')"
for rbf in "${core_rbfs[@]}"; do
    echo "${rbf##*/} SHA-256: $(sha256sum "$rbf" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$rbf" | awk '{print $1}')"
done
echo "Main SHA-256:     $(sha256sum "$main_binary" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$main_binary" | awk '{print $1}')"
echo "Kernel SHA-256:   $(sha256sum "$kernel_image" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$kernel_image" | awk '{print $1}')"
mtools_run mdir -i "$image_spec" ::
printf '%s\n' "${core_categories[@]}" | sort -u | while IFS= read -r category; do
    mtools_run mdir -i "$image_spec" "::/$category"
done
mtools_run mdir -i "$image_spec" ::/Scripts
