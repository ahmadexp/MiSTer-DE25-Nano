// Minimal behavioral model for the altsyncram configuration used by the
// TurboGrafx16 Agilex mixed-width compatibility RAM. This is intentionally
// not a general replacement for the Quartus simulation library.
module altsyncram #(
    parameter address_reg_b = "CLOCK0",
    parameter integer byte_size = 8,
    parameter clock_enable_input_a = "BYPASS",
    parameter clock_enable_input_b = "BYPASS",
    parameter clock_enable_output_a = "BYPASS",
    parameter clock_enable_output_b = "BYPASS",
    parameter indata_reg_b = "CLOCK0",
    parameter init_file = " ",
    parameter intended_device_family = "Agilex 5",
    parameter lpm_type = "altsyncram",
    parameter integer numwords_a = 1,
    parameter integer numwords_b = 1,
    parameter operation_mode = "BIDIR_DUAL_PORT",
    parameter outdata_aclr_a = "NONE",
    parameter outdata_aclr_b = "NONE",
    parameter outdata_reg_a = "UNREGISTERED",
    parameter outdata_reg_b = "UNREGISTERED",
    parameter power_up_uninitialized = "FALSE",
    parameter read_during_write_mode_port_a = "DONT_CARE",
    parameter read_during_write_mode_port_b = "DONT_CARE",
    parameter integer widthad_a = 1,
    parameter integer widthad_b = 1,
    parameter integer width_a = 1,
    parameter integer width_b = 1,
    parameter integer width_byteena_a = 1,
    parameter integer width_byteena_b = 1,
    parameter wrcontrol_wraddress_reg_b = "CLOCK0"
) (
    input  wire [widthad_a-1:0]       address_a,
    input  wire [widthad_b-1:0]       address_b,
    input  wire [width_byteena_a-1:0] byteena_a,
    input  wire [width_byteena_b-1:0] byteena_b,
    input  wire                       clock0,
    input  wire                       clock1,
    input  wire [width_a-1:0]         data_a,
    input  wire [width_b-1:0]         data_b,
    input  wire                       wren_a,
    input  wire                       wren_b,
    output wire [width_a-1:0]         q_a,
    output wire [width_b-1:0]         q_b
);

logic [width_a-1:0] memory [0:numwords_a-1];
logic [widthad_b-1:0] registered_address_b;
localparam integer lane_width = width_a / width_byteena_a;
integer lane;

initial begin
    for (lane = 0; lane < numwords_a; lane = lane + 1)
        memory[lane] = '0;
end

always_ff @(posedge clock0) begin
    registered_address_b <= address_b;
    if (wren_a)
        for (lane = 0; lane < width_byteena_a; lane = lane + 1)
            if (byteena_a[lane])
                memory[address_a][lane*lane_width +: lane_width] <=
                    data_a[lane*lane_width +: lane_width];
    if (wren_b)
        for (lane = 0; lane < width_byteena_b; lane = lane + 1)
            if (byteena_b[lane])
                memory[address_b][lane*lane_width +: lane_width] <=
                    data_b[lane*lane_width +: lane_width];
end

assign q_a = memory[address_a];
assign q_b = memory[registered_address_b];

endmodule
