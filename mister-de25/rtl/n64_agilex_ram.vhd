library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

-- Same-clock true dual-port replacement for the Cyclone V BIDIR_DUAL_PORT
-- memories used by N64. Agilex 5 requires both port register sets on CLOCK0.
-- The held-address muxes retain the original independent clock-enable
-- behavior even though both physical port register sets share that clock.
entity n64_dpram_tdp_sc is
   generic (
      addr_width : integer := 8;
      data_width : integer := 8
   );
   port (
      clock_a   : in  std_logic;
      clken_a   : in  std_logic := '1';
      address_a : in  std_logic_vector(addr_width - 1 downto 0);
      data_a    : in  std_logic_vector(data_width - 1 downto 0);
      wren_a    : in  std_logic := '0';
      q_a       : out std_logic_vector(data_width - 1 downto 0);
      clock_b   : in  std_logic;
      clken_b   : in  std_logic := '1';
      address_b : in  std_logic_vector(addr_width - 1 downto 0);
      data_b    : in  std_logic_vector(data_width - 1 downto 0) := (others => '0');
      wren_b    : in  std_logic := '0';
      q_b       : out std_logic_vector(data_width - 1 downto 0)
   );
end entity;

architecture rtl of n64_dpram_tdp_sc is
   signal held_address_a : std_logic_vector(addr_width - 1 downto 0) := (others => '0');
   signal held_address_b : std_logic_vector(addr_width - 1 downto 0) := (others => '0');
   signal effective_address_a : std_logic_vector(addr_width - 1 downto 0);
   signal effective_address_b : std_logic_vector(addr_width - 1 downto 0);
begin
   process (clock_a)
   begin
      if rising_edge(clock_a) and clken_a = '1' then
         held_address_a <= address_a;
      end if;
   end process;

   process (clock_b)
   begin
      if rising_edge(clock_b) and clken_b = '1' then
         held_address_b <= address_b;
      end if;
   end process;

   effective_address_a <= address_a when clken_a = '1' else held_address_a;
   effective_address_b <= address_b when clken_b = '1' else held_address_b;

   ram: altsyncram
   generic map (
      address_reg_b                 => "CLOCK0",
      clock_enable_input_a          => "BYPASS",
      clock_enable_input_b          => "BYPASS",
      clock_enable_output_a         => "BYPASS",
      clock_enable_output_b         => "BYPASS",
      indata_reg_b                  => "CLOCK0",
      intended_device_family        => "Agilex 5",
      lpm_type                      => "altsyncram",
      numwords_a                    => 2**addr_width,
      numwords_b                    => 2**addr_width,
      operation_mode                => "BIDIR_DUAL_PORT",
      outdata_aclr_a                => "NONE",
      outdata_aclr_b                => "NONE",
      outdata_reg_a                 => "UNREGISTERED",
      outdata_reg_b                 => "UNREGISTERED",
      power_up_uninitialized        => "FALSE",
      read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
      read_during_write_mode_port_b => "NEW_DATA_NO_NBE_READ",
      width_a                       => data_width,
      width_b                       => data_width,
      width_byteena_a               => 1,
      width_byteena_b               => 1,
      widthad_a                     => addr_width,
      widthad_b                     => addr_width,
      wrcontrol_wraddress_reg_b     => "CLOCK0"
   )
   port map (
      address_a => effective_address_a,
      address_b => effective_address_b,
      clock0    => clock_a,
      data_a    => data_a,
      data_b    => data_b,
      wren_a    => wren_a and clken_a,
      wren_b    => wren_b and clken_b,
      q_a       => q_a,
      q_b       => q_b
   );

   assert clock_a = clock_b
      report "n64_dpram_tdp_sc requires a common port clock"
      severity warning;
end architecture;

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

