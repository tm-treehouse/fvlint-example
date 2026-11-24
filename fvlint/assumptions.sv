// SPDX-FileCopyrightText: 2026 The fvlint Authors
// SPDX-License-Identifier: ISC
//
// Environment constraints for demo_top.  Ports are matched by name to the
// top-level inputs; only top-level inputs can be constrained.

module fvlint_assumptions (input [1:0] lane);
  // The integration guarantees only lanes 0..2 are ever requested.
  always @* assume (lane <= 2'd2);
endmodule
