// Self-checking testbench for spi_master (mode 0).
// A simple peripheral model on the other side of the SPI wires sends its own
// byte back, so every transfer checks both directions.
`timescale 1ns/1ps
module spi_master_tb;

  //other SCLK speeds (2, 3, 5)
  localparam int CLKS_PER_HALF_BIT = 2;
  localparam real CLK_PERIOD = 83.333;    // 12 MHz

  logic       r_Clk      = 0;
  logic       r_Rst_n    = 0;
  logic [7:0] r_Tx_Byte  = 0;
  logic       r_Tx_Start = 0;

  wire        w_Busy;
  wire  [7:0] w_Rx_Byte;
  wire        w_Rx_Done;
  wire        w_SPI_Clk;
  wire        w_SPI_MOSI;
  wire        w_SPI_CS_n;
  logic       r_MISO = 0;

  spi_master #(.CLKS_PER_HALF_BIT(CLKS_PER_HALF_BIT)) dut (
    .i_Clk     (r_Clk),
    .i_Rst_n   (r_Rst_n),
    .i_Tx_Byte (r_Tx_Byte),
    .i_Tx_Start(r_Tx_Start),
    .o_Busy    (w_Busy),
    .o_Rx_Byte (w_Rx_Byte),
    .o_Rx_Done (w_Rx_Done),
    .o_SPI_Clk (w_SPI_Clk),
    .o_SPI_MOSI(w_SPI_MOSI),
    .i_SPI_MISO(r_MISO),
    .o_SPI_CS_n(w_SPI_CS_n)
  );

  always #(CLK_PERIOD / 2) r_Clk = ~r_Clk;

  int errors = 0;

  // ---------------------------------------------------------------
  // Peripheral model (mode 0)
  // ---------------------------------------------------------------
  logic [7:0] r_P_Tx = 0;   // byte the peripheral sends
  logic [7:0] r_P_Rx = 0;   // byte the peripheral receives

  // CS_n falls: put the first bit on MISO
  always @(negedge w_SPI_CS_n)
    r_MISO = r_P_Tx[7];

  // SCLK rising: read MOSI into the bottom
  always @(posedge w_SPI_Clk)
    if (!w_SPI_CS_n)
      r_P_Rx = {r_P_Rx[6:0], w_SPI_MOSI};

  // SCLK falling: shift, put the next bit on MISO
  always @(negedge w_SPI_Clk)
    if (!w_SPI_CS_n) begin
      r_P_Tx = {r_P_Tx[6:0], 1'b0};
      r_MISO = r_P_Tx[7];
    end

  // ---------------------------------------------------------------
  // Counters and SCLK period measurement
  // ---------------------------------------------------------------
  int  r_Pulses   = 0;      // SCLK rising edges in the current transfer
  int  r_CS_Falls = 0;      // number of transfers started
  realtime r_Last_Rise = 0;
  realtime r_Period    = 0;

  always @(negedge w_SPI_CS_n) begin
    r_Pulses = 0;
    r_CS_Falls++;
  end

  always @(posedge w_SPI_Clk) begin
    r_Pulses = r_Pulses + 1;
    if (r_Pulses > 1) r_Period = $realtime - r_Last_Rise;
    r_Last_Rise = $realtime;
  end

  // ---------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------
  task automatic check(input string       name,
                       input logic [31:0] got,
                       input logic [31:0] expected);
    if (got === expected)
      $display("PASS  %s = %h", name, got);
    else begin
      $display("FAIL  %s = %h, expected %h   (time %0t)", name, got, expected, $time);
      errors++;
    end
  endtask

  // Start one transfer: wait until the master is free, then a 1-clock start pulse
  task automatic start_transfer(input logic [7:0] m_byte,
                                input logic [7:0] p_byte);
    r_P_Tx = p_byte;
    wait (w_Busy == 0);
    @(posedge r_Clk);
    r_Tx_Byte  <= m_byte;
    r_Tx_Start <= 1;
    @(posedge r_Clk);
    r_Tx_Start <= 0;
  endtask

  // One full transfer with all the checks
  task automatic spi_transfer(input logic [7:0] m_byte,
                              input logic [7:0] p_byte);
    start_transfer(m_byte, p_byte);
    @(posedge w_Rx_Done);
    #1;
    check("master got",  w_Rx_Byte, p_byte);
    check("periph got",  r_P_Rx,    m_byte);
    check("SCLK pulses", r_Pulses,  8);
    check("SCLK idle",   w_SPI_Clk, 0);
    check("CS_n idle",   w_SPI_CS_n, 1);
    check("busy at done", w_Busy,   0);
    // o_Rx_Done must be high for one clock only
    @(posedge r_Clk);
    #1;
    check("done is 1 clock", w_Rx_Done, 0);
  endtask

  // Watchdog: stop if the test hangs
  initial begin
    #2ms;
    $display("FAIL  timeout");
    $display("TEST FAILED");
    $finish;
  end

  // ---------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------
  int  falls_before;
  int  expected_period;

  initial begin
    $display("CLKS_PER_HALF_BIT = %0d", CLKS_PER_HALF_BIT);
    repeat (3) @(posedge r_Clk);
    r_Rst_n <= 1;
    repeat (2) @(posedge r_Clk);

    // Test 1: lines at rest after reset
    $display("--- Test 1: after reset");
    check("SCLK", w_SPI_Clk,  0);
    check("CS_n", w_SPI_CS_n, 1);
    check("busy", w_Busy,     0);

    // Test 2: both directions
    $display("--- Test 2: A5 / 3C");
    spi_transfer(8'hA5, 8'h3C);

    // Test 3: data line held at 0 or 1 for the whole byte
    $display("--- Test 3: 00 / FF and FF / 00");
    spi_transfer(8'h00, 8'hFF);
    spi_transfer(8'hFF, 8'h00);

    // Test 4: bit order, most significant bit first
    $display("--- Test 4: 80 / 01");
    spi_transfer(8'h80, 8'h01);
    spi_transfer(8'h01, 8'h80);

    // Test 5 (SCLK pulses) and test 6 (busy, done) are checked in every transfer

    // Test 7: a new start while busy is ignored
    $display("--- Test 7: start while busy");
    falls_before = r_CS_Falls;
    start_transfer(8'hC3, 8'h5A);
    repeat (4 * CLKS_PER_HALF_BIT) @(posedge r_Clk);   // somewhere in the middle
    r_Tx_Byte  <= 8'hFF;
    r_Tx_Start <= 1;
    @(posedge r_Clk);
    r_Tx_Start <= 0;
    @(posedge w_Rx_Done);
    #1;
    check("master got",  w_Rx_Byte, 8'h5A);
    check("periph got",  r_P_Rx,    8'hC3);
    check("SCLK pulses", r_Pulses,  8);
    repeat (20) @(posedge r_Clk);
    check("no second transfer", r_CS_Falls - falls_before, 1);
    check("busy after",  w_Busy, 0);

    // Test 8: two bytes back to back
    $display("--- Test 8: back to back");
    falls_before = r_CS_Falls;
    spi_transfer(8'h12, 8'h34);
    spi_transfer(8'h56, 8'h78);
    check("CS_n fell twice", r_CS_Falls - falls_before, 2);

    // Test 9: random bytes
    $display("--- Test 9: 20 random pairs");
    repeat (20) spi_transfer($urandom, $urandom);

    // Test 10: SCLK period
    $display("--- Test 10: SCLK period");
    expected_period = $rtoi(2 * CLKS_PER_HALF_BIT * CLK_PERIOD + 0.5);
    $display("SCLK period measured %0.1f ns, expected %0d ns", r_Period, expected_period);
    check("SCLK period (ns)", $rtoi(r_Period + 0.5), expected_period);

    $display("==========================================");
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d errors", errors);
    $display("==========================================");
    $finish;
  end

endmodule