-- Byte-enabled variant of the same-clock true dual-port adapter. This is
-- used for the CPU-domain overlay in the N64 data cache.
entity n64_dpram_tdp_sc_be is
   generic (
      addr_width     : integer := 8;
      data_width     : integer := 32;
      width_byteena  : integer := 4
   );
   port (
      clock_a   : in  std_logic;
      clken_a   : in  std_logic := '1';
      address_a : in  std_logic_vector(addr_width - 1 downto 0);
      data_a    : in  std_logic_vector(data_width - 1 downto 0);
      byteena_a : in  std_logic_vector(width_byteena - 1 downto 0) := (others => '1');
      wren_a    : in  std_logic := '0';
      q_a       : out std_logic_vector(data_width - 1 downto 0);
      clock_b   : in  std_logic;
      clken_b   : in  std_logic := '1';
      address_b : in  std_logic_vector(addr_width - 1 downto 0);
      data_b    : in  std_logic_vector(data_width - 1 downto 0) := (others => '0');
      byteena_b : in  std_logic_vector(width_byteena - 1 downto 0) := (others => '1');
      wren_b    : in  std_logic := '0';
      q_b       : out std_logic_vector(data_width - 1 downto 0)
   );
end entity;

architecture rtl of n64_dpram_tdp_sc_be is
   signal held_address_a : std_logic_vector(addr_width - 1 downto 0) := (others => '0');
   signal held_address_b : std_logic_vector(addr_width - 1 downto 0) := (others => '0');
   signal effective_address_a : std_logic_vector(addr_width - 1 downto 0);
   signal effective_address_b : std_logic_vector(addr_width - 1 downto 0);
begin
   process (clock_a)
   begin
      if rising_edge(clock_a) and clken_a = '1' then
         held_address_a <= address_a;
      end if;
   end process;

   process (clock_b)
   begin
      if rising_edge(clock_b) and clken_b = '1' then
         held_address_b <= address_b;
      end if;
   end process;

   effective_address_a <= address_a when clken_a = '1' else held_address_a;
   effective_address_b <= address_b when clken_b = '1' else held_address_b;

   ram: altsyncram
   generic map (
      address_reg_b                 => "CLOCK0",
      byte_size                     => data_width / width_byteena,
      byteena_reg_b                 => "CLOCK0",
      clock_enable_input_a          => "BYPASS",
      clock_enable_input_b          => "BYPASS",
      clock_enable_output_a         => "BYPASS",
      clock_enable_output_b         => "BYPASS",
      indata_reg_b                  => "CLOCK0",
      intended_device_family        => "Agilex 5",
      lpm_type                      => "altsyncram",
      numwords_a                    => 2**addr_width,
      numwords_b                    => 2**addr_width,
      operation_mode                => "BIDIR_DUAL_PORT",
      outdata_aclr_a                => "NONE",
      outdata_aclr_b                => "NONE",
      outdata_reg_a                 => "UNREGISTERED",
      outdata_reg_b                 => "UNREGISTERED",
      power_up_uninitialized        => "FALSE",
      read_during_write_mode_port_a => "NEW_DATA_WITH_NBE_READ",
      read_during_write_mode_port_b => "NEW_DATA_WITH_NBE_READ",
      width_a                       => data_width,
      width_b                       => data_width,
      width_byteena_a               => width_byteena,
      width_byteena_b               => width_byteena,
      widthad_a                     => addr_width,
      widthad_b                     => addr_width,
      wrcontrol_wraddress_reg_b     => "CLOCK0"
   )
   port map (
      address_a => effective_address_a,
      address_b => effective_address_b,
      byteena_a => byteena_a,
      byteena_b => byteena_b,
      clock0    => clock_a,
      data_a    => data_a,
      data_b    => data_b,
      wren_a    => wren_a and clken_a,
      wren_b    => wren_b and clken_b,
      q_a       => q_a,
      q_b       => q_b
   );

   assert clock_a = clock_b
      report "n64_dpram_tdp_sc_be requires a common port clock"
      severity warning;
end architecture;

library ieee;
use ieee.std_logic_1164.all;

