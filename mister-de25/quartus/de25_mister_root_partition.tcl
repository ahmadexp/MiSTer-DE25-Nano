# SPDX-License-Identifier: GPL-3.0-or-later

# Experimental Quartus root-partition study for the DE25 MiSTer platform.
#
# This is not used by production builds. The supported architecture compiles
# the common source shell into a complete HPS-first RBF for every core. Tests
# showed that a Reserved Core boundary cannot legally route all required core
# clocks on this Agilex 5 package, while the same designs fit as full images.
# Keep the opt-in modes only for future Quartus/device research:
#   DE25_ROOT_SHELL_MODE=source  compile a base persona and export the root QDB
#   DE25_ROOT_SHELL_MODE=reuse   import that root QDB and fit the current persona
#
# The root partition retains HPS/LPDDR, board I/O, platform PLL, Main bridge,
# DDRAM adapter, OSD, HDMI, and audio. Only the fixed-interface
# core_partition instance is excluded from the root export.
set de25_root_shell_mode ""
if {[info exists ::env(DE25_ROOT_SHELL_MODE)]} {
    set de25_root_shell_mode $::env(DE25_ROOT_SHELL_MODE)
}

if {$de25_root_shell_mode ne ""} {
    set de25_root_shell_qdb \
        ../artifacts/shell/de25_mister_root_078a_final.qdb
    if {[info exists ::env(DE25_ROOT_SHELL_QDB)] &&
        $::env(DE25_ROOT_SHELL_QDB) ne ""} {
        set de25_root_shell_qdb $::env(DE25_ROOT_SHELL_QDB)
    }

    set_instance_assignment -name PARTITION core_partition \
        -to core_partition
    set_instance_assignment -name RESERVED_CORE ON \
        -to core_partition
    # Experimental reservation sized for the largest supported core, PC110:
    # 24,794 persona ALMs and 337 persona M20Ks. An upper band distributes
    # persona logic across both clock sectors, leaving a broad lower band for
    # the 9,500-ALM HPS/HDMI root. Narrow lower extensions reserve all eight
    # M20K columns without also excluding nearby root ALMs. This distribution
    # prevents the static root clocks from being compressed into one eastern
    # placement area. M20K_X116_Y39 is a static JTAG-debug FIFO in Terasic's
    # HPS system, so the upper band deliberately leaves that site to the root.
    # Give the persona a continuous routing region. Its placement region is
    # intentionally nonrectangular, but mirroring those disconnected boxes in
    # ROUTE_REGION prevents global clocks from reaching every reserved M20K
    # column. Routing may overlap the fixed root because route reservation is
    # disabled; only persona placement remains excluded from the root.
    set_instance_assignment -name REGION_NAME core_partition \
        -to core_partition
    set_instance_assignment -name PLACE_REGION \
        "X0 Y23 X114 Y51; X118 Y23 X121 Y51; X115 Y23 X117 Y38; X115 Y40 X117 Y51; X4 Y5 X6 Y22; X23 Y5 X25 Y22; X28 Y5 X30 Y22; X55 Y5 X57 Y22; X64 Y5 X66 Y22; X91 Y5 X93 Y22; X96 Y5 X98 Y22; X115 Y5 X117 Y22" \
        -to core_partition
    set_instance_assignment -name RESERVE_PLACE_REGION ON \
        -to core_partition
    set_instance_assignment -name CORE_ONLY_PLACE_REGION ON \
        -to core_partition
    set_instance_assignment -name ROUTE_REGION \
        "X0 Y5 X121 Y51" \
        -to core_partition
    set_instance_assignment -name RESERVE_ROUTE_REGION OFF \
        -to core_partition
    if {$de25_root_shell_mode eq "source"} {
        set_instance_assignment -name EXPORT_PARTITION_SNAPSHOT_FINAL \
            $de25_root_shell_qdb -to |
    } elseif {$de25_root_shell_mode eq "reuse"} {
        if {![file isfile $de25_root_shell_qdb]} {
            post_message -type error \
                "DE25 root shell is missing: $de25_root_shell_qdb"
            error "DE25 root shell is missing"
        }
        set_instance_assignment -name QDB_FILE_PARTITION \
            $de25_root_shell_qdb -to |
        set_instance_assignment -name ENTITY_REBINDING de25_mister_core \
            -to core_partition
    } else {
        post_message -type error \
            "Invalid DE25_ROOT_SHELL_MODE: $de25_root_shell_mode"
        error "DE25_ROOT_SHELL_MODE must be source or reuse"
    }
}
