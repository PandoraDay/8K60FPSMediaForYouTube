# Ask user for the MOV filename
$inputFile = Read-Host "Enter the MOV filename (with extension)"

# Check if file exists
if (!(Test-Path $inputFile)) {
    Write-Host "File not found: $inputFile" -ForegroundColor Red
    exit
}

Write-Host "`nProcessing: $inputFile" -ForegroundColor Cyan
Write-Host "----------------------------------------"

# Condition 01/04 - Metadata Cleanup Check
Write-Host "`n[Metadata Cleanup]" -ForegroundColor Yellow
Write-Host "----------------------------------------"
$metadataOutput = ffprobe -hide_banner "$inputFile" 2>&1
if ($metadataOutput -match "(?i)major_brand\s*:\s*qt" -and 
    $metadataOutput -match "(?i)minor_version\s*:\s*\d+" -and 
    $metadataOutput -match "(?i)compatible_brands\s*:\s*qt") {
    $metadataClean = $true
    Write-Host "Metadata clean: major_brand, minor_version, compatible_brands found."
} else {
    $metadataClean = $false
    Write-Host "Metadata not clean: major_brand, minor_version, compatible_brands are missing or incorrect."
}

# Condition 02/04 - FPS & Timebase Check
    Write-Host "`n[60FPS Check]" -ForegroundColor Yellow
    Write-Host "----------------------------------------"
    $fpsOutput = ffprobe -hide_banner -i "$($inputFile.FullName)" -show_streams 2>&1
    if ($fpsOutput -match "time_base=1/60000") {
    if ($fpsOutput -match "time_base=1/48000") {
        $fpsClean = $true
        Write-Host "FPS is clean: Timebase matches 1/60000 and 1/48000." -ForegroundColor Green
    } elseif ($fpsOutput -match "time_base=1/44100") {
        $fpsClean = $true
        Write-Host "FPS is clean: Timebase matches 1/60000 and 1/44100." -ForegroundColor Green
    } else {
        $fpsClean = $false
        Write-Host "FPS not clean: time_base does not match the required conditions." -ForegroundColor Red
    }
    } else {
    $fpsClean = $false
    Write-Host "FPS not clean: time_base=1/60000 not found." -ForegroundColor Red
    }

# Condition 03/04 - Fast Start (Seeks) Check
Write-Host "`n[Fast Start Check]" -ForegroundColor Yellow
Write-Host "----------------------------------------"
$seeksOutput = ffprobe -hide_banner -v debug "$inputFile" 2>&1 | Select-String "seeks"
$seekCount1 = ($seeksOutput | Select-String "seeks:0").Count
$seekCount2 = ($seeksOutput | Select-String "0 seeks").Count
$seekTotal = $seekCount1 + $seekCount2

Write-Host "Detected 'seeks:0' count: $seekCount1" -ForegroundColor Magenta
Write-Host "Detected '0 seeks' count: $seekCount2" -ForegroundColor Magenta
Write-Host "Total valid seek occurrences: $seekTotal" -ForegroundColor Magenta

if ($seekTotal -ge 3) {
    $fastStartEnabled = $true
    Write-Host "Fast Start is enabled: Seeks count is 0."
} else {
    $fastStartEnabled = $false
    Write-Host "Fast Start not enabled: Seeks count is greater than 0 or not found."
}

# Condition 04/04 - 'moov' Before 'mdat' Check
Write-Host "`n[Moov vs. Mdat Check]" -ForegroundColor Yellow
Write-Host "----------------------------------------"
$moovMdatOutput = ffmpeg -hide_banner -v trace -i "$inputFile" 2>&1 | Select-String -Pattern "type:'moov'", "type:'mdat'"
$moovIndex = ($moovMdatOutput | Select-String "type:'moov'").LineNumber
$mdatIndex = ($moovMdatOutput | Select-String "type:'mdat'").LineNumber
if ($moovIndex -lt $mdatIndex) {
    $moovBeforeMdat = $true
    Write-Host "'moov' comes before 'mdat'. File is streamable."
} else {
    $moovBeforeMdat = $false
    Write-Host "'moov' does not come before 'mdat'. File is not streamable."
}

# Parameter 05 - Streamability Check (IsStreamable)
Write-Host "`n[Streamability Check]" -ForegroundColor Yellow
Write-Host "----------------------------------------"
$streamableOutput = mediainfo -f "$inputFile" 2>&1 | Select-String "IsStreamable"
if ($streamableOutput -match "IsStreamable\s+:\s+Yes") {
    $isStreamable = $true
    Write-Host "File is streamable."
} else {
    $isStreamable = $false
    Write-Host "File is not streamable."
}

# Additional Check for Handler Names and Vendor ID
Write-Host "`n[Handler Names Check]" -ForegroundColor Yellow
Write-Host "----------------------------------------"
# Run ffprobe once and store output
$ffprobeOutput = ffprobe -hide_banner -i "$inputFile" -show_streams 2>&1

# Extract handler names
$videoHandler = ($ffprobeOutput | Select-String -Pattern "handler_name\s*[:=]\s*VideoHandler" | Select-Object -First 1).Line
$audioHandler = ($ffprobeOutput | Select-String -Pattern "handler_name\s*[:=]\s*SoundHandler" | Select-Object -First 1).Line

# Only print debug info if something goes wrong
if (-not $videoHandler -or -not $audioHandler) {
    Write-Host "`nDEBUG: ffprobe output (only printed if error occurs):`n$ffprobeOutput" -ForegroundColor Cyan
}

# Validate handler names
if ($videoHandler -match "VideoHandler" -and $audioHandler -match "SoundHandler") {
    Write-Host "Handler names are valid." -ForegroundColor Green
} else {
    Write-Host "Invalid handler names found." -ForegroundColor Red
}

Write-Host "`n----------------------------------------"

# Final Verdict
Write-Host "`n[Final Verdict]" -ForegroundColor Yellow
Write-Host "----------------------------------------"
if ($metadataClean -and $fpsClean -and $fastStartEnabled -and $moovBeforeMdat -and $isStreamable -and $videoHandler -match "VideoHandler" -and $audioHandler -match "SoundHandler") {
    Write-Host "STREAMABLE CLEAN MOV PERFECT 60FPS" -ForegroundColor Green
} else {
    Write-Host "NOT CLEAN MOV" -ForegroundColor Red
}

Write-Host "========================================`n"
Write-Host "All checks completed!" -ForegroundColor Green
Read-Host "Press Enter to exit"