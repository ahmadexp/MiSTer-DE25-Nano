# Keep every clock that reaches an HPS I/O bank on the same physical route as
# the Menu image proven on the DE25-Nano. Quartus includes the terminating
# clock spine used by register-packed GPIO in the HPS I/O hash. An otherwise
# equivalent unconstrained fit can therefore produce a phase-2 image that
# Linux cannot load over the installed phase-1 QSPI platform.
#
# These assignments were back-annotated from the timing-clean FDCD Menu fit.
# The build still extracts and compares the generated HPS I/O hash, so these
# placement constraints are necessary for reproducibility but never replace
# the post-assembly compatibility gate.
set_instance_assignment -name CLOCK_REGION "SX0 SY0 SX0 SY0" \
    -to {hps|subsys_hps|agilex_hps|intel_agilex_5_soc_inst|sm_hps|h2f_reset[0]}
set_instance_assignment -name CLOCK_SPINE 29 \
    -to {hps|subsys_hps|agilex_hps|intel_agilex_5_soc_inst|sm_hps|h2f_reset[0]}

set_instance_assignment -name CLOCK_REGION "SX0 SY0 SX1 SY0" \
    -to platform_clocks|system_pll|system_pll|tennm_ph2_iopll~O_OUT_CLK0
set_instance_assignment -name CLOCK_SPINE 24 \
    -to platform_clocks|system_pll|system_pll|tennm_ph2_iopll~O_OUT_CLK0
set_instance_assignment -name CLOCK_REGION "SX1 SY0 SX1 SY0" \
    -to platform_clocks|system_pll|system_pll|tennm_ph2_iopll~O_OUT_CLK1
set_instance_assignment -name CLOCK_SPINE 9 \
    -to platform_clocks|system_pll|system_pll|tennm_ph2_iopll~O_OUT_CLK1
set_instance_assignment -name CLOCK_REGION "SX1 SY0 SX1 SY0" \
    -to platform_clocks|system_pll|system_pll|tennm_ph2_iopll~O_OUT_CLK2
set_instance_assignment -name CLOCK_SPINE 4 \
    -to platform_clocks|system_pll|system_pll|tennm_ph2_iopll~O_OUT_CLK2
set_location_assignment IOPLL_X63_Y0_N91 \
    -to platform_clocks|system_pll|system_pll|tennm_ph2_iopll

set_instance_assignment -name CLOCK_REGION "SX0 SY0 SX1 SY0" \
    -to core|pll|impl|iopll_0|iopll_0|tennm_ph2_iopll~O_OUT_CLK0
set_instance_assignment -name CLOCK_SPINE 30 \
    -to core|pll|impl|iopll_0|iopll_0|tennm_ph2_iopll~O_OUT_CLK0
set_instance_assignment -name CLOCK_REGION "SX1 SY0 SX1 SY0" \
    -to core|pll|impl|iopll_0|iopll_0|tennm_ph2_iopll~O_OUT_CLK1
set_instance_assignment -name CLOCK_SPINE 25 \
    -to core|pll|impl|iopll_0|iopll_0|tennm_ph2_iopll~O_OUT_CLK1
set_instance_assignment -name CLOCK_REGION "SX1 SY0 SX1 SY0" \
    -to core|pll|impl|iopll_0|iopll_0|tennm_ph2_iopll~O_OUT_CLK2
set_instance_assignment -name CLOCK_SPINE 18 \
    -to core|pll|impl|iopll_0|iopll_0|tennm_ph2_iopll~O_OUT_CLK2
set_instance_assignment -name CLOCK_REGION "SX0 SY0 SX1 SY0" \
    -to core|pll|impl|iopll_0|iopll_0|tennm_ph2_iopll~O_OUT_CLK3
set_instance_assignment -name CLOCK_SPINE 27 \
    -to core|pll|impl|iopll_0|iopll_0|tennm_ph2_iopll~O_OUT_CLK3
set_location_assignment IOPLL_X63_Y0_N0 \
    -to core|pll|impl|iopll_0|iopll_0|tennm_ph2_iopll

set_instance_assignment -name CLOCK_REGION "SX1 SY0 SX1 SY0" -to CLOCK0_50
set_instance_assignment -name CLOCK_SPINE 28 -to CLOCK0_50
