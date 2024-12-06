-- =================================================================
-- File Name: bfm_spi_master.vhd
-- Type     : Package
-- Purpose  : SPI Master Bus Functional Model
-- Version  : 1.0
-- =================================================================
-- Revision History
-- Version/Date : V0.0 / 2024-Dec-04 / G.RUIZ
--		Initial release
-- =================================================================



library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;


-- =================================================================
package bfm_spi_master is
-- =================================================================

--	SPI_CSN_TOGGLE( csn_logic, CSN );
	procedure SPI_CSN_TOGGLE
	(	
		constant csn_logic	: in	std_logic := '1';					-- '1' = assert, '0' = deassert
		constant waitdly	: in	time := 125 ns;
		signal CSN			: out	std_logic
	);


--	SPI_WRITE( expByte, bitcount, waitdly, SCK, CSN, MOSI );
	procedure SPI_WRITE
	(
		constant expByte	: in	std_logic_vector(31 downto 0 );
		constant SPI_CPOL	: in	std_logic := '0';
		constant SPI_CPHA	: in	std_logic := '0';
		constant bitcount	: in	integer range 0 to 32 := 8;
		constant waitdly	: in	time := 125 ns;
		signal SCK			: out	std_logic;
		signal MOSI			: out	std_logic
	); 


--	SPI_READ( rdByte, bitcount, waitdly, SCK, CSN, MISO );
	procedure SPI_READ
	(
		constant SPI_CPOL	: in	std_logic := '0';
		constant bitcount	: in	integer range 0 to 32 := 8;
		constant waitdly	: in	time := 125 ns;
		signal SCK			: out	std_logic
	);




-- =================================================================
end package;
package body bfm_spi_master is
-- =================================================================



	procedure SPI_CSN_TOGGLE
	(	
		constant csn_logic	: in	std_logic := '1';					-- '1' = assert, '0' = deassert
		constant waitdly	: in	time := 125 ns;
		signal CSN			: out	std_logic
	) is 
	begin
		wait for waitdly * 2;
		if csn_logic = '1' then
			CSN			<= '0';
		else
			CSN			<= '1';
		end if;

		wait for waitdly;
	end procedure SPI_CSN_TOGGLE;



	procedure SPI_WRITE
	(
		constant expByte	: in	std_logic_vector(31 downto 0 );
		constant SPI_CPOL	: in	std_logic := '0';
		constant SPI_CPHA	: in	std_logic := '0';
		constant bitcount	: in	integer range 0 to 32 := 8;
		constant waitdly	: in	time := 125 ns;
		signal SCK			: out	std_logic;
		signal MOSI			: out	std_logic
	) is
	begin
		wait for waitdly;
		for i in bitcount - 1 downto 0 loop									-- Start the transaction; split 1 SCK into 4 quadrants
			SCK			<= SPI_CPOL;
			if SPI_CPHA = '0' then
				MOSI		<= expByte(i);
			end if;
			wait for waitdly;

			SCK			<= not SPI_CPOL;
			if SPI_CPHA = '1' then
				MOSI		<= expByte(i);
			end if;
			wait for waitdly * 2;
			SCK			<= SPI_CPOL;
			
			wait for waitdly;
		end loop;	
	end procedure SPI_WRITE;


	procedure SPI_READ
	(
		constant SPI_CPOL			: in	std_logic := '0';
		constant bitcount			: in	integer range 0 to 32 := 8;
		constant waitdly			: in	time := 125 ns;
		signal SCK					: out	std_logic
	) is
	begin
		for i in bitcount - 1 downto 0 loop									-- Start the transaction; split 1 SCK into 4 quadrants
			SCK			<= SPI_CPOL;
			wait for waitdly;
			SCK			<= not SPI_CPOL;

			wait for waitdly * 2;
			SCK			<= SPI_CPOL;

			wait for waitdly;
		end loop;
	end procedure SPI_READ;



-- =================================================================
end package body;
-- =================================================================