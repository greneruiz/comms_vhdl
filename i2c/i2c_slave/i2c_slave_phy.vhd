--===================================================================
-- File Name: i2c_slave_phy.vhd
-- Type     : FSM
-- Purpose  : Generic I2C slave controller (oversample method)
-- Version  : 1.0
--===================================================================
-- Revision History
-- Version/Date : V1.0 / 2025-Jan-28 / G.RUIZ
--		* Initial release
--===================================================================
--	Functional Description:
--		* FSM uses SYS_CLK to oversample the SCL and SDA pins
--		* FSM uses the external I2C Pull-Ups as Logic-1 ('Z')
--		* SYSCLK must be able to at least 8x oversample the SCL
--		* Can perform clock stretching - To Be Implemented
--		* Clock stretching is NOT compatible with I2C High-speed mode
--===================================================================



library ieee;
use ieee.std_logic_1164.all;



entity i2c_slave_phy is
generic
(
	SLAVE_ADDRESS		: std_logic_vector( 7 downto 0 ) := x"C8"		-- Slave Address; [0] = MASTER_RD_WRN bit
);
port
(
	i_sysclk			: in	std_logic;								-- System clock;
	i_reset_n			: in	std_logic;								-- FSM reset; '0' = reset
	i_tx_data			: in	std_logic_vector( 7 downto 0 );			-- Byte to be sent to master
	o_tx_byte_done		: out	std_logic;								-- Pulse (in SYSCLK) to indicate byte write completion
	o_rx_data			: out	std_logic_vector( 7 downto 0 );			-- Byte received from master
	o_rx_valid			: out	std_logic;								-- Valid pulse (in SYSCLK) for read byte
	o_fsm_frame			: out	std_logic;								-- FSM busy status; '0' = idle; '1' = active
	o_nack				: out	std_logic;								-- Master NACKs; can indicate end of comms. '1' = NACK
	io_phy_scl			: inout	std_logic;
	io_phy_sda			: inout	std_logic
);
end entity i2c_slave_phy;



--===================================================================
architecture RTL_I2C_SLAVE_PHY of i2c_slave_phy is
--===================================================================


	type I2C_SLV_PHY_STATE is
	(
		STATE_SENSE_I2C_START,
		STATE_I2C_ADDRCMD,
		STATE_I2C_ACK,
		STATE_I2C_RX,
		STATE_I2C_TX_READY,
		STATE_I2C_TX,
		STATE_WAIT_MASTER_ACK
	);


	signal s_state, n_state					: I2C_SLV_PHY_STATE;
	signal s_bit_ctr, n_bit_ctr				: integer;
	signal s_dev_addr, n_dev_addr			: std_logic_vector( 7 downto 0 );
	signal s_sda_hiz_n, n_sda_hiz_n			: std_logic := '0';
	signal s_tx_byte, n_tx_byte				: std_logic_vector( 7 downto 0 );
	signal s_rx_byte, n_rx_byte				: std_logic_vector( 7 downto 0 );
	signal s_nack, n_nack					: std_logic;


	signal s_rx_valid, n_rx_valid			: std_logic;
	signal s_tx_byte_done, n_tx_byte_done	: std_logic;
	
	
	
	signal s_sda_det						: std_logic_vector( 1 downto 0 );
	signal s_scl_det						: std_logic_vector( 1 downto 0 );
	signal s_frame							: std_logic := '0';
	signal s_scl_stretch					: std_logic := '0';
	
	

--===================================================================
begin
--===================================================================


	o_tx_byte_done		<= s_tx_byte_done;
	o_rx_data			<= s_rx_byte;
	o_rx_valid			<= s_rx_valid;
	o_fsm_frame			<= s_frame;
	o_nack				<= s_nack;
	
	io_phy_scl			<= '0' when s_scl_stretch = '1' else 'Z';
	io_phy_sda			<= '0' when s_sda_hiz_n = '1' else 'Z';


-- -----------------------------------------------------------------
--	Edge Detector
-- -----------------------------------------------------------------

process( i_sysclk )
begin
	if rising_edge( i_sysclk ) then
		if io_phy_sda = '0' then
			s_sda_det(0)	<= '0';
		else
			s_sda_det(0)	<= '1';
		end if;

		if io_phy_scl = '0' then
			s_scl_det(0)	<= '0';
		else
			s_scl_det(0)	<= '1';
		end if;

		s_sda_det(1)	<= s_sda_det(0);
		s_scl_det(1)	<= s_scl_det(0);
	end if;
end process;



-- -----------------------------------------------------------------
--	Start & Stop Detector
-- -----------------------------------------------------------------

process( i_sysclk )
begin
	if rising_edge( i_sysclk ) then
		if s_scl_det = "11" and s_sda_det = "10" then
			s_frame		<= '1';
		end if;
		
		if s_scl_det = "11" and s_sda_det = "01" then
			s_frame		<= '0';
		end if;
	end if;
end process;



-- -----------------------------------------------------------------
--	FSM Registers
-- -----------------------------------------------------------------

process( i_sysclk, i_reset_n, s_frame )
begin
	if i_reset_n = '0' or s_frame = '0' then
		s_state			<= STATE_SENSE_I2C_START;
		s_bit_ctr		<= 0;
		s_dev_addr		<= x"00";
		s_sda_hiz_n		<= '0';
		s_nack			<= '0';
		s_tx_byte		<= x"00";
		s_rx_byte		<= x"00";
		s_rx_valid		<= '0';
		s_tx_byte_done	<= '0';
	
	elsif rising_edge( i_sysclk ) then
		s_state			<= n_state			;
        s_bit_ctr		<= n_bit_ctr		;
        s_dev_addr		<= n_dev_addr		;
		s_sda_hiz_n		<= n_sda_hiz_n		;
        s_nack			<= n_nack			;
		s_tx_byte		<= n_tx_byte		;
		s_rx_byte		<= n_rx_byte		;
        s_rx_valid		<= n_rx_valid		;
        s_tx_byte_done	<= n_tx_byte_done	;
		
	end if;
