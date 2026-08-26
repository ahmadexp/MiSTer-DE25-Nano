-- Agilex 5 implementation of the legacy ao486 single-port RAM wrappers.
-- spram_sz is declared first because Quartus Pro resolves direct VHDL entity
-- references in source order.

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity spram_sz is
    generic (
        addr_width    : integer := 8;
        data_width    : integer := 8;
        numwords      : integer := 2**8;
        mem_init_file : string := " ";
        mem_name      : string := "MEM"
    );
    port (
        clock   : in  std_logic;
        address : in  std_logic_vector(addr_width-1 downto 0);
        data    : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
        enable  : in  std_logic := '1';
        wren    : in  std_logic := '0';
        q       : out std_logic_vector(data_width-1 downto 0);
        cs      : in  std_logic := '1'
    );
end entity;

architecture syn of spram_sz is
    signal q0 : std_logic_vector(data_width-1 downto 0);
begin
    q <= q0 when cs = '1' else (others => '1');

    ram : altsyncram
        generic map (
            clock_enable_input_a         => "NORMAL",
            clock_enable_output_a        => "BYPASS",
            intended_device_family       => "Agilex 5",
            lpm_type                     => "altsyncram",
            numwords_a                   => numwords,
            operation_mode               => "SINGLE_PORT",
            outdata_aclr_a               => "NONE",
            outdata_reg_a                => "UNREGISTERED",
            power_up_uninitialized       => "FALSE",
            read_during_write_mode_port_a => "DONT_CARE",
            init_file                    => mem_init_file,
            widthad_a                    => addr_width,
            width_a                      => data_width,
            width_byteena_a              => 1
        )
        port map (
            address_a => address,
            clock0    => clock,
            clocken0  => enable,
            data_a    => data,
            wren_a    => wren and cs,
            q_a       => q0
        );
end architecture;

library ieee;
use ieee.std_logic_1164.all;

entity spram is
    generic (
        addr_width    : integer := 8;
        data_width    : integer := 8;
        mem_init_file : string := " ";
        mem_name      : string := "MEM"
    );
    port (
        clock   : in  std_logic;
        address : in  std_logic_vector(addr_width-1 downto 0);
        data    : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
        enable  : in  std_logic := '1';
        wren    : in  std_logic := '0';
        q       : out std_logic_vector(data_width-1 downto 0);
        cs      : in  std_logic := '1'
    );
end entity;

architecture syn of spram is
begin
    ram : entity work.spram_sz
        generic map (addr_width, data_width, 2**addr_width, mem_init_file, mem_name)
        port map (clock, address, data, enable, wren, q, cs);
end architecture;
