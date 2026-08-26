#!/bin/sh
set -eu

usage() {
    cat <<'EOF'
Usage: update_de25.sh DIRECTORY|URL

Install a DE25-Nano MiSTer update bundle. The bundle is fully staged and
SHA-256 verified before any installed file is changed. Existing files are
retained beside their replacements with a .previous suffix.

Environment:
  DE25_FAT_ROOT   MiSTer FAT root (default: /media/fat)
  DE25_SYS_ROOT   Linux system root (default: /)
EOF
}

if [ "$#" -ne 1 ]; then
    usage >&2
    exit 2
fi

source_root=${1%/}
fat_root=${DE25_FAT_ROOT:-/media/fat}
sys_root=${DE25_SYS_ROOT:-/}
stage_root=$(mktemp -d /tmp/mister-de25-update.XXXXXX)
prepared_list=$stage_root/prepared.tsv
compatibility_prepared_list=$stage_root/compatibility-prepared.tsv
regular_prepared_list=$stage_root/regular-prepared.tsv
installed_list=$stage_root/installed.tsv
rbf_list=$stage_root/rbf-destinations.txt
rbf_hash_list=$stage_root/rbf-hashes.tsv
rbf_digest_list=$stage_root/rbf-digests.tsv
destination_list=$stage_root/destinations.txt
manifest=$stage_root/manifest.tsv
item_index=0
install_started=0
committed=0

cleanup() {
    if [ "$install_started" -eq 1 ] && [ "$committed" -eq 0 ] && \
       [ -s "$installed_list" ]; then
        echo "Update failed, restoring the previous installation..." >&2
        tab=$(printf '\t')
        while IFS="$tab" read -r target existed; do
            if [ "$existed" -eq 1 ] && [ -e "$target.previous" ]; then
                cp -p "$target.previous" "$target"
            else
                rm -f "$target"
            fi
        done <"$installed_list"
    fi
    if [ -s "$prepared_list" ]; then
        tab=$(printf '\t')
        while IFS="$tab" read -r prepared target; do
            rm -f "$prepared"
        done <"$prepared_list"
    fi
    rm -rf "$stage_root"
}
trap cleanup EXIT HUP INT TERM

case "$source_root" in
    http://*|https://*)
        command -v curl >/dev/null 2>&1 || {
            echo "curl is required for network updates" >&2
            exit 1
        }
        fetch() {
            relative=$1
            destination=$2
            curl --fail --location --proto '=https' --tlsv1.2 \
                --retry 3 --output "$destination" \
                "$source_root/$relative"
        }
        ;;
    *)
        if [ ! -d "$source_root" ]; then
            echo "Update directory not found: $source_root" >&2
            exit 1
        fi
        fetch() {
            relative=$1
            destination=$2
            cp "$source_root/$relative" "$destination"
        }
        ;;
esac

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "No SHA-256 utility is installed" >&2
        exit 1
    fi
}

file_size() {
    if stat -c %s "$1" >/dev/null 2>&1; then
        stat -c %s "$1"
    else
        stat -f %z "$1"
    fi
}

safe_relative_path() {
    case "$1" in
        ''|/*|.|./*|*/./*|*/.|..|../*|*/../*|*/..|*//*|*.previous)
            return 1
            ;;
    esac
    return 0
}

# Refuse to traverse symlinks below either installation root. The updater runs
# as root on a real board, so following a pre-existing directory symlink could
# otherwise redirect a valid relative manifest destination outside the FAT or
# system tree. Existing file and backup symlinks are rejected for the same
# reason.
safe_install_path() {
    base=$1
    relative=$2
    if [ ! -d "$base" ] || [ -L "$base" ]; then
        return 1
    fi
    cursor=${base%/}
    [ -n "$cursor" ] || cursor=/
    remaining=$relative
    while [ -n "$remaining" ]; do
        component=${remaining%%/*}
        if [ "$remaining" = "$component" ]; then
            remaining=
        else
            remaining=${remaining#*/}
        fi
        if [ "$cursor" = / ]; then
            cursor=/$component
        else
            cursor=$cursor/$component
        fi
        if [ -L "$cursor" ]; then
            return 1
        fi
    done
    if [ -L "$cursor.previous" ]; then
        return 1
    fi
    return 0
}

