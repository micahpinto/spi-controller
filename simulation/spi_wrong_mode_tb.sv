// SPI master and the peripheral use different modes.
// The master is fixed in mode 0. The peripheral model first uses mode 0 (same as
// the master), then mode 1 (wrong mode). Each data wire has a small delay, as on a
// real board, so a side that reads at the moment the other side changes the wire
// still sees the old bit. The test passes when every byte matches the prediction.
`timescale 1ns/1ps
module spi_wrong_mode_tb;

  localparam int  CLKS_PER_HALF_BIT = 2;
  localparam real CLK_PERIOD        = 83.333;   // 12 MHz
  localparam int  WIRE_DELAY        = 5;        // ns, delay on MOSI and MISO

  logic       r_Clk      = 0;
  logic       r_Rst_n    = 0;
  logic [7:0] r_Tx_Byte  = 0;
  logic       r_Tx_Start = 0;

  wire        w_Busy;
  wire  [7:0] w_Rx_Byte;
  wire        w_Rx_Done;
  wire        w_SPI_Clk;
  wire        w_SPI_CS_n;
  wire        w_MOSI_Out;                       // MOSI as it leaves the master
  logic       r_MISO_Out = 0;                   // MISO as it leaves the peripheral

  // The wires: each one delivers its value WIRE_DELAY ns later
  wire #(WIRE_DELAY) w_SPI_MOSI = w_MOSI_Out;
  wire #(WIRE_DELAY) w_SPI_MISO = r_MISO_Out;

  // Master, always mode 0
  spi_master #(.CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT), .CPOL(0), .CPHA(0)) dut (
    .i_Clk     (r_Clk),
    .i_Rst_n   (r_Rst_n),
    .i_Tx_Byte (r_Tx_Byte),
    .i_Tx_Start(r_Tx_Start),
    .o_Busy    (w_Busy),
    .o_Rx_Byte (w_Rx_Byte),
    .o_Rx_Done (w_Rx_Done),
    .o_SPI_Clk (w_SPI_Clk),
    .o_SPI_MOSI(w_MOSI_Out),
    .i_SPI_MISO(w_SPI_MISO),
    .o_SPI_CS_n(w_SPI_CS_n)
  );

  always #(CLK_PERIOD / 2) r_Clk = ~r_Clk;

  int errors = 0;

  // ---------------------------------------------------------------
  // Peripheral model. Its mode can be changed between transfers.
  // ---------------------------------------------------------------
  logic       r_P_CPOL = 0;
  logic       r_P_CPHA = 0;
  logic [7:0] r_P_Tx   = 0;   // byte the peripheral sends
  logic [7:0] r_P_Rx   = 0;   // byte the peripheral receives
  int         r_P_First = 0;  // first edges seen in this transfer

  always @(negedge w_SPI_CS_n) begin
    r_MISO_Out = r_P_Tx[7];
    r_P_First  = 0;
  end

  // First edge = SCLK moving away from the level the peripheral expects when idle
  always @(w_SPI_Clk)
    if (w_SPI_CS_n === 1'b0) begin
      if (w_SPI_Clk !== r_P_CPOL) begin       // first edge
        r_P_First++;
        if (!r_P_CPHA)
          r_P_Rx = {r_P_Rx[6:0], w_SPI_MOSI};
        else if (r_P_First > 1) begin
          r_P_Tx     = {r_P_Tx[6:0], 1'b0};
          r_MISO_Out = r_P_Tx[7];
        end
      end else begin                           // second edge
        if (!r_P_CPHA) begin
          r_P_Tx     = {r_P_Tx[6:0], 1'b0};
          r_MISO_Out = r_P_Tx[7];
        end else
          r_P_Rx = {r_P_Rx[6:0], w_SPI_MOSI};
      end
    end

  // ---------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------
  task automatic check(input string name, input logic [7:0] got, input logic [7:0] predicted);
    if (got === predicted)
      $display("PASS  %s = %h (as predicted)", name, got);
    else begin
      $display("FAIL  %s = %h, predicted %h", name, got, predicted);
      errors++;
    end
  endtask

  // One transfer, then compare both received bytes with the prediction
  task automatic transfer(input logic [7:0] m_byte, input logic [7:0] p_byte,
                          input logic [7:0] master_predicted,
                          input logic [7:0] periph_predicted);
    r_P_Tx = p_byte;
    wait (w_Busy == 0);
    @(posedge r_Clk);
    r_Tx_Byte  <= m_byte;
    r_Tx_Start <= 1;
    @(posedge r_Clk);
    r_Tx_Start <= 0;
    @(posedge w_Rx_Done);
    #1;
    $display("master sent %h, peripheral sent %h", m_byte, p_byte);
    check("  master got    ", w_Rx_Byte, master_predicted);
    check("  peripheral got", r_P_Rx,    periph_predicted);
  endtask

  initial begin
    #1ms;
    $display("FAIL  timeout");
    $finish;
  end

  initial begin
    repeat (3) @(posedge r_Clk);
    r_Rst_n <= 1;
    repeat (2) @(posedge r_Clk);

    $display("--- Master mode 0, peripheral mode 0 (same mode)");
    r_P_CPOL = 0;  r_P_CPHA = 0;
    transfer(8'hA5, 8'h3C, 8'h3C, 8'hA5);
    transfer(8'h80, 8'h01, 8'h01, 8'h80);
    transfer(8'h01, 8'h80, 8'h80, 8'h01);

    $display("--- Master mode 0, peripheral mode 1 (wrong mode)");
    r_P_CPOL = 0;  r_P_CPHA = 1;
    // The master reads each MISO bit at the moment the peripheral changes it,
    // so it gets the first bit twice and never gets the last one.
    transfer(8'hA5, 8'h3C, 8'h1E, 8'hA5);
    transfer(8'h80, 8'h01, 8'h00, 8'h80);
    transfer(8'h01, 8'h80, 8'hC0, 8'h01);

    $display("==========================================");
    if (errors == 0) $display("TEST PASSED: every byte matches the prediction");
    else             $display("TEST FAILED: %0d bytes differ from the prediction", errors);
    $display("==========================================");
    $finish;
  end

endmodule