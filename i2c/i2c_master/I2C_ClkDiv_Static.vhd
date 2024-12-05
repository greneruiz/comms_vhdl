--===================================================================
-- File Name: i2c_clkdiv.vhd
-- Type     : VHDL RTL
-- Purpose  : I2C - general purpose
-- Version  : 1.1
--===================================================================
-- Revision History
-- Version/Date : V1.0 / 2024-Nov-26 / G.RUIZ
--		* This is an initial release
-- Version/Date : V1.1 / 2024-Dec-04 / G.RUIZ
--		* Moved CLKDIV constants into Components' generic maps
--		* Renamed I_SYSCLK_8MHZ to I_SYSCLK
--===================================================================
--	Functional Description:
-- 		* This component is specifically designed to provide
-- 		DATA_ENA and SCL clocks for I2C master devices that
-- 		require Standard Mode (100kHz) or FastPlus Mode (1MHz),
-- 		where DATA_ENA = cos(SCL) (-90 degrees offset).
-- 		* SCL is divided into four quadrants; SYSCLK ticks per
-- 		quadrant are provided using vector constants.
--		* FPGA usage: 12 registers, 16 LUTs (Lattice MACHXO2)
--===================================================================


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;



entity I2C_ClkDiv_Static is
generic
(
	SLOW_CLKDIV		: integer range 0 to 20 := 19;					-- (80 / 4) - 1 = 19 SYSCLK ticks at 8 MHz per SCL quadrant
	FAST_CLKDIV		: integer range 0 to 20 := 1					-- ( 8 / 4) - 1 = 1 SYSCLK ticks at 8 MHz per SCL quadrant
);
port
(
	i_resetp		: in	std_logic;
	i_sysclk		: in	std_logic;								
	i_scl_mode_sel	: in	std_logic := '0';						-- '0' = SLOW_CLKDIV; '1' = FAST_CLKDIV
	i_update		: in	std_logic;								-- Pulse at sysclk freq to update CLKDIV
	o_data_ena		: out	std_logic;								-- -90 degrees offset from io_scl. Used to latch data to SDA (RE), or get data from SDA (FE)
	i_phy_scl		: in	std_logic;								-- Open-drain, assumed to be pulled high using a strap		
	o_scl_ena		: out	std_logic								-- SCL Ena
);
end entity I2C_ClkDiv_Static;



--===================================================================
architecture RTL_I2C_CLKDIV_STATIC of I2C_ClkDiv_Static is
--===================================================================


	signal s_maxdiv		: integer range 0 to 20;					-- Stores roll-over value
	signal s_ctr		: integer range 0 to 20;					-- sysclk tick counter
	signal s_quadrant	: integer range 0 to 3;						-- SCL quadrant state
	signal s_scl		: std_logic := '1';							-- SCL signal; '1' = release IO_SCL
	signal s_ena		: std_logic := '0';							-- Data enable for SDA events
	signal s_stretch	: std_logic := '0';							-- '1' = slave pulled SCL low
	
	
	

--===================================================================
begin
--===================================================================


	o_data_ena	<= s_ena;
	o_scl_ena	<= s_scl;



process( i_resetp, i_sysclk )
begin
	if rising_edge( i_sysclk ) then	
		if i_resetp = '1' then			
			s_maxdiv			<= FAST_CLKDIV;
			s_ctr				<= 0;
			s_quadrant			<= 0;
			s_scl				<= '0';
			s_ena				<= '0';
			s_stretch			<= '0';
		
		else
			if i_update = '1' then								-- Update down-counter max value based on SCL Mode				
				if i_scl_mode_sel = '0' then	
					s_maxdiv	<= SLOW_CLKDIV;
				else
					s_maxdiv	<= FAST_CLKDIV;
				end if;
				
				s_ctr		<= 0;
				s_quadrant	<= 0;
				s_stretch	<= '0';
	
			else
				if s_ctr = s_maxdiv then
					s_ctr	<= 0;
					if s_quadrant = 3 then
						s_quadrant	<= 0;
					elsif s_stretch = '0' then
						s_quadrant	<= s_quadrant + 1;
					end if;
				else
					s_ctr	<= s_ctr + 1;
				end if;
				
				
				case s_quadrant is
					when 0 =>
						s_scl		<= '0';
						s_ena		<= '0';
					
					when 1 =>
						s_scl		<= '0';
						s_ena		<= '1';
					
					when 2 =>
						s_scl		<= '1';
						s_ena		<= '1';
						
						if i_phy_scl = '0' then						-- We try to release SCL, but clock stretching is detected
							s_stretch	<= '1';
						else
							s_stretch	<= '0';
						end if;
					
					when 3 =>
						s_scl		<= '1';
						s_ena		<= '0';
						
				end case;
			end if;
		end if;
	end if;
end process;



--===================================================================
end RTL_I2C_CLKDIV_STATIC;
--===================================================================
