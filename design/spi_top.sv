// Board test for spi_master on the Arty S7-25.
// Sends 00, 01, 02 ... FF, 00 ... once every millisecond and checks that the
// same byte comes back. With MOSI wired to MISO, every byte should match.
//
// BTN0: reset (also clears the error LED)
// LD2:  heartbeat (the design is running)
// LD3:  error, stays on after any mismatch
// LD4:  top bit of the byte being sent (blinks while bytes are flowing)
// LD5:  next bit down (blinks twice as fast)
// JA7:  copy of MISO as received, JA8: copy of MOSI (logic analyzer test points)

module spi_top #(
  parameter int CLKS_PER_HALF_BIT = 6,       // 12 MHz / 12 = 1 MHz SCLK
  parameter int CLKS_PER_BYTE     = 12000    // one transfer every 1 ms
) (
  input  logic       i_Clk,       // 12 MHz
  input  logic       i_Btn0,      // 1 when pressed
  output logic       o_SPI_CS_n,
  output logic       o_SPI_MOSI,
  input  logic       i_SPI_MISO,
  output logic       o_SPI_Clk,
  output logic       o_Dbg_MISO,  // test point: copy of MISO
  output logic       o_Dbg_MOSI,  // test point: copy of MOSI
  output logic [3:0] o_Led
);

  // Reset: button pressed = reset (the design expects 0 = reset)
  wire w_Rst_n = ~i_Btn0;

  logic       r_Tx_Start;
  logic [7:0] r_Tx_Byte;
  wire        w_Busy;
  wire  [7:0] w_Rx_Byte;
  wire        w_Rx_Done;

  spi_master #(.CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT)) u_spi (
    .i_Clk     (i_Clk),
    .i_Rst_n   (w_Rst_n),
    .i_Tx_Byte (r_Tx_Byte),
    .i_Tx_Start(r_Tx_Start),
    .o_Busy    (w_Busy),
    .o_Rx_Byte (w_Rx_Byte),
    .o_Rx_Done (w_Rx_Done),
    .o_SPI_Clk (o_SPI_Clk),
    .o_SPI_MOSI(o_SPI_MOSI),
    .i_SPI_MISO(i_SPI_MISO),
    .o_SPI_CS_n(o_SPI_CS_n)
  );

  // Sender: start a transfer every CLKS_PER_BYTE clocks
  logic [$clog2(CLKS_PER_BYTE)-1:0] r_Timer;

  always_ff @(posedge i_Clk or negedge w_Rst_n) begin
    if (!w_Rst_n) begin
      r_Timer    <= '0;
      r_Tx_Start <= 1'b0;
      r_Tx_Byte  <= 8'hFF;      // first byte sent will be 00
    end else begin
      r_Tx_Start <= 1'b0;
      if (r_Timer == CLKS_PER_BYTE - 1) begin
        r_Timer <= '0;
        if (!w_Busy) begin
          r_Tx_Byte  <= r_Tx_Byte + 1'b1;
          r_Tx_Start <= 1'b1;
        end
      end else begin
        r_Timer <= r_Timer + 1'b1;
      end
    end
  end

  // Checker: the byte received must equal the byte sent
  logic r_Error;

  always_ff @(posedge i_Clk or negedge w_Rst_n) begin
    if (!w_Rst_n)
      r_Error <= 1'b0;
    else if (w_Rx_Done && (w_Rx_Byte != r_Tx_Byte))
      r_Error <= 1'b1;
  end

  // Heartbeat: about 0.7 Hz from the 12 MHz clock
  logic [23:0] r_Heartbeat;

  always_ff @(posedge i_Clk or negedge w_Rst_n) begin
    if (!w_Rst_n) r_Heartbeat <= '0;
    else          r_Heartbeat <= r_Heartbeat + 1'b1;
  end

  // Test points for the logic analyzer
  assign o_Dbg_MISO = i_SPI_MISO;
  assign o_Dbg_MOSI = o_SPI_MOSI;

  assign o_Led[0] = r_Heartbeat[23];
  assign o_Led[1] = r_Error;
  assign o_Led[2] = r_Tx_Byte[7];
  assign o_Led[3] = r_Tx_Byte[6];

endmodule