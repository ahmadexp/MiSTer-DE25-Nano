-- Agilex 5 implementations of the two legacy PC110 dual-port RAM wrappers.
-- Port timing matches rtl/common/bram.vhd, without its Cyclone V family lock.

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity dpram is
    generic (
        addr_width    : integer := 8;
        data_width    : integer := 8;
        mem_init_file : string := " "
    );
    port (
        clock     : in  std_logic;
        address_a : in  std_logic_vector(addr_width-1 downto 0);
        data_a    : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
        enable_a  : in  std_logic := '1';
        wren_a    : in  std_logic := '0';
        q_a       : out std_logic_vector(data_width-1 downto 0);
        cs_a      : in  std_logic := '1';
        address_b : in  std_logic_vector(addr_width-1 downto 0) := (others => '0');
        data_b    : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
        enable_b  : in  std_logic := '1';
        wren_b    : in  std_logic := '0';
        q_b       : out std_logic_vector(data_width-1 downto 0);
        cs_b      : in  std_logic := '1'
    );
end entity;

architecture syn of dpram is
    signal q0 : std_logic_vector(data_width-1 downto 0);
    signal q1 : std_logic_vector(data_width-1 downto 0);
begin
    q_a <= q0 when cs_a = '1' else (others => '1');
    q_b <= q1 when cs_b = '1' else (others => '1');

    ram : altsyncram
        generic map (
            address_reg_b                     => "CLOCK0",
            clock_enable_input_a              => "NORMAL",
            clock_enable_input_b              => "NORMAL",
            clock_enable_output_a             => "BYPASS",
            clock_enable_output_b             => "BYPASS",
            indata_reg_b                      => "CLOCK0",
            intended_device_family            => "Agilex 5",
            lpm_type                          => "altsyncram",
            numwords_a                        => 2**addr_width,
            numwords_b                        => 2**addr_width,
            operation_mode                    => "BIDIR_DUAL_PORT",
            outdata_aclr_a                    => "NONE",
            outdata_aclr_b                    => "NONE",
            outdata_reg_a                     => "UNREGISTERED",
            outdata_reg_b                     => "UNREGISTERED",
            power_up_uninitialized            => "FALSE",
            read_during_write_mode_port_a      => "NEW_DATA_NO_NBE_READ",
            read_during_write_mode_port_b      => "NEW_DATA_NO_NBE_READ",
            init_file                         => mem_init_file,
            widthad_a                         => addr_width,
            widthad_b                         => addr_width,
            width_a                           => data_width,
            width_b                           => data_width,
            width_byteena_a                   => 1,
            width_byteena_b                   => 1,
            wrcontrol_wraddress_reg_b         => "CLOCK0"
        )
        port map (
            address_a => address_a,
            address_b => address_b,
            clock0    => clock,
            clocken0  => enable_a,
            data_a    => data_a,
            data_b    => data_b,
            wren_a    => wren_a and cs_a,
            wren_b    => wren_b and cs_b,
            q_a       => q0,
            q_b       => q1
        );
end architecture;

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity dpram_difclk is
    generic (
        addr_width_a  : integer := 8;
        data_width_a  : integer := 8;
        addr_width_b  : integer := 8;
        data_width_b  : integer := 8;
        mem_init_file : string := " "
    );
    port (
        clk_a     : in  std_logic;
        clk_b     : in  std_logic;
        address_a : in  std_logic_vector(addr_width_a-1 downto 0);
        data_a    : in  std_logic_vector(data_width_a-1 downto 0) := (others => '0');
        enable_a  : in  std_logic := '1';
        wren_a    : in  std_logic := '0';
        q_a       : out std_logic_vector(data_width_a-1 downto 0);
        cs_a      : in  std_logic := '1';
        address_b : in  std_logic_vector(addr_width_b-1 downto 0) := (others => '0');
        data_b    : in  std_logic_vector(data_width_b-1 downto 0) := (others => '0');
        enable_b  : in  std_logic := '1';
        wren_b    : in  std_logic := '0';
        q_b       : out std_logic_vector(data_width_b-1 downto 0);
        cs_b      : in  std_logic := '1'
    );
end entity;

architecture syn of dpram_difclk is
    signal q0 : std_logic_vector(data_width_a-1 downto 0);
    signal q1 : std_logic_vector(data_width_b-1 downto 0);
begin
    q_a <= q0 when cs_a = '1' else (others => '1');
    q_b <= q1 when cs_b = '1' else (others => '1');

    -- Agilex 5 M20Ks do not support two clocks in true dual-port mode.
    -- VGA never writes port B, so replicate the write port into a host-read
    -- copy and a dual-clock video-read copy.
    host_ram : altsyncram
        generic map (
            clock_enable_input_a              => "NORMAL",
            clock_enable_output_a             => "BYPASS",
            intended_device_family            => "Agilex 5",
            lpm_type                          => "altsyncram",
            numwords_a                        => 2**addr_width_a,
            operation_mode                    => "SINGLE_PORT",
            outdata_aclr_a                    => "NONE",
            outdata_reg_a                     => "UNREGISTERED",
            power_up_uninitialized            => "FALSE",
            read_during_write_mode_port_a      => "DONT_CARE",
            init_file                         => mem_init_file,
            widthad_a                         => addr_width_a,
            width_a                           => data_width_a,
            width_byteena_a                   => 1
        )
        port map (
            address_a => address_a,
            clock0    => clk_a,
            clocken0  => enable_a,
            data_a    => data_a,
            wren_a    => wren_a and cs_a,
            q_a       => q0
        );

    video_ram : altsyncram
        generic map (
            address_reg_b                     => "CLOCK1",
            clock_enable_input_a              => "NORMAL",
            clock_enable_input_b              => "NORMAL",
            clock_enable_output_b             => "BYPASS",
            intended_device_family            => "Agilex 5",
            lpm_type                          => "altsyncram",
            numwords_a                        => 2**addr_width_a,
            numwords_b                        => 2**addr_width_b,
            operation_mode                    => "DUAL_PORT",
            outdata_aclr_b                    => "NONE",
            outdata_reg_b                     => "UNREGISTERED",
            power_up_uninitialized            => "FALSE",
            read_during_write_mode_mixed_ports => "DONT_CARE",
            init_file                         => mem_init_file,
            widthad_a                         => addr_width_a,
            widthad_b                         => addr_width_b,
            width_a                           => data_width_a,
            width_b                           => data_width_b,
            width_byteena_a                   => 1
        )
        port map (
            address_a => address_a,
            address_b => address_b,
            clock0    => clk_a,
            clock1    => clk_b,
            clocken0  => enable_a,
            clocken1  => enable_b,
            data_a    => data_a,
            wren_a    => wren_a and cs_a,
            q_b       => q1
        );
end architecture;
