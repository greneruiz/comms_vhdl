--===================================================================
-- File Name: i2c_master_phy.vhd
-- Type     : FSM
-- Purpose  : Generic I2C master controller
-- Version  : 1.1
--===================================================================
-- Revision History
-- Version/Date : V1.0 / 2024-Nov-28 / G.RUIZ
--		* Initial release
-- Version/Date : V1.1 / 2024-Dec-04 / G.RUIZ
--		* Moved CLKDIV constants into Components' generic maps
-- Version/Date : V1.2 / 2024-Dec-18 / G.RUIZ
--		* Renamed O_BYTE_ACK to O_BYTE_WR_DONE, including signals
--		* Declared new signal O_BYTE_ACK pulse - this is used
--		to indicate an I2C-Slave byte receive acknowledge.
--		* Split I2C_ACK state into -READ and -WRITE states,
--		to prevent O_BYTE_ACK from over-pulsing on READ-ACK states
--===================================================================
--	Functional Description:
--		* FSM uses the external I2C Pull-Ups as Logic-1 ('Z')
--		* Can detect slave clock stretching (SCL being pulled low)
--		* SCL is divided into 4 for FSM data clk
--===================================================================



library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;



entity i2c_master_phy is
generic
(
	SLOW_CLKDIV		: integer range 0 to 20 := 19;						-- (80 / 4) - 1 = 19 SYSCLK ticks at 8 MHz per SCL quadrant
	FAST_CLKDIV		: integer range 0 to 20 := 1						-- ( 8 / 4) - 1 = 1 SYSCLK ticks at 8 MHz per SCL quadrant
);
port
(
	i_sysclk			: in	std_logic;								-- System clock; 8 MHz
	i_reset_n			: in	std_logic;								-- FSM reset
	i_scl_mode_sel		: in	std_logic;								-- '0' = Standard (100kHz); '1' = FastPlus (1MHz)
	i_scl_mode_update	: in	std_logic;								-- Pulse in I_SYSCLK to update SCL frequency
	i_slave_addr		: in	std_logic_vector( 6 downto 0 );			-- I2C Slave device address
	i_rd_wrn			: in	std_logic;								-- 1 = rd; 0 = wr
	i_wr_data			: in	std_logic_vector( 7 downto 0 );			-- Byte to be written to slave
	o_rd_data			: out	std_logic_vector( 7 downto 0 );			-- Byte read from slave
	o_rd_valid			: out	std_logic;								-- Byte read valid
	o_byte_wr_done		: out	std_logic;								-- Pulse in I_SYSCLK to indicate previous byte from the interface layer was sent; can be connected to RDREQ of WRFIFO
	i_frame_ena			: in	std_logic;								-- Transaction frame; keep high to write/read multiple bytes
	o_ack_error			: out	std_logic;								-- I2C Ack; 1 = slave did not acknowledge the byte
	o_byte_ack			: out	std_logic;								-- Pulse in I_SYSCLK indicating a byte-write ACK from I2C Slave
	o_fsm_busyn			: out	std_logic;								-- FSM Status; 1 = idle; 0 = transacting
	io_phy_scl			: inout	std_logic;								-- I2C SCL; connect to bidirectional buffer primitive
	io_phy_sda			: inout	std_logic								-- I2C SDA; connect to bidirectional buffer primitive
);
end entity i2c_master_phy;



--===================================================================
architecture RTL_I2C_MASTER_PHY of i2c_master_phy is
--===================================================================


	type I2C_PHY_STATE is
	(
		STATE_IDLE,
		STATE_I2C_START,
		STATE_I2C_ADDRCMD,
		STATE_CHECK_ADDRCMD_ACK,
		STATE_I2C_WRITE,
		STATE_I2C_READ,
		STATE_I2C_ACK,
		STATE_I2C_RD_ACK,
		STATE_I2C_STOP
	);


	signal s_state, n_state			: I2C_PHY_STATE;
	signal s_wr_byte, n_wr_byte		: std_logic_vector( 7 downto 0 );
	signal s_rd_byte, n_rd_byte		: std_logic_vector( 7 downto 0 );
	signal s_dev_addr, n_dev_addr	: std_logic_vector( 7 downto 0 );
	signal s_busyn, n_busyn			: std_logic;
	signal s_bit_ctr, n_bit_ctr		: integer;
	signal s_byte_wr_done, n_byte_wr_done	: std_logic;
	signal s_rd_valid, n_rd_valid	: std_logic;
	signal s_ack_error, n_ack_error	: std_logic;
	signal s_sda_hiz, n_sda_hiz		: std_logic := '1';					-- Internal SDA; '1' = Tri-State PHY_SDA
	signal s_scl_hiz, n_scl_hiz		: std_logic := '1';					-- Internal SDA; '1' = Tri-State PHY_SCL
	signal s_byte_ack, n_byte_ack	: std_logic;
	
	signal s_data_ena				: std_logic;
	signal s_scl_int				: std_logic;

	signal s_data_ena_sreg			: std_logic_vector( 1 downto 0 );	-- Shift register to detect data_ena's RE/FE
	signal s_scl_int_sreg			: std_logic_vector( 1 downto 0 );	-- Shift register to detect scl_int's RE/FE

	signal s_resetp					: std_logic := '0';
	signal s_sda_final_n			: std_logic;