end process;



process
(
	i_tx_data		,
	io_phy_scl		,
	io_phy_sda		,
	s_scl_det		,
	s_sda_det		,
	s_frame			,

	s_state			,
	s_bit_ctr		,
	s_dev_addr		,
	s_sda_hiz_n		,	
	s_nack			,
	s_tx_byte		,
	s_rx_byte		,	
	s_rx_valid		,
	s_tx_byte_done	
	
)
begin

	n_state			<= s_state			;
	n_bit_ctr		<= s_bit_ctr		;
	n_dev_addr		<= s_dev_addr		;
	n_sda_hiz_n		<= s_sda_hiz_n		;
	n_nack			<= s_nack			;
	n_tx_byte		<= s_tx_byte		;
	n_rx_byte		<= s_rx_byte		;
	n_rx_valid		<= s_rx_valid		;
	n_tx_byte_done	<= s_tx_byte_done	;


	case s_state is
		when STATE_SENSE_I2C_START =>								
			n_bit_ctr			<= 8;											-- Reset bit counter;
			n_state				<= STATE_I2C_ADDRCMD;							-- Catch next byte as Slave Address + RD_WRN
			
	
		when STATE_I2C_ADDRCMD =>
			if s_scl_det = "01" then											-- Detect SCL rising edge
				if s_bit_ctr > 0 then								
					n_dev_addr(s_bit_ctr - 1)	<= s_sda_det(1);	
					n_bit_ctr					<= s_bit_ctr - 1;
				end if;
			end if;
			
			if s_scl_det = "10" then											-- Detect SCL falling edge
				if s_bit_ctr = 0 then											-- Received all 8 bits:
					if s_dev_addr(7 downto 1) = SLAVE_ADDRESS(7 downto 1) then	-- Slave address matched:
						n_sda_hiz_n			<= '1';								-- SDA = '0' for ACK
						n_bit_ctr			<= 8;
					else
						n_sda_hiz_n			<= '0';
					end if;
					
					n_state					<= STATE_I2C_ACK;
				end if;
			end if;
			
	
		-------------------------------------------------------------------------- I2C Acknowledge
		when STATE_I2C_ACK =>
			n_rx_valid					<= '0';
		
			if s_scl_det = "10" and s_sda_hiz_n = '1' then						-- Detect SCL falling edge; Address was acknowledged:
				if s_dev_addr(0) = '1' then										-- Master is READING; Slave is transmitting
					n_state				<= STATE_I2C_TX_READY;
					n_tx_byte			<= i_tx_data;			
				else															-- Master is WRITING; Slave is receiving
					n_state				<= STATE_I2C_RX;
					n_sda_hiz_n			<= '0';
				end if;
			end if;
		
		
		-------------------------------------------------------------------------- I2C Receive
		when STATE_I2C_RX =>
			if s_scl_det = "01" then											-- Detect SCL rising edge
				if s_bit_ctr > 0 then
					n_rx_byte(s_bit_ctr - 1)	<= s_sda_det(1);
					n_bit_ctr					<= s_bit_ctr - 1;
				end if;
			end if;
			
			if s_scl_det = "10" then											-- Detect SCL falling edge
				if s_bit_ctr = 0 then											-- Received all 8 bits:
					n_sda_hiz_n			<= '1';									-- SDA = '0' for ACK
					n_bit_ctr			<= 8;
					n_rx_valid			<= '1';
					n_state				<= STATE_I2C_ACK;
				else
					n_sda_hiz_n			<= '0';
					n_state				<= STATE_I2C_RX;
				end if;
				
			end if;


		-------------------------------------------------------------------------- I2C Transmit
		when STATE_I2C_TX_READY =>
			n_sda_hiz_n				<= not s_tx_byte(s_bit_ctr - 1);			-- SDA = 'Z' when TX[x] = '1'
			n_state					<= STATE_I2C_TX;

			
		when STATE_I2C_TX =>
			if s_scl_det = "01" then											-- Detect SCL rising edge
				if s_bit_ctr > 0 then
					n_bit_ctr		<= s_bit_ctr - 1;
				end if;
			end if;
		
			if s_scl_det = "10" then											-- Detect SCL falling edge
				if s_bit_ctr > 0 then
					n_state				<= STATE_I2C_TX_READY;
				else
					n_state				<= STATE_WAIT_MASTER_ACK;
					n_sda_hiz_n			<= '1';									-- Wait for Master-ACK
				end if;
			end if;
			
			
		when STATE_WAIT_MASTER_ACK =>
			if s_scl_det = "01" then											-- Detect SCL rising edge
				n_tx_byte_done			<= '1';									-- Pulse BYTE_DONE back to controller
				
				if s_sda_det(1) = '1' then										-- Master NACKs the tx
					n_nack				<= '1';
				end if;
			else
				n_tx_byte_done			<= '0';
				n_nack					<= '0';
			end if;
			
			if s_scl_det = "10" then											-- Detect SCL falling edge
				n_state					<= STATE_I2C_TX_READY;
				n_tx_byte				<= i_tx_data;
				n_bit_ctr				<= 8;
			end if;
			
		
	end case;
	

end process;





--===================================================================
end RTL_I2C_SLAVE_PHY;
--===================================================================