-- Agilex 5 has no dual-clock, dual-writer M20K mode. The N64 data cache has a
-- more specific topology that can be represented exactly: DDR fills write a
-- dual-clock base RAM, CPU writes update a same-clock byte overlay, and one
-- validity bit per byte selects the newest value. Both sides retain one word
-- per clock throughput and CPU write-through behavior.
entity n64_dcache_ram is
   port (
      fill_clock           : in  std_logic;
      fill_address         : in  std_logic_vector(9 downto 0);
      fill_data            : in  std_logic_vector(63 downto 0);
      fill_wren            : in  std_logic;
      cpu_clock            : in  std_logic;
      cpu_address          : in  std_logic_vector(9 downto 0);
      cpu_data             : in  std_logic_vector(63 downto 0);
      cpu_byteena          : in  std_logic_vector(7 downto 0);
      cpu_wren             : in  std_logic;
      invalidate_fill_line : in  std_logic;
      fill_line_address    : in  std_logic_vector(8 downto 0);
      cpu_q                : out std_logic_vector(63 downto 0)
   );
end entity;

architecture rtl of n64_dcache_ram is
   component n64_dpram_sdp_ab is
      generic (
         addr_width : integer := 8;
         data_width : integer := 8
      );
      port (
         clock_a   : in  std_logic;
         clken_a   : in  std_logic := '1';
         address_a : in  std_logic_vector(addr_width - 1 downto 0);
         data_a    : in  std_logic_vector(data_width - 1 downto 0);
         wren_a    : in  std_logic := '0';
         q_a       : out std_logic_vector(data_width - 1 downto 0);
         clock_b   : in  std_logic;
         clken_b   : in  std_logic := '1';
         address_b : in  std_logic_vector(addr_width - 1 downto 0);
         data_b    : in  std_logic_vector(data_width - 1 downto 0) := (others => '0');
         wren_b    : in  std_logic := '0';
         q_b       : out std_logic_vector(data_width - 1 downto 0)
      );
   end component;

   signal base_q       : std_logic_vector(63 downto 0);
   signal overlay_q    : std_logic_vector(63 downto 0);
   signal overlay_valid: std_logic_vector(7 downto 0);
   signal valid_b_address : std_logic_vector(9 downto 0);
   signal valid_b_data : std_logic_vector(0 downto 0);
begin
   base_ram: n64_dpram_sdp_ab
   generic map (
      addr_width => 10,
      data_width => 64
   )
   port map (
      clock_a   => fill_clock,
      address_a => fill_address,
      data_a    => fill_data,
      wren_a    => fill_wren,
      q_a       => open,
      clock_b   => cpu_clock,
      address_b => cpu_address,
      data_b    => (others => '0'),
      wren_b    => '0',
      q_b       => base_q
   );

   overlay_ram: entity work.n64_dpram_tdp_sc_be
   generic map (
      addr_width    => 10,
      data_width    => 64,
      width_byteena => 8
   )
   port map (
      clock_a   => cpu_clock,
      address_a => cpu_address,
      data_a    => (others => '0'),
      byteena_a => (others => '1'),
      wren_a    => '0',
      q_a       => open,
      clock_b   => cpu_clock,
      address_b => cpu_address,
      data_b    => cpu_data,
      byteena_b => cpu_byteena,
      wren_b    => cpu_wren,
      q_b       => overlay_q
   );

   -- A fill replaces both 64-bit words in one cache line. The two true-dual
   -- ports clear both validity words on the first FILL cycle. During normal
   -- operation port B independently marks only bytes written by the CPU.
   valid_b_address <= fill_line_address & '1' when invalidate_fill_line = '1'
                      else cpu_address;
   valid_b_data <= "0" when invalidate_fill_line = '1' else "1";

   valid_lanes: for lane in 0 to 7 generate
      valid_ram: entity work.n64_dpram_tdp_sc
      generic map (
         addr_width => 10,
         data_width => 1
      )
      port map (
         clock_a   => cpu_clock,
         address_a => fill_line_address & '0',
         data_a    => "0",
         wren_a    => invalidate_fill_line,
         q_a       => open,
         clock_b   => cpu_clock,
         address_b => valid_b_address,
         data_b    => valid_b_data,
         wren_b    => invalidate_fill_line or (cpu_wren and cpu_byteena(lane)),
         q_b(0)    => overlay_valid(lane)
      );

      cpu_q(((lane + 1) * 8) - 1 downto lane * 8) <=
         overlay_q(((lane + 1) * 8) - 1 downto lane * 8)
            when overlay_valid(lane) = '1' else
         base_q(((lane + 1) * 8) - 1 downto lane * 8);
   end generate;
