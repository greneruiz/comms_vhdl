--===================================================================
-- File Name: spi_slave_phy.vhd
-- Type     : FSM
-- Purpose  : SPI-Slave controller
-- Version  : 1.0
--===================================================================
-- Revision History
-- Version/Date : V1.0 / 2024-DEC-03 / GREN
--		* Initial release
--		* Resource utilization: 39 registers, 36 LUTs (Xilinx Virtex 6)
--===================================================================
--	Functional Description:
--	I.	Supports having a different bit size for the first
--		message (for devices that have command-address schemes).
--		Declare this on INIT_DATA_LENGTH generic map.
--		* Subsequent master-messages and slave-messages use the
--		same bit size, declared on the DATA_LENGTH generic map.
--		* Note that this controller does not support slave-writes
--		during the first master-message SCK's.
--	II.	Allows an MSB- or LSB-first bit ordering, CPOL and CPHA 
--	III. Note that generics are pre-set on compile-time, and
--		are not modifiable on-the-fly.
--===================================================================



library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;



entity spi_slave_phy is
generic
(
	ENDIAN				: string	:= "MSB";									-- Bit ordering: "LSB" = LSB first; "MSB" = MSB first
	DATA_LENGTH			: integer range 0 to 32	:= 8;							-- Message string bit length
	INIT_DATA_LENGTH	: integer range 0 to 32	:= 8;							-- First message string bit length
	SPI_CPOL			: std_logic	:= '0';										-- SCL Polarity: '1' : CSL = '1' when idle
	SPI_CPHA			: std_logic	:= '0'										-- Clock-Data phase: '1' : Data is shifted on RE of SCL
);
port
(
	i_reset_n			: in	std_logic;										-- FSM Reset, logic-low
	i_sysclk			: in	std_logic;										-- System clock; minimum 2x of SCK
	i_miso_data			: in	std_logic_vector( DATA_LENGTH - 1 downto 0 );	-- Data to be sent to the master
	o_miso_done			: out	std_logic;										-- Request new message to send to master; Pulses at SYSCLK frequency
	o_mosi_data1		: out	std_logic_vector( INIT_DATA_LENGTH - 1 downto 0 );	
	o_mosi_valid1		: out	std_logic;
	o_mosi_datax		: out	std_logic_vector( DATA_LENGTH - 1 downto 0 );	
	o_mosi_validx		: out	std_logic;
	o_spi_busyn			: out	std_logic;
	i_phy_sck			: in	std_logic;
	i_phy_csn			: in	std_logic;
	i_phy_sdi			: in	std_logic;
	o_phy_sdo			: out	std_logic
);
end entity spi_slave_phy;



--===================================================================
architecture RTL_SPI_SLAVE of spi_slave_phy is
--===================================================================

	
	
	type SPI_SLAVE_STATE is
	(
		STATE_IDLE,
		STATE_PROCESS_1ST_MESSAGE,
		STATE_PROCESS_NTH_MESSAGE,
		STATE_STOP
	);
	
	
	signal s_state, n_state			: SPI_SLAVE_STATE;
	signal s_busyn, n_busyn			: std_logic;
	signal s_bit_ctr, n_bit_ctr		: integer range 0 to 32;
	signal s_data1, n_data1			: std_logic_vector( INIT_DATA_LENGTH - 1 downto 0 );
	signal s_datax, n_datax			: std_logic_vector( DATA_LENGTH - 1 downto 0 );
	signal s_valid1, n_valid1		: std_logic;
	signal s_validx, n_validx		: std_logic;

	signal s_byte_wr, n_byte_wr		: std_logic_vector( DATA_LENGTH - 1 downto 0 );
	signal s_byte_done, n_byte_done	: std_logic;
	signal s_sdo, n_sdo				: std_logic;
	

	signal s_sck	: std_logic_vector( 1 downto 0 );
	signal s_csn	: std_logic_vector( 1 downto 0 );
	signal s_sdi	: std_logic_vector( 1 downto 0 );
	
	
	

