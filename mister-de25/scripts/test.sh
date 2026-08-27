#!/usr/bin/env bash
set -euo pipefail

target_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output=${TMPDIR:-/tmp}/de25_mister_gp_bridge_tb.vvp

"$target_root/scripts/check-timing-summary.sh" \
    "$target_root/sim/timing-pass.summary"
if "$target_root/scripts/check-timing-summary.sh" \
    "$target_root/sim/timing-fail.summary"; then
    echo "FAIL: negative Quartus slack passed the build timing gate" >&2
    exit 1
fi
if "$target_root/scripts/check-timing-summary.sh" \
    "$target_root/sim/timing-pass.summary" \
    "$target_root/sim/timing-unconstrained.rpt"; then
    echo "FAIL: unconstrained Quartus report passed the build timing gate" >&2
    exit 1
fi
for build_script in \
    build-menu.sh build-inputtest.sh build-memtest.sh build-nes.sh \
    build-snes.sh build-minimig.sh build-tgfx16.sh build-apple1.sh \
    build-pc110.sh build-pcxt.sh; do
    grep -q 'check-timing-summary.sh' "$target_root/scripts/$build_script"
    grep -q 'prepare-ghrd-worktree.sh' "$target_root/scripts/$build_script"
    grep -q 'acquire-ghrd-build-lock.sh' "$target_root/scripts/$build_script"
    grep -q 'quartus_ipgenerate' "$target_root/scripts/$build_script"
    grep -Eq 'quartus_syn|quartus-syn-de25\.sh' \
        "$target_root/scripts/$build_script"
    grep -q 'quartus_fit' "$target_root/scripts/$build_script"
    grep -q 'quartus_asm' "$target_root/scripts/$build_script"
    grep -q 'quartus_sta' "$target_root/scripts/$build_script"
    if grep -q 'quartus_sh --flow compile' "$target_root/scripts/$build_script"; then
        echo "FAIL: monolithic Quartus flow can regenerate HPS IP in $build_script" >&2
        exit 1
    fi
done
bash -n "$target_root/scripts/quartus-syn-de25.sh"
grep -q 'exec quartus_syn' "$target_root/scripts/quartus-syn-de25.sh"
echo "PASS: every FPGA build rejects negative slack and unconstrained timing"

bash -n "$target_root/scripts/prepare-ghrd-worktree.sh"
bash -n "$target_root/scripts/acquire-ghrd-build-lock.sh"
bash -n "$target_root/scripts/build-menu-after-pid.sh"
bash -n "$target_root/scripts/build-platform-candidates.sh"
bash -n "$target_root/scripts/docker-workspace-path.sh"
mapped_workspace_path=$("$target_root/scripts/docker-workspace-path.sh" \
    "$target_root/.." "$target_root/artifacts/shell/platform.qdb")
[[ $mapped_workspace_path == \
    /work/PC110-Mister/mister-de25/artifacts/shell/platform.qdb ]]
mapped_workspace_path=$("$target_root/scripts/docker-workspace-path.sh" \
    "$target_root/.." /work/PC110-Mister/mister-de25/platform.qdb)
[[ $mapped_workspace_path == \
    /work/PC110-Mister/mister-de25/platform.qdb ]]
if "$target_root/scripts/docker-workspace-path.sh" \
    "$target_root/.." /tmp/outside-workspace.qdb >/dev/null 2>&1; then
    echo "FAIL: Docker build accepted a partition outside the workspace" >&2
    exit 1
fi
if "$target_root/scripts/docker-workspace-path.sh" \
    "$target_root/.." "$target_root/../outside-workspace.qdb" \
    >/dev/null 2>&1; then
    echo "FAIL: Docker build accepted a partition path containing dot segments" >&2
    exit 1
fi
grep -q 'terasic-ghrd-pristine' \
    "$target_root/scripts/prepare-ghrd-worktree.sh"
grep -q 'DE25_HPS_PARTITION_MODE=reuse' \
    "$target_root/scripts/build-platform-candidates.sh"
grep -q 'candidate_valid' "$target_root/scripts/build-platform-candidates.sh"
grep -q 'manifest.tsv' "$target_root/scripts/build-platform-candidates.sh"
grep -q 'source_system ../../de25-nano/vendor/terasic-ghrd/qsys_top.qsys' \
    "$target_root/ip/create_mister_hps.tcl"
grep -q 'remove_connection rst_in.out_reset/subsys_hps.\$bridge_reset' \
    "$target_root/ip/create_mister_hps.tcl"
grep -q 'mister_h2f_reset_fanout.out_reset' \
    "$target_root/ip/create_mister_hps.tcl"
grep -q '\.mister_h2f_bridge_reset_reset(h2f_reset)' \
    "$target_root/rtl/de25_mister_menu_top.sv"
echo "PASS: every FPGA build refreshes an immutable Terasic HPS baseline"

grep -q 'strcmp(cmd, "menu")' \
    "$target_root/upstream/Main_MiSTer/input.cpp"
grep -q 'strcmp(cmd, "de25_x86_reset")' \
    "$target_root/upstream/Main_MiSTer/input.cpp"
grep -q 'if (is_x86() || is_pcxt()) x86_init();' \
    "$target_root/upstream/Main_MiSTer/input.cpp"
grep -q 'strncmp(cmd, "de25_load_mgl ", 14)' \
    "$target_root/upstream/Main_MiSTer/input.cpp"
grep -q 'DE25 armed MGL in place' \
    "$target_root/upstream/Main_MiSTer/input.cpp"
grep -A35 'void HandleUI(void)' \
    "$target_root/upstream/Main_MiSTer/menu.cpp" | \
    grep -q '#ifndef MISTER_DE25'
grep -q 'menu_key_set(KEY_F12 | UPSTROKE)' \
    "$target_root/upstream/Main_MiSTer/input.cpp"
grep -q 'EVIOCGBIT(EV_REL' \
    "$target_root/upstream/Main_MiSTer/input.cpp"
grep -q 'ioctl(pool\[n\].fd, EVIOCGRAB, input_grab_value(n))' \
    "$target_root/upstream/Main_MiSTer/input.cpp"
grep -A10 'void user_io_osd_key_enable' \
    "$target_root/upstream/Main_MiSTer/user_io.cpp" | \
    grep -q 'MakeFile("/tmp/OSD_VISIBLE"'
echo "PASS: DE25 Main exposes a maintenance command for opening the OSD"

for qsf in "$target_root"/quartus/DE25_MISTER_*.qsf; do
    if [[ $qsf == *_V2.qsf ]]; then
        base_qsf=${qsf%_V2.qsf}.qsf
        if [[ -f $base_qsf ]]; then
            grep -q "^source $(basename "$base_qsf")$" "$qsf"
        else
            grep -q '^source de25_simple_persona_base.qsf$' "$qsf"
        fi
        grep -q '^source de25_platform_v2.qsf$' "$qsf"
        continue
    fi
    grep -q 'HPS_INITIALIZATION "HPS First"' "$qsf"
    grep -q 'SYSTEMVERILOG_FILE ../rtl/de25_mister_menu_top.sv' "$qsf"
    grep -q 'SYSTEMVERILOG_FILE ../rtl/de25_hps_warm_reset_handshake.sv' "$qsf"
    grep -q 'QSYS_FILE ../../de25-nano/vendor/terasic-ghrd/mister_hps.qsys' "$qsf"
    if grep -q 'mister_hps_mister_ddram_bridge.ip' "$qsf"; then
        echo "FAIL: complete image uses the incompatible external DDR bridge" >&2
        exit 1
    fi
done
"$target_root/scripts/test-platform-v2.sh"

grep -q 'quartus_sh --clean -c "$project" "$project"' \
    "$target_root/scripts/build-pc110.sh"
grep -q 'DE25_EXPECTED_HPS_IO_HASH_FILE' \
    "$target_root/scripts/build-pc110.sh"
# HPS/JTAG Qsys order is part of the signed HPS platform input. Match the
# proven PC110 ordering in Menu.
menu_qsf=$target_root/quartus/DE25_MISTER_MENU.qsf
menu_jtag_line=$(grep -n 'QSYS_FILE .*jtag_subsys/jtag_subsys.qsys' "$menu_qsf" | cut -d: -f1)
menu_hps_line=$(grep -n 'QSYS_FILE .*hps_subsys/hps_subsys.qsys' "$menu_qsf" | cut -d: -f1)
[[ $menu_jtag_line -lt $menu_hps_line ]]
grep -q 'set_global_assignment -name SEED 1' "$menu_qsf"
grep -q 'source de25_mister_menu_clocks.tcl' "$menu_qsf"
grep -q 'source de25_mister_hps_partition.tcl' "$menu_qsf"
grep -q 'DE25_VIDEO_SCALER=1' "$menu_qsf"
grep -q 'VHDL_FILE ../../sys/ascal.vhd' "$menu_qsf"
for project in \
    APPLE1 INPUTTEST MEMTEST MENU MINIMIG NES PC110 PCXT SMS SNES TGFX16; do
    grep -q 'source de25_mister_hps_partition.tcl' \
        "$target_root/quartus/DE25_MISTER_$project.qsf"
done
grep -q 'EXPORT_PARTITION_SNAPSHOT_FINAL' \
    "$target_root/quartus/de25_mister_hps_partition.tcl"
grep -q 'EXPORT_PARTITION_SNAPSHOT_SYNTHESIZED' \
    "$target_root/quartus/de25_mister_hps_partition.tcl"
grep -q 'DE25_HPS_PARTITION_EXPORT_SNAPSHOT must be final or synthesized' \
    "$target_root/quartus/de25_mister_hps_partition.tcl"
grep -q 'DE25_HPS_PARTITION_EXPORT_SNAPSHOT=' \
    "$target_root/scripts/build-menu.sh"
grep -q 'QDB_FILE_PARTITION' \
    "$target_root/quartus/de25_mister_hps_partition.tcl"
! grep -q 'set_instance_assignment -name ENTITY_REBINDING' \
    "$target_root/quartus/de25_mister_hps_partition.tcl"
menu_clock_constraints=$target_root/quartus/de25_mister_menu_clocks.tcl
grep -q 'IOPLL_X63_Y0_N91' "$menu_clock_constraints"
grep -q 'CLOCK_SPINE 9' "$menu_clock_constraints"
grep -q 'CLOCK_SPINE 30' "$menu_clock_constraints"
echo "PASS: every persona compiles the common board shell into a complete image"
grep -q 'artifacts/menu/DE25_MISTER_MENU_HPS_FIRST"' \
    "$target_root/scripts/build-menu.sh"
