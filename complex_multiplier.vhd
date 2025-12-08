----------------------------------------------------------------------------------
-- Company: 
-- Engineer: JPLEE
-- 
-- Create Date: 2025/10/17 00:45:14
-- Design Name: 
-- Module Name: complex_multiplier - Behavioral
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
-- Complex Multiplier
-- Implemented with Gauss-3 Product for 3-Level Pipelined Multiply Architecture
-- =======================================================================

--  Input         Pre-Addition                  Pipeline 1      Multiplication                                  Pipeline 2                Negation                      Post-Addition                                                                         Pipeline 3          Output
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--  A_re    ->    Pre-Adder 1 (A_re + A_im) | ->    FF    -> |                                              |                |                                  |                                                                                       |                     |
--  A_im    ->                              |                |  Multiplier 1 (A_re + A_im) * (B_re + B_im)  | ->    FF    -> |                                  | ->                                                                                    |                     |
--  B_re    ->    Pre-Adder 2 (B_re + B_im) | ->    FF    -> |                                              |                |                                  |                                                                                       |                     |
--  B_im    ->                              |                |                                              |                |                                  |       Post-Adder 1 ((A_re + A_im ) * (B_re + B_im)) - (A_re * B_re + A_im * B_im)     |   ->    FF      ->  |   P_im = (A_re + A_im ) * (B_re + B_im) - (A_re * B_re + A_im * B_im)
--  A_re    ->                              | ->    FF    -> |  Multiplier 2 (A_re * B_re)                  | ->    FF    -> | ->  x (-1) = (-A_re * B_re)      | ->                                                                                    |                     |
--  B_re    ->                              | ->    FF    -> |                                              |                | ->           ( A_re * B_re)      | ->    Post-Adder 2 (A_re * B_re) - (A_im * B_im)                                      |   ->    FF      ->  |   P_re = (A_re * B_re) - (A_im * B_im)
--  A_im    ->                              | ->    FF    -> |  Multiplier 3 (A_im * B_im)                  | ->    FF    -> | ->  x (-1) = (-A_im * B_im)      | ->                                                                                    |                     |
--  B_im    ->                              | ->    FF    -> |                                              |                |                                  |                                                                                       |                     |
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

entity complex_multiplier is
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
end complex_multiplier;

-- =======================================================================
--  Architecture
-- =======================================================================

architecture Behavioral of complex_multiplier is

  -- =======================================================================
  --  Constants
  -- =======================================================================

  constant c_PRE_ADD_WIDTH           : integer := g_DATA_WIDTH + 1;
  constant c_MULT_WITH_PRE_ADD_WIDTH : integer := 2 * (g_DATA_WIDTH + 1);
  constant c_MULT_WIDTH              : integer := 2 * g_DATA_WIDTH;

  -- =======================================================================
  --  Signals
  -- =======================================================================

  signal r_A_re             : signed (g_DATA_WIDTH - 1 downto 0);
  signal r_A_im             : signed (g_DATA_WIDTH - 1 downto 0);
  signal r_B_re             : signed (g_DATA_WIDTH - 1 downto 0);
  signal r_B_im             : signed (g_DATA_WIDTH - 1 downto 0);
  signal r_pre_adder_1      : signed(c_PRE_ADD_WIDTH - 1 downto 0);           --  A_re + A_im
  signal r_pre_adder_2      : signed(c_PRE_ADD_WIDTH - 1 downto 0);           --  B_re + B_im
  signal r_pre_adder_valid  : std_logic;
  signal r_mult_1           : signed(c_MULT_WITH_PRE_ADD_WIDTH - 1 downto 0); --  (A_re + A_im) * (B_re + B_im)
  signal r_mult_2           : signed(c_MULT_WIDTH - 1 downto 0);              --  A_re * B_re
  signal r_mult_3           : signed(c_MULT_WIDTH - 1 downto 0);              --  A_im * B_im
  signal r_mult_valid       : std_logic;
  signal r_post_adder_1     : signed((g_DATA_WIDTH + 1) * 2 - 1 downto 0);    --  (A_re + A_im) * (B_re + B_im) - (A_re * B_re) - (A_im * B_im)
  signal r_post_adder_2     : signed((g_DATA_WIDTH + 1) * 2 - 1 downto 0);    --  (A_re * B_re) - (A_im * B_im)
  signal r_post_adder_valid : std_logic;

  -- =======================================================================
  --  Architecture Body
  -- =======================================================================

