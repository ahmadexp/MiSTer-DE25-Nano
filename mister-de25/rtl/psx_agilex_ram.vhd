library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity dpram_agilex_tdp_sc is
   generic (
      addr_width : integer := 8;
      data_width : integer := 8
   );
   port (
      clock_a  : in  std_logic;
      clken_a  : in  std_logic := '1';
      address_a: in  std_logic_vector(addr_width - 1 downto 0);
      data_a   : in  std_logic_vector(data_width - 1 downto 0);
      wren_a   : in  std_logic := '0';
      q_a      : out std_logic_vector(data_width - 1 downto 0);
      clock_b  : in  std_logic;
      clken_b  : in  std_logic := '1';
      address_b: in  std_logic_vector(addr_width - 1 downto 0);
      data_b   : in  std_logic_vector(data_width - 1 downto 0) := (others => '0');
      wren_b   : in  std_logic := '0';
      q_b      : out std_logic_vector(data_width - 1 downto 0)
   );
end entity;

architecture rtl of dpram_agilex_tdp_sc is
begin
   -- Agilex 5 M20Ks support true dual-port operation when both ports use the
   -- same clock. Route both port register sets to CLOCK0 so Quartus does not
   -- create the unsupported dual-clock BIDIR_DUAL_PORT configuration.
   ram: altsyncram
   generic map (
      address_reg_b                  => "CLOCK0",
      clock_enable_input_a           => "BYPASS",
      clock_enable_input_b           => "BYPASS",
      clock_enable_output_a          => "BYPASS",
      clock_enable_output_b          => "BYPASS",
      indata_reg_b                   => "CLOCK0",
      intended_device_family         => "Agilex 5",
      lpm_type                       => "altsyncram",
      numwords_a                     => 2**addr_width,
      numwords_b                     => 2**addr_width,
      operation_mode                 => "BIDIR_DUAL_PORT",
      outdata_aclr_a                 => "NONE",
      outdata_aclr_b                 => "NONE",
      outdata_reg_a                  => "UNREGISTERED",
      outdata_reg_b                  => "UNREGISTERED",
      power_up_uninitialized         => "FALSE",
      read_during_write_mode_port_a  => "NEW_DATA_NO_NBE_READ",
      read_during_write_mode_port_b  => "NEW_DATA_NO_NBE_READ",
      width_a                        => data_width,
      width_b                        => data_width,
      width_byteena_a                => 1,
      width_byteena_b                => 1,
      widthad_a                      => addr_width,
      widthad_b                      => addr_width,
      wrcontrol_wraddress_reg_b      => "CLOCK0"
   )
   port map (
      address_a => address_a,
      address_b => address_b,
      clock0    => clock_a,
      data_a    => data_a,
      data_b    => data_b,
      wren_a    => wren_a and clken_a,
      wren_b    => wren_b and clken_b,
      q_a       => q_a,
      q_b       => q_b
   );

   assert clock_a = clock_b
      report "dpram_agilex_tdp_sc requires a common port clock"
      severity warning;
end architecture;

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity dpram_agilex_sdp_ab is
   generic (
      addr_width : integer := 8;
      data_width : integer := 8
   );
   port (
      clock_a  : in  std_logic;
      clken_a  : in  std_logic := '1';
      address_a: in  std_logic_vector(addr_width - 1 downto 0);
      data_a   : in  std_logic_vector(data_width - 1 downto 0);
      wren_a   : in  std_logic := '0';
      q_a      : out std_logic_vector(data_width - 1 downto 0);
      clock_b  : in  std_logic;
      clken_b  : in  std_logic := '1';
      address_b: in  std_logic_vector(addr_width - 1 downto 0);
      data_b   : in  std_logic_vector(data_width - 1 downto 0) := (others => '0');
      wren_b   : in  std_logic := '0';
      q_b      : out std_logic_vector(data_width - 1 downto 0)
   );
end entity;

architecture rtl of dpram_agilex_sdp_ab is
   signal q_a_mem: std_logic_vector(data_width - 1 downto 0);
