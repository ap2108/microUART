# UART – RTL Design and Verification

A parameterised UART (Universal Asynchronous Receiver/Transmitter) implemented in Verilog, with a self-checking testbench that supports both transmitter and receiver verification including back-to-back frames, idle gaps, and invalid start bit rejection.

---

## Project Structure

```
├── uart.v              Top-level UART wrapper
├── u_baud.v            Baud rate generator (x16 clock)
├── u_xmit.v            UART transmitter
├── u_rec.v             UART receiver
├── uart_tb.v           Testbench
└── README.md
```

---

## Module Overview

### `uart.v` — Top Level

Instantiates and connects the three submodules. Exposes the full TX and RX interface to the outside world.

**Parameters**

| Parameter | Description |
|---|---|
| `WIDTH` | Data width in bits (default 8) |
| `SYS_CLK_FREQ` | System clock frequency in Hz |
| `BAUD_RATE` | Desired baud rate in bps |

**Ports**

| Port | Dir | Description |
|---|---|---|
| `sys_clk` | in | System clock |
| `sys_rst_l` | in | Active-low synchronous reset |
| `xmitH` | in | Assert to start transmission |
| `xmit_dataH` | in | Byte to transmit |
| `xmit_doneH` | out | Pulses high when frame is complete |
| `xmit_active` | out | High while transmitting |
| `uart_XMIT_dataH` | out | Serial TX line |
| `uart_REC_dataH` | in | Serial RX line |
| `rec_readyH` | out | High when received byte is valid |
| `rec_busy` | out | High while receiving a frame |
| `rec_dataH` | out | Received byte |

---

### `u_baud.v` — Baud Rate Generator

Divides `sys_clk` down to a x16 oversampling clock (`clk_out`) used by both the transmitter and receiver.

```
MAX_COUNT = SYS_CLK_FREQ / (BAUD_RATE * 32)
uart_clk toggles every MAX_COUNT sys_clk cycles
1 baud period = 16 uart_clk cycles
```

**Internal signals visible in waveform**

| Signal | Description |
|---|---|
| `count` | Current divider count |
| `clk_out` | x16 baud clock output |

---

### `u_xmit.v` — Transmitter

Serialises a `WIDTH`-bit word into a standard UART frame: start bit (0), LSB-first data, stop bit (1).

**Frame format**

```
  Idle  | Start | D0 | D1 | D2 | D3 | D4 | D5 | D6 | D7 | Stop | Idle
    1       0                      data bits (LSB first)       1
```

**Operation**

- When `xmitH` is asserted, loads `xmit_dataH` and begins shifting on the next `uart_clk` edge.
- `xmit_active` stays high for the duration of the frame.
- `xmit_doneH` pulses high on the final clock of the stop bit.
- If `xmitH` remains high when `xmit_doneH` pulses, the next byte is loaded immediately (back-to-back mode).

**Internal signals visible in waveform**

| Signal | Description |
|---|---|
| `tx_r` | Shift register holding the current frame |
| `count` | Bit clock counter (0–15 per bit) |
| `active` | Transmitter active flag |
| `done` | Frame complete flag |

**Known bugs fixed from original design**

| Bug | Description |
|---|---|
| Shift trigger | Original used `count==15`, shifting only once per 16 clocks. Fixed to shift every clock while active. |
| Completion check | Original used `tx_r==0` which never fires for data containing any 1 bit. Fixed to use counter: `count == WIDTH+1`. |
| Race on `done` | Two competing assignments to `done` in the same always block. Fixed by giving `done` a single priority-clear assignment path. |
| `active` never cleared | Depended on `done` which was stuck. Fixed to clear `active` directly when frame counter completes. |
| Unsized literal | `assign out = active ? tx_r[0] : 1` used a 32-bit literal. Fixed to `1'b1`. |

---

### `u_rec.v` — Receiver

Deserialises an incoming UART frame from `uart_REC_dataH` using x16 oversampling. Samples each bit at its centre clock (clock 8 of 16) for maximum noise margin.

**Operation**

- Detects the falling edge of the start bit using a two-flop synchroniser (`sync0`, `sync1`).
- Validates the start bit at the midpoint. If the line has returned high by then, the start bit is rejected as a glitch.
- Shifts in `WIDTH` data bits, sampling at clock 8 of each 16-clock window.
- Asserts `rec_readyH` for one clock after the stop bit is sampled and the full byte is in `rec_dataH`.

**Internal signals visible in waveform**

| Signal | Description |
|---|---|
| `sync0`, `sync1` | Two-flop synchroniser for `uart_REC_dataH` |
| `count` | Oversampling clock counter within the current bit |
| `nbits` | Number of bits received so far in current frame |
| `busy` | Receiver busy flag |
| `ready` | Byte ready flag |

---

## Testbench

### Timing and Parameters

```verilog
`timescale 1us/1ns

localparam real SYS_CLK_MHZ = 100;     // system clock in MHz
localparam      BAUD_RATE   = 9600;     // baud rate in bps
localparam      WIDTH       = 8;        // data width

