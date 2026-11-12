// Synchronous FIFO: one clock, write side and read side.
// DEPTH must be a power of 2 (4, 8, 16, ...) so the pointers wrap by themselves.
module fifo #(
  parameter WIDTH = 8,     // bits per slot (one byte)
  parameter DEPTH = 16     // number of slots
)(
  input  wire             i_Clk,
  // write side (the RX puts bytes in)
  input  wire             i_Wr_En,
  input  wire [WIDTH-1:0] i_Wr_Data,
  // read side (the TX takes bytes out)
  input  wire             i_Rd_En,
  output wire [WIDTH-1:0] o_Rd_Data,
  // status
  output wire             o_Empty,
  output wire             o_Full
);

  localparam PTR_W = $clog2(DEPTH);          // 16 slots -> 4-bit pointers

  // ---------- storage ----------
  reg [WIDTH-1:0] r_Mem [0:DEPTH-1];         // 16 slots of 8 bits
  reg [PTR_W-1:0] r_Wr_Ptr = 0;              // where the next byte goes
  reg [PTR_W-1:0] r_Rd_Ptr = 0;              // the oldest byte
  reg [PTR_W:0]   r_Count  = 0;              // 0..16 -> needs 5 bits

  // ---------- safety rules ----------
  wire w_Wr = i_Wr_En && !o_Full;            // never write when full
  wire w_Rd = i_Rd_En && !o_Empty;           // never read when empty

  // ---------- write, read, count ----------
  always @(posedge i_Clk) begin
    if (w_Wr) begin
      r_Mem[r_Wr_Ptr] <= i_Wr_Data;          // store the byte
      r_Wr_Ptr        <= r_Wr_Ptr + 1;       // move to the next slot (wraps 15 -> 0)
    end

    if (w_Rd)
      r_Rd_Ptr <= r_Rd_Ptr + 1;              // read = just move the pointer

    case ({w_Wr, w_Rd})
      2'b10:   r_Count <= r_Count + 1;       // write only
      2'b01:   r_Count <= r_Count - 1;       // read only
      default: ;                             // both or neither: no change
    endcase
  end

  // ---------- outputs ----------
  assign o_Rd_Data = r_Mem[r_Rd_Ptr];        // the front byte, always visible
  assign o_Empty   = (r_Count == 0);
  assign o_Full    = (r_Count == DEPTH);

endmodule