begin
   -- Port A writes while port B reads in an independent clock domain.
   cross_clock_ram: altsyncram
   generic map (
      address_reg_b                  => "CLOCK1",
      clock_enable_input_a           => "NORMAL",
      clock_enable_input_b           => "NORMAL",
      clock_enable_output_b          => "BYPASS",
      intended_device_family         => "Agilex 5",
      lpm_type                       => "altsyncram",
      numwords_a                     => 2**addr_width,
      numwords_b                     => 2**addr_width,
      operation_mode                 => "DUAL_PORT",
      outdata_aclr_b                 => "NONE",
      outdata_reg_b                  => "UNREGISTERED",
      power_up_uninitialized         => "FALSE",
      read_during_write_mode_mixed_ports => "DONT_CARE",
      width_a                        => data_width,
      width_b                        => data_width,
      width_byteena_a                => 1,
      widthad_a                      => addr_width,
      widthad_b                      => addr_width
   )
   port map (
      address_a => address_a,
      address_b => address_b,
      clock0    => clock_a,
      clock1    => clock_b,
      clocken0  => clken_a,
      clocken1  => clken_b,
      data_a    => data_a,
      wren_a    => wren_a,
      q_b       => q_b
   );

   -- A small mirror supplies the optional readback on the write port. Quartus
   -- removes it when q_a is open, as in the instruction-cache instances.
   write_port_mirror: altsyncram
   generic map (
      clock_enable_input_a           => "NORMAL",
      clock_enable_output_a          => "BYPASS",
      intended_device_family         => "Agilex 5",
      lpm_type                       => "altsyncram",
      numwords_a                     => 2**addr_width,
      operation_mode                 => "SINGLE_PORT",
      outdata_aclr_a                 => "NONE",
      outdata_reg_a                  => "UNREGISTERED",
      power_up_uninitialized         => "FALSE",
      read_during_write_mode_port_a  => "OLD_DATA",
      width_a                        => data_width,
      width_byteena_a                => 1,
      widthad_a                      => addr_width
   )
   port map (
      address_a => address_a,
      clock0    => clock_a,
      clocken0  => clken_a,
      data_a    => data_a,
      wren_a    => wren_a,
      q_a       => q_a_mem
   );

   q_a <= data_a when wren_a = '1' and clken_a = '1' else q_a_mem;

   assert wren_b = '0'
      report "dpram_agilex_sdp_ab ignores writes on read port B"
      severity warning;
end architecture;

library ieee;
use ieee.std_logic_1164.all;

entity dpram_agilex_sdp_ba is
   generic (
      addr_width : integer := 8;
      data_width : integer := 8
   );
   port (
      clock_a  : in  std_logic;
      clken_a  : in  std_logic := '1';
      address_a: in  std_logic_vector(addr_width - 1 downto 0);
      data_a   : in  std_logic_vector(data_width - 1 downto 0);
      wren_a   : in  std_logic := '0';
      q_a      : out std_logic_vector(data_width - 1 downto 0);
      clock_b  : in  std_logic;
      clken_b  : in  std_logic := '1';
      address_b: in  std_logic_vector(addr_width - 1 downto 0);
      data_b   : in  std_logic_vector(data_width - 1 downto 0) := (others => '0');
      wren_b   : in  std_logic := '0';
      q_b      : out std_logic_vector(data_width - 1 downto 0)
   );
end entity;

architecture rtl of dpram_agilex_sdp_ba is
begin
   reversed: entity work.dpram_agilex_sdp_ab
   generic map (
      addr_width => addr_width,
      data_width => data_width
   )
   port map (
      clock_a   => clock_b,
      clken_a   => clken_b,
      address_a => address_b,
      data_a    => data_b,
      wren_a    => wren_b,
      q_a       => q_b,
      clock_b   => clock_a,
      clken_b   => clken_a,
      address_b => address_a,
      data_b    => data_a,
      wren_b    => wren_a,
      q_b       => q_a
   );
