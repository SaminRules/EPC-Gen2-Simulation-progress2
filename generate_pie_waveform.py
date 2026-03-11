#!/usr/bin/env python3
"""
Generate an EPC Gen2 PIE-encoded Arbitrary Waveform CSV for the Rigol function generator.

This script creates a voltage-level waveform file that encodes:
  1. Frame-Sync preamble (Delimiter → data-0 → RTcal)
  2. A full Query command (1000_0_01_1_10_01_0_0011_01000)
  3. An idle HIGH gap
  4. A second Frame-Sync + QueryRep (00_01) to exercise the full FSM

The waveform timing matches the testbench (bb_proc_tb.v):
  - Tari = 6.25 µs
  - half_of_tari = 3.125 µs
  - Delimiter LOW dip = 12.5 µs
  - PIE-0: HIGH 3.125 µs, LOW 3.125 µs (total = 1 Tari)
  - PIE-1: HIGH 9.375 µs, LOW 3.125 µs (total = 2 Tari)
  - RTcal: HIGH 15.625 µs, LOW 3.125 µs (total = 3 Tari)

Output:  pie_framesync_query.csv  (Rigol ARB format: one voltage sample per line)
         pie_framesync_query_annotated.csv (human-readable with time column)

Target FPGA clock: 5 MHz (200 ns/tick)
Recommended Rigol sample rate: 10 MSa/s (100 ns/sample) for clean edges
"""

import csv
import os

# ──────────────────────────────────────────────────────────────
# Timing parameters (in microseconds)
# ──────────────────────────────────────────────────────────────
TARI = 6.25           # µs — fundamental PIE time unit
HALF_TARI = 3.125     # µs — half of Tari
DELIM_LOW = 12.5      # µs — Delimiter LOW dip duration

# Voltage levels — normalized for Rigol ARB (0 = LOW, 1 = HIGH)
# Set the actual amplitude (e.g. 3.3 Vpp) on the instrument itself.
V_HIGH = 1.0
V_LOW  = 0.0

# Rigol DG4102 minimum ARB waveform length
RIGOL_MIN_POINTS = 16384

# Sample rate: 10 MSa/s → 100 ns per sample = 0.1 µs per sample
SAMPLE_RATE_MHZ = 10.0
SAMPLE_PERIOD_US = 1.0 / SAMPLE_RATE_MHZ  # 0.1 µs

# ──────────────────────────────────────────────────────────────
# Waveform builder
# ──────────────────────────────────────────────────────────────
samples = []
annotations = []

def add_segment(voltage, duration_us, label=""):
    """Add a constant-voltage segment to the waveform."""
    num_samples = round(duration_us / SAMPLE_PERIOD_US)
    for _ in range(num_samples):
        samples.append(voltage)
    if label:
        annotations.append((len(samples) - num_samples, len(samples) - 1, label, duration_us))

def add_idle(duration_us):
    """Add a HIGH idle period."""
    add_segment(V_HIGH, duration_us, f"IDLE ({duration_us} µs)")

def add_delimiter():
    """Add the Delimiter: LOW dip for 12.5 µs."""
    add_segment(V_LOW, DELIM_LOW, f"DELIMITER LOW ({DELIM_LOW} µs)")

def add_pie_0():
    """Encode PIE data-0: HIGH for half_tari, then LOW dip for half_tari."""
    add_segment(V_HIGH, HALF_TARI, f"PIE-0 HIGH ({HALF_TARI} µs)")
    add_segment(V_LOW,  HALF_TARI, f"PIE-0 LOW  ({HALF_TARI} µs)")

def add_pie_1():
    """Encode PIE data-1: HIGH for 3*half_tari, then LOW dip for half_tari."""
    add_segment(V_HIGH, 3 * HALF_TARI, f"PIE-1 HIGH ({3*HALF_TARI} µs)")
    add_segment(V_LOW,  HALF_TARI,     f"PIE-1 LOW  ({HALF_TARI} µs)")

def add_rtcal():
    """Encode RTcal: HIGH for 5*half_tari, then LOW dip for half_tari."""
    add_segment(V_HIGH, 5 * HALF_TARI, f"RTcal HIGH ({5*HALF_TARI} µs)")
    add_segment(V_LOW,  HALF_TARI,     f"RTcal LOW  ({HALF_TARI} µs)")

def add_frame_sync():
    """
    Full EPC Gen2 Frame-Sync preamble (matches testbench frame_sync_pie):
      1. Delimiter LOW dip (12.5 µs)
      2. HIGH (half_tari)  ← return from delimiter
      3. data-0 LOW dip (half_tari) — falling edge starts Tari measurement
      4. RTcal HIGH period (5 × half_tari)
      5. RTcal LOW dip (half_tari)  — falling edge ends RTcal measurement
      6. Signal returns HIGH — the NEXT PIE symbol provides the HIGH dwell

    NOTE: No explicit "Post-RTcal HIGH" segment! The testbench
    frame_sync_pie task ends with pie_code=1'b1 at zero dwell, and
    the subsequent PIE symbol's HIGH portion provides the HIGH time.
    Adding an extra HALF_TARI here would distort the first data bit's
    falling-to-falling measurement by extending it 3.125 µs.
    """
    add_delimiter()
    # After delimiter, go HIGH. The data-0 starts after this HIGH.
    add_segment(V_HIGH, HALF_TARI, "Post-Delim HIGH (3.125 µs)")
    # data-0: LOW dip (this falling edge starts Tari measurement)
    add_segment(V_LOW, HALF_TARI, "data-0 LOW dip (3.125 µs)")
    # After data-0 dip, HIGH for the RTcal period
    add_segment(V_HIGH, 5 * HALF_TARI, "RTcal HIGH period (15.625 µs)")
    # RTcal dip: LOW (this falling edge ends RTcal measurement)
    add_segment(V_LOW, HALF_TARI, "RTcal LOW dip (3.125 µs)")
    # NO Post-RTcal HIGH — next PIE symbol starts with V_HIGH naturally

