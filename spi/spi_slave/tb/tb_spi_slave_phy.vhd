-- =================================================================
-- File Name: tb_spi_slave_phy.vhd
-- Type     : VHDL Testbench
-- Purpose  : SPI slave controller
-- Version  : 1.0
-- =================================================================
-- Revision History
-- Version/Date : V1.0 / 2024-Dec-04 / G.RUIZ
--		* Initial release
--		* Not a comprehensive test, for initial go-no-go only !!
-- =================================================================


library ieee;
use ieee.std_logic_1164.all;
use work.bfm_spi_master.all;


entity tb_spi_slave_phy is
end entity tb_spi_slave_phy;



-- =================================================================
architecture RTL_TB_SPI_SLAVE of tb_spi_slave_phy is
-- =================================================================


	constant ENDIAN				: string	:= "MSB";					-- Bit ordering: "LSB" = LSB first; "MSB" = MSB first
	constant DATA_LENGTH		: integer range 0 to 32	:= 8;			-- Message string bit length
	constant INIT_DATA_LENGTH	: integer range 0 to 32	:= 12;			-- First message string bit length
	constant SPI_CPOL			: std_logic	:= '1';						-- SCL Polarity: '1' : CSL = '1' when idle
	constant SPI_CPHA			: std_logic	:= '0';						-- Clock-Data phase: '1' : Data is shifted on RE of SCL

	signal i_reset_n			: std_logic := '0';														-- FSM Reset, logic-low
	signal i_sysclk				: std_logic;															-- System clock; minimum 2x of SCK
	signal i_miso_data			: std_logic_vector( DATA_LENGTH - 1 downto 0 ) := ( others => '0' );	-- Data to be send to the master
	signal o_miso_done			: std_logic;															-- Request new message to send to master; Pulses at SYSCLK frequency
	signal o_mosi_data1			: std_logic_vector( INIT_DATA_LENGTH - 1 downto 0 );	
	signal o_mosi_valid1		: std_logic;
	signal o_mosi_datax			: std_logic_vector( DATA_LENGTH - 1 downto 0 );	
	signal o_mosi_validx		: std_logic;
	signal o_spi_busyn			: std_logic;
	signal i_phy_sck			: std_logic := '0';
	signal i_phy_csn			: std_logic := '1';
	signal i_phy_sdi			: std_logic := '0';
	signal o_phy_sdo			: std_logic;

	constant waitdly			: time := 125 ns;
	signal slave_data			: std_logic_vector(31 downto 0 ) := x"00000000";


-- =================================================================
begin
-- =================================================================

uut: entity work.spi_slave_phy
generic map
(
	ENDIAN				=> ENDIAN				,							-- Bit ordering: "LSB" = LSB first; "MSB" = MSB first
	DATA_LENGTH			=> DATA_LENGTH			,							-- Message string bit length
	INIT_DATA_LENGTH	=> INIT_DATA_LENGTH		,							-- First message string bit length
	SPI_CPOL			=> SPI_CPOL				,							-- SCL Polarity: '1' : CSL = '1' when idle
	SPI_CPHA			=> SPI_CPHA											-- Clock-Data phase: '1' : Data is shifted on RE of SCL
)
port map
(
	i_reset_n			=> i_reset_n			,							-- FSM Reset, logic-low
	i_sysclk			=> i_sysclk				,							-- System clock; minimum 2x of SCK
	i_miso_data			=> i_miso_data			,							-- Data to be send to the master
	o_miso_done			=> o_miso_done			,							-- Request new message to send to master; Pulses at SYSCLK frequency
	o_mosi_data1		=> o_mosi_data1			,
	o_mosi_valid1		=> o_mosi_valid1		,
	o_mosi_datax		=> o_mosi_datax			,
	o_mosi_validx		=> o_mosi_validx		,
	o_spi_busyn			=> o_spi_busyn			,
	i_phy_sck			=> i_phy_sck			,
	i_phy_csn			=> i_phy_csn			,
	i_phy_sdi			=> i_phy_sdi			,
	o_phy_sdo			=> o_phy_sdo			
);



i_miso_data	<= slave_data( 7 downto 0 );

sim_sysclk: process begin
	i_sysclk	<= '0';
	wait for waitdly / 2;
	i_sysclk	<= '1';
	wait for waitdly / 2;
end process;


sim_stimulus: process begin
	i_phy_sck	<= SPI_CPOL;												-- Set SCK idle state	

	i_reset_n				<= '1';											-- Deassert Resetn
	wait for waitdly * 5;

---------------------------------------------------------------------- SPI Write: 1st msg = 11b; nth msgs = 8b
	SPI_CSN_TOGGLE( '1', waitdly, i_phy_csn );
	SPI_WRITE( x"0000" & x"0DAB", SPI_CPOL, SPI_CPHA, INIT_DATA_LENGTH, waitdly, i_phy_sck, i_phy_sdi );
	SPI_WRITE( x"0000" & x"0091", SPI_CPOL, SPI_CPHA, DATA_LENGTH, waitdly, i_phy_sck, i_phy_sdi );
	SPI_WRITE( x"0000" & x"0082", SPI_CPOL, SPI_CPHA, DATA_LENGTH, waitdly, i_phy_sck, i_phy_sdi );
	SPI_WRITE( x"0000" & x"0073", SPI_CPOL, SPI_CPHA, DATA_LENGTH, waitdly, i_phy_sck, i_phy_sdi );
	wait for waitdly;
	SPI_CSN_TOGGLE( '0', waitdly, i_phy_csn );
	wait until o_spi_busyn = '1';
	wait for waitdly * 10;

---------------------------------------------------------------------- SPI Read: 1st msg = 11b; nth msgs = 8b
	SPI_CSN_TOGGLE( '1', waitdly, i_phy_csn );
	SPI_WRITE( x"0000" & x"0DAB", SPI_CPOL, SPI_CPHA, INIT_DATA_LENGTH, waitdly, i_phy_sck, i_phy_sdi );
	SPI_READ(  SPI_CPOL, DATA_LENGTH, waitdly, i_phy_sck );
	SPI_READ(  SPI_CPOL, DATA_LENGTH, waitdly, i_phy_sck );
	SPI_READ(  SPI_CPOL, DATA_LENGTH, waitdly, i_phy_sck );
	SPI_CSN_TOGGLE( '0', waitdly, i_phy_csn );

	wait;
end process;


sim_rd_stim: process begin
	wait until o_mosi_valid1 = '1';									-- First SPI_WRITE(INIT_DATA_LENGTH) -> spi write mode
	wait until o_mosi_valid1 = '1';									-- Second SPI_WRITE(INIT_DATA_LENGTH) -> spi read mode
	slave_data( 7 downto 0 )	<= x"C8";
	wait until o_miso_done = '1';
	slave_data( 7 downto 0 )	<= x"D7";	
	wait until o_miso_done = '1';
	slave_data( 7 downto 0 )	<= x"E6";	

end process;





-- =================================================================
end RTL_TB_SPI_SLAVE;
-- =================================================================