end architecture;

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity dpram_agilex_mixed_sdp_ab is
   generic (
      addr_width_a : integer := 8;
      data_width_a : integer := 8;
      addr_width_b : integer := 8;
      data_width_b : integer := 8
   );
   port (
      clock_a  : in  std_logic;
      clken_a  : in  std_logic := '1';
      address_a: in  std_logic_vector(addr_width_a - 1 downto 0);
      data_a   : in  std_logic_vector(data_width_a - 1 downto 0) := (others => '0');
      wren_a   : in  std_logic := '0';
      q_a      : out std_logic_vector(data_width_a - 1 downto 0);
      cs_a     : in  std_logic := '1';
      clock_b  : in  std_logic;
      clken_b  : in  std_logic := '1';
      address_b: in  std_logic_vector(addr_width_b - 1 downto 0) := (others => '0');
      data_b   : in  std_logic_vector(data_width_b - 1 downto 0) := (others => '0');
      wren_b   : in  std_logic := '0';
      q_b      : out std_logic_vector(data_width_b - 1 downto 0);
      cs_b     : in  std_logic := '1'
   );
end entity;

architecture rtl of dpram_agilex_mixed_sdp_ab is
   signal q_b_int: std_logic_vector(data_width_b - 1 downto 0);
begin
   ram: altsyncram
   generic map (
      address_reg_b                  => "CLOCK1",
      clock_enable_input_a           => "NORMAL",
      clock_enable_input_b           => "NORMAL",
      clock_enable_output_b          => "BYPASS",
      intended_device_family         => "Agilex 5",
      lpm_type                       => "altsyncram",
      numwords_a                     => 2**addr_width_a,
      numwords_b                     => 2**addr_width_b,
      operation_mode                 => "DUAL_PORT",
      outdata_aclr_b                 => "NONE",
      outdata_reg_b                  => "UNREGISTERED",
      power_up_uninitialized         => "FALSE",
      read_during_write_mode_mixed_ports => "DONT_CARE",
      width_a                        => data_width_a,
      width_b                        => data_width_b,
      width_byteena_a                => 1,
      widthad_a                      => addr_width_a,
      widthad_b                      => addr_width_b
   )
   port map (
      address_a => address_a,
      address_b => address_b,
      clock0    => clock_a,
      clock1    => clock_b,
      clocken0  => clken_a,
      clocken1  => clken_b,
      data_a    => data_a,
      wren_a    => wren_a and cs_a,
      q_b       => q_b_int
   );

   q_a <= (others => '1') when cs_a = '0' else (others => '0');
   q_b <= q_b_int when cs_b = '1' else (others => '1');

   assert (2**addr_width_a) * data_width_a =
          (2**addr_width_b) * data_width_b
      report "mixed-width RAM ports describe different capacities"
      severity failure;
   assert wren_b = '0'
      report "dpram_agilex_mixed_sdp_ab ignores writes on read port B"
      severity warning;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram_agilex_mixed_tdp_sc is
   generic (
      addr_width_a : integer := 7;
      data_width_a : integer := 64;
      addr_width_b : integer := 9;
      data_width_b : integer := 16
   );
   port (
      clock_a  : in  std_logic;
      clken_a  : in  std_logic := '1';
      address_a: in  std_logic_vector(addr_width_a - 1 downto 0);
      data_a   : in  std_logic_vector(data_width_a - 1 downto 0) := (others => '0');
      wren_a   : in  std_logic := '0';
      q_a      : out std_logic_vector(data_width_a - 1 downto 0);
      cs_a     : in  std_logic := '1';
      clock_b  : in  std_logic;
      clken_b  : in  std_logic := '1';
      address_b: in  std_logic_vector(addr_width_b - 1 downto 0) := (others => '0');
      data_b   : in  std_logic_vector(data_width_b - 1 downto 0) := (others => '0');
      wren_b   : in  std_logic := '0';
      q_b      : out std_logic_vector(data_width_b - 1 downto 0);
      cs_b     : in  std_logic := '1'
   );
end entity;