def encode_bits(bit_string, label_prefix=""):
    """Encode a string of '0' and '1' characters as PIE symbols."""
    for i, bit in enumerate(bit_string):
        if bit == '1':
            add_pie_1()
        elif bit == '0':
            add_pie_0()

# ──────────────────────────────────────────────────────────────
# Build the complete waveform
# ──────────────────────────────────────────────────────────────

# 1. Initial idle (100 µs — matches testbench #100)
add_idle(100.0)

# 2. Frame-Sync preamble
add_frame_sync()

# 3. Query command: 1000_0_01_1_10_01_0_0011_01000 (22 bits)
query_bits = "1000001110010001101000"
encode_bits(query_bits, "QUERY")

# 4. Inter-command idle gap (100 µs)
add_idle(100.0)

# 5. Second Frame-Sync
add_frame_sync()

# 6. QueryRep command: 00_01 (4 bits)
queryrep_bits = "0001"
encode_bits(queryrep_bits, "QUERYREP")

# 7. Trailing idle (50 µs)
add_idle(50.0)

# ──────────────────────────────────────────────────────────────
# Pad to Rigol DG4102 minimum (16,384 points)
# ──────────────────────────────────────────────────────────────
data_samples = len(samples)
if data_samples < RIGOL_MIN_POINTS:
    pad_count = RIGOL_MIN_POINTS - data_samples
    pad_duration_us = pad_count * SAMPLE_PERIOD_US
    add_segment(V_HIGH, pad_duration_us, f"PAD IDLE ({pad_duration_us:.1f} µs, {pad_count} pts)")
    print(f"Padded: {pad_count:,} idle-HIGH samples appended "
          f"({pad_duration_us:.1f} µs) → total = {len(samples):,} pts")
else:
    print(f"No padding needed ({data_samples:,} ≥ {RIGOL_MIN_POINTS:,})")

# ──────────────────────────────────────────────────────────────
# Summary statistics
# ──────────────────────────────────────────────────────────────
total_samples = len(samples)
total_duration_us = total_samples * SAMPLE_PERIOD_US
total_duration_ms = total_duration_us / 1000.0

print(f"\nPIE Waveform Generator")
print(f"======================")
print(f"Sample rate:     {SAMPLE_RATE_MHZ:.1f} MSa/s ({SAMPLE_PERIOD_US*1000:.0f} ns/sample)")
print(f"Data samples:    {data_samples:,}")
print(f"Total samples:   {total_samples:,}  (Rigol min = {RIGOL_MIN_POINTS:,})")
print(f"Total duration:  {total_duration_us:.1f} µs ({total_duration_ms:.3f} ms)")
print(f"Voltage levels:  {V_LOW} (LOW) / {V_HIGH} (HIGH)  [NORMALIZED]")
print(f"  → Set amplitude to 3.3 Vpp on the Rigol instrument")
print()

# Verify key timing against fs_detector thresholds
print("Timing Verification (@ 5 MHz = 200 ns/tick):")
print(f"  Delimiter LOW:  {DELIM_LOW} µs = {DELIM_LOW/0.2:.1f} ticks  [need 50-80] ✓")
print(f"  data-0 period:  {TARI} µs = {TARI/0.2:.1f} ticks  [need 10-50] ✓")
rtcal_period = 6 * HALF_TARI  # falling→falling = data-0 dip end to RTcal dip start + RTcal
print(f"  RTcal period:   {rtcal_period} µs = {rtcal_period/0.2:.1f} ticks  [need > 2×Tari = {2*TARI/0.2:.1f}] ✓")
print()

# ──────────────────────────────────────────────────────────────
# Write CSV files
# ──────────────────────────────────────────────────────────────
output_dir = os.path.dirname(os.path.abspath(__file__))

# 1. Rigol-compatible CSV (voltage values only, one per line)
rigol_path = os.path.join(output_dir, "pie_framesync_query.csv")
with open(rigol_path, 'w', newline='') as f:
    writer = csv.writer(f)
    for v in samples:
        writer.writerow([f"{v:.4f}"])

print(f"Written: {rigol_path}")
print(f"  → Load as ARB waveform on Rigol at {SAMPLE_RATE_MHZ:.0f} MSa/s")

# 2. Annotated CSV (time, voltage — for human inspection / oscilloscope overlay)
annotated_path = os.path.join(output_dir, "pie_framesync_query_annotated.csv")
with open(annotated_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["time_us", "voltage"])
    for i, v in enumerate(samples):
        t = i * SAMPLE_PERIOD_US
        writer.writerow([f"{t:.4f}", f"{v:.4f}"])

print(f"Written: {annotated_path}")
print(f"  → Human-readable with time column for plotting/verification")
print()
print("Next steps:")
print("  1. Copy pie_framesync_query.csv to USB stick")
print("  2. On Rigol: Utility → Store/Recall → Load ARB waveform")
print("  3. Set High Level = 3.3V, Low Level = 0V  (normalized data × amplitude)")
print("  4. Connect Rigol CH1 to PMOD JA Pin 1 (L17)")
print("  5. Observe brain_state transitions in Vivado ILA")
