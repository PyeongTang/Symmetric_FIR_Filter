----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 2025/10/25 02:01:13
-- Design Name: 
-- Module Name: tb_Symmetric_FIR - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

use std.textio.all;
use ieee.std_logic_textio.all;
use work.my_types_pkg.all;

entity tb_Symmetric_FIR is
  --  Port ( );
end tb_Symmetric_FIR;

-- ======================================================================
--  Architecture
-- ======================================================================

architecture Behavioral of tb_Symmetric_FIR is

-- ======================================================================
--  Components
-- ======================================================================

  component Symmetric_FIR is
    generic (
      g_DATA_WIDTH : integer := 16;
      g_NUM_TAPS   : integer := 5; -- N for Direct Form
      g_GUARD_BIT  : integer := 1
    );
    port (
      -- System
      i_clk     : in std_logic;
      i_n_reset : in std_logic;

      -- Input
      i_x_re    : in signed(g_DATA_WIDTH - 1 downto 0);
      i_x_im    : in signed(g_DATA_WIDTH - 1 downto 0);
      i_x_valid : in std_logic;

      -- Coeff
      i_h_re : in t_array_s_n(0 to (g_NUM_TAPS / 2 + g_NUM_TAPS mod 2) - 1)(g_DATA_WIDTH - 1 downto 0);
      i_h_im : in t_array_s_n(0 to (g_NUM_TAPS / 2 + g_NUM_TAPS mod 2) - 1)(g_DATA_WIDTH - 1 downto 0);

      -- Output
      o_y_re    : out signed(g_DATA_WIDTH - 1 downto 0);
      o_y_im    : out signed(g_DATA_WIDTH - 1 downto 0);
      o_y_valid : out std_logic
    );
  end component;

-- ======================================================================
--  Constants
-- ======================================================================

  constant g_NUM_TAPS   : integer := 65;
  constant g_GUARD_BIT  : integer := 1;
  constant g_DATA_WIDTH : integer := 16;

-- ======================================================================
--  Signals
-- ======================================================================

  signal t_clk_period : time      := 10 ns;
  signal RESET_DONE   : std_logic := '0';

  -- System
  signal i_clk     : std_logic := '1';
  signal i_n_reset : std_logic := '0';

  -- Input
  signal i_x_re    : signed(g_DATA_WIDTH - 1 downto 0);
  signal i_x_im    : signed(g_DATA_WIDTH - 1 downto 0);
  signal i_x_valid : std_logic;

  -- Coeff
  signal i_h_re : t_array_s_n(0 to (g_NUM_TAPS / 2 + g_NUM_TAPS mod 2) - 1)(g_DATA_WIDTH - 1 downto 0);
  signal i_h_im : t_array_s_n(0 to (g_NUM_TAPS / 2 + g_NUM_TAPS mod 2) - 1)(g_DATA_WIDTH - 1 downto 0);

  -- Output
  signal o_y_re    : signed(g_DATA_WIDTH - 1 downto 0);
  signal o_y_im    : signed(g_DATA_WIDTH - 1 downto 0);
  signal o_y_valid : std_logic;

-- ======================================================================
--  Functions
-- ======================================================================

  --   File
  file FILT_DATA_IN_TXT           : text open read_mode is "FILT_DATA_IN.txt";
  file Symmetric_FIR_DATA_OUT_TXT : text open write_mode is "Symmetric_FIR_DATA_OUT.txt";

  impure function read_hex_line(
    file f : text;
    width  : integer
  ) return std_logic_vector is
    variable l   : line;
    variable tmp : std_logic_vector(width - 1 downto 0);
  begin
    if endfile(f) then
      tmp := (others => '0');
    else
      readline(f, l);
      hread(l, tmp);
    end if;
    return tmp;
  end function;

-- ======================================================================
--  Architecture Body
-- ======================================================================

begin

-- ======================================================================
--  Instances
-- ======================================================================

  Symmetric_FIR_inst : Symmetric_FIR
  generic map(
    g_DATA_WIDTH => g_DATA_WIDTH,
    g_GUARD_BIT  => g_GUARD_BIT,
    g_NUM_TAPS   => g_NUM_TAPS
  )
  port map
  (
    i_clk     => i_clk,
    i_n_reset => i_n_reset,
    i_x_re    => i_x_re,
    i_x_im    => i_x_im,
    i_x_valid => i_x_valid,
    i_h_re    => i_h_re,
    i_h_im    => i_h_im,
    o_y_re    => o_y_re,
    o_y_im    => o_y_im,
    o_y_valid => o_y_valid
  );

-- ======================================================================
--  Processes
-- ======================================================================

  TOGGLE_CLK : process
  begin
    i_clk <= not i_clk;
    wait for t_clk_period;
  end process; -- TOGGLE_CLK

  ASSERT_RESET : process
  begin
    wait for 7 ns;
    i_n_reset <= '1';
    wait for 7 ns;
    i_n_reset <= '0';
    wait for 7 ns;
    i_n_reset <= '1';
    wait for 7 ns;
    RESET_DONE <= '1';
    wait;
  end process; -- ASSERT_RESET

  IMPULSE_RESPONSE : process
  begin
    wait until RESET_DONE = '1';
    i_x_re    <= x"7FFF";
    i_x_im    <= x"0000";
    i_x_valid <= '1';

    i_h_im <= (others => (others => '0'));

    wait until (rising_edge(i_clk));

    i_x_re    <= x"0000";
    i_x_im    <= x"0000";
    i_x_valid <= '1';

    wait;
  end process; -- IMPULSE_RESPONSE

  READ_FILTER_COEFF : process (i_clk)
  begin
    if not endfile(FILT_DATA_IN_TXT) then
      for i in 0 to (g_NUM_TAPS / 2 + g_NUM_TAPS mod 2) - 1 loop
        i_h_re(i) <= signed(read_hex_line(FILT_DATA_IN_TXT, 16));
      end loop;
    end if;
  end process;

  capture_process : process (i_clk)
    variable l : line;
  begin
    if (rising_edge(i_clk)) then
      if (o_y_valid = '1') then
        hwrite(l, o_y_re);
        writeline(Symmetric_FIR_DATA_OUT_TXT, l);
      end if;
    end if;
  end process; -- capture_process

end Behavioral;
