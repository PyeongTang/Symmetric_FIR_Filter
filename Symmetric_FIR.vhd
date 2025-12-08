----------------------------------------------------------------------------------
-- Company: 
-- Engineer: JPLEE
-- 
-- Create Date: 2025/10/23 22:42:57
-- Design Name: 
-- Module Name: Symmetric_FIR - Behavioral
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

-- =======================================================================
-- Symmetric FIR Filter consists 3 components
--  1. FIRST_TAP : Prev-Acc value tied to 0, its filter coeff. has very first and last value
--  2. EVEN_TAPS : Inner taps except to middle one, input path and accumulation path enabled
--  3. ODD_TAP : Middle tap for odd-numbered filter, input delay path disabled and tied to 0 for its value
-- =======================================================================

use work.my_types_pkg.all;
entity Symmetric_FIR is
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
    i_h_re : in t_array_s16(0 to (g_NUM_TAPS / 2 + g_NUM_TAPS mod 2) - 1);
    i_h_im : in t_array_s16(0 to (g_NUM_TAPS / 2 + g_NUM_TAPS mod 2) - 1);

    -- Output
    o_y_re    : out signed(g_DATA_WIDTH - 1 downto 0);
    o_y_im    : out signed(g_DATA_WIDTH - 1 downto 0);
    o_y_valid : out std_logic
  );
end Symmetric_FIR;

-- =======================================================================
--  Architecture
-- =======================================================================

