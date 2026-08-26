// Agilex 5-compatible replacements for the legacy Cyclone altsyncram
// wrappers used by the NES core. All mapper instances use a common clock.

module spram #(
    parameter integer addr_width = 8,
    parameter integer data_width = 8,
    parameter string  mem_init_file = " ",
    parameter string  mem_name = "MEM"
) (
    input  logic                  clock,
    input  logic [addr_width-1:0] address,
    input  logic [data_width-1:0] data,
    input  logic                  enable,
    input  logic                  wren,
    output logic [data_width-1:0] q,
    input  logic                  cs
);
    spram_sz #(
        .addr_width(addr_width),
        .data_width(data_width),
        .numwords(1 << addr_width),
        .mem_init_file(mem_init_file),
        .mem_name(mem_name)
    ) impl (.*);
endmodule

module spram_sz #(
    parameter integer addr_width = 8,
    parameter integer data_width = 8,
    parameter integer numwords = 1 << addr_width,
    parameter string  mem_init_file = " ",
    parameter string  mem_name = "MEM"
) (
    input  logic                  clock,
    input  logic [addr_width-1:0] address,
    input  logic [data_width-1:0] data,
    input  logic                  enable,
    input  logic                  wren,
    output logic [data_width-1:0] q,
    input  logic                  cs
);
    logic [data_width-1:0] q_mem;

    generate
        if (mem_init_file == " ") begin : g_uninitialized
            (* ramstyle = "M20K" *) logic [data_width-1:0] mem [0:numwords-1];
            always_ff @(posedge clock) begin
                if (wren && cs) begin
                    mem[address] <= data;
                    q_mem <= data;
                end else begin
                    q_mem <= mem[address];
                end
            end
        end else begin : g_initialized
            (* ramstyle = "M20K", ram_init_file = mem_init_file *)
            logic [data_width-1:0] mem [0:numwords-1];
            always_ff @(posedge clock) begin
                if (wren && cs) begin
                    mem[address] <= data;
                    q_mem <= data;
                end else begin
                    q_mem <= mem[address];
                end
            end
        end
    endgenerate

    always_comb q = cs ? q_mem : {data_width{1'b1}};

    logic _unused;
    always_comb _unused = enable ^ mem_name[0];
endmodule

module dpram #(
    parameter string  init_file = " ",
    parameter integer widthad_a = 8,
    parameter integer width_a = 8,
    parameter string  outdata_reg_a = "UNREGISTERED",
    parameter string  outdata_reg_b = "UNREGISTERED"
) (
    input  logic [widthad_a-1:0] address_a,
    input  logic [widthad_a-1:0] address_b,
    input  logic                 clock_a,
    input  logic                 clock_b,
    input  logic [width_a-1:0]   data_a,
    input  logic [width_a-1:0]   data_b,
    input  logic                 wren_a,
    input  logic                 wren_b,
    input  logic [width_a/8-1:0] byteena_a,
    input  logic [width_a/8-1:0] byteena_b,
    output logic [width_a-1:0]   q_a,
    output logic [width_a-1:0]   q_b
);
    localparam integer BYTE_LANES = width_a / 8;
    localparam integer WORDS = 1 << widthad_a;

    (* ramstyle = "M20K" *)
    logic [width_a-1:0] mem [0:WORDS-1];

    integer lane;
    always_ff @(posedge clock_a) begin
        q_a <= mem[address_a];
        q_b <= mem[address_b];

        if (wren_b) begin
            for (lane = 0; lane < BYTE_LANES; lane = lane + 1) begin
                if (byteena_b[lane]) begin
                    mem[address_b][lane*8 +: 8] <= data_b[lane*8 +: 8];
                    q_b[lane*8 +: 8] <= data_b[lane*8 +: 8];
                    if (address_a == address_b)
                        q_a[lane*8 +: 8] <= data_b[lane*8 +: 8];
                end
            end
        end else if (wren_a) begin
            for (lane = 0; lane < BYTE_LANES; lane = lane + 1) begin
                if (byteena_a[lane]) begin
                    mem[address_a][lane*8 +: 8] <= data_a[lane*8 +: 8];
                    q_a[lane*8 +: 8] <= data_a[lane*8 +: 8];
                    if (address_a == address_b)
                        q_b[lane*8 +: 8] <= data_a[lane*8 +: 8];
                end
            end
        end
    end

    logic _unused;
    always_comb _unused = clock_b ^ init_file[0] ^ outdata_reg_a[0] ^ outdata_reg_b[0];
endmodule