read_hps_io_hash() {
    hash_path=$1
    if [ ! -s "$hash_path" ]; then
        echo "DE25-Nano HPS I/O compatibility metadata is missing: $hash_path" >&2
        exit 1
    fi
    normalized_hash=$(tr -d '[:space:]' <"$hash_path" | \
        tr '[:lower:]' '[:upper:]')
    case "$normalized_hash" in
        ''|*[!0-9A-F]*)
            echo "Invalid DE25-Nano HPS I/O hash in $hash_path" >&2
            exit 1
            ;;
    esac
    if [ "${#normalized_hash}" -ne 64 ]; then
        echo "Invalid DE25-Nano HPS I/O hash in $hash_path" >&2
        exit 1
    fi
    printf '%s\n' "$normalized_hash"
}

read_sha256() {
    digest_path=$1
    if [ ! -s "$digest_path" ]; then
        echo "DE25-Nano RBF SHA-256 metadata is missing: $digest_path" >&2
        exit 1
    fi
    normalized_digest=$(tr -d '[:space:]' <"$digest_path" | \
        tr '[:upper:]' '[:lower:]')
    case "$normalized_digest" in
        ''|*[!0-9a-f]*)
            echo "Invalid DE25-Nano RBF SHA-256 in $digest_path" >&2
            exit 1
            ;;
    esac
    if [ "${#normalized_digest}" -ne 64 ]; then
        echo "Invalid DE25-Nano RBF SHA-256 in $digest_path" >&2
        exit 1
    fi
    printf '%s\n' "$normalized_digest"
}

fetch manifest.tsv "$manifest"
printf '%s\n' "Staging and verifying DE25-Nano MiSTer update..."