architecture Behavioral of Symmetric_FIR is

  -- =======================================================================
  --  Components
  -- =======================================================================

  component Symmetric_FIR_single_tap is
    generic (
      g_DATA_WIDTH : integer := 16;
      g_GUARD_BIT  : integer := 1
    );
    port (
      -- System
      i_clk     : in std_logic;
      i_n_reset : in std_logic;

      -- Input fed from previous tap
      i_x_re    : in signed(g_DATA_WIDTH - 1 downto 0);
      i_x_im    : in signed(g_DATA_WIDTH - 1 downto 0);
      i_x_valid : in std_logic;

      -- Delayed input fed globally
      i_xz_re    : in signed(g_DATA_WIDTH - 1 downto 0);
      i_xz_im    : in signed(g_DATA_WIDTH - 1 downto 0);
      i_xz_valid : in std_logic;

      -- Input feed to next tap
      o_xz_re    : out signed(g_DATA_WIDTH - 1 downto 0);
      o_xz_im    : out signed(g_DATA_WIDTH - 1 downto 0);
      o_xz_valid : out std_logic;

      -- Coefficient
      i_h_re    : in signed(g_DATA_WIDTH - 1 downto 0);
      i_h_im    : in signed(g_DATA_WIDTH - 1 downto 0);
      i_h_valid : in std_logic;

      -- Fed from Previous Tap
      i_yz_re    : in signed((g_DATA_WIDTH + 1) * 2 + 2 + g_GUARD_BIT - 1 downto 0); -- 16b -> Adder -> 17b -> Mult -> 36b -> Guard -> 37b
      i_yz_im    : in signed((g_DATA_WIDTH + 1) * 2 + 2 + g_GUARD_BIT - 1 downto 0);
      i_yz_valid : in std_logic;

      -- Accumulation
      o_y_re    : out signed((g_DATA_WIDTH + 1) * 2 + 2 + g_GUARD_BIT - 1 downto 0);
      o_y_im    : out signed((g_DATA_WIDTH + 1) * 2 + 2 + g_GUARD_BIT - 1 downto 0);
      o_y_valid : out std_logic
    );
  end component;

  -- =======================================================================
  --  Constants
  -- =======================================================================

  constant c_ODD_TAP_ENABLE    : boolean := (g_NUM_TAPS mod 2 = 1);
  constant c_NUM_INPUT_DELAY   : integer := g_NUM_TAPS - 1;
  constant c_NUM_EVEN_TAP      : integer := g_NUM_TAPS / 2;
  constant c_PRE_ADDER_WIDTH   : integer := g_DATA_WIDTH + 1;
  constant c_MULT_WIDTH        : integer := (c_PRE_ADDER_WIDTH + 1) * 2;
  constant c_OUTPUT_DATA_WIDTH : integer := c_MULT_WIDTH + g_GUARD_BIT;

  -- =======================================================================
  --  Signals
  -- =======================================================================

  -- Input Data Delay (global, (nTAP - 1)-clk delayed) to ALL EVEN Tap
  signal r_x_re_input_delay_shift_register  : t_array_s_n(0 to g_NUM_TAPS - 1)(g_DATA_WIDTH - 1 downto 0);
  signal r_x_im_input_delay_shift_register  : t_array_s_n(0 to g_NUM_TAPS - 1)(g_DATA_WIDTH - 1 downto 0);
  signal r_valid_input_delay_shift_register : t_array_sl(0 to g_NUM_TAPS - 1);

  signal w_xz_input_delay_re    : signed(g_DATA_WIDTH - 1 downto 0) := (others => '0'); -- Z6, if nTAP = 7
  signal w_xz_input_delay_im    : signed(g_DATA_WIDTH - 1 downto 0) := (others => '0'); -- Z6, if nTAP = 7
  signal w_xz_input_delay_valid : std_logic                         := '0';

  -- Symmetry Delay (bypass, 2-clk delayed) to NEXT EVEN Tap
  signal w_xz_symmetry_delay_re    : t_array_s_n(0 to c_NUM_EVEN_TAP - 1)(g_DATA_WIDTH - 1 downto 0) := (others => (others => '0')); -- Z2
  signal w_xz_symmetry_delay_im    : t_array_s_n(0 to c_NUM_EVEN_TAP - 1)(g_DATA_WIDTH - 1 downto 0) := (others => (others => '0')); -- Z2
  signal w_xz_symmetry_delay_valid : t_array_sl(0 to c_NUM_EVEN_TAP - 1)                             := (others => '0');

  -- Accumulation
  signal w_y_re    : t_array_s_n(0 to c_NUM_EVEN_TAP - 1)(g_OUTPUT_DATA_WIDTH - 1 downto 0) := (others => (others => '0'));
  signal w_y_im    : t_array_s_n(0 to c_NUM_EVEN_TAP - 1)(g_OUTPUT_DATA_WIDTH - 1 downto 0) := (others => (others => '0'));
  signal w_y_valid : t_array_sl(0 to c_NUM_EVEN_TAP - 1)                                    := (others => '0');

  -- Accumulation of ODD Tap (Last Tap)
  signal w_odd_y_re    : signed(c_OUTPUT_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal w_odd_y_im    : signed(c_OUTPUT_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal w_odd_y_valid : std_logic                                := '0';

  signal w_y_re_selected    : signed(c_OUTPUT_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal w_y_im_selected    : signed(c_OUTPUT_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal w_y_valid_selected : std_logic                                := '0';

  -- =======================================================================
  --  Architecture Body
  -- =======================================================================

begin

  -- =======================================================================
  --  Output Buffering
  -- =======================================================================

  o_y_re    <= w_y_re_selected(c_OUTPUT_DATA_WIDTH - 1 - 5 - g_GUARD_BIT downto (g_DATA_WIDTH - 1)); -- Output Data Truncation, Overhead from addition, multiplication, guarding
  o_y_im    <= w_y_im_selected(c_OUTPUT_DATA_WIDTH - 1 - 5 - g_GUARD_BIT downto (g_DATA_WIDTH - 1));
  o_y_valid <= w_y_valid_selected;

  -- =======================================================================
  --  Wiring
  -- =======================================================================

  -- Shift Register for Input Delay
  w_xz_input_delay_re    <= r_x_re_input_delay_shift_register(c_NUM_INPUT_DELAY - 1); -- Highest Index of shift register
  w_xz_input_delay_im    <= r_x_im_input_delay_shift_register(c_NUM_INPUT_DELAY - 1); -- Highest Index of shift register
  w_xz_input_delay_valid <= r_valid_input_delay_shift_register(c_NUM_INPUT_DELAY - 1); -- Highest Index of shift register

  -- Accumulation Result Selection, Multiplexing Accumulated Data between EVEN tap and ODD tap
  w_y_re_selected <= w_y_re(c_NUM_EVEN_TAP - 1) when (c_ODD_TAP_ENABLE = FALSE) else
    w_odd_y_re; -- 
  w_y_im_selected <= w_y_im(c_NUM_EVEN_TAP - 1) when (c_ODD_TAP_ENABLE = FALSE) else
    w_odd_y_im;
  w_y_valid_selected <= w_y_valid(c_NUM_EVEN_TAP - 1) when (c_ODD_TAP_ENABLE = FALSE) else
    w_odd_y_valid;

  -- =======================================================================
  --  Instances
  -- =======================================================================

  FIRST_TAP : Symmetric_FIR_single_tap
    generic map(
      g_DATA_WIDTH => g_DATA_WIDTH,
      g_GUARD_BIT  => g_GUARD_BIT
    )
    port map
    (
      i_clk      => i_clk,
      i_n_reset  => i_n_reset,
      i_x_re     => i_x_re,
      i_x_im     => i_x_im,
      i_x_valid  => i_x_valid,
      i_xz_re    => w_xz_input_delay_re,
      i_xz_im    => w_xz_input_delay_im,
      i_xz_valid => w_xz_input_delay_valid,
      o_xz_re    => w_xz_symmetry_delay_re(0),
      o_xz_im    => w_xz_symmetry_delay_im(0),
      o_xz_valid => w_xz_symmetry_delay_valid(0),
      i_h_re     => i_h_re(0),
      i_h_im     => i_h_im(0),
      i_h_valid  => '1',
      i_yz_re => (others => '0'),
      i_yz_im => (others => '0'),
      i_yz_valid => '1',
      o_y_re     => w_y_re(0),
      o_y_im     => w_y_im(0),
      o_y_valid  => w_y_valid(0)
  );

  EVEN_TAPS : if (c_NUM_EVEN_TAP > 1) generate
      TAPS : for i in 1 to c_NUM_EVEN_TAP - 1 generate
        Symmetric_FIR_TAP : Symmetric_FIR_single_tap
        generic map(
          g_DATA_WIDTH => g_DATA_WIDTH,
          g_GUARD_BIT  => g_GUARD_BIT
        )
        port map
        (
          i_clk      => i_clk,
          i_n_reset  => i_n_reset,
          i_x_re     => w_xz_symmetry_delay_re(i - 1),
          i_x_im     => w_xz_symmetry_delay_im(i - 1),
          i_x_valid  => w_xz_symmetry_delay_valid(i - 1),
          i_xz_re    => w_xz_input_delay_re,
          i_xz_im    => w_xz_input_delay_im,
          i_xz_valid => w_xz_input_delay_valid,
          o_xz_re    => w_xz_symmetry_delay_re(i),
          o_xz_im    => w_xz_symmetry_delay_im(i),
          o_xz_valid => w_xz_symmetry_delay_valid(i),
          i_h_re     => i_h_re(i),
          i_h_im     => i_h_im(i),
          i_h_valid  => '1',
          i_yz_re    => w_y_re(i - 1),
          i_yz_im    => w_y_im(i - 1),
          i_yz_valid => w_y_valid(i - 1),
          o_y_re     => w_y_re(i),
          o_y_im     => w_y_im(i),
          o_y_valid  => w_y_valid(i)
        );
      end generate;
  end generate;

  ODD_TAP : if (g_NUM_TAPS > 1 and c_ODD_TAP_ENABLE = TRUE) generate
      Symmetric_FIR_single_tap_inst : Symmetric_FIR_single_tap
      generic map(
        g_DATA_WIDTH => g_DATA_WIDTH,
        g_GUARD_BIT  => g_GUARD_BIT
      )
      port map
      (
        i_clk      => i_clk,
        i_n_reset  => i_n_reset,
        i_x_re     => w_xz_symmetry_delay_re(c_NUM_EVEN_TAP - 1),
        i_x_im     => w_xz_symmetry_delay_im(c_NUM_EVEN_TAP - 1),
        i_x_valid  => w_xz_symmetry_delay_valid(c_NUM_EVEN_TAP - 1),
        i_xz_re => (others => '0'),
        i_xz_im => (others => '0'),
        i_xz_valid => '1',
        o_xz_re    => open,
        o_xz_im    => open,
        o_xz_valid => open,
        i_h_re     => i_h_re(c_NUM_EVEN_TAP),
        i_h_im     => i_h_im(c_NUM_EVEN_TAP),
        i_h_valid  => '1',
        i_yz_re    => w_y_re(c_NUM_EVEN_TAP - 1),
        i_yz_im    => w_y_im(c_NUM_EVEN_TAP - 1),
        i_yz_valid => w_y_valid(c_NUM_EVEN_TAP - 1),
        o_y_re     => w_odd_y_re,
        o_y_im     => w_odd_y_im,
        o_y_valid  => w_odd_y_valid
      );
  end generate;

  -- =======================================================================
  --  Processes
  -- =======================================================================

  INPUT_DELAY_SHIFT : process (i_clk, i_n_reset)
  begin
    if (i_n_reset = '0') then
      r_x_re_input_delay_shift_register  <= (others => (others => '0'));
      r_x_im_input_delay_shift_register  <= (others => (others => '0'));
      r_valid_input_delay_shift_register <= (others => '0');
    elsif (rising_edge(i_clk)) then
      r_x_re_input_delay_shift_register(0)  <= i_x_re;
      r_x_im_input_delay_shift_register(0)  <= i_x_im;
      r_valid_input_delay_shift_register(0) <= i_x_valid;
      for i in 0 to c_NUM_INPUT_DELAY - 1 loop
        r_x_re_input_delay_shift_register(i + 1)  <= r_x_re_input_delay_shift_register(i);
        r_x_im_input_delay_shift_register(i + 1)  <= r_x_im_input_delay_shift_register(i);
        r_valid_input_delay_shift_register(i + 1) <= r_valid_input_delay_shift_register(i);
      end loop;
    end if;
  end process; -- INPUT_DELAY_SHIFT

end Behavioral;