--===================================================================
begin
--===================================================================


	o_rd_data		<= s_rd_byte;
	o_rd_valid		<= s_rd_valid;
	o_byte_wr_done	<= s_byte_wr_done;
	o_ack_error		<= s_ack_error;
	o_fsm_busyn		<= s_busyn;
	o_byte_ack		<= s_byte_ack;


	with s_state select	s_sda_final_n
		<=	s_data_ena_sreg(1) when STATE_I2C_START,
			not s_data_ena_sreg(1) when STATE_I2C_STOP,
			s_sda_hiz when others;


	io_phy_scl			<= '0' when s_scl_int_sreg(1) = '0' and s_scl_hiz = '0' else 'Z';
	io_phy_sda			<= '0' when s_sda_final_n = '0' else 'Z';



-- -----------------------------------------------------------------
--	Bus clock generator
--		+ Calculates SYSCLK divider
--		+ Generates Data_Ena
-- -----------------------------------------------------------------

	s_resetp			<= not i_reset_n; 

inst_i2c_clkdiv: entity work.I2C_ClkDiv_Static
generic map
(
	SLOW_CLKDIV			=> SLOW_CLKDIV,									-- (80 / 4) - 1 = 19 SYSCLK ticks at 8 MHz per SCL quadrant
	FAST_CLKDIV			=> FAST_CLKDIV									-- ( 8 / 4) - 1 = 1 SYSCLK ticks at 8 MHz per SCL quadrant
)
port map
(
	i_resetp			=> s_resetp,
	i_sysclk			=> i_sysclk,									-- 8 MHz, to meet generic FPGA minimum PLL Fout
	i_scl_mode_sel		=> i_scl_mode_sel,								-- '0' = Standard (100kHz); '1' = FastPlus (1MHz)
	i_update			=> i_scl_mode_update,							-- Pulse at sysclk freq to update CLKDIV
	o_data_ena			=> s_data_ena,									-- 90 degrees offset from io_scl. Used to latch data to SDA (RE), or get data from SDA (FE)
	i_phy_scl			=> io_phy_scl,									-- Open-drain, assumed to be pulled high using a strap		
	o_scl_ena			=> s_scl_int									-- SCL Ena
);



process( i_sysclk )
begin
	if rising_edge( i_sysclk ) then										-- Shift registers to detect Rising/Falling Edges from CLKDIV
		s_data_ena_sreg(0)	<= s_data_ena;
		s_scl_int_sreg(0)	<= s_scl_int;
		s_data_ena_sreg(1)	<= s_data_ena_sreg(0);
		s_scl_int_sreg(1)	<= s_scl_int_sreg(0);
	end if;
end process;


-- -----------------------------------------------------------------
--	FSM Registers
-- -----------------------------------------------------------------

process( i_sysclk, i_reset_n )
begin
	if i_reset_n = '0' then
		s_state			<= STATE_IDLE			;
		s_wr_byte		<= ( others => '0' )	;
		s_rd_byte		<= ( others => '0' )	;
		s_dev_addr		<= ( others => '0' )	;
		s_bit_ctr 		<= 0					;
		s_busyn			<= '0'					;
		s_rd_valid		<= '0'					;
		s_byte_wr_done	<= '0'					;
		s_ack_error		<= '0'					;
		s_sda_hiz		<= '1'					;
		s_scl_hiz		<= '1'					;
		s_byte_ack		<= '0'					;

	elsif rising_edge( i_sysclk ) then
		s_state			<= n_state		;
		s_wr_byte		<= n_wr_byte	;
		s_rd_byte		<= n_rd_byte	;
		s_dev_addr		<= n_dev_addr	;
		s_bit_ctr 		<= n_bit_ctr 	;
		s_busyn			<= n_busyn		;
		s_rd_valid		<= n_rd_valid	;
		s_byte_wr_done	<= n_byte_wr_done;
		s_ack_error		<= n_ack_error	;
		s_sda_hiz		<= n_sda_hiz	;
		s_scl_hiz		<= n_scl_hiz	;
		s_byte_ack		<= n_byte_ack	;

	end if;