localparam real SYS_CLK_HALF_PERIOD = 1.0 / (SYS_CLK_MHZ * 2.0);   // us
localparam      BAUD_CLKS = (SYS_CLK_MHZ * 1000) / BAUD_RATE;       // sys_clk cycles per baud bit
```

With these values: 1 uart_clk period = 20 sys_clk cycles, 1 baud period = 16 uart_clk cycles = 320 sys_clk cycles.

---

### Testbench Architecture

The testbench separates driving and checking into distinct tasks, then composes them.

```
drive_tx          — asserts xmitH, loads xmit_dataH, builds exp_frame
check_tx          — samples uart_XMIT_dataH for one full frame, compares to exp_frame
check_and_drive_tx — forks drive_tx and check_tx in parallel for back-to-back TX
drive_and_check_rx — drives uart_REC_dataH serially and checks rec_dataH and flags
do_reset          — applies active-low reset and initialises all inputs
```

**Module-level registers** (`exp_frame`, `got_frame`, `invalid_start`) are used instead of task-local variables to retain state across task calls, since Verilog-2001 tasks are automatic by default and do not preserve local values between invocations.

---

### TX Checking — `check_tx`

Samples `uart_XMIT_dataH` using the x16 `uart_clk`. For each of the `WIDTH+2` bits (start + data + stop), it samples at every clock within the 16-clock window and sets `pass=0` if the line disagrees with `exp_frame[i]` at any point.

After the frame, it checks:
- `xmit_doneH == 1` — frame completed
- `xmit_active == 0` — transmitter returned to idle
- `xmitH && !xmit_active == 0` — no spurious active drop while en is held

---

### RX Checking — `drive_and_check_rx`

Forks two parallel threads:

**DRIVE thread** — serialises the input byte onto `uart_REC_dataH`, one bit per 16 uart_clk cycles. If `invalid_start` is set, drives a short 2-clock glitch and returns the line high, simulating a false start bit.

**CHECK thread** — waits 2 uart_clk cycles after start, then monitors `rec_busy` and `rec_readyH` across the full frame duration (`16*9 + 8` clocks). After the frame, checks `rec_dataH == in`.

For the invalid start case, the CHECK thread verifies that `rec_busy` de-asserts and `rec_readyH` does not assert — confirming the receiver correctly rejected the glitch.

---

### Test Cases

| TC | Feature | Description |
|---|---|---|
| 1 | TX basic | Single byte `0xB3` |
| 2 | TX all-ones | `0xFF` — all data bits high |
| 3 | TX all-zeros | `0x00` — all data bits low |
| 4 | TX back-to-back | `0xC5` → `0x7D` → `0x4F` with no idle gap between frames |
| 5 | TX xmitH=0 | `xmitH` de-asserted — transmitter stays idle, line stays high |
| 6 | RX basic | Receive `0xB3` |
| 7 | RX all-ones | Receive `0xFF` |
| 8 | RX all-zeros | Receive `0x00` |
| 9 | RX back-to-back | Receive `0xC5` → `0x7D` → `0x4F` with no idle gap |
| 10 | RX invalid start | 2-clock glitch on RX line — receiver must reject and not assert `rec_readyH` |

---

### Output Format

```
TC=1 | PASS | EXP_FRAME: [START=0  DATA=10110011  STOP=1] | GOT_FRAME: [START=0  DATA=10110011  STOP=1] | FLAG CHECK PASS
TC=6 | PASS | EXP_DATA=10110011 | GOT_DATA=10110011 | FLAG CHECK PASS
```

TX tests print the full serialised frame (start + data + stop). RX tests print the received data byte. Both report a FLAG Check which verifies the control signals (`xmit_active`, `xmit_doneH`, `rec_busy`, `rec_readyH`) behaved correctly across the frame.

---

### Running the Simulation

**Icarus Verilog**
```bash
iverilog -o sim uart_tb.v uart.v u_baud.v u_xmit.v u_rec.v
vvp sim
gtkwave wave.vcd
```

**ModelSim / Questa**
```bash
vlog uart.v u_baud.v u_xmit.v u_rec.v uart_tb.v
vsim uart_tb
run -all
```

---

### Waveform — Key Signals to Observe

| Signal | What to look for |
|---|---|
| `uart_XMIT_dataH` | Start bit low, 8 data bits LSB-first, stop bit high |
| `xmit_active` | High for exactly `WIDTH+2` baud periods |
| `xmit_doneH` | Single-clock pulse at end of stop bit |
| `uart_REC_dataH` | Driven serial waveform from testbench |
| `rec_busy` | Goes high on start bit detection, low after stop bit |
| `rec_readyH` | Single-clock pulse after valid frame received |
| `dut.u1.clk_out` | x16 baud clock — 16 cycles per baud bit |
| `dut.u2.tx_r` | Shift register draining LSB-first during TX |
| `dut.u3.nbits` | Increments 0→9 as each bit is received |
