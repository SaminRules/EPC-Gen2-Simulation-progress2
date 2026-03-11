# run_sim.ps1 — Run iverilog simulation and extract clean $display lines
# vvp writes progress updates using \r on the same line as $display output.
# We run vvp with output going to a temp file, then post-process.

$vvp = "C:\iverilog\bin\vvp.exe"
$vvp_file = "bb_proc_sim.vvp"
$raw_log = "sim_raw.log"

# Run vvp, capture all output (stdout + stderr combined) to raw log
& $vvp $vvp_file *> $raw_log

Write-Host "=== Simulation finished, exit code: $LASTEXITCODE ==="
Write-Host ""

# Post-process: read raw bytes, split on 0x0A (\n), 
# then for each line take the last \r-delimited segment (the surviving content)
$raw = [System.IO.File]::ReadAllBytes($raw_log)
$text = [System.Text.Encoding]::ASCII.GetString($raw)
$lines = $text -split [char]0x0A

$output = @()
foreach ($line in $lines) {
    # Split on \r, last segment is what was NOT overwritten by progress bar
    $segs = $line -split [char]0x0D
    $last = $segs[-1].Trim()
    if ($last -ne '') {
        $output += $last
    }
}

$output | ForEach-Object { Write-Host $_ }

# Also save clean output
$output | Out-File -Encoding ascii sim_clean_output.txt
Write-Host ""
Write-Host "=== Clean output saved to sim_clean_output.txt ==="
