// PC-driven test for spi_master on the Arty S7-25.
// Each byte received from the PC over the UART is sent out on SPI. The byte
// read back on MISO is stored in a FIFO and sent back to the PC by the UART TX.
// With MOSI wired to MISO, the PC gets back exactly what it sent.
//
// BTN0: reset (SPI master and error flag)
// LD2:  heartbeat
// LD3:  error: a byte arrived while the SPI master was busy, or the FIFO was full
// LD4, LD5: lowest two bits of the last byte read back on SPI
// JA7:  copy of MISO, JA8: copy of MOSI (logic analyzer test points)

module spi_uart_top #(
  parameter int CLKS_PER_BIT      = 104,   // 12,000,000 / 115,200
  parameter int CLKS_PER_HALF_BIT = 6      // 12 MHz / 12 = 1 MHz SCLK
) (
  input  logic       i_Clk,        // 12 MHz
  input  logic       i_Btn0,       // 1 when pressed
  input  logic       uart_txd_in,  // PC to FPGA line
  output logic       uart_rxd_out, // FPGA to PC line
  output logic       o_SPI_CS_n,
  output logic       o_SPI_MOSI,
  input  logic       i_SPI_MISO,
  output logic       o_SPI_Clk,
  output logic       o_Dbg_MISO,   // test point: copy of MISO
  output logic       o_Dbg_MOSI,   // test point: copy of MOSI
  output logic [3:0] o_Led
);

  wire w_Rst_n = ~i_Btn0;

  // UART receiver: byte from the PC
  wire       w_Uart_Rx_DV;
  wire [7:0] w_Uart_Rx_Byte;

  uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_rx (
    .i_Clock     (i_Clk),
    .i_Rx_Serial (uart_txd_in),
    .o_Rx_DV     (w_Uart_Rx_DV),
    .o_Rx_Byte   (w_Uart_Rx_Byte)
  );

  // SPI master: send the byte, read the byte coming back on MISO
  wire       w_Spi_Busy;
  wire       w_Spi_Done;
  wire [7:0] w_Spi_Byte;
  wire       w_Spi_Start = w_Uart_Rx_DV && !w_Spi_Busy;

  spi_master #(.CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT)) u_spi (
    .i_Clk      (i_Clk),
    .i_Rst_n    (w_Rst_n),
    .i_Tx_Byte  (w_Uart_Rx_Byte),
    .i_Tx_Start (w_Spi_Start),
    .o_Busy     (w_Spi_Busy),
    .o_Rx_Byte  (w_Spi_Byte),
    .o_Rx_Done  (w_Spi_Done),
    .o_SPI_Clk  (o_SPI_Clk),
    .o_SPI_MOSI (o_SPI_MOSI),
    .i_SPI_MISO (i_SPI_MISO),
    .o_SPI_CS_n (o_SPI_CS_n)
  );

  // FIFO: holds the bytes read on SPI until the UART transmitter is free
  wire       w_Fifo_Empty;
  wire       w_Fifo_Full;
  wire [7:0] w_Fifo_Byte;
  wire       w_Tx_Ready;
  wire       w_Tx_Start = !w_Fifo_Empty && w_Tx_Ready;

  fifo #(.WIDTH(8), .DEPTH(16)) u_fifo (
    .i_Clk     (i_Clk),
    .i_Wr_En   (w_Spi_Done),
    .i_Wr_Data (w_Spi_Byte),
    .i_Rd_En   (w_Tx_Start),
    .o_Rd_Data (w_Fifo_Byte),
    .o_Empty   (w_Fifo_Empty),
    .o_Full    (w_Fifo_Full)
  );

  // UART transmitter: byte back to the PC
  uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
    .i_Clock     (i_Clk),
    .i_Tx_DV     (w_Tx_Start),
    .i_Tx_Byte   (w_Fifo_Byte),
    .o_Tx_Active (),
    .o_Tx_Serial (uart_rxd_out),
    .o_Tx_Done   (),
    .o_Tx_Ready  (w_Tx_Ready)
  );

  // Error flag: a byte would be lost (SPI busy, or FIFO full). Stays on until reset.
  logic r_Error;

  always_ff @(posedge i_Clk or negedge w_Rst_n) begin
    if (!w_Rst_n)
      r_Error <= 1'b0;
    else if ((w_Uart_Rx_DV && w_Spi_Busy) || (w_Spi_Done && w_Fifo_Full))
      r_Error <= 1'b1;
  end

  // Heartbeat: about 0.7 Hz from the 12 MHz clock
  logic [23:0] r_Heartbeat;

  always_ff @(posedge i_Clk or negedge w_Rst_n) begin
    if (!w_Rst_n) r_Heartbeat <= '0;
    else          r_Heartbeat <= r_Heartbeat + 1'b1;
  end

  // Last byte read back on SPI
  logic [7:0] r_Last_Byte;

  always_ff @(posedge i_Clk or negedge w_Rst_n) begin
    if (!w_Rst_n)        r_Last_Byte <= '0;
    else if (w_Spi_Done) r_Last_Byte <= w_Spi_Byte;
  end

  // Test points for the logic analyzer
  assign o_Dbg_MISO = i_SPI_MISO;
  assign o_Dbg_MOSI = o_SPI_MOSI;

  assign o_Led[0] = r_Heartbeat[23];
  assign o_Led[1] = r_Error;
  assign o_Led[2] = r_Last_Byte[0];
  assign o_Led[3] = r_Last_Byte[1];

endmodule