end process;


-- -----------------------------------------------------------------
--	FSM Logic
--		Rising Edge of DATA_ENA:
--			+ Assert new data bit to SDA
--			+ Check for slave acknowledge
--		Falling Edge of DATA_ENA:
--			+ Store new data bit from SDA
--			+ Assert ack-error
-- -----------------------------------------------------------------

process
(
	s_state			,
	s_wr_byte		,
	s_rd_byte		,
	s_dev_addr		,
	s_bit_ctr 		,
	s_busyn			,
	s_rd_valid		,
	s_byte_wr_done	,
	s_ack_error		,
	s_sda_hiz		,
	s_scl_hiz		,
	s_byte_ack		,
	i_slave_addr	,
	i_rd_wrn		,
	i_wr_data		,
	i_frame_ena		,
	io_phy_sda		,
	s_data_ena_sreg
)
begin

	n_state			<= s_state		;
	n_wr_byte		<= s_wr_byte	;
	n_rd_byte		<= s_rd_byte	;
	n_dev_addr		<= s_dev_addr	;
	n_bit_ctr 		<= s_bit_ctr 	;
	n_busyn			<= s_busyn		;
	n_rd_valid		<= s_rd_valid	;
	n_byte_wr_done	<= s_byte_wr_done;
	n_ack_error		<= s_ack_error	;
	n_sda_hiz		<= s_sda_hiz	;
	n_scl_hiz		<= s_scl_hiz	;
	n_byte_ack		<= s_byte_ack	;


	------------------------------------------------------------------ Rising edge of DATA_ENA
	if s_data_ena_sreg = "01" then										
		case s_state is
		-------------------------------------------------------------- IDLE STATE
			when STATE_IDLE =>

				if i_frame_ena = '1' then
					n_busyn		<= '0';								-- Begin transaction
					n_dev_addr	<= i_slave_addr & i_rd_wrn;			-- FSM will pump out MSB to SDA
					n_wr_byte	<= i_wr_data;						
					n_bit_ctr	<= 7;								-- MSB; count-down
					n_state		<= STATE_I2C_START;
				else
					n_busyn		<= '1';
					n_state		<= STATE_IDLE;
				end if;


		-------------------------------------------------------------- I2C START, SEND SLAVE ADDR, AND RD_WRN CHECK
			when STATE_I2C_START =>
				n_sda_hiz		<= s_dev_addr( s_bit_ctr );			-- Preload sda_hiz with the data; SDA_FINAL should be pulled low using post-FSM logic 
				n_state			<= STATE_I2C_ADDRCMD;


			when STATE_I2C_ADDRCMD =>
				if s_bit_ctr = 0 then
					n_sda_hiz	<= '1';								-- Tri-state to allow slave byte acknowledge
					n_bit_ctr	<= 7;								
					n_state		<= STATE_CHECK_ADDRCMD_ACK;
				else
					n_sda_hiz	<= s_dev_addr( s_bit_ctr - 1 ); 
					n_bit_ctr	<= s_bit_ctr - 1;
					n_state		<= STATE_I2C_ADDRCMD;
				end if;


			when STATE_CHECK_ADDRCMD_ACK =>							-- Actual slave ack check is done at DATA_ENA FE; we check RD/WRn here
				if s_dev_addr(0) = '0' then							-- I2C Write
					n_sda_hiz	<= s_wr_byte( s_bit_ctr );
					n_state		<= STATE_I2C_WRITE;
				else												-- I2C Read
					n_sda_hiz	<= '1';								-- Tri-state to allow slave byte push
					n_state		<= STATE_I2C_READ;
				end if;
				

		-------------------------------------------------------------- I2C WRITE
			when STATE_I2C_WRITE =>
				if s_bit_ctr = 0 then
					n_sda_hiz	<= '1';
					n_bit_ctr	<= 7;
					n_byte_wr_done	<= '1';								-- Acknowledge the requested byte-write from the interface layer
					n_state		<= STATE_I2C_ACK;
				else
					n_sda_hiz	<= s_wr_byte( s_bit_ctr - 1 );
					n_bit_ctr	<= s_bit_ctr - 1;
					n_state		<= STATE_I2C_WRITE; 
				end if;


			when STATE_I2C_ACK =>
				n_byte_wr_done	<= '0';
				n_rd_valid		<= '0';

				if i_frame_ena = '1' then
					n_busyn		<= '0';								-- Continue transaction
					n_dev_addr	<= i_slave_addr & i_rd_wrn;
					n_wr_byte	<= i_wr_data;						
					n_bit_ctr	<= 7;
					
					if s_dev_addr = i_slave_addr & i_rd_wrn then
						if s_dev_addr(0) = '0' then
							n_sda_hiz	<= i_wr_data( s_bit_ctr );
							n_state	<= STATE_I2C_WRITE;
						else
							n_sda_hiz	<= '1';
							n_state	<= STATE_I2C_READ;
						end if;
					else
						n_state	<= STATE_I2C_START;
					end if;
				else
					n_sda_hiz	<= '0';								-- Prep SDA low for I2C stop sequence
