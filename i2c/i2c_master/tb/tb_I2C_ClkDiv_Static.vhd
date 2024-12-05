-- ==============================================================
-- File Name: tb_I2C_ClkDiv_Static.vhd
-- Type     : VHDL Testbench
-- Purpose  : I2C - general purpose
-- Version  : 1.4
-- ==============================================================
-- Revision History
-- Version/Date : V1.0 / 2024-Nov-26 / GREN
--		* This is an initial release
-- ==============================================================



library ieee;
use ieee.std_logic_1164.all;



entity tb_I2C_ClkDiv_Static is
end entity tb_I2C_ClkDiv_Static;



architecture RTL_TB_I2C_CLKDIV_STATIC of tb_I2C_ClkDiv_Static is

	signal i_resetp			: std_logic := '0';
	signal i_sysclk_8MHz	: std_logic;								-- 8 MHz, to meet generic FPGA minimum PLL Fout
	signal i_scl_mode_sel	: std_logic := '0';						-- '0' = Standard (100kHz); '1' = FastPlus (1MHz)
	signal i_update			: std_logic := '0';								-- Pulse at sysclk freq to update CLKDIV
	signal o_data_ena		: std_logic;								-- -90 degrees offset from io_scl. Used to latch data to SDA (RE), or get data from SDA (FE)
	signal io_scl			: std_logic := 'Z';								-- Open-drain, assumed to be pulled high using a strap

	constant waitdly		: time := 125 ns;	-- 8 MHz



begin


	uut: entity work.I2C_ClkDiv_Static
	port map
	(
		i_resetp			=> i_resetp			,
		i_sysclk_8MHz		=> i_sysclk_8MHz	,
		i_scl_mode_sel		=> i_scl_mode_sel	,
		i_update			=> i_update			,
		o_data_ena			=> o_data_ena		,
		io_scl				=> io_scl			
	);


	prc_clk: process begin
		i_sysclk_8MHz	<= '0';
		wait for waitdly / 2;
		i_sysclk_8MHz	<= '1';
		wait for waitdly / 2;
	end process;



	prc_stim: process begin
		io_scl		<= '1';	-- pullup emulation
		wait for waitdly * 10;
		i_scl_mode_sel	<= '0';	-- Standard SCL
		wait for waitdly * 2;
		
		
		i_update	<= '1';
		wait for waitdly;
		i_update	<= '0';
		
		
		wait for 200 us;

		io_scl		<= '0';	-- slave clock stretch	
		wait for 100 us;
		io_scl		<= '1';	-- slave releases scl line

		wait for 200 us;
	-------------		
	
		i_scl_mode_sel	<= '1';	-- FastPlus SCL
		wait for waitdly * 2;

		i_update	<= '1';
		wait for waitdly;
		i_update	<= '0';
		
		
		wait for 20 us;

		io_scl		<= '0';	-- slave clock stretch	
		wait for 10 us;
		io_scl		<= '1';	-- slave releases scl line

		wait;
	end process;






end RTL_TB_I2C_CLKDIV_STATIC;