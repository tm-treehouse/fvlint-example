<!--
SPDX-FileCopyrightText: 2026 The fvlint Authors
SPDX-License-Identifier: ISC
-->
# fvlint example

A minimal project that runs [fvlint](https://github.com/tm-treehouse/fvlint)
in GitHub Actions. fvlint finds common structures in RTL (counters, case
statements, variable part-selects, memories, FIFOs, FSMs), writes a small property
for each one, and proves it formally on the logic around that structure. You
get lint-style output, where each result is a proof or a counterexample trace.

Everything fvlint needs is in four files:

| File | What it is |
|---|---|
| [`fvlint.toml`](fvlint.toml) | The project file: top module, sources, frontend, assumptions, waivers |
| [`fvlint/assumptions.sv`](fvlint/assumptions.sv) | What the design may assume about its inputs |
| [`fvlint/waivers.txt`](fvlint/waivers.txt) | Findings that are intentional |
| [`.github/workflows/fvlint.yml`](.github/workflows/fvlint.yml) | The CI job: checkout, then `uses: tm-treehouse/fvlint@v0.7.0` |

## The design

[`rtl/demo_top.sv`](rtl/demo_top.sv) is a small, made-up packet buffer: a
FIFO with 100 entries (not a power of two) and a framer FSM. fvlint finds 13
checks in it:

| Structure | Check | Result |
|---|---|---|
| FIFO read and write pointers, `wp`, `rp` | `counter_overflow` | PROVEN: they go back to 0 after 99, so `+ 1` never overflows |
| FIFO fill level, `count` | `counter_overflow`, `counter_underflow` | PROVEN: never wraps in either direction |
| FIFO memory, `mem[100]` | `mem_addr` (read and write) | PROVEN: the address never reaches 100..127 |
| The FIFO as a whole | `fifo_overflow`, `fifo_underflow` | PROVEN: no write while it holds 100 entries, no read while it is empty |
| Framer padding counter, `pad` | `counter_overflow` | PROVEN |
| Header byte select, `hdr[lane*8 +: 8]` | `index_range` | PROVEN, given the assumption `lane <= 2` |
| Framer FSM, `st` | `fsm_summary` | INFO: 4 states reachable from reset |
| Framer state `S_ERR` | `fsm_unreachable` | WAIVED: a defensive state, kept on purpose (waiver file) |
| Sequence number, `seq` | `counter_overflow` | WAIVED: wraps by design (`fvlint_waive` attribute in the RTL) |

## What CI shows

Each push runs the workflow. The job summary has a table of the results, and
the `fvlint` artifact has `results.json`, a JUnit file and, for any failure,
the counterexample trace (VCD). A finding fails the job and appears as an
annotation on the RTL line it is about. This repository has none, so the job
passes.

## Running it locally

Install the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build)
(Yosys, SymbiYosys, solvers and the yosys-slang SystemVerilog frontend), then:

```
pip install git+https://github.com/tm-treehouse/fvlint@v0.7.0
fvlint --config fvlint.toml -v
```

```
=== fvlint: demo
fvlint 0.7.0: top demo_top, 62 cells, 13 checks; reset: rst_n (active 0, held 1 cycle(s)); yosys 0.71 (native), solver=yices, abc=yes

12.9s, 14 solver jobs, engine pdr; results in fvlint_out/demo/
fvlint: 13 checks: 1 info, 10 proven, 2 waived

INFO    fsm_summary:u_framer.st             rtl/demo_top.sv:61  4 reachable states from reset 3'b000
PROVEN  fifo_overflow:u_fifo.mem            rtl/demo_top.sv:23  proven by k-induction with 3 helper lemma(s) on cone full (with the design's count as a helper)
PROVEN  fifo_underflow:u_fifo.mem           rtl/demo_top.sv:23  proven by PDR on cone 0 (with the design's count as a helper)
PROVEN  mem_addr:u_fifo.mem.rd0             rtl/demo_top.sv:23  proven by k-induction with 3 helper lemma(s) on cone 0+1r after 1 refinement(s)
PROVEN  mem_addr:u_fifo.mem.wr0             rtl/demo_top.sv:23  proven by k-induction with 3 helper lemma(s) on cone 0+1r after 1 refinement(s)
PROVEN  counter_overflow:u_fifo.rp          rtl/demo_top.sv:24  proven by k-induction with 3 helper lemma(s) on cone 1
PROVEN  counter_overflow:u_fifo.wp          rtl/demo_top.sv:24  proven by PDR on cone 0
PROVEN  counter_overflow:u_fifo.count       rtl/demo_top.sv:25  proven by k-induction with 3 helper lemma(s) on cone full
PROVEN  counter_underflow:u_fifo.count      rtl/demo_top.sv:25  proven by PDR on cone 0
PROVEN  counter_overflow:u_framer.pad       rtl/demo_top.sv:62  proven by k-induction with 3 helper lemma(s) on cone full after 1 refinement(s)
PROVEN  index_range:u_framer.hdr_byte       rtl/demo_top.sv:88  proven by PDR on cone full
WAIVED  counter_overflow:u_framer.seq       rtl/demo_top.sv:57  fvlint_waive attribute (counter_overflow)
WAIVED  fsm_unreachable:u_framer.st=3'b100  rtl/demo_top.sv:61  waiver file: fsm_unreachable:u_framer.st=* (S_ERR is a defensive state kept on purpose)
```

The exit status is 0 when there are no findings, 1 when there are, and 2
when fvlint couldn't run.

## Seeing a finding

Delete the `assume = ...` line from `fvlint.toml` and run again. Nothing then
stops `lane` from being 3, so the header select can read past the 24-bit
header:

```
fvlint: 13 checks: 1 fail, 1 info, 9 proven, 2 waived

FAIL  index_range:u_framer.hdr_byte  rtl/demo_top.sv:88  counterexample at step 1 on the full design (top-level inputs unconstrained)
```

The trace is in `fvlint_out/demo/`; `results.json` names its file. In CI the
same finding fails the job, with an annotation on line 88.

## Using it on your own design

Copy `fvlint.toml` and `.github/workflows/fvlint.yml`, and set `top` and
`files` (drop `frontend = "slang"` for plain Verilog). Run once without
assumptions or waivers. For each finding, either fix the RTL, constrain an
input in the assumptions file, or waive it as intentional.

A design that already has findings you can't deal with at once can still
gate CI on new ones: add `baseline = "fvlint/baseline.json"` to its
configuration, record the current findings with
`fvlint --config fvlint.toml --update-baseline`, and commit the file. From
then on only findings that aren't in it fail the job; the known ones are
still reported, as notices.

The fvlint README explains
[project files](https://github.com/tm-treehouse/fvlint#project-files),
[assumptions and waivers](https://github.com/tm-treehouse/fvlint#triage-assumptions-and-waivers),
[baselines](https://github.com/tm-treehouse/fvlint#baselines) and the
[Action's inputs](https://github.com/tm-treehouse/fvlint#in-ci-github-actions).
For a real design, see
[picorv32-fvlint](https://github.com/tm-treehouse/picorv32-fvlint), which
runs fvlint on the PicoRV32 RISC-V core.

The design and files here are ISC-licensed, like fvlint.
