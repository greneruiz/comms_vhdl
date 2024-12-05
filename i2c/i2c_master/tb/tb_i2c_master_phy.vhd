-- =================================================================
-- File Name: tb_i2c_master_phy.vhd
-- Type     : VHDL Testbench
-- Purpose  : Generic I2C master controller
-- Version  : 1.0
-- =================================================================
-- Revision History
-- Version/Date : V0.0 / 2024-Nov-28 / GREN
--		* Initial release
--		* Not a comprehensive test, for initial go-no-go only !!
-- =================================================================



library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.bfm_i2c_slave.all;



entity tb_i2c_master_phy is
end entity tb_i2c_master_phy;



-- =================================================================
architecture RTL_TB_I2C_PHY of tb_i2c_master_phy is
-- =================================================================


	signal i_sysclk				: std_logic;												-- System clock; 8 MHz
	signal i_reset_n			: std_logic := '0';											-- FSM reset
	signal i_scl_mode_sel		: std_logic := '0';											-- '0' = Standard (100kHz); '1' = FastPlus (1MHz)
	signal i_scl_mode_update	: std_logic := '0';											-- Pulse in I_SYSCLK to update SCL frequency
	signal i_slave_addr			: std_logic_vector( 6 downto 0 ) := ( others => '0' );		-- I2C Slave device address
	signal i_rd_wrn				: std_logic := '0';											-- 1 = rd; 0 = wr
	signal i_wr_data			: std_logic_vector( 7 downto 0 ) := ( others => '0' );		-- Byte to be written to slave
	signal o_rd_data			: std_logic_vector( 7 downto 0 );							-- Byte read from slave
	signal o_rd_valid			: std_logic;												-- Byte read valid
	signal o_byte_ack			: std_logic;												-- Byte-ack pulse in I_SYSCLK to acknowledge the previous byte from the interface layer
	signal i_frame_ena			: std_logic := '0';											-- Transaction frame; keep high to write/read multiple bytes
	signal o_ack_error			: std_logic;												-- I2C Ack; 1 = slave did not acknowledge the byte
	signal o_fsm_busyn			: std_logic;												-- FSM Status; 1 = idle; 0 = transacting
	signal io_phy_scl			: std_logic := 'H';											-- I2C SCL; connect to bidirectional buffer primitive
	signal io_phy_sda			: std_logic := 'H';											-- I2C SDA; connect to bidirectional buffer primitive

	constant waitdly			: time := 125 ns;

	signal s_debug_byte			: std_logic_vector( 7 downto 0 ) := x"00";


-- =================================================================
begin
-- =================================================================


uut: entity work.i2c_master_phy
port map
(
	i_sysclk			=> i_sysclk				,		
	i_reset_n			=> i_reset_n			,		
	i_scl_mode_sel		=> i_scl_mode_sel		,		
	i_scl_mode_update	=> i_scl_mode_update	,		
	i_slave_addr		=> i_slave_addr			,		
	i_rd_wrn			=> i_rd_wrn				,		
	i_wr_data			=> i_wr_data			,		
	o_rd_data			=> o_rd_data			,		
	o_rd_valid			=> o_rd_valid			,		
	o_byte_ack			=> o_byte_ack			,		
	i_frame_ena			=> i_frame_ena			,		
	o_ack_error			=> o_ack_error			,		
	o_fsm_busyn			=> o_fsm_busyn			,		
	io_phy_scl			=> io_phy_scl			,		
	io_phy_sda			=> io_phy_sda					
);


sim_sysclk: process begin
	i_sysclk	<= '0';
	wait for waitdly / 2;
	i_sysclk	<= '1';
	wait for waitdly / 2;
end process;


sim_stimulus: process begin

--	I2C_WRITE( expByte, waitdly, SCL, SDA );
--	I2C_READ( rdByte, waitdly, SCL, SDA );

	i_reset_n				<= '1';									-- Deassert Resetn
	wait for waitdly * 5;

	wait for waitdly * 5;
	i_scl_mode_sel			<= '1';									-- FastPlus Mode (1 MHz)
	i_scl_mode_update		<= '1';
	wait for waitdly;
	i_scl_mode_update		<= '0';
	wait for waitdly;

---------------------------------------------------------------------- I2C Write
	i_slave_addr			<= "1100100";							-- ATSHA204A slave address = 0xC8
	i_rd_wrn				<= '0';									-- I2C Write
	i_wr_data				<= x"6B";
	wait for waitdly * 2;
	i_frame_ena				<= '1';
	wait for waitdly;

	I2C_WRITE( i_slave_addr & i_rd_wrn, io_phy_scl, io_phy_sda, s_debug_byte );
	wait for waitdly;
	I2C_WRITE( i_wr_data, io_phy_scl, io_phy_sda, s_debug_byte );
	i_wr_data				<= x"5A";
	wait for waitdly;
	I2C_WRITE( i_wr_data, io_phy_scl, io_phy_sda, s_debug_byte );
	wait for waitdly;
	i_frame_ena				<= '0';

	wait for waitdly * 10;

---------------------------------------------------------------------- I2C Read
	i_slave_addr			<= "1100100";							-- ATSHA204A slave address = 0xC8
	i_rd_wrn				<= '1';									-- I2C Read
	wait for waitdly * 2;
	i_frame_ena				<= '1';
	wait for waitdly;
	I2C_WRITE( i_slave_addr & i_rd_wrn, io_phy_scl, io_phy_sda, s_debug_byte );
	wait for waitdly;
	I2C_READ( x"A5", waitdly, io_phy_scl, io_phy_sda );
	wait for waitdly;
	I2C_READ( x"CD", waitdly, io_phy_scl, io_phy_sda );
	wait for waitdly;
	i_frame_ena				<= '0';

	wait;
end process;



 process begin
	wait for 3187500 ps;
	io_phy_scl	<= '0';												-- Caveman style simulation of clock stretching
	wait for 1 us;
	io_phy_scl	<= 'Z';
	wait;
end process;


-- =================================================================
end RTL_TB_I2C_PHY;
-- =================================================================