tab=$(printf '\t')
while IFS="$tab" read -r expected_hash expected_size mode scope destination payload; do
    case "$expected_hash" in
        ''|'#'*) continue ;;
    esac

    safe_relative_path "$destination" || {
        echo "Unsafe update destination: $destination" >&2
        exit 1
    }
    safe_relative_path "$payload" || {
        echo "Unsafe update payload: $payload" >&2
        exit 1
    }
    if grep -Fqx "$scope/$destination" "$destination_list" 2>/dev/null; then
        echo "Duplicate update destination: $scope/$destination" >&2
        exit 1
    fi
    printf '%s\n' "$scope/$destination" >>"$destination_list"
    case "$scope" in
        fat)
            safe_install_path "$fat_root" "$destination" || {
                echo "Unsafe symlink in update destination: $scope/$destination" >&2
                exit 1
            }
            target=$fat_root/$destination
            ;;
        root)
            if [ "$sys_root" = / ] && [ "$(id -u)" -ne 0 ]; then
                echo "Root privileges are required for $destination" >&2
                exit 1
            fi
            safe_install_path "$sys_root" "$destination" || {
                echo "Unsafe symlink in update destination: $scope/$destination" >&2
                exit 1
            }
            target=${sys_root%/}/$destination
            ;;
        *)
            echo "Unknown update scope: $scope" >&2
            exit 1
            ;;
    esac
    case "$mode" in
        0644|0755) ;;
        *)
            echo "Unsupported file mode: $mode" >&2
            exit 1
            ;;
    esac

    staged=$stage_root/payload/$payload
    mkdir -p "$(dirname "$staged")"
    fetch "payload/$payload" "$staged"
    actual_hash=$(hash_file "$staged")
    actual_size=$(file_size "$staged")
    if [ "$actual_hash" != "$expected_hash" ]; then
        echo "SHA-256 mismatch for $payload" >&2
        exit 1
    fi
    if [ "$actual_size" != "$expected_size" ]; then
        echo "Size mismatch for $payload" >&2
        exit 1
    fi

    target_dir=$(dirname "$target")
    mkdir -p "$target_dir"
    item_index=$((item_index + 1))
    prepared=$target_dir/.de25-update.$$.$item_index.tmp
    cp "$staged" "$prepared"
    chmod "$mode" "$prepared"
    case "$scope/$destination" in
        fat/*.rbf.hps-io-hash)
            printf '%s\t%s\n' "$prepared" "$target" >>"$compatibility_prepared_list"
            printf '%s\t%s\n' "$destination" "$prepared" >>"$rbf_hash_list"
            ;;
        fat/*.rbf.sha256)
            printf '%s\t%s\n' "$prepared" "$target" >>"$compatibility_prepared_list"
            printf '%s\t%s\n' "$destination" "$prepared" >>"$rbf_digest_list"
            ;;
        fat/*.rbf)
            printf '%s\t%s\n' "$destination" "$prepared" >>"$rbf_list"
            printf '%s\t%s\n' "$prepared" "$target" >>"$regular_prepared_list"
            ;;
        *)
            printf '%s\t%s\n' "$prepared" "$target" >>"$regular_prepared_list"
            ;;
    esac
done <"$manifest"

# An ordinary update may replace phase-2 fabric images, but it must never
# replace the QSPI phase-1 compatibility record. Verify every staged RBF
# against the hash recorded only after successful QSPI programming, before
# changing any installed file.
if [ -s "$rbf_list" ]; then
    platform_hash_file=${sys_root%/}/etc/mister-de25/hps-io-hash
    platform_hash=$(read_hps_io_hash "$platform_hash_file")
    while IFS="$tab" read -r rbf_destination rbf_prepared; do
        expected_sidecar=$rbf_destination.hps-io-hash
        sidecar_prepared=$(awk -F '\t' -v wanted="$expected_sidecar" \
            '$1 == wanted { print $2; found = 1 } END { if (!found) exit 1 }' \
            "$rbf_hash_list") || {
                echo "RBF compatibility sidecar is absent from update: $expected_sidecar" >&2
                exit 1
            }
        runtime_hash=$(read_hps_io_hash "$sidecar_prepared")
        if [ "$runtime_hash" != "$platform_hash" ]; then
            echo "Refusing update with incompatible DE25-Nano FPGA image: $rbf_destination" >&2
            echo "  QSPI HPS I/O hash: $platform_hash" >&2
            echo "  RBF HPS I/O hash:  $runtime_hash" >&2
            exit 1
        fi
        expected_digest_sidecar=$rbf_destination.sha256
        digest_prepared=$(awk -F '\t' -v wanted="$expected_digest_sidecar" \
            '$1 == wanted { print $2; found = 1 } END { if (!found) exit 1 }' \
            "$rbf_digest_list") || {
                echo "RBF SHA-256 sidecar is absent from update: $expected_digest_sidecar" >&2
                exit 1
            }
        expected_digest=$(read_sha256 "$digest_prepared")
        actual_digest=$(hash_file "$rbf_prepared")
        if [ "$actual_digest" != "$expected_digest" ]; then
            echo "Refusing update with stale or mismatched RBF metadata: $rbf_destination" >&2
            echo "  Metadata SHA-256: $expected_digest" >&2
            echo "  Actual SHA-256:   $actual_digest" >&2
            exit 1
        fi
    done <"$rbf_list"
fi

# Install sidecars before their RBFs. If Main attempts a core switch during
# the short transaction, it will reject an old-RBF/new-sidecar mismatch rather
# than load an incompatible phase-2 image.
cat "$compatibility_prepared_list" "$regular_prepared_list" \
    2>/dev/null >"$prepared_list" || true

if [ ! -s "$prepared_list" ]; then
    echo "Update manifest contains no payloads" >&2
    exit 1
fi

printf '%s\n' "Installing verified payloads..."
install_started=1
while IFS="$tab" read -r prepared target; do
    if [ -L "$target" ] || [ -L "$target.previous" ]; then
        echo "Update destination became a symlink: $target" >&2
        exit 1
    fi
    if [ -e "$target" ]; then
        cp -p "$target" "$target.previous"
        existed=1
    else
        existed=0
    fi
    mv -f "$prepared" "$target"
    printf '%s\t%s\n' "$target" "$existed" >>"$installed_list"
    printf '  %s\n' "$target"
done <"$prepared_list"

sync
if [ "$sys_root" = / ] && [ "$(id -u)" -eq 0 ]; then
    systemd-tmpfiles --create mister-de25.conf
    systemctl daemon-reload
    systemctl enable --now \
        mister-de25-core-request.path \
        mister-de25-platform-migration.path
fi
committed=1
pruner=${sys_root%/}/usr/libexec/mister-de25-prune-cores
core_catalog=${sys_root%/}/etc/mister-de25/cores.tsv
if [ -x "$pruner" ] && [ -s "$core_catalog" ]; then
    if ! DE25_FAT_ROOT="$fat_root" DE25_CORE_CATALOG="$core_catalog" \
        "$pruner"; then
        echo "Warning: update succeeded, but old managed cores were not archived" >&2
    fi
fi
printf '%s\n' "DE25-Nano MiSTer update installed. Reboot to load the new Menu."