--					n_busyn		<= '1';
					n_state		<= STATE_I2C_STOP;
				end if;


		-------------------------------------------------------------- I2C READ
			when STATE_I2C_READ =>
				if s_bit_ctr = 0 then
					n_bit_ctr	<= 7;
					n_rd_valid	<= '1';
					n_state		<= STATE_I2C_RD_ACK;

					if i_frame_ena = '1' and s_dev_addr = i_slave_addr & i_rd_wrn then	-- Check if there's a next byte transaction
						n_sda_hiz	<= '0';							-- Byte acknowledge
					else											-- This is the last byte; NACK to mark as last of the block transfer 
						n_sda_hiz	<= '1';
					end if;
				else
					n_bit_ctr	<= s_bit_ctr - 1;
					n_state		<= STATE_I2C_READ;
				end if;


			when STATE_I2C_RD_ACK =>
				n_rd_valid		<= '0';

				if i_frame_ena = '1' then
					n_busyn		<= '0';								-- Continue transaction
					n_dev_addr	<= i_slave_addr & i_rd_wrn;
					n_wr_byte	<= i_wr_data;						
					n_bit_ctr	<= 7;
					
					if s_dev_addr = i_slave_addr & i_rd_wrn then
						if s_dev_addr(0) = '0' then
							n_sda_hiz	<= i_wr_data( s_bit_ctr );
							n_state	<= STATE_I2C_WRITE;
						else
							n_sda_hiz	<= '1';
							n_state	<= STATE_I2C_READ;
						end if;
					else
						n_state	<= STATE_I2C_START;
					end if;
				else
					n_sda_hiz	<= '0';								-- Prep SDA low for I2C stop sequence
--					n_busyn		<= '1';
					n_state		<= STATE_I2C_STOP;
				end if;


		-------------------------------------------------------------- I2C STOP
			when STATE_I2C_STOP =>
				n_scl_hiz		<= '1';
				n_sda_hiz		<= '1';
				n_busyn		<= '1';
				n_state		<= STATE_IDLE;

		end case;

	------------------------------------------------------------------ Falling edge of DATA_ENA
	elsif s_data_ena_sreg = "10" then								
		case s_state is
			WHEN STATE_I2C_START =>
				n_scl_hiz		<= '0';
				n_ack_error		<= '0';
				n_byte_ack		<= '0';


			when STATE_CHECK_ADDRCMD_ACK =>
				if io_phy_sda /= '0' or s_ack_error = '1' then
					n_ack_error		<= '1';
				else
					n_byte_ack		<= '1';
				end if;

			
			when STATE_I2C_WRITE =>
				n_byte_ack			<= '0';


			when STATE_I2C_READ =>
				n_rd_byte(s_bit_ctr)	<= io_phy_sda;
				n_byte_ack				<= '0';


			when STATE_I2C_ACK =>
				if io_phy_sda /= '0' or s_ack_error = '1' then
					n_ack_error		<= '1';
				else
					n_byte_ack		<= '1';
				end if;
				
				
			when STATE_I2C_RD_ACK =>
				if io_phy_sda /= '0' or s_ack_error = '1' then
					n_ack_error		<= '1';
				end if;


			when STATE_I2C_STOP =>
				n_scl_hiz		<= '1';
				n_byte_ack		<= '0';

			
			when others => NULL;
		end case;
	end if;

end process;




--===================================================================
end RTL_I2C_MASTER_PHY;
--===================================================================