grep -q -- '-o hps=1' "$target_root/scripts/build-menu.sh"
grep -q -- '-o device=MT25QU128' "$target_root/scripts/build-menu.sh"
grep -q -- '-o flash_loader=A5EB013BB23B' "$target_root/scripts/build-menu.sh"
grep -q 'DE25_HPS_RESET_RECOVERY' "$target_root/scripts/build-menu.sh"
grep -q 'DE25_HPS_RESET_V1_REPRO' "$target_root/scripts/build-menu.sh"
grep -q 'DE25_HPS_RESET_V1_RECOVERY' "$target_root/scripts/build-menu.sh"
grep -q 'DE25_SKIP_QUARTUS_CLEAN' "$target_root/scripts/build-menu.sh"
grep -q 'DE25_INCREMENTAL_RECOMPILE' "$target_root/scripts/build-menu.sh"
for build_script in \
    build-menu.sh build-inputtest.sh build-memtest.sh build-nes.sh build-snes.sh \
    build-minimig.sh build-tgfx16.sh build-apple1.sh build-pc110.sh \
    build-pcxt.sh build-sms.sh; do
    grep -q 'make-hps-first-rbf.sh' "$target_root/scripts/$build_script"
    grep -q 'quartus_sh --clean' "$target_root/scripts/$build_script"
    grep -q 'DE25_EXPECTED_HPS_IO_HASH_FILE' \
        "$target_root/scripts/$build_script"
    grep -q 'DE25_HPS_PARTITION_MODE' "$target_root/scripts/$build_script"
    grep -q 'DE25_HPS_PARTITION_QDB' "$target_root/scripts/$build_script"
    grep -q 'docker-workspace-path.sh' "$target_root/scripts/$build_script"
    grep -q 'DE25_HPS_RESET_V1_REPRO' \
        "$target_root/scripts/$build_script"
done
if grep -q '^export DE25_HPS_RESET_V1_REPRO=1$' \
    "$target_root/scripts/build-platform-candidates.sh" \
    "$target_root/scripts/rebuild-platform-release.sh"; then
    echo "FAIL: production catalog builds enable the legacy reset handshake" >&2
    exit 1
fi
echo "PASS: production catalog builds use the safe HPS reset handshake"
grep -q 'cores=(INPUTTEST MEMTEST NES SNES MINIMIG TGFX16 PC110 PCXT AO486 APPLE1 SMS)' \
    "$target_root/scripts/build-platform-candidates.sh"
