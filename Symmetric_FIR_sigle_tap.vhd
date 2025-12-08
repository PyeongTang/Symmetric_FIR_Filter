----------------------------------------------------------------------------------
-- Company: 
-- Engineer: JPLEE
-- 
-- Create Date: 2025/10/23 22:17:17
-- Design Name: 
-- Module Name: Symmetric_FIR_single_tap - Behavioral
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
-- Single Tap for Symmetric FIR Filter
--  1. Apply Delay on Input-to-Ouput Bypass Path (2-clk)
--  2. Pre-Addition to Input and Delayed input (N-clk, N : number of taps using symmetry)
--  3. MAC Operation for Current Tap Multplication Result + Previous Tap Result
-- =======================================================================

entity Symmetric_FIR_single_tap is
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
end Symmetric_FIR_single_tap;

-- =======================================================================
--  Architecture
-- =======================================================================

architecture Behavioral of Symmetric_FIR_single_tap is

  -- =======================================================================
  --  Components
  -- =======================================================================

  component complex_multiplier is
    generic (
      g_DATA_WIDTH : integer := 16
    );
    port (
      -- System
      i_clk     : in std_logic;
      i_n_reset : in std_logic;

      -- Input Data
      i_A_re  : in signed(g_DATA_WIDTH - 1 downto 0);
      i_A_im  : in signed(g_DATA_WIDTH - 1 downto 0);
      i_B_re  : in signed(g_DATA_WIDTH - 1 downto 0);
      i_B_im  : in signed(g_DATA_WIDTH - 1 downto 0);
      i_valid : in std_logic;

      -- Product
      o_P_re  : out signed((g_DATA_WIDTH + 1) * 2 - 1 downto 0);
      o_P_im  : out signed((g_DATA_WIDTH + 1) * 2 - 1 downto 0);
      o_valid : out std_logic
    );
  end component;

  -- =======================================================================
  --  Constants
  -- =======================================================================

  constant c_PRE_ADD_WIDTH     : integer := g_DATA_WIDTH + 1;
  constant c_MULT_WIDTH        : integer := (c_PRE_ADD_WIDTH + 1) * 2; -- Complex Multiplier Input bit width = Pre-Adder Data width
  constant c_OUTPUT_DATA_WIDTH : integer := c_MULT_WIDTH + g_GUARD_BIT;

  -- =======================================================================
  --  Signals
  -- =======================================================================

  signal r_x_re        : signed(g_DATA_WIDTH - 1 downto 0)        := (others => '0');
  signal r_x_im        : signed(g_DATA_WIDTH - 1 downto 0)        := (others => '0');
  signal r_x_valid     : std_logic                                := '0';
  signal r_x_re_z      : signed(g_DATA_WIDTH - 1 downto 0)        := (others => '0');
  signal r_x_im_z      : signed(g_DATA_WIDTH - 1 downto 0)        := (others => '0');
  signal r_x_valid_z   : std_logic                                := '0';
  signal w_sum_re      : signed(c_PRE_ADD_WIDTH - 1 downto 0)     := (others => '0');
  signal w_sum_im      : signed(c_PRE_ADD_WIDTH - 1 downto 0)     := (others => '0');
  signal w_h_re_resize : signed(c_PRE_ADD_WIDTH - 1 downto 0)     := (others => '0');
  signal w_h_im_resize : signed(c_PRE_ADD_WIDTH - 1 downto 0)     := (others => '0');
  signal w_mult_enable : std_logic                                := '0';
  signal w_mult_re     : signed(c_MULT_WIDTH - 1 downto 0)        := (others => '0');
  signal w_mult_im     : signed(c_MULT_WIDTH - 1 downto 0)        := (others => '0');
  signal w_mult_valid  : std_logic                                := '0';
  signal r_y_re        : signed(c_OUTPUT_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal r_y_im        : signed(c_OUTPUT_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal r_y_valid     : std_logic                                := '0';

  -- =======================================================================
  --  Architecture Body
  -- =======================================================================

begin

  -- =======================================================================
  --  Output Buffering
  -- =======================================================================

  o_xz_re    <= r_x_re_z;
  o_xz_im    <= r_x_im_z;
  o_xz_valid <= r_x_valid_z;
  o_y_re     <= r_y_re;
  o_y_im     <= r_y_im;
  o_y_valid  <= r_y_valid;

  -- =======================================================================
  --  Wiring
  -- =======================================================================

  w_mult_enable <= i_x_valid and i_h_valid;
  w_sum_re      <= resize(i_x_re + i_xz_re, c_PRE_ADD_WIDTH);
  w_sum_im      <= resize(i_x_im + i_xz_im, c_PRE_ADD_WIDTH);
  w_h_re_resize <= resize(i_h_re, c_PRE_ADD_WIDTH);
  w_h_im_resize <= resize(i_h_im, c_PRE_ADD_WIDTH);

  -- =======================================================================
  --  Instances
  -- =======================================================================

  complex_multiplier_inst : complex_multiplier
  generic map(
    g_DATA_WIDTH => c_PRE_ADD_WIDTH
  )
  port map
  (
    i_clk     => i_clk,
    i_n_reset => i_n_reset,
    i_A_re    => w_sum_re,
    i_A_im    => w_sum_im,
    i_B_re    => w_h_re_resize,
    i_B_im    => w_h_im_resize,
    i_valid   => w_mult_enable,
    o_P_re    => w_mult_re,
    o_P_im    => w_mult_im,
    o_valid   => w_mult_valid
  );

  -- =======================================================================
  --  Process
  -- =======================================================================

  INPUT_FEED_DELAY : process (i_clk, i_n_reset)
  begin
    if (i_n_reset = '0') then
      r_x_re      <= (others => '0');
      r_x_im      <= (others => '0');
      r_x_valid   <= '0';
      r_x_re_z    <= (others => '0');
      r_x_im_z    <= (others => '0');
      r_x_valid_z <= '0';
    elsif (rising_edge(i_clk)) then
      r_x_re      <= i_x_re;
      r_x_im      <= i_x_im;
      r_x_valid   <= i_x_valid;
      r_x_re_z    <= r_x_re;
      r_x_im_z    <= r_x_im;
      r_x_valid_z <= r_x_valid;
    end if;
  end process; -- INPUT_FEED_DELAY

  ACCUMULATOR_DELAY : process (i_clk, i_n_reset)
  begin
    if (i_n_reset = '0') then
      r_y_re    <= (others => '0');
      r_y_im    <= (others => '0');
      r_y_valid <= '0';
    elsif (rising_edge(i_clk)) then
      r_y_re    <= w_mult_re + i_yz_re;
      r_y_im    <= w_mult_im + i_yz_im;
      r_y_valid <= i_yz_valid;
    end if;
  end process; -- ACCUMULATOR_DELAY

end Behavioral;