architecture rtl of dpram_agilex_mixed_tdp_sc is
   constant ratio     : positive := data_width_a / data_width_b;
   constant lane_bits : natural  := addr_width_b - addr_width_a;
   type bank_data is array (0 to ratio - 1) of
      std_logic_vector(data_width_b - 1 downto 0);
   signal bank_q_b: bank_data;
begin
   banks: for lane in 0 to ratio - 1 generate
      signal lane_wren_b: std_logic;
   begin
      lane_wren_b <= wren_b and cs_b when
         to_integer(unsigned(address_b(lane_bits - 1 downto 0))) = lane else '0';

      bank: entity work.dpram_agilex_tdp_sc
      generic map (
         addr_width => addr_width_a,
         data_width => data_width_b
      )
      port map (
         clock_a   => clock_a,
         clken_a   => clken_a,
         address_a => address_a,
         data_a    => data_a(((lane + 1) * data_width_b) - 1 downto lane * data_width_b),
         wren_a    => wren_a and cs_a,
         q_a       => q_a(((lane + 1) * data_width_b) - 1 downto lane * data_width_b),
         clock_b   => clock_b,
         clken_b   => clken_b,
         address_b => address_b(addr_width_b - 1 downto lane_bits),
         data_b    => data_b,
         wren_b    => lane_wren_b,
         q_b       => bank_q_b(lane)
      );
   end generate;

   q_b <= bank_q_b(to_integer(unsigned(address_b(lane_bits - 1 downto 0))))
      when cs_b = '1' else (others => '1');

   assert data_width_a mod data_width_b = 0
      report "mixed true dual-port RAM requires an integral width ratio"
      severity failure;
   assert ratio = 2**lane_bits
      report "mixed true dual-port RAM address and width ratios disagree"
      severity failure;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram_agilex_joypad is
   port (
      clock_a  : in  std_logic;
      address_a: in  std_logic_vector(6 downto 0);
      data_a   : in  std_logic_vector(7 downto 0);
      wren_a   : in  std_logic;
      q_a      : out std_logic_vector(7 downto 0);
      clock_b  : in  std_logic;
      address_b: in  std_logic_vector(3 downto 0);
      data_b   : in  std_logic_vector(63 downto 0);
      wren_b   : in  std_logic;
      q_b      : out std_logic_vector(63 downto 0)
   );
end entity;

architecture rtl of dpram_agilex_joypad is
   type byte_array is array (0 to 7) of std_logic_vector(7 downto 0);
   signal slow_phase: std_logic := '1';
   signal bank_q_a : byte_array;
   signal bank_q_b : byte_array;
   signal bank_wren_a: std_logic_vector(7 downto 0);
begin
   -- clk1x and clk2x are exact 1:2 phase-related PSX PLL outputs. Keep this
   -- tiny mixed-width buffer on clk2x and use eight byte-wide true-dual-port
   -- banks. A local phase bit preserves the clk1x transaction boundary
   -- without sampling a clock as data on their coincident edges.
   process (clock_b)
   begin
      if rising_edge(clock_b) then
         slow_phase <= not slow_phase;
      end if;
   end process;

   banks: for lane in 0 to 7 generate
      bank_wren_a(lane) <= wren_a and slow_phase when
                           to_integer(unsigned(address_a(2 downto 0))) = lane else '0';

      bank: entity work.dpram_agilex_tdp_sc
      generic map (
         addr_width => 4,
         data_width => 8
      )
      port map (
         clock_a   => clock_b,
         address_a => address_a(6 downto 3),
         data_a    => data_a,
         wren_a    => bank_wren_a(lane),
         q_a       => bank_q_a(lane),
         clock_b   => clock_b,
         address_b => address_b,
         data_b    => data_b(((lane + 1) * 8) - 1 downto lane * 8),
         wren_b    => wren_b,
         q_b       => bank_q_b(lane)
      );

      q_b(((lane + 1) * 8) - 1 downto lane * 8) <= bank_q_b(lane);
   end generate;

   q_a <= bank_q_a(to_integer(unsigned(address_a(2 downto 0))));
end architecture;