for build_output in \
    build-inputtest.sh:DE25_INPUTTEST_OUTPUT_RBF \
    build-memtest.sh:DE25_MEMTEST_OUTPUT_RBF \
    build-nes.sh:DE25_NES_OUTPUT_RBF \
    build-snes.sh:DE25_SNES_OUTPUT_RBF \
    build-minimig.sh:DE25_MINIMIG_OUTPUT_RBF \
    build-tgfx16.sh:DE25_TGFX16_OUTPUT_RBF \
    build-apple1.sh:DE25_APPLE1_OUTPUT_RBF \
    build-sms.sh:DE25_SMS_OUTPUT_RBF \
    build-pc110.sh:DE25_PC110_OUTPUT_RBF \
    build-pcxt.sh:DE25_PCXT_OUTPUT_RBF \
    build-ao486.sh:DE25_AO486_OUTPUT_RBF; do
    build_script=${build_output%%:*}
    output_variable=${build_output#*:}
    grep -q "$output_variable" "$target_root/scripts/$build_script"
done
bash -n "$target_root/scripts/make-hps-first-rbf.sh"
grep -q 'Generated runtime RBF is incompatible with the DE25 boot platform' \
    "$target_root/scripts/make-hps-first-rbf.sh"
grep -q 'legacy_jtag_sof=.*\.jtag\.sof' \
    "$target_root/scripts/make-hps-first-rbf.sh"
if grep -q 'quartus_pfg -c "$input_sof" "$legacy_jtag_sof"' \
    "$target_root/scripts/make-hps-first-rbf.sh"; then
    echo "FAIL: HPS-first builder still creates an invalid JTAG SOF" >&2
    exit 1
fi
grep -q 'rm -f .*"$legacy_jtag_sof"' \
    "$target_root/scripts/make-hps-first-rbf.sh"
grep -q -- '-o "hps_path=$hps_bootloader"' \
    "$target_root/scripts/make-hps-first-rbf.sh"
grep -q -- '-o hps=1' \
    "$target_root/scripts/make-hps-first-rbf.sh"
bash -n "$target_root/scripts/program-hps-first-jtag.sh"
grep -q 'packet_send_command.*0x00000047' \
    "$target_root/scripts/reboot-hps-sdm.tcl"
grep -q 'llength.*config_paths.*== 0' \
    "$target_root/scripts/reboot-hps-sdm.tcl"
grep -q 'refresh_connections' \
    "$target_root/scripts/reboot-hps-sdm.tcl"
grep -q 'quartus_pgm -m jtag -o "p;.*@$device_index"' \
    "$target_root/scripts/program-hps-first-jtag.sh"
echo "PASS: every MiSTer image clean-builds and guards its HPS-first platform"

output=${TMPDIR:-/tmp}/de25_mister_reset_control_tb.vvp
iverilog -g2012 -Wall \
    -s de25_hps_warm_reset_handshake_tb \
    -o "$output" \
    "$target_root/rtl/de25_hps_warm_reset_handshake.sv" \
    "$target_root/sim/de25_hps_warm_reset_handshake_tb.sv"
vvp "$output"

iverilog -g2012 -Wall \
    -s de25_mister_reset_control_tb \
    -o "$output" \
    "$target_root/rtl/de25_mister_reset_control.sv" \
    "$target_root/sim/de25_mister_reset_control_tb.sv"
vvp "$output"

grep -q '\.fabric_reset_request(core_domain_reset)' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -A1 -q 'qsys_reset_n = ~ninit_done & KEY\[0\] & platform_locked &' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'hps_warm_reset_pending | h2f_reset' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'wire qsys_reset_n = ~ninit_done & KEY\[0\] & platform_locked &' \
    "$target_root/rtl/de25_mister_menu_top.sv"
if grep -A1 'wire qsys_reset_n = ~ninit_done & KEY\[0\] & platform_locked &' \
    "$target_root/rtl/de25_mister_menu_top.sv" | grep -q '~h2f_reset'; then
    echo "HPS bridge reset must not feed the global Qsys reset" >&2
    exit 1
fi
grep -q 'hps_warm_reset_pending' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'emu core' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q '\.mister_ddram_clk_clk(ddram_domain_clk)' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'add_instance mister_vbuf_bridge altera_avalon_mm_bridge' \
    "$target_root/ip/create_mister_hps.tcl"
grep -q 'mister_vbuf_bridge.m0/subsys_hps.f2sdram_adapter_axi4_sub' \
    "$target_root/ip/create_mister_hps.tcl"
grep -A3 'add_instance mister_vbuf_bridge' \
    "$target_root/ip/create_mister_hps.tcl" | \
    grep -q 'DATA_WIDTH 128'
grep -q 'set_instance_parameter_value mister_vbuf_bridge MAX_BURST_SIZE 16' \
    "$target_root/ip/create_mister_hps.tcl"
grep -q 'set_instance_parameter_value mister_vbuf_bridge MAX_PENDING_RESPONSES 2' \
    "$target_root/ip/create_mister_hps.tcl"
grep -q 'set_instance_parameter_value mister_vbuf_bridge PIPELINE_RESPONSE 1' \
    "$target_root/ip/create_mister_hps.tcl"
if grep -q 'force-vbuf-fifos-mlab.sh.*ghrd_root' \
    "$target_root/scripts/build-pc110.sh"; then
    echo "PC110 must not rewrite a removed video response FIFO" >&2
    exit 1
fi
if grep -q '\.mister_vbuf_clk_clk\|\.mister_vbuf_reset_reset' \
    "$target_root/rtl/de25_mister_menu_top.sv"; then
    echo "The synchronous video bridge must use the existing HPS clock" >&2
    exit 1
fi
grep -q 'mister_hps_mister_vbuf_bridge.ip' \
    "$target_root/quartus/DE25_MISTER_PC110.qsf"
if grep -q 'mister_hps_mister_vbuf_cdc.ip' \
    "$target_root/quartus/DE25_MISTER_PC110.qsf"; then
    echo "PC110 project must not retain the removed video FIFO IP" >&2
    exit 1
fi
grep -A4 'de25_mister_ddram #(' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q ') vbuf_bridge'
echo "PASS: complete images keep the core clock crossing inside the shared HPS subsystem"

iverilog -g2012 -Wall \
    -s de25_mister_gp_bridge_tb \
    -o "$output" \
    "$target_root/rtl/de25_mister_gp_bridge.sv" \
    "$target_root/sim/de25_mister_gp_bridge_tb.sv"

vvp "$output"
grep -q 'osd_status(shell_osd_status)' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'hps_gp_in\[27\].*OSD compositor status' \
    "$target_root/sim/de25_mister_gp_bridge_tb.sv"
grep -q 'MakeFile("/tmp/HW_OSD_VISIBLE"' \
    "$target_root/upstream/Main_MiSTer/input.cpp"
grep -q 'execl(appname, appname, path, xml, NULL)' \
    "$target_root/patches/Main_MiSTer/0011-keep-de25-core-switch-under-systemd.patch"
grep -q 'mister-de25-load /media/fat/menu.rbf' \
    "$target_root/patches/Main_MiSTer/0012-recover-menu-before-de25-mmio.patch"
grep -q 'de25_menu_is_preloaded' \
    "$target_root/upstream/Main_MiSTer/main.cpp"
grep -q 'fpga-load.current' \
    "$target_root/patches/Main_MiSTer/0035-trust-verified-de25-menu-preload.patch"
grep -q 'chmod(CMD_FIFO, 0666)' \
    "$target_root/patches/Main_MiSTer/0013-allow-de25-remote-command-writes.patch"
grep -q '/run/mister-de25-selected-core' \
    "$target_root/patches/Main_MiSTer/0014-preserve-one-guarded-core-start.patch"
grep -q 'asm__ volatile("dsb sy"' \
    "$target_root/upstream/Main_MiSTer/fpga_io.cpp"
grep -q 'Complete DE25 MMIO transactions' \
    "$target_root/patches/Main_MiSTer/0015-complete-de25-mmio-transactions.patch"
grep -q 'HPS frame buffer is unavailable in this shell' \
    "$target_root/upstream/Main_MiSTer/video.cpp"
grep -q 'Disable unsupported DE25 HPS frame buffer' \
    "$target_root/patches/Main_MiSTer/0016-disable-de25-hps-framebuffer.patch"
grep -q 'disabling unsupported DDR save-state buffer' \
    "$target_root/upstream/Main_MiSTer/user_io.cpp"
grep -q 'Disable unavailable DE25 DDR save states' \
    "$target_root/patches/Main_MiSTer/0017-disable-de25-ddr-savestates.patch"
grep -q 'selected_xml' \
    "$target_root/upstream/Main_MiSTer/main.cpp"
grep -q 'Preserve guarded content on one-shot core start' \
    "$target_root/patches/Main_MiSTer/0019-preserve-guarded-content-start.patch"
grep -q 'DE25 arming content descriptor' \
    "$target_root/upstream/Main_MiSTer/user_io.cpp"
grep -q 'stable copy made at function entry' \
    "$target_root/patches/Main_MiSTer/0020-use-stable-guarded-content-path.patch"
grep -q 'Arm guarded MGL before peripheral initialization' \
    "$target_root/patches/Main_MiSTer/0021-arm-guarded-mgl-before-core-init.patch"
grep -q 'DE25 Main loop: entering user_io_poll' \
    "$target_root/upstream/Main_MiSTer/main.cpp"
grep -q 'DE25 MGL:' \
    "$target_root/upstream/Main_MiSTer/menu.cpp"
grep -q 'Trace guarded MGL initialization and transitions' \
    "$target_root/patches/Main_MiSTer/0022-trace-guarded-mgl-runtime.patch"
grep -q 'fixed fabric video active' \
    "$target_root/upstream/Main_MiSTer/user_io.cpp"
grep -q 'Use the fixed Agilex fabric video pipeline' \
    "$target_root/patches/Main_MiSTer/0023-use-fixed-fabric-video-pipeline.patch"
echo "PASS: FPGA OSD status is remotely observable on DE25"

output=${TMPDIR:-/tmp}/de25_mister_osd_bridge_tb.vvp
iverilog -g2012 -Wall \
    -s de25_mister_osd_bridge_tb \
    -o "$output" \
    "$target_root/rtl/de25_mister_gp_bridge.sv" \
    "$target_root/upstream/cores/Menu/sys/osd.v" \
    "$target_root/sim/de25_mister_osd_bridge_tb.sv"
vvp "$output"

"$target_root/scripts/test-tgfx16-memory.sh"
tgfx16_latest_patch=$(find "$target_root/patches/TurboGrafx16" -name '*.patch' \
    -type f | sort | tail -1)
git -C "$target_root/upstream/cores/TurboGrafx16" apply --reverse --check \
    --ignore-whitespace "$tgfx16_latest_patch"
echo "PASS: TurboGrafx16 packed Agilex RAM mapping and portability patch"

memtest_source="$target_root/upstream/cores/MemTest/memtest.sv"
memtest_latest_patch=$(find "$target_root/patches/MemTest" -name '*.patch' \
    -type f | sort | tail -1)
git -C "$target_root/upstream/cores/MemTest" apply --reverse --check \
    --ignore-whitespace "$memtest_latest_patch"
grep -q 'ASYNC_REG = "TRUE".*ram_reconfig_sync' "$memtest_source"
grep -q 'ASYNC_REG = "TRUE".*ram_reset_sync' "$memtest_source"
grep -q 'if(ram_reconfig_sync\[1\].*timeout < 1000000' "$memtest_source"
grep -q 'if(ram_reset_sync\[1\]).*timeout <= 100000000' "$memtest_source"
echo "PASS: MemTest reset request is synchronized into the variable PLL domain"

grep -q 'curr_state <= RESET' \
    "$target_root/upstream/cores/MemTest/rtl/tester.v"
grep -q 'if(!rst_n)' "$target_root/upstream/cores/MemTest/rtl/sdram.v"
grep -q 'state <= 0' "$target_root/upstream/cores/MemTest/rtl/sdram.v"
echo "PASS: MemTest FSMs have explicit Agilex-safe reset states"

grep -q 'always @ (posedge clk_capture)' \
    "$target_root/upstream/cores/MemTest/rtl/sdram.v"
grep -q '\.clk_capture(sdram_capture_clk)' "$memtest_source"
echo "PASS: MemTest captures SDRAM reads with the forwarded clock"

grep -q 'recfg && de25_ram_quiesced' "$memtest_source"
grep -q 'if(de25_control_reset)' "$memtest_source"
grep -q 'assign SDRAM_CKE = ram_active' "$memtest_source"
grep -q 'de25_sdram_dq_oe = ram_active && sdram_dq_oe' "$memtest_source"
grep -q 'assign DRAM_DQ = core_sdram_dq_oe' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q '^module de25_mister_top (' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'assign DRAM_CS_n\[0\] =  core_sdram_ncs' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'assign DRAM_CS_n\[1\] = ~core_sdram_ncs' \
    "$target_root/rtl/de25_mister_menu_top.sv"
echo "PASS: SDRAM is quiesced through CKE and rank selects retain I/O timing"
grep -q 'warm_reset_handshake|acknowledge_delay\[\*\]' \
    "$target_root/quartus/DE25_MISTER_MINIMIG.sdc"
grep -q 'set_false_path -from \$de25_minimig_platform_reset_gate' \
    "$target_root/quartus/DE25_MISTER_MINIMIG.sdc"
echo "PASS: Minimig excludes only the asynchronous platform CKE safety gate"

for wrapper in de25_nes_pll.sv de25_snes_pll.sv de25_minimig_pll.sv \
    de25_memtest_pll.sv de25_sms_pll.sv; do
    grep -q 'control_reset_pipe' "$target_root/rtl/$wrapper"
    grep -q '\.reset(control_reset)' "$target_root/rtl/$wrapper"
    grep -q '\.s0_axil_rst_n_reset_n(~control_reset)' \
        "$target_root/rtl/$wrapper"
done
grep -q 'logic \[7:0\] pll_por = 8.hFF' \
    "$target_root/rtl/de25_nes_pll.sv"
grep -q '\.reset_reset(pll_por\[7\])' \
    "$target_root/rtl/de25_nes_pll.sv"
grep -q '\.reset_reset(reset)' "$target_root/rtl/de25_memtest_pll.sv"
grep -q '\.reset_reset(1.b0)' "$target_root/rtl/de25_snes_pll.sv"
grep -q '\.reset_reset(1.b0)' "$target_root/rtl/de25_minimig_pll.sv"
echo "PASS: variable PLL control resets release synchronously at 50 MHz"

output=${TMPDIR:-/tmp}/de25_sdram_quiesce_tb.vvp

iverilog -g2012 -Wall \
    -s de25_sdram_quiesce_tb \
    -o "$output" \
    "$target_root/rtl/de25_sdram_quiesce.sv" \
    "$target_root/sim/de25_sdram_quiesce_tb.sv"

vvp "$output"

sms_profiles_tmp=$(mktemp)
python3 "$target_root/scripts/generate-sms-pll-profiles.py" \
    "$target_root/sim/sms-pll-profiles.log" "$sms_profiles_tmp"
cmp "$sms_profiles_tmp" "$target_root/rtl/de25_sms_pll_profiles.sv"
rm -f "$sms_profiles_tmp"
grep -q 'C_COUNTERS(3)' "$target_root/rtl/de25_sms_pll.sv"

output=${TMPDIR:-/tmp}/de25_sms_sdram_tb.vvp
iverilog -g2012 -Wall -DDE25_AGILEX_PLL_RECONFIG \
    -s sms_sdram_tb \
    -o "$output" \
    "$target_root/upstream/cores/SMS/rtl/sdram.sv" \
    "$target_root/sim/sms_sdram_tb.sv"
vvp "$output"

sms_latest_patch=$(find "$target_root/patches/SMS" -name '*.patch' \
    -type f | sort | tail -1)
git -C "$target_root/upstream/cores/SMS" apply --reverse --check \
    --ignore-whitespace "$sms_latest_patch"
echo "PASS: exact-device SMS profiles and pipelined SDRAM read capture"

# Reproduce the exact-device PAL/NTSC profiles and verify all five related
# IOPLL counters are carried through the Agilex reconfiguration transaction.
nes_profiles_tmp=$(mktemp)
python3 "$target_root/scripts/generate-nes-pll-profiles.py" \
    "$target_root/sim/nes-pll-profiles.log" "$nes_profiles_tmp"
cmp "$nes_profiles_tmp" "$target_root/rtl/de25_nes_pll_profiles.sv"
grep -q "1'b0: profile = {32'h0BD20403" "$nes_profiles_tmp"
grep -q "1'b1: profile = {32'h08F00402" "$nes_profiles_tmp"
grep -q '1000000.0 / double($controller) - 500.0' \
    "$target_root/ip/inspect_nes_pll_profiles.tcl"
grep -q 'gui_phase_shift4 11140.21203438' \
    "$target_root/ip/create_nes_core_pll_cal.tcl"
grep -q 'dq_in <= #5.5' "$target_root/sim/nes_sdram_tb.sv"
rm -f "$nes_profiles_tmp"
grep -q 'C_COUNTERS(5)' "$target_root/rtl/de25_nes_pll.sv"
echo "PASS: exact-device NES NTSC/PAL five-clock PLL profiles"

output=${TMPDIR:-/tmp}/de25_nes_sdram_tb.vvp
iverilog -g2012 -Wall -DDE25_AGILEX_PLL_RECONFIG \
    -s nes_sdram_tb \
    -o "$output" \
    "$target_root/upstream/cores/NES/rtl/sdram.sv" \
    "$target_root/sim/nes_sdram_tb.sv"
vvp "$output"

output=${TMPDIR:-/tmp}/de25_nes_loader_bridge_tb.vvp
iverilog -g2012 -Wall \
    -s de25_nes_loader_bridge_tb \
    -o "$output" \
    "$target_root/rtl/de25_nes_loader_bridge.sv" \
    "$target_root/sim/de25_nes_loader_bridge_tb.sv"
vvp "$output"

nes_latest_patch=$(find "$target_root/patches/NES" -name '*.patch' \
    -type f | sort | tail -1)
git -C "$target_root/upstream/cores/NES" apply --reverse --check \
    --ignore-whitespace "$nes_latest_patch"
grep -q 'de25_nes_loader_bridge.sv' \
    "$target_root/quartus/DE25_MISTER_NES.qsf"
grep -q 'de25_loader_bridge|request_sync\[0\]' \
    "$target_root/quartus/DE25_MISTER_MENU.sdc"
grep -q 'de25_loader_bridge|verify_error_sync\[0\]' \
    "$target_root/quartus/DE25_MISTER_MENU.sdc"
grep -q 'src_verify_error' \
    "$target_root/rtl/de25_nes_loader_bridge.sv"
grep -q 'assign de25_gpi_diagnostic' \
    "$target_root/upstream/cores/NES/NES.sv"
grep -q 'DE25_NES_GPI_DIAGNOSTIC=1' \
    "$target_root/quartus/DE25_MISTER_NES.qsf"
grep -q 'DE25_NES_PIPELINE_DIAGNOSTIC=1' \
    "$target_root/quartus/DE25_MISTER_NES.qsf"
grep -q 'DE25_NES_CORE=1' \
    "$target_root/quartus/DE25_MISTER_NES.qsf"
grep -q 'nes_reset_vector_low_seen' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'nes_bus_trace_count' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'BUS_TRACE_SELECT' \
    "$target_root/scripts/read-nes-trace.py"
grep -q 'mister_hps_mister_vbuf_bridge.ip' \
    "$target_root/quartus/DE25_MISTER_NES.qsf"
if grep -q 'mister_hps_mister_vbuf_cdc.ip' \
    "$target_root/quartus/DE25_MISTER_NES.qsf"; then
    echo "FAIL: NES project retains the removed video FIFO IP" >&2
    exit 1
fi
grep -q -- '--parallel=off' "$target_root/scripts/build-nes.sh"
grep -q 'de25_ppu_read_seen' \
    "$target_root/upstream/cores/NES/NES.sv"
grep -A7 'assign de25_gpi_diagnostic = {' \
    "$target_root/upstream/cores/NES/NES.sv" | \
    grep -q 'de25_loader_complete_seen'
grep -A7 'assign de25_gpi_diagnostic = {' \
    "$target_root/upstream/cores/NES/NES.sv" | \
    grep -q 'de25_cpu_data_active'
for scaler_project in NES SNES MINIMIG TGFX16 APPLE1 PC110 PCXT SMS; do
    scaler_qsf="$target_root/quartus/DE25_MISTER_${scaler_project}.qsf"
    grep -q 'DE25_VIDEO_SCALER=1' "$scaler_qsf"
    grep -q 'VHDL_FILE ../../sys/ascal.vhd' "$scaler_qsf"
done
# PC110 plus the screenshot scaler exceeds the Agilex 5 M20K budget unless
# its small register files and lookup tables use the plentiful MLAB fabric.
pc110_chipset_source="$target_root/../rtl/pc110/pc110_chipset.sv"
for memory in scamp block2 ecb pos xr; do
    grep -Eq "ramstyle *= *\"MLAB\".*$memory *\[" \
        "$pc110_chipset_source"
done
grep -A4 'DE25_PC110_CORE' \
    "$target_root/../rtl/common/simple_fifo.v" | grep -q 'ramstyle = "MLAB"'
grep -A5 'DE25_PC110_CORE' \
    "$target_root/../rtl/common/simple_ram.v" | grep -q 'ramstyle = "MLAB"'
grep -A5 'DE25_PC110_CORE' \
    "$target_root/../sys/gamma_corr.sv" | grep -q 'MLAB, no_rw_check'
grep -q 'pc110_refresh_div == 9.d451' \
    "$target_root/../rtl/system.v"
grep -q 'pc110_refresh_toggle, pit_readdata\[3:0\]' \
    "$target_root/../rtl/system.v"
echo "PASS: PC110 preserves its scaler within the Agilex M20K budget"
grep -q 'o_vacc_ini.*4\*OHRESH.*MOD (4\*OHRESH)' \
    "$target_root/../sys/ascal.vhd"
grep -q 'dif_v.*8\*OHRESH.*MOD (8\*OHRESH)' \
    "$target_root/../sys/ascal.vhd"
grep -q 'IF dif_v>=4\*OHRESH THEN' \
    "$target_root/../sys/ascal.vhd"
echo "PASS: small scaler profiles retain full-width vertical accumulators"
grep -A45 ') video_scaler (' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q '\.run(1.b1)'
grep -A55 ') video_scaler (' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q '\.o_r(scaler_video_data\[23:16\])'
grep -A90 ') video_scaler (' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q '\.avl_write(scaler_ddram_write)'
grep -q 'shell_osd_input_data = scaler_video_data' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q '\.din(shell_osd_input_data)' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -A40 ') video_scaler (' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q '\.i_r(core_r)'
grep -q 'hdmi_selected_data <= shell_video_data' \
    "$target_root/rtl/de25_mister_menu_top.sv"
echo "PASS: scaled cores composite the OSD in the fixed 640x480 domain"
grep -B8 ') video_scaler (' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q '\.N_DW(128)'
grep -A4 'de25_mister_ddram #(' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q '\.DATA_WIDTH(128)'
if grep -q 'de25_pc110_line_scanout' \
    "$target_root/rtl/de25_mister_menu_top.sv"; then
    echo "FAIL: PC110 still contains the split-frame line scanout" >&2
    exit 1
fi
grep -A18 'Register the scaler bus on the source-clock edge' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q 'always_ff @(posedge clk_aux)'
echo "PASS: PC110 screenshots and HDMI share the full-frame scaler"
grep -Fq '{*|system_pll|*outclk2}' \
    "$target_root/quartus/DE25_MISTER_PC110.sdc"
grep -q '^set pc110_expected_clock_groups 9$' \
    "$target_root/quartus/DE25_MISTER_PC110.sdc"
grep -A4 'foreach de25_pcxt_generated_clock' \
    "$target_root/quartus/DE25_MISTER_MENU.sdc" | \
    grep -q 'de25_pcxt_generated_clock ne ""'
grep -Fq 'set de25_ao486_uart_clock [get_clocks -nowarn DE25_AO486_UART]' \
    "$target_root/quartus/DE25_MISTER_MENU.sdc"
grep -Fq 'set de25_pcxt_clk_14_318 [get_clocks -nowarn DE25_PCXT_CLK_14_318]' \
    "$target_root/quartus/DE25_MISTER_MENU.sdc"
echo "PASS: PC110 constrains the scaler and video clocks as asynchronous"
grep -q 'wire PC110_VGA_FORCE_60 = 1.b0' \
    "$target_root/../PC110.sv"
grep -q '\.video_f60.*(PC110_VGA_FORCE_60)' \
    "$target_root/../PC110.sv"
echo "PASS: PC110 source timing remains native before frame-store conversion"
grep -q '\.CONF_STR_BRAM(1)' "$target_root/../PC110.sv"
grep -q '^localparam CONF_AW = \$clog2(STRLEN+1);$' \
    "$target_root/../sys/hps_io.sv"
grep -A2 '^wire \[CONF_AW-1:0\] conf_addr =' \
    "$target_root/../sys/hps_io.sv" | \
    grep -q 'byte_cnt\[CONF_AW-1:0\]'
grep -q '\.conf_addr(conf_addr)' "$target_root/../sys/hps_io.sv"
grep -q 'pc110_execution_diagnostic = core\.hps_io\.conf_byte\[5:0\]' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'pc110_execution_diagnostic = core\.hps_io\.byte_cnt\[5:0\]' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -A5 'if (gp_out_sync\[29\])' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q 'io_uio'
echo "PASS: PC110 configuration string uses the full-width synchronous ROM path"
grep -q '\.avl_clk(clk_hps)' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -A5 'de25_mister_ddram #(' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q '\.reset(vbuf_domain_reset)'
grep -q 'ready_sdram(de25_sdram_controller_quiesced)' \
    "$target_root/upstream/cores/NES/NES.sv"
grep -q '\.reset_reset(pll_por\[7\])' "$target_root/rtl/de25_nes_pll.sv"
grep -q 'assign quiesced = quiesce_sync' \
    "$target_root/upstream/cores/NES/rtl/sdram.sv"
if grep -q "SDRAM_DQ_OUT <= '0" \
    "$target_root/upstream/cores/NES/rtl/sdram.sv"; then
    echo "FAIL: NES SDRAM write data still infers an I/O synchronous clear" >&2
    exit 1
fi
grep -q 'Keep write data continuously registered' \
    "$target_root/upstream/cores/NES/rtl/sdram.sv"
grep -q 'FAST_OUTPUT_REGISTER OFF -to DRAM_DQ' \
    "$target_root/quartus/DE25_MISTER_NES.qsf"
grep -q 'FAST_OUTPUT_ENABLE_REGISTER OFF -to DRAM_DQ' \
    "$target_root/quartus/DE25_MISTER_NES.qsf"
echo "PASS: NES quiesce and Agilex SDRAM output-register packing"

# Reproduce the exact-device SNES profiles. SNES keeps the same five related
# clocks as NES but has its own PAL master frequency and video phase.
snes_profiles_tmp=$(mktemp)
python3 "$target_root/scripts/generate-snes-pll-profiles.py" \
    "$target_root/sim/snes-pll-profiles.log" "$snes_profiles_tmp"
cmp "$snes_profiles_tmp" "$target_root/rtl/de25_snes_pll_profiles.sv"
grep -q "1'b0: profile = {32'h0BD20403" "$snes_profiles_tmp"
grep -q "1'b1: profile = {32'h08F20202" "$snes_profiles_tmp"
rm -f "$snes_profiles_tmp"
grep -q 'C_COUNTERS(5)' "$target_root/rtl/de25_snes_pll.sv"
snes_latest_patch=$(find "$target_root/patches/SNES" -name '*.patch' \
    -type f | sort | tail -1)
git -C "$target_root/upstream/cores/SNES" apply --reverse --check \
    --ignore-whitespace "$snes_latest_patch"
echo "PASS: exact-device SNES NTSC/PAL five-clock PLL profiles"

output=${TMPDIR:-/tmp}/de25_snes_sdram_tb.vvp
iverilog -g2012 -Wall -DDE25_AGILEX_PLL_RECONFIG \
    -s snes_sdram_tb \
    -o "$output" \
    "$target_root/upstream/cores/SNES/rtl/sdram.sv" \
    "$target_root/sim/snes_sdram_tb.sv"
vvp "$output"

grep -q 'ready_sdram(de25_sdram_controller_quiesced)' \
    "$target_root/upstream/cores/SNES/SNES.sv"
grep -q 'assign quiesced = quiesce_sync' \
    "$target_root/upstream/cores/SNES/rtl/sdram.sv"
if grep -q "SDRAM_DQ_OUT <= '0" \
    "$target_root/upstream/cores/SNES/rtl/sdram.sv"; then
    echo "FAIL: SNES SDRAM write data still infers an I/O synchronous clear" >&2
    exit 1
fi
grep -q 'continuously clocked data' \
    "$target_root/upstream/cores/SNES/rtl/sdram.sv"
grep -q 'FAST_OUTPUT_REGISTER OFF -to DRAM_DQ' \
    "$target_root/quartus/DE25_MISTER_SNES.qsf"
grep -q 'FAST_OUTPUT_ENABLE_REGISTER OFF -to DRAM_DQ' \
    "$target_root/quartus/DE25_MISTER_SNES.qsf"
grep -q 'snes_core_pll_cal' "$target_root/quartus/DE25_MISTER_MENU.sdc"
echo "PASS: SNES quiesce and Agilex SDRAM output-register packing"

apple1_latest_patch=$(find "$target_root/patches/Apple-I" -name '*.patch' \
    -type f | sort | tail -1)
git -C "$target_root/upstream/cores/Apple-I" apply --reverse --check \
    --ignore-whitespace "$apple1_latest_patch"
grep -q 'gui_output_clock_frequency1 25.0' \
    "$target_root/ip/create_apple1_core_pll.tcl"
grep -q 'DE25_CORE_HAS_TAPE_IN=1' \
    "$target_root/quartus/DE25_MISTER_APPLE1.qsf"
grep -q '\.TAPE_IN(1.b0)' "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'wire \[127:0\] status_bus;' \
    "$target_root/upstream/cores/Apple-I/boards/MiSTer/Apple-I.sv"
echo "PASS: Apple-I uses the common source shell and Agilex core PLL overlay"

# Ensure the exact Quartus-derived MemTest profiles remain reproducible and
# retain the legacy packed-decimal frequency display convention.
profiles_tmp=$(mktemp)
trap 'rm -f "$profiles_tmp"' EXIT
python3 "$target_root/scripts/generate-memtest-pll-profiles.py" \
    "$target_root/sim/memtest-pll-profiles.log" "$profiles_tmp"
cmp "$profiles_tmp" "$target_root/rtl/de25_memtest_pll_profiles.sv"
grep -q "6'd0: profile = {12'h167" "$profiles_tmp"
grep -q "32'h02800805, 32'h02882805" "$profiles_tmp"
grep -q "6'd27: profile = {12'h125.*32'h0620580C" "$profiles_tmp"
grep -q "6'd34: profile = {12'h100.*32'h07A0700F" "$profiles_tmp"
grep -q "6'd36: profile = {12'h080.*32'h0620600D" "$profiles_tmp"
grep -q 'reg \[5:0\] pos = 36' "$memtest_source"
grep -q '\.reset_reset(reset)' \
    "$target_root/rtl/de25_memtest_pll.sv"
grep -q 'A normal reset does not need to rewrite the same PLL profile' \
    "$memtest_source"
grep -q "6'd45: profile = {12'h625" "$profiles_tmp"
grep -q "6'd63: profile = {12'h045" "$profiles_tmp"
echo "PASS: 64 exact MemTest PLL profiles and packed-decimal display values"

output=${TMPDIR:-/tmp}/de25_iopll_avmm_tb.vvp

iverilog -g2012 -Wall \
    -s de25_iopll_avmm_tb \
    -o "$output" \
    "$target_root/rtl/de25_iopll_avmm.sv" \
    "$target_root/sim/de25_iopll_avmm_tb.sv"

vvp "$output"

grep -q 'HSIO flow must not access HVIO recalibration-enable register' \
    "$target_root/sim/de25_iopll_reconfig_axil_tb.sv"
if grep -q 'DE25_PLL_DIAGNOSTIC_AUTO=1' \
    "$target_root/quartus/DE25_MISTER_MEMTEST.qsf"; then
    echo "FAIL: production MemTest build enables the one-shot PLL diagnostic" >&2
    exit 1
fi
python3 -m py_compile "$target_root/sw/mister-de25-pll-diagnostic"
echo "PASS: production HSIO flow excludes HVIO-only writes and diagnostic triggers"

grep -q 'reg reset = 1' \
    "$target_root/upstream/cores/AO486/ao486.sv"
grep -q 'reg de25_init_reset_n = 0' \
    "$target_root/upstream/cores/AO486/ao486.sv"
grep -q 'if(!RESET) de25_init_reset_n <= 1' \
    "$target_root/upstream/cores/AO486/ao486.sv"
if grep -q 'de25_status_reset_armed' \
    "$target_root/upstream/cores/AO486/ao486.sv"; then
    echo "FAIL: ao486 DE25 reset still depends on a status edge" >&2
    exit 1
fi
echo "PASS: ao486 DE25 reset releases from the synchronized platform level"

grep -q 'reg \[27:0\] ce_video_accum = 28'\''d0' \
    "$target_root/upstream/cores/AO486/rtl/soc/vga.v"
grep -q 'ce_video_accum <= ce_video_accum + pixclk - clk_rate' \
    "$target_root/upstream/cores/AO486/rtl/soc/vga.v"
grep -q '~vga_f60 || !pixclk' \
    "$target_root/upstream/cores/AO486/rtl/soc/vga.v"
echo "PASS: ao486 VGA pixel clock self-starts after a runtime fabric load"

output=${TMPDIR:-/tmp}/de25_iopll_reconfig_axil_tb.vvp

iverilog -g2012 -Wall \
    -s de25_iopll_reconfig_axil_tb \
    -o "$output" \
    "$target_root/rtl/de25_iopll_axil.sv" \
    "$target_root/rtl/de25_iopll_reconfig_axil.sv" \
    "$target_root/sim/de25_iopll_reconfig_axil_tb.sv"

vvp "$output"

output=${TMPDIR:-/tmp}/de25_iopll_axil_tb.vvp

iverilog -g2012 -Wall \
    -s de25_iopll_axil_tb \
    -o "$output" \
    "$target_root/rtl/de25_iopll_axil.sv" \
    "$target_root/sim/de25_iopll_axil_tb.sv"

vvp "$output"

output=${TMPDIR:-/tmp}/de25_iopll_reconfig_tb.vvp

iverilog -g2012 -Wall \
    -s de25_iopll_reconfig_tb \
    -o "$output" \
    "$target_root/rtl/de25_iopll_avmm.sv" \
    "$target_root/rtl/de25_iopll_reconfig.sv" \
    "$target_root/sim/de25_iopll_reconfig_tb.sv"

vvp "$output"

# The Menu core historically relies on Verilog's implicit nets. On Agilex this
# is dangerous when a signal is used before its later, wider declaration.
# Ensure the platform patch keeps every affected signal declared up front.
menu_source="$target_root/upstream/cores/Menu/menu.sv"
menu_latest_patch=$(find "$target_root/patches/Menu" -name '*.patch' \
    -type f | sort | tail -1)
git -C "$target_root/upstream/cores/Menu" apply --reverse --check \
    --ignore-whitespace "$menu_latest_patch"
for signal in clk_sys ce_pix FB sdram_addr sdram_ready sdram_dout sdram_din sdram_we cfg addr we; do
    first_use=$(awk -v signal="$signal" '
        $0 ~ "(^|[^[:alnum:]_])" signal "([^[:alnum:]_]|$)" { print NR; exit }
    ' "$menu_source")
    declaration=$(awk -v signal="$signal" '
        $0 ~ "^[[:space:]]*(wire|reg|logic)([[:space:]]+\\[[^]]+\\])?[[:space:]]+" signal "([[:space:]=;,]|$)" { print NR; exit }
    ' "$menu_source")
    if [[ -z "$declaration" || "$declaration" != "$first_use" ]]; then
        echo "FAIL: Menu signal $signal is used before its declaration" >&2
        exit 1
    fi
done

echo "PASS: Menu signals are declared before use"

if ! grep -q 'assign de25_sdram_dq_oe = sdram_dq_oe' "$menu_source"; then
    echo "FAIL: Menu SDRAM output enable is not exported to the board boundary" >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*inout.*SDRAM_DQ([,[:space:]]|$)' \
    "$target_root/upstream/cores/Menu/rtl/sdram.sv"; then
    echo "FAIL: nested SDRAM controller still contains a tri-state port" >&2
    exit 1
fi

echo "PASS: Menu SDRAM tri-state is at the board boundary"

grep -q 'gui_number_of_clocks 3' \
    "$target_root/ip/create_mister_pll.tcl"
grep -q 'gui_output_clock_frequency2 25.175' \
    "$target_root/ip/create_mister_pll.tcl"
grep -q 'add_instance clk_100 altera_clock_bridge 19.2.0' \
    "$target_root/ip/create_mister_hps.tcl"
grep -q 'set_instance_parameter_value clk_100 EXPLICIT_CLOCK_RATE 100000000' \
    "$target_root/ip/create_mister_hps.tcl"
grep -q '\.clk_100_clk(clk_hps)' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'DE25_AO486_CORE=1' \
    "$target_root/quartus/DE25_MISTER_AO486.qsf"
grep -q '\.DE25_CLK_VGA(clk_hps)' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q '\.clk_audio(CLK_AUDIO)' \
    "$target_root/upstream/cores/AO486/ao486.sv"
grep -q 'mpu_phase <= mpu_phase + 10.d125' \
    "$target_root/rtl/de25_ao486_pll.sv"
if grep -q 'ao486_peripheral_pll' \
    "$target_root/quartus/DE25_MISTER_AO486.qsf" || \
   grep -q 'create_ao486_peripheral_pll.tcl' \
    "$target_root/scripts/build-ao486.sh"; then
    echo "FAIL: ao486 still builds the fitter-rejected fixed peripheral PLL" >&2
    exit 1
fi

grep -q 'DE25_CORE_HAS_SDRAM=1' \
    "$target_root/quartus/DE25_MISTER_AO486.qsf"
grep -q 'C_COUNTERS(2)' "$target_root/rtl/de25_ao486_pll.sv"
grep -q 'cpu_sdram_outclk_clk(clk_sdram_physical)' \
    "$target_root/rtl/de25_ao486_pll.sv"
grep -q '^reg \[15:0\] new_data;' \
    "$target_root/upstream/cores/AO486/rtl/soc/gus/sdram.sv"
grep -q '^state_t state;' \
    "$target_root/upstream/cores/AO486/rtl/soc/gus/sdram.sv"
grep -q 'synthesis removed the GUS SDRAM write datapath' \
    "$target_root/scripts/build-ao486.sh"
grep -q 'quartus_sta -t ../scripts/report-sdram-timing.tcl' \
    "$target_root/scripts/build-ao486.sh"

ao486_profiles_tmp=$(mktemp)
python3 "$target_root/scripts/generate-ao486-pll-profiles.py" \
    "$target_root/sim/ao486-pll-profiles.log" "$ao486_profiles_tmp"
cmp "$ao486_profiles_tmp" "$target_root/rtl/de25_ao486_pll_profiles.sv"
rm -f "$ao486_profiles_tmp"

output=${TMPDIR:-/tmp}/ao486_gus_sdram_tb.vvp
iverilog -g2012 -Wall -DDE25_AGILEX_PLL \
    -DDE25_CORE_HAS_SPLIT_SDRAM_DQ \
    -s ao486_gus_sdram_tb \
    -o "$output" \
    "$target_root/upstream/cores/AO486/rtl/soc/gus/sdram.sv" \
    "$target_root/sim/ao486_gus_sdram_tb.sv"
vvp "$output"

ao486_latest_patch=$(find "$target_root/patches/AO486" -name '*.patch' \
    -type f | sort | tail -1)
git -C "$target_root/upstream/cores/AO486" apply --reverse --check \
    --ignore-whitespace "$ao486_latest_patch"

echo "PASS: ao486 uses the shared video PLL and timing-checked GUS SDRAM"

grep -q 'gui_number_of_clocks 4' \
    "$target_root/ip/create_menu_core_pll.tcl"
grep -q 'create_menu_core_pll.tcl' \
    "$target_root/scripts/build-menu.sh"
if grep -q 'create_de25_core_clock_banks.tcl' \
    "$target_root/scripts/build-menu.sh"; then
    echo "FAIL: Menu build still uses the experimental fixed clock service" >&2
    exit 1
fi
grep -q 'wire core_clk_video;' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'DE25_STANDARD_HDMI_TIMING=1' \
    "$target_root/quartus/DE25_MISTER_MENU.qsf"
grep -q 'io_osd(io_osd)' "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'OSD_STATUS(shell_osd_status)' "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'wire \[23:0\] hdmi_selected_data = SW\[3\] ? hdmi_probe_data : shell_video_data;' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'assign HDMI_TX_CLK = ~core_clk_video' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'input         menu_core' \
    "$target_root/upstream/cores/Menu/sys/osd.v"
grep -q 'osd_buffer\[0:' \
    "$target_root/upstream/cores/Menu/sys/osd.v"
for qsf in "$target_root"/quartus/DE25_MISTER_*.qsf; do
    if [[ $qsf == *_V2.qsf ]]; then
        base_qsf=${qsf%_V2.qsf}.qsf
        if [[ -f $base_qsf ]]; then
            grep -q "^source $(basename "$base_qsf")$" "$qsf"
        else
            grep -q '^source de25_simple_persona_base.qsf$' "$qsf"
        fi
    else
        grep -q 'upstream/cores/Menu/sys/osd.v' "$qsf" ||
            grep -q '^source DE25_MISTER_MENU.qsf$' "$qsf"
    fi
done
grep -q '\.outclk_2(de25_sdram_clk)' "$menu_source"
grep -q '\.outclk_3(de25_sdram_capture_clk)' "$menu_source"
grep -q 'assign SDRAM_CLK = de25_sdram_clk' "$menu_source"
grep -q '\.clk_capture(de25_sdram_capture_clk)' "$menu_source"
grep -q 'read_capture_toggle <= ~read_capture_toggle' \
    "$target_root/upstream/cores/Menu/rtl/sdram.sv"
grep -q 'data_capture      <= SDRAM_DQ_IN' \
    "$target_root/upstream/cores/Menu/rtl/sdram.sv"
grep -q 'data_ready_delay\[CAS_LATENCY\] <= 1' \
    "$target_root/upstream/cores/Menu/rtl/sdram.sv"
grep -q '^`ifndef DE25_AGILEX_SDRAM_CLOCK' \
    "$target_root/upstream/cores/Menu/rtl/sdram.sv"
echo "PASS: Menu uses independently phase-shifted SDRAM output and capture clocks"

grep -q 'require_nonnegative_slack output-setup' \
    "$target_root/scripts/report-sdram-timing.tcl"
grep -q 'Full-design setup and hold are enforced separately' \
    "$target_root/scripts/report-sdram-timing.tcl"
grep -q 'require_nonnegative_slack input-hold' \
    "$target_root/scripts/report-sdram-timing.tcl"
grep -q 'set_multicycle_path -setup 2 -from .de25_sdram_dq' \
    "$target_root/quartus/DE25_MISTER_MENU.sdc"
grep -q 'set_multicycle_path -setup 2 -from .de25_sdram_capture_registers' \
    "$target_root/quartus/DE25_MISTER_MENU.sdc"
grep -q 'report-sdram-timing.tcl' "$target_root/scripts/build-memtest.sh"
grep -q 'report-sdram-timing.tcl' "$target_root/scripts/build-menu.sh"
grep -q "wire \[1:0\] de25_test_sdram_sz = 2'd3" \
    "$target_root/upstream/cores/MemTest/memtest.sv"
grep -q 'de25_reconfig_error, de25_ram_quiesced' \
    "$target_root/upstream/cores/MemTest/memtest.sv"
grep -q 'displayed_passcount_meta <= de25_raw_displayed_passcount' \
    "$target_root/upstream/cores/MemTest/memtest.sv"
grep -q 'de25_memtest_display_meta' \
    "$target_root/quartus/DE25_MISTER_MENU.sdc"
grep -q 'DE25 onboard SDRAM config: 3 (128 MB)' \
    "$target_root/upstream/Main_MiSTer/user_io.cpp"
echo "PASS: Quartus builds enforce external SDRAM setup and hold timing"

output=${TMPDIR:-/tmp}/de25_mister_menu_sdram_tb.vvp

iverilog -g2012 -Wall \
    -s menu_sdram_tb \
    -o "$output" \
    "$target_root/upstream/cores/Menu/rtl/sdram.sv" \
    "$target_root/sim/menu_sdram_tb.sv"

vvp "$output"

output=${TMPDIR:-/tmp}/de25_mister_ddram_tb.vvp

iverilog -g2012 -Wall \
    -s de25_mister_ddram_tb \
    -o "$output" \
    "$target_root/rtl/de25_mister_ddram.sv" \
    "$target_root/sim/de25_mister_ddram_tb.sv"

vvp "$output"

dtbo=${TMPDIR:-/tmp}/mister-de25-fpga-load.dtbo
dtc -q -@ -I dts -O dtb -o "$dtbo" \
    "$target_root/boot/mister-fpga-load-overlay.dts"
main_latest_patch=$(find "$target_root/patches/Main_MiSTer" -name '*.patch' \
    -type f | sort | tail -1)
git -C "$target_root/upstream/Main_MiSTer" apply --reverse --check \
    --ignore-whitespace "$main_latest_patch"
dtc -q -I dtb -O dts -o - "$dtbo" | \
    grep -q 'firmware-name = "mister-de25-core.rbf"'
dtc -q -I dtb -O dts -o - "$dtbo" | \
    grep -q '#address-cells = <0x02>'
dtc -q -I dtb -O dts -o - "$dtbo" | \
    grep -q '#size-cells = <0x02>'
grep -q 'de25_apply_fpga_overlay' \
    "$target_root/upstream/Main_MiSTer/fpga_io.cpp"
grep -q 'de25_modprobe("stratix10_soc")' \
    "$target_root/upstream/Main_MiSTer/fpga_io.cpp"
grep -q 'de25_modprobe("of-fpga-region")' \
    "$target_root/upstream/Main_MiSTer/fpga_io.cpp"
grep -q '/sys/class/fpga_region/region0' \
    "$target_root/upstream/Main_MiSTer/fpga_io.cpp"
grep -q '/sys/kernel/config/device-tree/overlays/mister-de25/dtbo' \
    "$target_root/upstream/Main_MiSTer/fpga_io.cpp"
grep -q 'shmem_map_physical(FPGA_REG_BASE, FPGA_REG_SIZE)' \
    "$target_root/upstream/Main_MiSTer/fpga_io.cpp"
grep -q 'void \*shmem_map_physical' \
    "$target_root/upstream/Main_MiSTer/shmem.cpp"
grep -q 'cur_btn & (BUTTON_OSD | BUTTON_USR)' \
    "$target_root/upstream/Main_MiSTer/user_io.cpp"
if grep -q '/sys/class/fpga_manager/fpga0/firmware"' \
    "$target_root/upstream/Main_MiSTer/fpga_io.cpp"; then
    echo "FAIL: Main still targets the nonexistent FPGA Manager sysfs loader" >&2
    exit 1
fi
echo "PASS: Main loads Agilex RBF files through the FPGA-region overlay API"

bash -n "$target_root/sw/mister-de25-load"
bash -n "$target_root/sw/mister-de25-check-rbf"
bash -n "$target_root/sw/mister-de25-platform-migration"
bash -n "$target_root/sw/mister-de25-headless-bootstrap"
grep -q 'MISTER_DE25_LAUNCHER' \
    "$target_root/upstream/Main_MiSTer/user_io.cpp"
bash -n "$target_root/sw/mister-de25-headless-migrate"
bash -n "$target_root/sw/mister-de25-migrate"
bash -n "$target_root/sw/mister-de25-test-rbf"
bash -n "$target_root/sw/mister-de25-select-core"
bash -n "$target_root/sw/mister-de25-process-core-request"
bash -n "$target_root/sw/mister-de25-core"
bash -n "$target_root/sw/mister-de25-screenshot"
bash -n "$target_root/scripts/make-runtime-core-catalog.sh"
bash -n "$target_root/scripts/extract-hps-io-hash.sh"
grep -q 'RBF inspection input must be inside the workspace' \
    "$target_root/scripts/extract-hps-io-hash.sh"
bash -n "$target_root/scripts/program-qspi.sh"
bash -n "$target_root/scripts/make-qspi-jic-from-hps-rbf.sh"
bash -n "$target_root/sw/mister-de25-bridge"
bash -n "$target_root/sw/mister-de25-watchdog-run"
"$target_root/scripts/test-hps-io-compatibility.sh"
grep -q 'quartus_pgm -m jtag -o "ibpv;' \
    "$target_root/scripts/program-qspi.sh"
grep -q 'jic_hash !=.*runtime_hash' \
    "$target_root/scripts/program-qspi.sh"
grep -q '/sys/class/fpga_bridge' "$target_root/sw/mister-de25-bridge"
if grep -q 'import mmap\|mmap\.mmap\|RSTMGR_BASE\|SYSMGR_BASE' \
    "$target_root/sw/mister-de25-bridge"; then
    echo "FAIL: bridge helper must not access Agilex secure registers" >&2
    exit 1
fi
bash -n "$target_root/scripts/prepare-sd-image.sh"
bash -n "$target_root/scripts/make-update-bundle.sh"
bash -n "$target_root/scripts/build-main-aarch64.sh"
bash -n "$target_root/scripts/list-packaged-artifacts.sh"
bash -n "$target_root/scripts/capture-board-screenshot.sh"
bash -n "$target_root/scripts/rebuild-platform-release.sh"
bash -n "$target_root/scripts/fetch-official-core.sh"
bash -n "$target_root/scripts/official-port-inventory.sh"
[[ $("$target_root/scripts/list-packaged-artifacts.sh" | wc -l | tr -d ' ') -eq 8 ]]
[[ $("$target_root/scripts/list-packaged-artifacts.sh" --managed | wc -l | tr -d ' ') -eq 18 ]]
grep -q $'^NES\tpackaged\tscripts/build-nes-v2.sh\tartifacts/nes-v2/NES_v2.rbf\tpass\tpending$' \
    "$target_root/port-status.tsv"
grep -q $'^PC110\tpackaged\tscripts/build-pc110.sh\tartifacts/pc110/IBM_PC110_20260825_FDCD_VERTICAL_ACCUM_FIX.rbf\tpass\tpending$' \
    "$target_root/port-status.tsv"
grep -q $'^PCXT\tbuilt\tscripts/build-pcxt-v2.sh\tartifacts/pcxt-v2/PCXT_v2.rbf\tpass\tpending$' \
    "$target_root/port-status.tsv"
grep -q $'^_Computer\tIBM PC/XT\tPCXT\tyes\t.*\tbuilt\tscripts/build-pcxt-v2.sh\tartifacts/pcxt-v2/PCXT_v2.rbf\tpass\tpending\t' \
    "$target_root/build-matrix.tsv"
grep -q $'^SMS\tbuilt\tscripts/build-sms-v2.sh\tartifacts/sms-v2/SMS_v2.rbf\tpass\tpending$' \
    "$target_root/port-status.tsv"
grep -q $'^AO486\tbuilt\tscripts/build-ao486-v2.sh\tartifacts/ao486-v2/AO486_v2.rbf\tpass\tpending$' \
    "$target_root/port-status.tsv"
grep -q $'^ATARI7800\tbuilt\tscripts/build-atari7800-v2.sh\tartifacts/atari7800-v2/Atari7800_v2.rbf\tpass\tload-pass$' \
    "$target_root/port-status.tsv"
grep -q $'^Jaguar\tbuilt\tscripts/build-jaguar-v2.sh\tartifacts/jaguar-v2/Jaguar_v2.rbf\tpass\tload-pass$' \
    "$target_root/port-status.tsv"
grep -q $'^PSX\tbuilt\tscripts/build-psx-v2.sh\tartifacts/psx-v2/PSX_v2_ntsc_bringup.rbf\tpass\tload-pass$' \
    "$target_root/port-status.tsv"
grep -q $'^N64\tbuilt\tscripts/build-n64-v2.sh\tartifacts/n64-v2/N64_v2_ntsc_bringup.rbf\tpass\tpending$' \
    "$target_root/port-status.tsv"
grep -q $'^Saturn\tbuilt\tscripts/build-saturn-v2.sh\tartifacts/saturn-v2/Saturn_v2_ntsc_light_bringup.rbf\tpass\tpending$' \
    "$target_root/port-status.tsv"
grep -q $'^_Console\tSega Master System, Game Gear\tSMS\tyes\t.*\tbuilt\tscripts/build-sms-v2.sh\tartifacts/sms-v2/SMS_v2.rbf\tpass\tpending\t' \
    "$target_root/build-matrix.tsv"
grep -q $'^_Computer\tao486 (PC 486)\tAO486\tno\t.*\tbuilt\tscripts/build-ao486-v2.sh\tartifacts/ao486-v2/AO486_v2.rbf\tpass\tpending\t' \
    "$target_root/build-matrix.tsv"
grep -q 'Refusing mixed HPS I/O hashes in the update bundle' \
    "$target_root/scripts/make-update-bundle.sh"
grep -q 'MISTER_DE25_MENU_RBF' "$target_root/scripts/make-update-bundle.sh"
grep -q 'make-runtime-core-catalog.sh" --managed' \
    "$target_root/scripts/make-update-bundle.sh"
grep -q 'list-packaged-artifacts.sh' "$target_root/scripts/make-update-bundle.sh"
grep -q 'list-packaged-artifacts.sh' "$target_root/scripts/prepare-sd-image.sh"
grep -q 'MISTER_DE25_MENU_RBF' "$target_root/scripts/prepare-sd-image.sh"
grep -q 'MISTER_DE25_PLATFORM_HASH_FILE' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'artifacts/main/MiSTer' "$target_root/scripts/prepare-sd-image.sh"
grep -q 'artifacts/kernel/Image' "$target_root/scripts/prepare-sd-image.sh"
grep -q 'artifacts/kernel/stratix10-soc.ko' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'artifacts/kernel/modules-' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q '^+CONFIG_INPUT_MOUSEDEV=m$' \
    "$target_root/kernel/patches/0005-input-enable-mousedev.patch"
grep -q '^mousedev$' \
    "$target_root/systemd/mister-de25-input.conf"
grep -q 'mister-de25-input.conf' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'mister-de25-input.conf' \
    "$target_root/scripts/make-update-bundle.sh"
grep -q 'Expected 1335 matching kernel modules' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'rm -rf -- "$module_dir"' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'module_relative=kernel/drivers/fpga/stratix10-soc.ko' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'Obsolete SDM remapper survived' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'artifacts/kernel/Image' \
    "$target_root/scripts/rebuild-platform-release.sh"
grep -q 'module_count.*tar -tzf' \
    "$target_root/scripts/rebuild-platform-release.sh"
for kernel_patch in "$target_root"/kernel/patches/*.patch; do
    git apply --numstat "$kernel_patch" >/dev/null
done
grep -q 'arm_smmu_make_bypass_ste' \
    "$target_root/kernel/patches/0002-iommu-arm-smmu-v3-bypass-unattached-de25-streams.patch"
grep -q '/delete-property/ iommus' \
    "$target_root/kernel/patches/0003-arm64-dts-intel-de25-isolate-sdm-smmu-stream.patch"
grep -q 'address >= 0xa0000000ULL && address < 0xc0000000ULL' \
    "$target_root/kernel/patches/0004-devmem-allow-mister-ddram-aperture.patch"
if rg -q 'sdm-remapper' "$target_root/kernel/patches"; then
    echo "FAIL: obsolete SDM remapper kernel patch remains" >&2
    exit 1
fi
grep -q 'artifacts/main/MiSTer' "$target_root/scripts/make-update-bundle.sh"
grep -q 'MISTER_DE25_MAIN_OUTPUT' "$target_root/scripts/build-main-aarch64.sh"
grep -q 'if (osd_size > 8) spi_osd_cmd(OSD_CMD_WRITE | 8);' \
    "$target_root/upstream/Main_MiSTer/osd.cpp"
echo "PASS: Main reasserts 16-row geometry for in-core menus"
grep -q 'list-packaged-artifacts.sh" --managed' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q -- '--registered' "$target_root/scripts/build-catalog.sh"
grep -q 'build-catalog.sh" --registered' \
    "$target_root/scripts/rebuild-platform-release.sh"
grep -q 'DE25_HPS_PARTITION_MODE=reuse' \
    "$target_root/scripts/rebuild-platform-release.sh"
grep -q -- '--image BASE.img OUTPUT.img' \
    "$target_root/scripts/rebuild-platform-release.sh"
grep -q 'prepare-sd-image.sh" "$image_base" "$image_output"' \
    "$target_root/scripts/rebuild-platform-release.sh"
grep -q 'verify_artifact.*artifacts/menu/menu.rbf' \
    "$target_root/scripts/rebuild-platform-release.sh"
grep -q 'Release HPS metadata does not match the RBF payload' \
    "$target_root/scripts/rebuild-platform-release.sh"
grep -q 'Non-packaged DE25 artifact survived in SD image' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'Superseded managed DE25 artifact survived in SD image' \
    "$target_root/scripts/prepare-sd-image.sh"
sh -n "$target_root/sw/update_de25.sh"
sh -n "$target_root/sw/mister-de25-prune-cores"
grep -q 'mister-de25-prune-cores' "$target_root/sw/update_de25.sh"
grep -q 'mister-de25-prune-cores' "$target_root/scripts/make-update-bundle.sh"
grep -q 'mister-de25-prune-cores' "$target_root/scripts/prepare-sd-image.sh"
grep -q 'mister-de25-screenshot' "$target_root/scripts/make-update-bundle.sh"
grep -q 'mister-de25-screenshot' "$target_root/scripts/prepare-sd-image.sh"
grep -q 'mister-de25-headless-migrate' "$target_root/scripts/make-update-bundle.sh"
grep -q 'mister-de25-headless-migrate' "$target_root/scripts/prepare-sd-image.sh"
grep -q 'mister-de25-platform-migration.path' \
    "$target_root/scripts/make-update-bundle.sh"
grep -q 'mister-de25-platform-migration.path' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'rootfs/var/lib/mister-de25/boot/menu.rbf' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'root var/lib/mister-de25/boot/menu.rbf' \
    "$target_root/scripts/make-update-bundle.sh"
grep -q 'mister-de25-platform-migration.path' \
    "$target_root/sw/update_de25.sh"
grep -q '#define MISTER_SCALER_BASEADDR     0x30000000' \
    "$target_root/upstream/Main_MiSTer/scaler.h"
grep -q '#define MISTER_AO486_SCALER_BASEADDR 0x20000000' \
    "$target_root/upstream/Main_MiSTer/scaler.h"
grep -A8 'int offset = MISTER_SCALER_BASEADDR' \
    "$target_root/upstream/Main_MiSTer/scaler.cpp" | \
    grep -q 'MISTER_AO486_SCALER_BASEADDR'
grep -A8 'int offset = MISTER_SCALER_BASEADDR' \
    "$target_root/upstream/Main_MiSTer/scaler.cpp" | \
    grep -q 'strcasecmp(core_name, "AO486")'
grep -A9 'int offset = MISTER_SCALER_BASEADDR' \
    "$target_root/upstream/Main_MiSTer/scaler.cpp" | \
    grep -q 'strcasecmp(core_name, "PC110")'
grep -A15 'uint64_t image_end' \
    "$target_root/upstream/Main_MiSTer/scaler.cpp" | \
    grep -q 'image_end > (uint64_t)ms->num_bytes'
grep -A15 'uint64_t image_end' \
    "$target_root/upstream/Main_MiSTer/scaler.cpp" | \
    grep -q 'Invalid scaler header'
grep -A8 'The FPGA writes this buffer' \
    "$target_root/upstream/Main_MiSTer/scaler.cpp" | \
    grep -q 'shmem_map_physical(map_start + 0x80000000'
grep -q '#if defined(__ARM_NEON) && !defined(MISTER_DE25)' \
    "$target_root/upstream/Main_MiSTer/scaler.cpp"
grep -A15 'No NEON is available, or this is DE25 framebuffer I/O' \
    "$target_root/upstream/Main_MiSTer/scaler.cpp" | \
    grep -q 'volatile unsigned char \*buffer'
grep -A8 'Menu and fixed-scaled DE25 personas always own a 16-row bitmap' \
    "$target_root/upstream/cores/Menu/sys/osd.v" | \
    grep -q 'OSD_HEIGHT<<(highres | menu_core | force_highres)'
grep -A12 'Fixed-scaled cores expose a full 16-row MiSTer configuration menu' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q '\.force_highres(1.b1)'
echo "PASS: fixed-scaled cores retain every in-core OSD row"
grep -q 'scaler_rambase = 32.h2000_0000' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -A5 'DE25_AO486_CORE' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q 'DE25_PC110_CORE'
grep -A1 'DE25_PC110_CORE' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q 'scaler_rambase = 32.h2000_0000'
grep -q 'scaler_rambase = 32.h3000_0000' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q '\.RAMBASE(scaler_rambase)' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'parameter logic \[31:0\] PHYSICAL_OFFSET = 32.h8000_0000' \
    "$target_root/rtl/de25_mister_ddram.sv"
grep -q 'address += 0x80000000' \
    "$target_root/upstream/Main_MiSTer/shmem.cpp"
grep -q 'static int physical_memfd = -1' \
    "$target_root/upstream/Main_MiSTer/shmem.cpp"
grep -q 'return shmem_map_address(address, size, false)' \
    "$target_root/upstream/Main_MiSTer/shmem.cpp"
grep -A6 'void \*shmem_map_physical' \
    "$target_root/upstream/Main_MiSTer/shmem.cpp" | \
    grep -q 'return shmem_map_address(address, size, true)'
grep -q 'static void de25_mapped_memset' \
    "$target_root/upstream/Main_MiSTer/support/x86/x86.cpp"
if grep -A45 'static void de25_mapped_memset' \
    "$target_root/upstream/Main_MiSTer/support/x86/x86.cpp" | \
    grep -Eq '^[[:space:]]+memset\('; then
    echo 'DE25 x86 mapped-memory fill delegates to unsafe libc memset' >&2
    exit 1
fi
grep -A10 'static int mem_set' \
    "$target_root/upstream/Main_MiSTer/support/x86/x86.cpp" | \
    grep -q 'de25_mapped_memset(buf, fill_byte, size)'
grep -q 'MakeFile("/tmp/DE25_SCREENSHOT", result_data->filename)' \
    "$target_root/upstream/Main_MiSTer/scaler.cpp"
grep -A8 'every frame, check if a screenshot' \
    "$target_root/upstream/Main_MiSTer/user_io.cpp" | \
    grep -q 'screenshot_cb();'
grep -q 'mister-de25-screenshot' \
    "$target_root/scripts/capture-board-screenshot.sh"
grep -q '89504e470d0a1a0a' \
    "$target_root/scripts/capture-board-screenshot.sh"
screenshot_test=$(mktemp -d "${TMPDIR:-/tmp}/de25-screenshot-test.XXXXXXXX")
mkdir -p "$screenshot_test/fat/screenshots/Menu"
touch "$screenshot_test/cmd"
(
    sleep 0.2
    touch "$screenshot_test/fat/screenshots/Menu/test-shot.png"
    printf '%s\n' 'screenshots/Menu/test-shot.png' >"$screenshot_test/status"
) &
screenshot_path=$(MISTER_CMD_FIFO="$screenshot_test/cmd" \
    MISTER_SCREENSHOT_STATUS="$screenshot_test/status" \
    MISTER_FAT_ROOT="$screenshot_test/fat" \
    MISTER_SCREENSHOT_TIMEOUT=2 \
    "$target_root/sw/mister-de25-screenshot" test-shot)
wait
[[ $screenshot_path == "$screenshot_test/fat/screenshots/Menu/test-shot.png" ]]
grep -q '^screenshot test-shot$' "$screenshot_test/cmd"
rm -rf "$screenshot_test"
echo "PASS: DE25 native screenshot command and completed-image handoff"
"$target_root/scripts/test-updater.sh"
"$target_root/scripts/test-runtime-rbf-swap.sh"
"$target_root/scripts/test-watchdog-run.sh"
"$target_root/scripts/test-runtime-loader-recovery.sh"
"$target_root/scripts/test-runtime-core-selector.sh"
"$target_root/scripts/test-catalog.sh"
grep -q "awk -F '\\\\t'" "$target_root/scripts/build-catalog.sh"
if grep -q "IFS=\\$'\\\\t'.*category.*status.*build_script" \
    "$target_root/scripts/build-catalog.sh"; then
    echo "FAIL: catalog dispatcher uses whitespace-collapsing TSV parsing" >&2
    exit 1
fi
grep -q 'core_categories' "$target_root/scripts/prepare-sd-image.sh"
grep -q 'core_rbfs' "$target_root/scripts/prepare-sd-image.sh"
grep -q '::/Scripts/update_de25.sh' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'Refusing mixed HPS I/O hashes in the SD image' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'check-menu.rbf.hps-io-hash' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'libimlib2_1.7.4-1build1_arm64.deb' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'test -e /mnt/root/usr/lib/aarch64-linux-gnu/libImlib2.so.1' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'install -m 0755 /payload/usr/libexec/mister-de25-test-rbf' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'mister-de25-core-request.path' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'mister-de25-platform-migration.path' \
    "$target_root/scripts/prepare-sd-image.sh"
minimig_latest_patch=$(find "$target_root/patches/Minimig" -name '*.patch' \
    -type f | sort | tail -1)
git -C "$target_root/upstream/cores/Minimig" apply --reverse --check \
    --ignore-whitespace "$minimig_latest_patch"
grep -q '"$bridge_helper" disable' \
    "$target_root/sw/mister-de25-load"
grep -q '"$bridge_helper" enable' \
    "$target_root/sw/mister-de25-load"
grep -q '"$compatibility_helper" --print-digest "$rbf"' \
    "$target_root/sw/mister-de25-load"
grep -q '"$migration_helper" finalize-boot' \
    "$target_root/sw/mister-de25-load"
grep -q 'mister-de25-watchdog-run' \
    "$target_root/sw/mister-de25-load"
grep -q '^modprobe stratix10_soc$' \
    "$target_root/sw/mister-de25-load"
if grep -q 'subsys_debug.fpga_m_master subsys_hps.fpga2hps' \
    "$target_root/ip/create_mister_hps.tcl"; then
    echo "Production HPS generation must not add an unsupported Avalon-to-ACE5 connection" >&2
    exit 1
fi
grep -q 'separate coherent hps_m master' \
    "$target_root/ip/create_mister_hps.tcl"
if ! grep -B1 'add_instance mister_h2f_reset_fanout' \
    "$target_root/ip/create_mister_hps.tcl" | \
    grep -q 'if {!\$legacy_no_vbuf}'; then
    echo "The 078-compatible HPS build must retain the original bridge-reset boundary" >&2
    exit 1
fi
if grep -q 'set legacy_no_vbuf 1' \
    "$target_root/scripts/build-pc110.sh" || \
   grep -q 'DE25_HPS_LEGACY_NO_VBUF' \
    "$target_root/quartus/DE25_MISTER_PC110.qsf"; then
    echo "PC110 must use the common hot-load-compatible HPS interconnect" >&2
    exit 1
fi
grep -A3 'h2f_reset_reset(h2f_reset)' \
    "$target_root/rtl/de25_mister_menu_top.sv" | \
    grep -q 'mister_h2f_bridge_reset_reset(h2f_reset)'
grep -q 'DE25_HPS_RESET_RECOVERY' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'DE25_HPS_RESET_V1_RECOVERY' \
    "$target_root/rtl/de25_mister_menu_top.sv"
grep -q 'VERILOG_MACRO=DE25_HPS_RESET_RECOVERY' \
    "$target_root/scripts/quartus-syn-de25.sh"
grep -q 'MISTER_DE25_WATCHDOG_FAILURE_ACTION' \
    "$target_root/sw/mister-de25-watchdog-run"
grep -q "trap '' HUP INT QUIT TERM" \
    "$target_root/sw/mister-de25-watchdog-run"
grep -q -- '--keeper' \
    "$target_root/sw/mister-de25-watchdog-run"
grep -q 'watchdog keeper service is not running' \
    "$target_root/sw/mister-de25-watchdog-run"
grep -q 'wdctl --settimeout' \
    "$target_root/sw/mister-de25-watchdog-run"
grep -q 'fpga-load.pending' \
    "$target_root/sw/mister-de25-load"
grep -q 'mister-de25-watchdog-run' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'mister-de25-watchdog-run' \
    "$target_root/scripts/make-update-bundle.sh"
grep -q 'mister-de25-watchdog-keeper.service' \
    "$target_root/scripts/make-update-bundle.sh"
grep -q 'mister-de25-watchdog-keeper.service' \
    "$target_root/scripts/prepare-sd-image.sh"
grep -q 'ExecStart=/usr/libexec/mister-de25-watchdog-run --keeper /dev/watchdog0 90 /run/mister-de25-watchdog' \
    "$target_root/systemd/mister-de25-watchdog-keeper.service"
grep -q 'DefaultDependencies=no' \
    "$target_root/systemd/mister-de25-watchdog-keeper.service"
grep -q 'ExecStartPre=.*test\|ExecStartPre=.*watchdog0' \
    "$target_root/systemd/mister-de25-watchdog-keeper.service"
grep -q 'DefaultDependencies=no' \
    "$target_root/systemd/mister-de25-preload.service"
grep -q 'systemd-remount-fs.service' \
    "$target_root/systemd/mister-de25-preload.service"
grep -q 'Requires=mister-de25-watchdog-keeper.service' \
    "$target_root/systemd/mister-de25-preload.service"
grep -q 'Requires=mister-de25-watchdog-keeper.service' \
    "$target_root/systemd/mister-de25-core-request.service"
grep -q 'platform migration is pending' \
    "$target_root/sw/mister-de25-check-rbf"
grep -q 'de25_check_rbf_compatibility(path)' \
    "$target_root/upstream/Main_MiSTer/fpga_io.cpp"
grep -q 'de25_load_rbf_path(path)' \
    "$target_root/upstream/Main_MiSTer/fpga_io.cpp"
grep -q 'ExecStart=/usr/libexec/mister-de25-load /var/lib/mister-de25/boot/menu.rbf' \
    "$target_root/systemd/mister-de25-preload.service"
grep -q 'ExecCondition=/usr/bin/test ! -s /run/mister-de25-selected-core' \
    "$target_root/systemd/mister-de25-preload.service"
grep -q 'TimeoutStartSec=infinity' \
    "$target_root/systemd/mister-de25-preload.service"
grep -q 'Requires=mister-de25-preload.service' \
    "$target_root/systemd/mister.service"
grep -q 'RequiresMountsFor=/media/fat' \
    "$target_root/systemd/mister.service"
if grep -q 'RequiresMountsFor=/media/fat' \
    "$target_root/systemd/mister-de25-platform-migration.path"; then
    echo "Platform migration watcher must not delay the early boot cache" >&2
    exit 1
fi
grep -q 'PathExists=/media/fat/.mister-de25/headless-migration/request' \
    "$target_root/systemd/mister-de25-platform-migration.path"
grep -q 'ExecStart=/usr/libexec/mister-de25-headless-migrate' \
    "$target_root/systemd/mister-de25-platform-migration-request.service"
grep -q 'mister_ddram@a0000000' "$target_root/boot/mister-memory-overlay.dts"
grep -q 'mem=512M' "$target_root/boot/boot-mister.cmd"
if sed -n '/mister_ddram@a0000000 {/,/};/p' \
    "$target_root/boot/mister-memory-overlay.dts" | grep -q 'no-map;'; then
    echo "MiSTer LPDDR reservation must remain in the ARM64 linear map" >&2
    exit 1
fi
echo "PASS: SD image boots Menu before starting ARM64 Main"

"$target_root/scripts/test-platform-migration.sh"
"$target_root/scripts/test-headless-platform-migration.sh"
"$target_root/scripts/test-platform-candidates.sh"
