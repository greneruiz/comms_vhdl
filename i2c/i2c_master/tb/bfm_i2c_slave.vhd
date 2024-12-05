-- =================================================================
-- File Name: bfm_i2c_slave.vhd
-- Type     : Package
-- Purpose  : I2C Slave Bus Functional Model
-- Version  : 1.0
-- =================================================================
-- Revision History
-- Version/Date : V0.0 / 2024-Nov-28 / GREN
--		Initial release
-- =================================================================




library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;



-- =================================================================
package bfm_i2c_slave is
-- =================================================================

--	I2C_WRITE( expByte, waitdly, SCL, SDA );
	procedure I2C_WRITE
	(
		constant expByte	: in	std_logic_vector( 7 downto 0 );		-- Expected byte to be received by slave
		signal SCL 			: in	std_logic;							
		signal SDA			: inout	std_logic;
		signal outByte		: out	std_logic_vector( 7 downto 0 )
	);
	
--	I2C_READ( rdByte, waitdly, SCL, SDA );
	procedure I2C_READ
	(
		constant rdByte		: in	std_logic_vector( 7 downto 0 );		-- Byte to write
		constant waitdly	: in	time := 125 ns;						-- Duration of an SCL quadrant
		signal SCL			: in	std_logic;
		signal SDA			: inout	std_logic
	);



-- =================================================================
end package;
package body bfm_i2c_slave is
-- =================================================================


	procedure I2C_WRITE
	(
		constant expByte	: in	std_logic_vector( 7 downto 0 );
		signal SCL 			: in	std_logic;
		signal SDA			: inout	std_logic;
		signal outByte		: out	std_logic_vector( 7 downto 0 )
	) is
		variable byte_str	: std_logic_vector( 7 downto 0 );
	begin

		for i in 7 downto 0 loop
			wait until ( SCL'EVENT and SCL = 'Z' );
			
			if SDA = '0' then
				byte_str(i)		:= '0';
			else 
				byte_str(i)		:= '1';
			end if;
		end loop;

		wait until  ( SCL'EVENT and SCL = '0' );
		if byte_str = expByte then
			outByte	<= byte_str;
			SDA		<= '0';												-- Slave acknowledges write
		else
			outByte	<= x"FF";
			SDA		<= '1';
		end if;
	
		wait until ( SCL'EVENT and SCL = '0' );
		SDA			<= 'H';												-- Slave releases SDA

	end procedure I2C_WRITE;



	procedure I2C_READ
	(
		constant rdByte		: in	std_logic_vector( 7 downto 0 );
		constant waitdly	: in	time := 125 ns;
		signal SCL			: in	std_logic;
		signal SDA			: inout	std_logic
	) is
	begin

		for i in 7 downto 0 loop
			wait until  ( SCL'EVENT and SCL = 'Z' );
			SDA	<= rdByte(i);
		end loop;

		wait until ( SCL'EVENT and SCL = 'Z' );
		SDA		<= 'H';												-- Slave releases SDA for master ack
		wait for waitdly;
		SDA		<= 'Z';
	end procedure I2C_READ;




-- =================================================================
end package body;
-- =================================================================