--===================================================================
begin
--===================================================================

	
	o_miso_done			<= s_byte_done;
	o_mosi_data1		<= s_data1;
	o_mosi_valid1		<= s_valid1;
	o_mosi_datax		<= s_datax;
	o_mosi_validx		<= s_validx;
	o_spi_busyn			<= s_busyn;
	o_phy_sdo			<= s_sdo;
	
	

process( i_sysclk )
begin
	if rising_edge( i_sysclk ) then
		if SPI_CPOL = '0' then
			s_sck(0)	<= i_phy_sck;
		else
			s_sck(0)	<= not i_phy_sck;
		end if;
		s_csn(0)		<= i_phy_csn;
		s_sdi(0)		<= i_phy_sdi;

		s_sck(1)		<= s_sck(0);
		s_csn(1)		<= s_csn(0);
		s_sdi(1)		<= s_sdi(0);
	end if;
end process;

	


process( i_sysclk, i_reset_n )
begin
	if i_reset_n = '0' then
		s_state			<= STATE_IDLE;
		s_busyn			<= '0';
		s_bit_ctr		<= 0;
		s_data1			<= ( others => '0' );
		s_datax			<= ( others => '0' );
		s_valid1		<= '0';
		s_validx		<= '0';
		s_byte_wr		<= ( others => '0' );
		s_byte_done		<= '0';
		s_sdo			<= '0';
		
	elsif rising_edge( i_sysclk ) then
		s_state			<= n_state;
		s_busyn			<= n_busyn;
		s_bit_ctr		<= n_bit_ctr;
		s_data1			<= n_data1;
		s_datax			<= n_datax;
		s_valid1		<= n_valid1;
		s_validx		<= n_validx;
		s_byte_wr		<= n_byte_wr;
		s_byte_done		<= n_byte_done;
		s_sdo			<= n_sdo;
	end if;
end process;



process
(
	s_state			,
	s_busyn			,
	s_bit_ctr		,
	s_data1			,
	s_datax			,
	s_valid1		,
	s_validx		,
	s_byte_wr		,
	s_byte_done		,
	s_sdo			,
	s_sck			,
	s_csn			,
	s_sdi			,
	i_miso_data
)
is
	variable CPHA_COND_WR		: std_logic_vector( 1 downto 0 ) := "00";
	variable CPHA_COND_RD		: std_logic_vector( 1 downto 0 ) := "00";
begin

	if SPI_CPHA = '0' then
		CPHA_COND_WR	:= "01";
		CPHA_COND_RD	:= "10";
	else
		CPHA_COND_WR	:= "10";
		CPHA_COND_RD	:= "01";
	end if;

	n_state			<= s_state;
	n_busyn			<= s_busyn;
	n_bit_ctr		<= s_bit_ctr;
	n_data1			<= s_data1;
	n_datax			<= s_datax;
	n_valid1		<= s_valid1;
	n_validx		<= s_validx;
	n_byte_wr		<= s_byte_wr;
	n_byte_done		<= s_byte_done;
	n_sdo			<= s_sdo;
	
	
