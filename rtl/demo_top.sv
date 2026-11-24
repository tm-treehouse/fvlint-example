// SPDX-FileCopyrightText: 2026 The fvlint Authors
// SPDX-License-Identifier: ISC
//
// A small, made-up packet buffer used to demonstrate fvlint on a design with
// hierarchy, a package and a mix of clean and buggy structures.

package demo_pkg;
  localparam int DEPTH = 100;   // deliberately not a power of two
  localparam int AW = 7;
  typedef enum logic [2:0] {S_IDLE, S_HDR, S_BODY, S_PAD, S_ERR} state_t;
endpackage

// Ring buffer with a registered almost-full flag.
module demo_fifo import demo_pkg::*; (
  input  logic          clk,
  input  logic          rst_n,
  input  logic          push,
  input  logic          pop,
  input  logic [7:0]    din,
  output logic [7:0]    dout,
  output logic          afull
);
  logic [7:0]    mem [DEPTH];
  logic [AW-1:0] wp, rp;
  logic [AW:0]   count;          // 0..DEPTH
  wire do_push = push && !afull;
  wire do_pop  = pop && (count != 0);

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) begin
      wp <= '0;
      rp <= '0;
      count <= '0;
      afull <= 1'b0;
    end else begin
      if (do_push) wp <= (wp == AW'(DEPTH - 1)) ? '0 : wp + 1'b1;
      if (do_pop)  rp <= (rp == AW'(DEPTH - 1)) ? '0 : rp + 1'b1;
      if (do_push && !do_pop) count <= count + 1'b1;
      else if (do_pop && !do_push) count <= count - 1'b1;
      afull <= (count >= (AW+1)'(DEPTH - 2));   // registered: leaves room for 2 in flight
    end

  always_ff @(posedge clk) if (do_push) mem[wp] <= din;
  assign dout = mem[rp];
endmodule

// Framer FSM with a byte-lane select.
module demo_framer import demo_pkg::*; (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic        last,
  input  logic [1:0]  lane,      // which byte of the 3-byte header word
  input  logic [23:0] hdr,
  output logic [7:0]  hdr_byte,
  (* fvlint_waive = "counter_overflow" *)   // sequence number wraps by design
  output logic [3:0]  seq,
  output logic        err,
  output logic        busy
);
  state_t st;
  logic [3:0] pad;

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) begin
      st  <= S_IDLE;
      seq <= '0;
      pad <= '0;
      err <= 1'b0;
    end else begin
      case (st)
        S_IDLE: if (start) st <= S_HDR;
        S_HDR:  st <= S_BODY;
        S_BODY: if (last) begin
                  st <= S_PAD;
                  seq <= seq + 1'b1;
                end
        S_PAD:  if (pad == 4'd3) st <= S_IDLE;
        S_ERR:  begin                    // nothing ever enters S_ERR
                  err <= 1'b1;
                  st  <= S_IDLE;
                end
        default: st <= S_IDLE;
      endcase
      if (st == S_PAD) pad <= pad + 1'b1; else pad <= '0;
    end

  assign hdr_byte = hdr[lane*8 +: 8];    // lane 3 would read past the header
  assign busy = (st != S_IDLE);
endmodule

module demo_top (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        push,
  input  logic        pop,
  input  logic [7:0]  din,
  input  logic        start,
  input  logic        last,
  input  logic [1:0]  lane,
  input  logic [23:0] hdr,
  output logic [7:0]  dout,
  output logic        afull,
  output logic [7:0]  hdr_byte,
  output logic [3:0]  seq,
  output logic        err,
  output logic        busy
);
  demo_fifo   u_fifo   (.*);
  demo_framer u_framer (.*);
endmodule
