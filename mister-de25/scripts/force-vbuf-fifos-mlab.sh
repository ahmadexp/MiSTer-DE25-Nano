#!/usr/bin/env bash
set -euo pipefail

ghrd_root=${1:?usage: force-vbuf-fifos-mlab.sh GHRD_ROOT}
vbuf_ip_root="$ghrd_root/ip/mister_hps/mister_hps_mister_vbuf_cdc"

mapfile -t fifo_sources < <(
    find "$vbuf_ip_root" -type f \
        -path '*/st_dc_fifo_*/synth/*_st_dc_fifo_*.v' -print
)

if [[ ${#fifo_sources[@]} -ne 1 ]]; then
    echo "Expected exactly one generated vbuf dual-clock FIFO source under $vbuf_ip_root" >&2
    exit 1
fi

fifo_source=${fifo_sources[0]}
if ! grep -q 'ramstyle="\(logic, \|MLAB, \)\?no_rw_check"' "$fifo_source"; then
    echo "Generated vbuf FIFO RAM style marker is missing: $fifo_source" >&2
    exit 1
fi

# The 128-bit vbuf bridge uses two very shallow FIFOs. AUTO mapping consumes
# nine M20Ks solely because the words are wide, even though both memories total
# only 5,496 bits. The generated FIFO does not use its generic `mem` declaration:
# its actual storage is an altera_syncram hard-coded to M20K. Force that instance
# into MLABs and leave the PC110 core's functional block memories unchanged.
sed -i \
    -e 's/ramstyle="logic, no_rw_check"/ramstyle="MLAB, no_rw_check"/' \
    -e 's/ramstyle="no_rw_check"/ramstyle="MLAB, no_rw_check"/' \
    -e 's/\.ram_block_type  ("M20K")/\.ram_block_type  ("MLAB")/' \
    "$fifo_source"

grep -q 'ramstyle="MLAB, no_rw_check"' "$fifo_source"
grep -q '\.ram_block_type  ("MLAB")' "$fifo_source"