---------------------------------------------------------------------------------- SLAVE RECEIVE STATES
	case s_state is
		when STATE_IDLE =>
			if s_csn = "10" then												-- Slave becomes active on CSN falling edge, regardless of SCK idle level
				n_busyn			<= '0';
				if ENDIAN = "MSB" then											-- Check bit ordering; assign bit pointer's initial index
					n_bit_ctr	<= INIT_DATA_LENGTH - 1;					
				else
					n_bit_ctr	<= 0;
				end if;
				
				n_state			<= STATE_PROCESS_1ST_MESSAGE;					-- Handles INIT_DATA_LENGTH-sized first string.
			else
				n_busyn			<= '1';
				n_state			<= STATE_IDLE;
			end if;
		

		when STATE_PROCESS_1ST_MESSAGE =>
			n_valid1		<= '0';
			
			if s_sck = CPHA_COND_WR and s_csn = "00" then						-- If SCK transitions to data phase
				n_data1( s_bit_ctr )	<= s_sdi(0);
				
				if ENDIAN = "MSB" then											-- Bit order = MSB first
					if s_bit_ctr = 0 then										-- If INIT_DATA is completely transmitted by master,
						n_valid1		<= '1';									-- Mark first message
						n_bit_ctr		<= DATA_LENGTH - 1;						-- reset bit pointer to nth_message bit length
						n_state			<= STATE_PROCESS_NTH_MESSAGE;			-- wait for nth message/s
					else
						n_bit_ctr		<= s_bit_ctr - 1;						-- decrement bit pointer
						n_state			<= STATE_PROCESS_1ST_MESSAGE;
					end if;
				else															-- Bit order = LSB first
					if s_bit_ctr = INIT_DATA_LENGTH - 1 then					-- If INIT_DATA is completely transmitted by master,
						n_valid1		<= '1';									-- Mark first message
						n_bit_ctr		<= 0;									-- reset bit pointer
						n_state			<= STATE_PROCESS_NTH_MESSAGE;			-- wait for nth message/s
					else
						n_bit_ctr		<= s_bit_ctr + 1;						-- increment bit pointer
						n_state			<= STATE_PROCESS_1ST_MESSAGE;
					end if;
				end if;
			else
				n_valid1		<= '0';
				n_state			<= STATE_PROCESS_1ST_MESSAGE;
			end if;
			
	
		when STATE_PROCESS_NTH_MESSAGE =>
			n_valid1			<= '0';
			n_validx			<= '0';
			
			if s_sck = CPHA_COND_WR and s_csn = "00" then						-- If SCK transitions to data phase
				n_datax( s_bit_ctr )	<= s_sdi(0);
				
				if ENDIAN = "MSB" then											-- Bit order = MSB first
					if s_bit_ctr = 0 then										-- If DATA is completely transmitted by master,
						n_validx		<= '1';									-- Mark completed message
						n_bit_ctr		<= DATA_LENGTH - 1;						-- reset bit pointer
					else
						n_bit_ctr		<= s_bit_ctr - 1;						-- decrement bit pointer
					end if;
				else															-- Bit order = LSB first
					if s_bit_ctr = DATA_LENGTH - 1 then							-- If DATA is completely transmitted by master,
						n_validx		<= '1';									-- Mark completed message
						n_bit_ctr		<= 0;									-- reset bit pointer
					else
						n_bit_ctr		<= s_bit_ctr + 1;						-- increment bit pointer						n_state			<= STATE_PROCESS_NTH_MESSAGE;
					end if;
				end if;
			end if;

			if s_csn = "01" then												-- If CSN deasserts, stop transacting
				n_state			<= STATE_STOP;
			else
				n_state			<= STATE_PROCESS_NTH_MESSAGE;
			end if;
		
		
		when STATE_STOP =>
			n_busyn			<= '1';
			n_state			<= STATE_IDLE;
	end case;



---------------------------------------------------------------------------------- SLAVE TRANSMIT STATES
	case s_state is
		when STATE_PROCESS_NTH_MESSAGE =>
			n_byte_wr		<= i_miso_data;
			n_byte_done		<= '0';
			
			if s_sck = CPHA_COND_RD and s_csn = "00" then						-- If SCK transitions to data phase
				n_sdo		<= s_byte_wr( s_bit_ctr );
				
				if ENDIAN = "MSB" then											-- Bit order = MSB first
					if s_bit_ctr = 0 then
						n_byte_done		<= '1';									-- Assert O_BYTE_DONE to get next data (if any)
					end if;

					if s_bit_ctr = DATA_LENGTH - 1 then
						n_byte_wr	<= i_miso_data;
					end if;
				else															-- Bit order = LSb first
					if s_bit_ctr = DATA_LENGTH - 1 then
						n_byte_done		<= '1';									-- Assert O_BYTE_DONE to get next data (if any)
					end if;

					if s_bit_ctr = 0 then
						n_byte_wr	<= i_miso_data;
					end if;
				end if;
			end if;
	
		when others => NULL;
	end case;

end process;




--===================================================================
end RTL_SPI_SLAVE;
--===================================================================
