# LED Mapping Changes — RGB LED (LD0) → cmd_proc States + Diagnostic Bypass

**Date:** 2026-03-02  
**Project:** EPC Gen2 RFID Tag (Arty S7)

---

## Summary

The RGB LED (LD0, "Brain") was previously driven by `fs_detector` states (physical pulse-width detection). It is now driven by the **EPC Gen2 tag state machine** inside `cmd_proc`, which represents the true semantic state of the RFID tag.

A **Hardware Diagnostic Bypass** was subsequently added: switch SW0 selects between *Smart Mode* (real FSM) and *Diagnostic Mode* (manual test state). RGB LED1 (LD1) acts as a visible mode indicator.

---

## Files Changed

| File | Change |
|------|--------|
| `bb_proc.v` | Added `output wire [3:0] cmd_state` port; wired from `cmd_proc.debug_state` |
| `fpga_top.v` | Added `cmd_state` wire + port connection; replaced RGB assign logic |
| `fpga_top.v` | Added Diagnostic Bypass: `sw_diag_mode`, `diag_btn`, `test_state_reg`, `active_state` mux, LD1 logic |
| `arty_s7.xdc` | Added SW0 (A8), diag_btn (K16), LED1 RGB pins (E15/F18/E14); removed `rx_debug` from K16 |
| `led_mapping_changes.md` | This documentation file |

---

## State-to-Color Mapping (LD0 — Brain)

| LED State | Color | Behavior | `active_state` Values |
|-----------|-------|----------|----------------------|
| **IDLE** | 🔵 Blue | Solid ON | `4'h0` |
| **RECEIVE** | 🔵 Blue | Blinking (~2.4 Hz) | `4'h1` (Sloting), `4'h2` (Arbitrate) |
| **PROCESS** | 🔴 Red | Solid + pulse-stretched (~3.35s) | `4'h3` (Reply), `4'h4` (Acknowledged) |
| **ERROR** | 🔴 Red | Blinking (~2.4 Hz) | PROCESS held >6.7s → auto-resets after 6.7s |
| **REPLY** | 🟢 Green | Slow-pulse + pulse-stretched (~3.35s) | `4'h5`–`4'h9` (SlotTran/Open/Secured/Killing/Killed) |

---

## Diagnostic UI — Mode Indicator & Manual Control

### LD1 Mode Indicator

| SW0 Position | Mode | LD1 Color | LD0 Source |
|---|---|---|---|
| **SW0 = 0** | Smart Mode | 🔵 Solid Blue | Real `cmd_state` from `bb_proc > cmd_proc` |
| **SW0 = 1** | Diagnostic Mode | 🔴 Solid Red | Manual `test_state_reg` (stepped by BTN1) |

> **LD1 is exclusively a mode indicator.** It has no relation to the RFID tag FSM.
> - `led1_r = sw_diag_mode` — Red ON in Diagnostic Mode
> - `led1_g = 1'b0` — Green always OFF
> - `led1_b = ~sw_diag_mode` — Blue ON in Smart Mode

### BTN1 Diagnostic Step (Diagnostic Mode only)

| `test_state_reg` | Button Presses | LD0 Behavior | Semantic State |
|---|---|---|---|
| `2'd0` | 0 (or 4) | Solid Blue | IDLE |
| `2'd1` | 1 | Blinking Blue (~2.4 Hz) | RECEIVE |
| `2'd2` | 2 | Solid Red + 3.35s stretch | PROCESS |
| `2'd3` | 3 | Slow Green Pulse + 3.35s stretch | REPLY |

- Pressing BTN1 in Smart Mode has **no effect** (gated by `sw_diag_mode`).
- State wraps automatically: `2'd3 + 1 → 2'd0`.
- Debounce window: ~209 ms (20-bit counter @ 5 MHz) — prevents double-stepping.

### Pin Assignments (New)

| Signal | Port | Physical Pin | IOSTANDARD |
|--------|------|-------------|-----------|
| `sw_diag_mode` | SW0 | A8 | LVCMOS33 |
| `diag_btn` | BTN1 | K16 | LVCMOS33 |
| `led1_r` | LD1 Red | E15 | LVCMOS33 |
| `led1_g` | LD1 Green | F18 | LVCMOS33 |
| `led1_b` | LD1 Blue | E14 | LVCMOS33 |