end architecture;

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

-- Dual-clock simple dual-port RAM. Port A is the writer and port B is the
-- reader. A single-port mirror preserves the optional port-A readback.
entity n64_dpram_sdp_ab is
   generic (
      addr_width : integer := 8;
      data_width : integer := 8
   );
   port (
      clock_a   : in  std_logic;
      clken_a   : in  std_logic := '1';
      address_a : in  std_logic_vector(addr_width - 1 downto 0);
      data_a    : in  std_logic_vector(data_width - 1 downto 0);
      wren_a    : in  std_logic := '0';
      q_a       : out std_logic_vector(data_width - 1 downto 0);
      clock_b   : in  std_logic;
      clken_b   : in  std_logic := '1';
      address_b : in  std_logic_vector(addr_width - 1 downto 0);
      data_b    : in  std_logic_vector(data_width - 1 downto 0) := (others => '0');
      wren_b    : in  std_logic := '0';
      q_b       : out std_logic_vector(data_width - 1 downto 0)
   );
end entity;

architecture rtl of n64_dpram_sdp_ab is
   signal q_a_mem : std_logic_vector(data_width - 1 downto 0);
begin
   cross_clock_ram: altsyncram
   generic map (
      address_reg_b                 => "CLOCK1",
      clock_enable_input_a          => "NORMAL",
      clock_enable_input_b          => "NORMAL",
      clock_enable_output_b         => "BYPASS",
      intended_device_family        => "Agilex 5",
      lpm_type                      => "altsyncram",
      numwords_a                    => 2**addr_width,
      numwords_b                    => 2**addr_width,
      operation_mode                => "DUAL_PORT",
      outdata_aclr_b                => "NONE",
      outdata_reg_b                 => "UNREGISTERED",
      power_up_uninitialized        => "FALSE",
      read_during_write_mode_mixed_ports => "DONT_CARE",
      width_a                       => data_width,
      width_b                       => data_width,
      width_byteena_a               => 1,
      widthad_a                     => addr_width,
      widthad_b                     => addr_width
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

   write_port_mirror: altsyncram
   generic map (
      clock_enable_input_a          => "NORMAL",
      clock_enable_output_a         => "BYPASS",
      intended_device_family        => "Agilex 5",
      lpm_type                      => "altsyncram",
      numwords_a                    => 2**addr_width,
      operation_mode                => "SINGLE_PORT",
      outdata_aclr_a                => "NONE",
      outdata_reg_a                 => "UNREGISTERED",
      power_up_uninitialized        => "FALSE",
      read_during_write_mode_port_a => "OLD_DATA",
      width_a                       => data_width,
      width_byteena_a               => 1,
      widthad_a                     => addr_width
   )
   port map (
      address_a => address_a,
      clock0    => clock_a,
      clocken0  => clken_a,
      data_a    => data_a,
      wren_a    => wren_a,
      q_a       => q_a_mem
   );

   -- Agilex 5 single-port M20Ks do not expose the Cyclone V NEW_DATA mode.
   -- The explicit bypass retains the original write-through port-A result.
   q_a <= data_a when wren_a = '1' and clken_a = '1' else q_a_mem;

   assert wren_b = '0'
      report "n64_dpram_sdp_ab ignores writes on read port B"
      severity warning;
end architecture;

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity n64_dpram_mixed_sdp_ab is
   generic (
      addr_width_a : integer := 8;
      data_width_a : integer := 8;
      addr_width_b : integer := 8;
      data_width_b : integer := 8
   );
   port (
      clock_a   : in  std_logic;
      address_a : in  std_logic_vector(addr_width_a - 1 downto 0);
      data_a    : in  std_logic_vector(data_width_a - 1 downto 0) := (others => '0');
      clken_a   : in  std_logic := '1';
      wren_a    : in  std_logic := '0';
      q_a       : out std_logic_vector(data_width_a - 1 downto 0);
      cs_a      : in  std_logic := '1';
      clock_b   : in  std_logic;
      address_b : in  std_logic_vector(addr_width_b - 1 downto 0) := (others => '0');
      data_b    : in  std_logic_vector(data_width_b - 1 downto 0) := (others => '0');
      clken_b   : in  std_logic := '1';
      wren_b    : in  std_logic := '0';
      q_b       : out std_logic_vector(data_width_b - 1 downto 0);
      cs_b      : in  std_logic := '1'
   );
end entity;

architecture rtl of n64_dpram_mixed_sdp_ab is
   signal q_a_int : std_logic_vector(data_width_a - 1 downto 0);
   signal q_b_int : std_logic_vector(data_width_b - 1 downto 0);
begin
   cross_clock_ram: altsyncram
   generic map (
      address_reg_b                 => "CLOCK1",
      clock_enable_input_a          => "NORMAL",
      clock_enable_input_b          => "NORMAL",
      clock_enable_output_b         => "BYPASS",
      intended_device_family        => "Agilex 5",
      lpm_type                      => "altsyncram",
      numwords_a                    => 2**addr_width_a,
      numwords_b                    => 2**addr_width_b,
      operation_mode                => "DUAL_PORT",
      outdata_aclr_b                => "NONE",
      outdata_reg_b                 => "UNREGISTERED",
      power_up_uninitialized        => "FALSE",
      read_during_write_mode_mixed_ports => "DONT_CARE",
      width_a                       => data_width_a,
      width_b                       => data_width_b,
      width_byteena_a               => 1,
      widthad_a                     => addr_width_a,
      widthad_b                     => addr_width_b
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

   write_port_mirror: altsyncram
   generic map (
      clock_enable_input_a          => "NORMAL",
      clock_enable_output_a         => "BYPASS",
      intended_device_family        => "Agilex 5",
      lpm_type                      => "altsyncram",
      numwords_a                    => 2**addr_width_a,
      operation_mode                => "SINGLE_PORT",
      outdata_aclr_a                => "NONE",
      outdata_reg_a                 => "UNREGISTERED",
      power_up_uninitialized        => "FALSE",
      read_during_write_mode_port_a => "OLD_DATA",
      width_a                       => data_width_a,
      width_byteena_a               => 1,
      widthad_a                     => addr_width_a
   )
   port map (
      address_a => address_a,
      clock0    => clock_a,
      clocken0  => clken_a,
      data_a    => data_a,
      wren_a    => wren_a and cs_a,
      q_a       => q_a_int
   );

   q_a <= data_a when cs_a = '1' and clken_a = '1' and wren_a = '1' else
          q_a_int when cs_a = '1' else (others => '1');
   q_b <= q_b_int when cs_b = '1' else (others => '1');

   assert (2**addr_width_a) * data_width_a =
          (2**addr_width_b) * data_width_b
      report "N64 mixed-width RAM ports describe different capacities"
      severity failure;
   assert wren_b = '0'
      report "n64_dpram_mixed_sdp_ab ignores writes on read port B"
      severity warning;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity n64_dpram_mixed_tdp_sc is
   generic (
      addr_width_a : integer := 7;
      data_width_a : integer := 64;
      addr_width_b : integer := 9;
      data_width_b : integer := 16
   );
   port (
      clock_a   : in  std_logic;
      address_a : in  std_logic_vector(addr_width_a - 1 downto 0);
      data_a    : in  std_logic_vector(data_width_a - 1 downto 0) := (others => '0');
      clken_a   : in  std_logic := '1';
      wren_a    : in  std_logic := '0';
      q_a       : out std_logic_vector(data_width_a - 1 downto 0);
      cs_a      : in  std_logic := '1';
      clock_b   : in  std_logic;
      address_b : in  std_logic_vector(addr_width_b - 1 downto 0) := (others => '0');
      data_b    : in  std_logic_vector(data_width_b - 1 downto 0) := (others => '0');
      clken_b   : in  std_logic := '1';
      wren_b    : in  std_logic := '0';
      q_b       : out std_logic_vector(data_width_b - 1 downto 0);
      cs_b      : in  std_logic := '1'
   );
end entity;

architecture rtl of n64_dpram_mixed_tdp_sc is
   constant ratio     : positive := data_width_a / data_width_b;
   constant lane_bits : natural  := addr_width_b - addr_width_a;
   type bank_data is array (0 to ratio - 1) of
      std_logic_vector(data_width_b - 1 downto 0);
   signal bank_q_a : bank_data;
   signal bank_q_b : bank_data;
   signal selected_lane_b : natural range 0 to ratio - 1 := 0;
begin
   process (clock_b)
   begin
      if rising_edge(clock_b) and clken_b = '1' then
         selected_lane_b <= to_integer(unsigned(address_b(lane_bits - 1 downto 0)));
      end if;
   end process;

   banks: for lane in 0 to ratio - 1 generate
      signal lane_wren_b : std_logic;
   begin
      lane_wren_b <= wren_b and cs_b when
         to_integer(unsigned(address_b(lane_bits - 1 downto 0))) = lane else '0';

      bank: entity work.n64_dpram_tdp_sc
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
         q_a       => bank_q_a(lane),
         clock_b   => clock_b,
         clken_b   => clken_b,
         address_b => address_b(addr_width_b - 1 downto lane_bits),
         data_b    => data_b,
         wren_b    => lane_wren_b,
         q_b       => bank_q_b(lane)
      );
   end generate;

   assemble_a: for lane in 0 to ratio - 1 generate
      q_a(((lane + 1) * data_width_b) - 1 downto lane * data_width_b) <=
         bank_q_a(lane) when cs_a = '1' else (others => '1');
   end generate;
   q_b <= bank_q_b(selected_lane_b) when cs_b = '1' else (others => '1');

   assert data_width_a mod data_width_b = 0
      report "N64 mixed true dual-port RAM requires an integral width ratio"
      severity failure;
   assert ratio = 2**lane_bits
      report "N64 mixed true dual-port RAM address and width ratios disagree"
      severity failure;
end architecture;

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

-- Byte-enabled mixed-width simple dual-port RAM used by RSP IMEM. Its read
-- port never writes, so an Agilex DUAL_PORT plus a byte-enabled A-port mirror
-- preserves both visible read ports without unsupported bidirectional mode.
entity n64_dpram_mixed_sdp_ab_be is
   generic (
      addr_width_a    : integer := 8;
      data_width_a    : integer := 8;
      addr_width_b    : integer := 8;
      data_width_b    : integer := 8;
      width_byteena_a : integer := 1;
      width_byteena_b : integer := 1
   );
   port (
      clock_a   : in  std_logic;
      address_a : in  std_logic_vector(addr_width_a - 1 downto 0);
      data_a    : in  std_logic_vector(data_width_a - 1 downto 0) := (others => '0');
      clken_a   : in  std_logic := '1';
      byteena_a : in  std_logic_vector(width_byteena_a - 1 downto 0) := (others => '1');
      wren_a    : in  std_logic := '0';
      q_a       : out std_logic_vector(data_width_a - 1 downto 0);
      cs_a      : in  std_logic := '1';
      clock_b   : in  std_logic;
      address_b : in  std_logic_vector(addr_width_b - 1 downto 0) := (others => '0');
      data_b    : in  std_logic_vector(data_width_b - 1 downto 0) := (others => '0');
      clken_b   : in  std_logic := '1';
      byteena_b : in  std_logic_vector(width_byteena_b - 1 downto 0) := (others => '1');
      wren_b    : in  std_logic := '0';
      q_b       : out std_logic_vector(data_width_b - 1 downto 0);
      cs_b      : in  std_logic := '1'
   );
end entity;

architecture rtl of n64_dpram_mixed_sdp_ab_be is
   signal q_a_int : std_logic_vector(data_width_a - 1 downto 0);
   signal q_b_int : std_logic_vector(data_width_b - 1 downto 0);
   signal q_a_write_through : std_logic_vector(data_width_a - 1 downto 0);
begin
   cross_clock_ram: altsyncram
   generic map (
      address_reg_b                 => "CLOCK1",
      clock_enable_input_a          => "NORMAL",
      clock_enable_input_b          => "NORMAL",
      clock_enable_output_b         => "BYPASS",
      intended_device_family        => "Agilex 5",
      lpm_type                      => "altsyncram",
      numwords_a                    => 2**addr_width_a,
      numwords_b                    => 2**addr_width_b,
      operation_mode                => "DUAL_PORT",
      outdata_aclr_b                => "NONE",
      outdata_reg_b                 => "UNREGISTERED",
      power_up_uninitialized        => "FALSE",
      read_during_write_mode_mixed_ports => "DONT_CARE",
      width_a                       => data_width_a,
      width_b                       => data_width_b,
      width_byteena_a               => width_byteena_a,
      widthad_a                     => addr_width_a,
      widthad_b                     => addr_width_b
   )
   port map (
      address_a => address_a,
      address_b => address_b,
      byteena_a => byteena_a,
      clock0    => clock_a,
      clock1    => clock_b,
      clocken0  => clken_a,
      clocken1  => clken_b,
      data_a    => data_a,
      wren_a    => wren_a and cs_a,
      q_b       => q_b_int
   );

   write_port_mirror: altsyncram
   generic map (
      clock_enable_input_a          => "NORMAL",
      clock_enable_output_a         => "BYPASS",
      intended_device_family        => "Agilex 5",
      lpm_type                      => "altsyncram",
      numwords_a                    => 2**addr_width_a,
      operation_mode                => "SINGLE_PORT",
      outdata_aclr_a                => "NONE",
      outdata_reg_a                 => "UNREGISTERED",
      power_up_uninitialized        => "FALSE",
      read_during_write_mode_port_a => "OLD_DATA",
      width_a                       => data_width_a,
      width_byteena_a               => width_byteena_a,
      widthad_a                     => addr_width_a
   )
   port map (
      address_a => address_a,
      byteena_a => byteena_a,
      clock0    => clock_a,
      clocken0  => clken_a,
      data_a    => data_a,
      wren_a    => wren_a and cs_a,
      q_a       => q_a_int
   );

   process (all)
      variable merged : std_logic_vector(data_width_a - 1 downto 0);
      constant lane_width : positive := data_width_a / width_byteena_a;
   begin
      merged := q_a_int;
      for lane in 0 to width_byteena_a - 1 loop
         if byteena_a(lane) = '1' then
            merged(((lane + 1) * lane_width) - 1 downto lane * lane_width) :=
               data_a(((lane + 1) * lane_width) - 1 downto lane * lane_width);
         end if;
      end loop;
      q_a_write_through <= merged;
   end process;

   q_a <= q_a_write_through when
             cs_a = '1' and clken_a = '1' and wren_a = '1' else
          q_a_int when cs_a = '1' else (others => '1');
   q_b <= q_b_int when cs_b = '1' else (others => '1');

   assert (2**addr_width_a) * data_width_a =
          (2**addr_width_b) * data_width_b
      report "N64 byte-enabled RAM ports describe different capacities"
      severity failure;
   assert wren_b = '0'
      report "n64_dpram_mixed_sdp_ab_be ignores writes on read port B"
      severity warning;
end architecture;
