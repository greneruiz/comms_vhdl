--===================================================================
-- File Name: tb_i2c_slave_phy.vhd
-- Type     : Testbench
-- Purpose  : Generic I2C slave controller (oversample method)
-- Version  : 1.0
--===================================================================
-- Revision History
-- Version/Date : V1.0 / 2025-Jan-29 / G.RUIZ
--		* Initial release
--===================================================================

library ieee;
use ieee.std_logic_1164.all;


entity tb_i2c_slave_phy is
end entity tb_i2c_slave_phy;



--===================================================================
architecture TB_I2C_SLAVE of tb_i2c_slave_phy is
--===================================================================


	signal i_sysclk				: std_logic;								-- System clock;
	signal i_reset_n			: std_logic := '0';							-- FSM reset; '0' = reset
	signal i_tx_data			: std_logic_vector( 7 downto 0 ):= x"00";	-- Byte to be sent to master
	signal o_tx_byte_done		: std_logic;								-- Pulse (in SYSCLK) to indicate byte write completion
	signal o_rx_data			: std_logic_vector( 7 downto 0 );			-- Byte received from master
	signal o_rx_valid			: std_logic;								-- Valid pulse (in SYSCLK) for read byte
	signal o_fsm_frame			: std_logic;								-- FSM busy status; '0' = idle; '1' = active
	signal o_nack				: std_logic;								-- Master NACKs; can indicate end of comms. '1' = NACK
	signal io_phy_scl			: std_logic := 'Z';
	signal io_phy_sda			: std_logic := 'Z';

	constant waitdly : time := 125 ns;



procedure I2C_BEGIN
(
	signal scl		: out	std_logic;
	signal sda		: out	std_logic
) is
begin
	sda		<= '0';
	wait for waitdly * 2;
	scl		<= '0';
	wait for waitdly * 2;
end procedure I2C_BEGIN;



procedure I2C_END
(
	signal scl		: out	std_logic;
	signal sda		: out	std_logic
) is
begin
	sda		<= '0';
	wait for waitdly * 2;
	scl		<= '0';
	wait for waitdly * 2;
	scl		<= '1';
	wait for waitdly * 2;
	sda		<= '1';
	wait for waitdly * 2;
end procedure I2C_END;



procedure I2C_WRITE
(
	constant byte	: in	std_logic_vector( 7 downto 0 );
	signal scl		: out	std_logic;
	signal sda		: out	std_logic
) is
	variable x	: integer := 0;

begin
	for x in 8 downto 0 loop
		scl		<= '0';
		
		if x > 0 then
			sda		<= byte(x - 1);
			wait for waitdly * 2;
		else
			sda		<= '0';
			wait for waitdly;
			sda		<= 'H';
			wait for waitdly;
		end if;
		
		scl		<= '1';
		wait for waitdly * 4;
		scl		<= '0';
		wait for waitdly * 2;
	end loop;
end procedure I2C_WRITE;



procedure I2C_READ
(
--	constant byte	: in	std_logic_vector( 7 downto 0 );
	constant ack	: in	std_logic;
	signal tx_data	: out	std_logic_vector( 7 downto 0 );
	signal scl		: out	std_logic;
	signal sda		: out	std_logic
) is
begin
--	tx_data	<= byte;
	
	for x in 8 downto 0 loop
		scl		<= '0';
		
		if x = 0 and ack = '1' then		-- simulate Master ACK
			sda	<= '0';
		else
			sda	<= 'H';
		end if;
		
		wait for waitdly * 2;
		scl		<= '1';
		wait for waitdly * 4;
		scl		<= '0';
		wait for waitdly * 2;
	end loop;

end procedure I2C_READ;


--===================================================================
begin
--===================================================================



process begin
	i_sysclk	<= '0';
	wait for waitdly / 2;
	i_sysclk	<= '1';
	wait for waitdly / 2;
end process;



uut: entity work.i2c_slave_phy
port map
(
	i_sysclk			=> i_sysclk			,		-- System clock;
	i_reset_n			=> i_reset_n		,		-- FSM reset; '0' = reset
	i_tx_data			=> i_tx_data		,		-- Byte to be sent to master
	o_tx_byte_done		=> o_tx_byte_done	,		-- Pulse (in SYSCLK) to indicate byte write completion
	o_rx_data			=> o_rx_data		,		-- Byte received from master
	o_rx_valid			=> o_rx_valid		,		-- Valid pulse (in SYSCLK) for read byte
	o_fsm_frame			=> o_fsm_frame		,		-- FSM busy status; '0' = idle; '1' = active
	o_nack				=> o_nack			,		-- Master NACKs; can indicate end of comms. '1' = NACK
	io_phy_scl			=> io_phy_scl		,
	io_phy_sda			=> io_phy_sda			
);



process begin
	io_phy_scl		<= 'H';
	io_phy_sda		<= 'H';
	
	
	wait for waitdly * 10;
	
	i_reset_n		<= '1';
	wait for waitdly * 10;
	
	i_tx_data		<= x"A5";
	wait for waitdly * 5;
	


-- I2C Master WRITE:	
	I2C_BEGIN( io_phy_scl, io_phy_sda );
	
	I2C_WRITE( x"C8", io_phy_scl, io_phy_sda );
	I2C_WRITE( x"A5", io_phy_scl, io_phy_sda );
	
	I2C_END( io_phy_scl, io_phy_sda );

	wait for waitdly * 10;
	
	
-- I2C Master READ:
	I2C_BEGIN( io_phy_scl, io_phy_sda );
	
	i_tx_data	<= x"B3";
	I2C_WRITE( x"C9", io_phy_scl, io_phy_sda );

	I2C_READ( '1', i_tx_data, io_phy_scl, io_phy_sda ); 	
	I2C_END( io_phy_scl, io_phy_sda );

	wait for waitdly * 10;



	wait;
end process;






--===================================================================
end TB_I2C_SLAVE;
--===================================================================