> `rx_debug` (previously K16) was removed from the port list. `reader_cmd` is `mark_debug` and visible in Vivado ILA at no pin cost.

---

## Signal Routing

```
sw_diag_mode (SW0)
    ├──→ LD1: led1_r = sw_diag_mode, led1_b = ~sw_diag_mode, led1_g = 0
    └──→ active_state mux selector
             ├── sw_diag_mode=0: active_state = cmd_state (real bb_proc FSM)
             └── sw_diag_mode=1: active_state = diag_state_mapped (from test_state_reg)

diag_btn (BTN1)
    └──→ 2-stage sync + 20-bit debounce → db_press (single-cycle pulse)
             └──→ test_state_reg [1:0] (increments when sw_diag_mode=1)
                      └──→ diag_state_mapped [3:0]

active_state [3:0]
    ├──→ is_idle / is_receive / is_process / is_reply (decode wires)
    ├──→ proc_stretch [23:0] (pulse-stretch counter, guarded by !error_active)
    ├──→ reply_stretch [23:0] (pulse-stretch counter)
    ├──→ err_timeout_cnt [24:0] (counts while is_process; triggers error_active after ~6.7s)
    ├──→ err_autoreset_cnt [24:0] (counts while error_active; auto-resets after ~6.7s)
    ├──→ led0_b = error_active ? 0 : is_idle | (is_receive & blink)
    ├──→ led0_r = error_active ? blink : proc_stretched
    └──→ led0_g = error_active ? 0 : reply_stretched & ~blink
```

### Error Mode

If `active_state` stays at `4'h3` (PROCESS) for more than ~6.7 seconds (two 3.35s pulse durations), the system enters **Error Mode**:

| Phase | Duration | LD0 Behavior | What Happens |
|-------|----------|--------------|--------------|
| PROCESS (normal) | 0–6.7s | 🟥 Solid Red | `proc_stretched` holds red ON |
| ERROR | 6.7–13.4s | 🟥 Blinking Red (~2.4 Hz) | `error_active=1`, overrides LED |
| AUTO-RESET | 13.4s+ | 🟦 Solid Blue (IDLE) | `error_active` cleared, `test_state_reg→2'd0` |

- Works identically in Smart Mode and Diagnostic Mode (both feed `active_state`).
- Ghost-pulse prevention: `proc_stretch` is guarded by `!error_active` and force-cleared on auto-reset.

---

## Pulse-Stretching Implementation

PROCESS and REPLY states are transient (microsecond-scale at 200 kHz baseband). Without stretching they would be invisible.

**Mechanism:** Two independent 24-bit down-counters clocked at 5 MHz.

- When `is_process` is HIGH → `proc_stretch` is loaded to `24'hFF_FFFF`
- When `is_reply` is HIGH → `reply_stretch` is loaded to `24'hFF_FFFF`
- **Hold time:** 2²⁴ / 5,000,000 Hz ≈ **3.35 seconds**

Works identically in Smart Mode and Diagnostic Mode (since both set the same `active_state` decode wires).

---

## Unchanged LED Mappings (LD2)

| LED | Name | Signal | Condition |
|-----|------|--------|-----------|
| `led[1]` | **Ears** | `locked & ~reader_cmd` | ON when PLL locked AND no active RFID command |
| `led[2]` | **Mouth** | `tag_reply` | ON during backscatter reply (tx active) |

---

## Single-Driver Audit Results

```
led0_b  : 1 driver  →  assign led0_b = error_active ? 1'b0 : (is_idle | (is_receive & blink));
led0_r  : 1 driver  →  assign led0_r = error_active ? blink : proc_stretched;
led0_g  : 1 driver  →  assign led0_g = error_active ? 1'b0 : (reply_stretched & ~blink);
led1_r  : 1 driver  →  assign led1_r = sw_diag_mode;
led1_g  : 1 driver  →  assign led1_g = 1'b0;
led1_b  : 1 driver  →  assign led1_b = ~sw_diag_mode;
led[1]  : 1 driver  →  assign led[1] = locked & ~reader_cmd;
led[2]  : 1 driver  →  assign led[2] = tag_reply;
db_press: 1 driver  →  assign db_press = db_stable & ~db_prev;
```

No multiple-driver violations. Verified via `Select-String` audit on `fpga_top.v`.