begin

  -- =======================================================================
  --  Output Buffering
  -- =======================================================================

  o_valid <= r_post_adder_valid;
  o_P_re  <= r_post_adder_2;
  o_P_im  <= r_post_adder_1;

  -- =======================================================================
  --  Processes
  -- =======================================================================

  PRE_ADD : process (i_clk, i_n_reset) -- Pipeline Stage 1
  begin
    if (i_n_reset = '0') then
      r_pre_adder_1     <= (others => '0');
      r_pre_adder_2     <= (others => '0');
      r_pre_adder_valid <= '0';
    elsif (rising_edge(i_clk)) then
      if (i_valid = '1') then
        r_pre_adder_1     <= resize(signed(i_A_re) + signed(i_A_im), c_PRE_ADD_WIDTH); -- Pre-Addition, Bit width (n + 1)
        r_pre_adder_2     <= resize(signed(i_B_re) + signed(i_B_im), c_PRE_ADD_WIDTH); -- Pre-Addition, Bit width (n + 1)
        r_pre_adder_valid <= '1';
      else
        r_pre_adder_valid <= '0';
      end if;
    end if;
  end process; -- PRE_ADD

  INPUT_LATCH : process (i_clk, i_n_reset) -- Pipeline Stage 1
  begin
    if (i_n_reset = '0') then
      r_A_re <= (others => '0');
      r_A_im <= (others => '0');
      r_B_re <= (others => '0');
      r_B_im <= (others => '0');
    elsif (rising_edge(i_clk)) then
      if (i_valid = '1') then
        r_A_re <= signed(i_A_re);
        r_A_im <= signed(i_A_im);
        r_B_re <= signed(i_B_re);
        r_B_im <= signed(i_B_im);
      end if;
    end if;
  end process; -- INPUT_LATCH

  MULT : process (i_clk, i_n_reset) -- Pipeline Stage 2
  begin
    if (i_n_reset = '0') then
      r_mult_1     <= (others => '0');
      r_mult_2     <= (others => '0');
      r_mult_3     <= (others => '0');
      r_mult_valid <= '0';
    elsif (rising_edge(i_clk)) then
      if (r_pre_adder_valid = '1') then
        r_mult_1     <= resize(r_pre_adder_1 * r_pre_adder_2, c_MULT_WITH_PRE_ADD_WIDTH); -- Multiplication, Bit Width 2 * (n + 1)
        r_mult_2     <= resize(r_A_re * r_B_re, c_MULT_WIDTH);                            -- Multiplication, Bit Width 2 * (n)
        r_mult_3     <= resize(r_A_im * r_B_im, c_MULT_WIDTH);                            -- Multiplication, Bit Width 2 * (n)
        r_mult_valid <= '1';
      else
        r_mult_valid <= '0';
      end if;
    end if;
  end process; -- MULT

  POST_ADD : process (i_clk, i_n_reset) -- Pipeline Stage 3
  begin
    if (i_n_reset = '0') then
      r_post_adder_1     <= (others => '0');
      r_post_adder_2     <= (others => '0');
      r_post_adder_valid <= '0';
    elsif (rising_edge(i_clk)) then
      if (r_mult_valid = '1') then
        r_post_adder_1     <= r_mult_1 - resize(r_mult_2, c_MULT_WITH_PRE_ADD_WIDTH) - resize(r_mult_3, c_MULT_WITH_PRE_ADD_WIDTH); -- Post-Addition, Bit Width 2 * (n + 1)
        r_post_adder_2     <= resize(r_mult_2 - r_mult_3, c_MULT_WITH_PRE_ADD_WIDTH);                                               -- Post-Addition, Bit Width 2 * (n + 1)
        r_post_adder_valid <= r_mult_valid;
      else
        r_post_adder_valid <= '0';
      end if;
    end if;
  end process; -- POST_ADD

end Behavioral;
