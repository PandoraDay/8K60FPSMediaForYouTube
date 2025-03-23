# Get the current directory path
$folderPath = Get-Location

# Get all MOV files in the current folder
$movFiles = Get-ChildItem -Path $folderPath -Filter "*.MOV"

# Check if there are MOV files in the folder
if ($movFiles.Count -eq 0) {
    Write-Host "No MOV files found in the current directory." -ForegroundColor Red
    exit
}

# Initialize counters
$filesProcessed = 0
$filesPassedVerification = 0

# Process each MOV file
foreach ($inputFile in $movFiles) {
    $filesProcessed++

    Write-Host "`nProcessing: $($inputFile.Name)" -ForegroundColor Cyan
    Write-Host "----------------------------------------"

# Condition 01/04 - Metadata Cleanup Check
Write-Host "`n[Metadata Cleanup]" -ForegroundColor Yellow
Write-Host "----------------------------------------"
$metadataOutput = ffprobe -hide_banner "$($inputFile.FullName)" 2>&1

# Check for MOV file metadata
$movMajorBrand = $metadataOutput -match "(?i)major_brand\s*:\s*qt"
$movMinorVersion = $metadataOutput -match "(?i)minor_version\s*:\s*\d+"
$movCompatibleBrands = $metadataOutput -match "(?i)compatible_brands\s*:\s*qt"

# Check for MP4 file metadata
$mp4MajorBrand = $metadataOutput -match "(?i)major_brand\s*:\s*isom"
$mp4MinorVersion = $metadataOutput -match "(?i)minor_version\s*:\s*512"
$mp4CompatibleBrands = $metadataOutput -match "(?i)compatible_brands\s*:\s*isomav01iso2mp41"

# Debugging information
Write-Host "`nDEBUG: ffprobe output:`n$metadataOutput" -ForegroundColor Cyan
Write-Host "`nDEBUG: MOV Metadata Match:`n" -ForegroundColor Cyan
Write-Host "MOV Major Brand Match: $movMajorBrand" -ForegroundColor Green
Write-Host "MOV Minor Version Match: $movMinorVersion" -ForegroundColor Green
Write-Host "MOV Compatible Brands Match: $movCompatibleBrands" -ForegroundColor Green

Write-Host "`nDEBUG: MP4 Metadata Match:`n" -ForegroundColor Cyan
Write-Host "MP4 Major Brand Match: $mp4MajorBrand" -ForegroundColor Green
Write-Host "MP4 Minor Version Match: $mp4MinorVersion" -ForegroundColor Green
Write-Host "MP4 Compatible Brands Match: $mp4CompatibleBrands" -ForegroundColor Green

if (($movMajorBrand -and $movMinorVersion -and $movCompatibleBrands) -or
    ($mp4MajorBrand -and $mp4MinorVersion -and $mp4CompatibleBrands)) {
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
        Write-Host "FPS is clean: Timebase matches 1/60000 and 1/48000."
    } elseif ($fpsOutput -match "time_base=1/44100") {
        $fpsClean = $true
        Write-Host "FPS is clean: Timebase matches 1/60000 and 1/44100."
    } else {
        $fpsClean = $false
        Write-Host "FPS not clean: time_base does not match the required conditions."
    }
    } else {
    $fpsClean = $false
    Write-Host "FPS not clean: time_base=1/60000 not found."
    }

    # Condition 03/04 - Fast Start (Seeks) Check
    Write-Host "`n[Fast Start Check]" -ForegroundColor Yellow
    Write-Host "----------------------------------------"
    $seeksOutput = ffprobe -hide_banner -v debug "$($inputFile.FullName)" 2>&1 | Select-String "seeks"
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
    $moovMdatOutput = ffmpeg -hide_banner -v trace -i "$($inputFile.FullName)" 2>&1 | Select-String -Pattern "type:'moov'", "type:'mdat'"
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
    $streamableOutput = mediainfo -f "$($inputFile.FullName)" 2>&1 | Select-String "IsStreamable"
    if ($streamableOutput -match "IsStreamable\s+:\s+Yes") {
        $isStreamable = $true
        Write-Host "File is streamable."
    } else {
        $isStreamable = $false
        Write-Host "File is not streamable."
    }

    # Additional Check for Handler Names and Vendor ID
Write-Host "`n[Handler Names and Vendor ID Check]" -ForegroundColor Yellow
Write-Host "----------------------------------------"
$ffprobeOutput = ffprobe -hide_banner -i "$($inputFile.FullName)" -show_streams 2>&1

$videoHandlerPattern = "handler_name\s*[:=]\s*VideoHandler"
$audioHandlerPattern = "handler_name\s*[:=]\s*SoundHandler"
$vendorIDPattern = "vendor_id\s*[:=]\s*

\[0\]



\[0\]



\[0\]



\[0\]

"

$videoHandler = ($ffprobeOutput | Select-String -Pattern $videoHandlerPattern | Select-Object -First 1).Line
$audioHandler = ($ffprobeOutput | Select-String -Pattern $audioHandlerPattern | Select-Object -First 1).Line
$videoVendor = ($ffprobeOutput | Select-String -Pattern $vendorIDPattern | Select-Object -First 1).Line
$audioVendor = ($ffprobeOutput | Select-String -Pattern $vendorIDPattern | Select-Object -First 1).Line

Write-Host "`nDEBUG: Video Handler: $videoHandler"
Write-Host "`nDEBUG: Audio Handler: $audioHandler"
Write-Host "`nDEBUG: Video Vendor: $videoVendor"
Write-Host "`nDEBUG: Audio Vendor: $audioVendor"

if (-not $videoHandler -or -not $audioHandler) {
    Write-Host "`nDEBUG: ffprobe output (only printed if error occurs):`n$ffprobeOutput" -ForegroundColor Cyan
}

if ($videoHandler -match "VideoHandler" -and $audioHandler -match "SoundHandler" -and ($videoVendor -eq "[0][0][0][0]" -or -not $videoVendor) -and ($audioVendor -eq "[0][0][0][0]" -or -not $audioVendor)) {
    Write-Host "Handler names and vendor IDs are valid." -ForegroundColor Green
} else {
    Write-Host "Invalid handler names or vendor IDs found." -ForegroundColor Red
}

Write-Host "`n----------------------------------------"

    # Final Verdict
    Write-Host "`n[Final Verdict]" -ForegroundColor Yellow
    Write-Host "----------------------------------------"
    if ($metadataClean -and $fpsClean -and $fastStartEnabled -and $moovBeforeMdat -and $isStreamable -and $videoHandler -match "VideoHandler" -and $audioHandler -match "SoundHandler") {
        Write-Host "STREAMABLE CLEAN MOV PERFECT 60FPS" -ForegroundColor Green
        $filesPassedVerification++
    } else {
        Write-Host "NOT CLEAN MOV" -ForegroundColor Red
    }

    Write-Host "========================================`n"

    # Display progress
    Write-Host "$filesProcessed/$($movFiles.Count) Files Processed"
    Write-Host "$filesPassedVerification/$($filesProcessed) Files Passed Verification"
}

Write-Host "All checks completed!" -ForegroundColor Green
Read-Host "Press Enter to exit"