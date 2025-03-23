# Get the current directory path
$folderPath = Get-Location

# Get all MOV and MP4 files in the current folder
$videoFiles = Get-ChildItem -Path $folderPath | Where-Object { $_.Extension -match "(?i)\.mp4|\.mov" }

# Debugging output
Write-Host "Found files:" -ForegroundColor Yellow
$videoFiles | ForEach-Object { Write-Host $_.FullName }

# Check if there are MOV or MP4 files in the folder
if ($videoFiles.Count -eq 0) {
    Write-Host "No MOV or MP4 files found in the current directory." -ForegroundColor Red
    exit
}

# Initialize counters and an array for failed files (will store an object with FileName and Reason)
$filesProcessed = 0
$filesPassedVerification = 0
$filesFailedVerification = 0
$failedFiles = @()

# Create a list to hold the jobs
$jobs = @()

# Process each media file in parallel using Start-Job
foreach ($inputFile in $videoFiles) {
    $filesProcessed++

    $jobs += Start-Job -ScriptBlock {
        param($inputFile)

        $failures = @()
        $fileName = $inputFile.Name

        # ---- Condition 01: Metadata Cleanup Check ----
        Write-Host "`n[Metadata Cleanup]" -ForegroundColor Yellow
        Write-Host "----------------------------------------"
        $metadataOutput = ffprobe -hide_banner "$($inputFile.FullName)" 2>&1

        $movMajorBrand = $metadataOutput -match "(?i)major_brand\s*:\s*qt"
        $movMinorVersion = $metadataOutput -match "(?i)minor_version\s*:\s*\d+"
        $movCompatibleBrands = $metadataOutput -match "(?i)compatible_brands\s*:\s*qt"

        $mp4MajorBrand = $metadataOutput -match "(?i)major_brand\s*:\s*isom"
        $mp4MinorVersion = $metadataOutput -match "(?i)minor_version\s*:\s*512"
        $mp4CompatibleBrands = $metadataOutput -match "(?i)compatible_brands\s*:\s*isomav01iso2mp41"

        Write-Host "MOV Metadata Match:" -ForegroundColor Cyan
        Write-Host "MOV Major Brand Match: $movMajorBrand"
        Write-Host "MOV Minor Version Match: $movMinorVersion"
        Write-Host "MOV Compatible Brands Match: $movCompatibleBrands"
        Write-Host "`nMP4 Metadata Match:" -ForegroundColor Cyan
        Write-Host "MP4 Major Brand Match: $mp4MajorBrand"
        Write-Host "MP4 Minor Version Match: $mp4MinorVersion"
        Write-Host "MP4 Compatible Brands Match: $mp4CompatibleBrands"

        if ( ($movMajorBrand -and $movMinorVersion -and $movCompatibleBrands) -or
             ($mp4MajorBrand -and $mp4MinorVersion -and $mp4CompatibleBrands) ) {
            Write-Host "Metadata clean: required tags found." -ForegroundColor Green
        } else {
            Write-Host "Metadata not clean." -ForegroundColor Red
            $failures += "Metadata failure: missing or incorrect tags"
        }

        # ---- Condition 02: FPS & Timebase Check ----
        Write-Host "`n[60FPS Check]" -ForegroundColor Yellow
        Write-Host "----------------------------------------"
        $fpsOutput = ffprobe -hide_banner -i "$($inputFile.FullName)" -show_streams 2>&1
        if ($fpsOutput -match "time_base=1/60000") {
            if ($fpsOutput -match "time_base=1/48000") {
                Write-Host "FPS is clean: time_base matches 1/60000 and 1/48000." -ForegroundColor Green
            } elseif ($fpsOutput -match "time_base=1/44100") {
                Write-Host "FPS is clean: time_base matches 1/60000 and 1/44100." -ForegroundColor Green
            } else {
                Write-Host "FPS not clean: secondary time_base mismatch." -ForegroundColor Red
                $failures += "FPS failure: secondary time_base mismatch"
            }
        } else {
            Write-Host "FPS not clean: time_base=1/60000 not found." -ForegroundColor Red
            $failures += "FPS failure: time_base=1/60000 not found"
        }

        # ---- Condition 03: Fast Start (Seeks) Check ----
        Write-Host "`n[Fast Start Check]" -ForegroundColor Yellow
        Write-Host "----------------------------------------"
        $seeksOutput = ffprobe -hide_banner -v debug "$($inputFile.FullName)" 2>&1 | Select-String "seeks"
        $seekCount1 = ($seeksOutput | Select-String "seeks:0").Count
        $seekCount2 = ($seeksOutput | Select-String "0 seeks").Count
        $seekTotal = $seekCount1 + $seekCount2
        Write-Host "Detected 'seeks:0' count: $seekCount1"
        Write-Host "Detected '0 seeks' count: $seekCount2"
        Write-Host "Total valid seek occurrences: $seekTotal"
        if ($seekTotal -ge 3) {
            Write-Host "Fast Start enabled." -ForegroundColor Green
        } else {
            Write-Host "Fast Start not enabled." -ForegroundColor Red
            $failures += "Fast Start failure: insufficient seek occurrences"
        }

        # ---- Condition 04: 'moov' Before 'mdat' Check ----
        Write-Host "`n[Moov vs. Mdat Check]" -ForegroundColor Yellow
        Write-Host "----------------------------------------"
        $moovMdatOutput = ffmpeg -hide_banner -v trace -i "$($inputFile.FullName)" 2>&1 |
                          Select-String -Pattern "type:'moov'", "type:'mdat'"
        $moovString = $moovMdatOutput | Select-String "type:'moov'"
        $mdatString = $moovMdatOutput | Select-String "type:'mdat'"
        if ($moovString -and $mdatString) {
            if ($moovString.LineNumber -lt $mdatString.LineNumber) {
                Write-Host "'moov' comes before 'mdat'." -ForegroundColor Green
            } else {
                Write-Host "'moov' does not come before 'mdat'." -ForegroundColor Red
                $failures += "Moov/Mdat failure: 'moov' not before 'mdat'"
            }
        } else {
            Write-Host "Moov/Mdat check inconclusive." -ForegroundColor Red
            $failures += "Moov/Mdat check inconclusive"
        }

        # ---- Condition 05: Streamability Check ----
        Write-Host "`n[Streamability Check]" -ForegroundColor Yellow
        Write-Host "----------------------------------------"
        $streamableOutput = mediainfo -f "$($inputFile.FullName)" 2>&1 | Select-String "IsStreamable"
        if ($streamableOutput -match "IsStreamable\s+:\s+Yes") {
            Write-Host "File is streamable." -ForegroundColor Green
        } else {
            Write-Host "File is not streamable." -ForegroundColor Red
            $failures += "Streamability failure"
        }

        # ---- Condition 06: Handler Names and Vendor ID Check ----
        Write-Host "`n[Handler Names and Vendor ID Check]" -ForegroundColor Yellow
        Write-Host "----------------------------------------"
        $ffprobeOutput = ffprobe -hide_banner -i "$($inputFile.FullName)" -show_streams 2>&1

        $videoHandlerPattern = "handler_name\s*[:=]\s*VideoHandler"
        $audioHandlerPattern = "handler_name\s*[:=]\s*SoundHandler"
        $vendorIDPattern = "vendor_id\s*[:=]\s*\[0\]\[0\]\[0\]\[0\]"

        $videoHandler = ($ffprobeOutput | Select-String -Pattern $videoHandlerPattern | Select-Object -First 1).Line
        $audioHandler = ($ffprobeOutput | Select-String -Pattern $audioHandlerPattern | Select-Object -First 1).Line
        $videoVendor = ($ffprobeOutput | Select-String -Pattern $vendorIDPattern | Select-Object -First 1).Line
        $audioVendor = ($ffprobeOutput | Select-String -Pattern $vendorIDPattern | Select-Object -Last 1).Line

        # Clean up the output by removing 'TAG:' prefix if present, trimming spaces, and standardizing formatting
        $videoHandler = ($videoHandler -replace "TAG:", "").Trim()
        $audioHandler = ($audioHandler -replace "TAG:", "").Trim()
        $videoVendor = ($videoVendor -replace "TAG:", "").Trim()
        $audioVendor = ($audioVendor -replace "TAG:", "").Trim()

        # Validate the handlers and vendor IDs
        $videoVendorIsInvalid = ($cleanedVideoVendor -eq "00000000" -or $cleanedVideoVendor -eq "")
        $audioVendorIsInvalid = ($cleanedAudioVendor -eq "00000000" -or $cleanedAudioVendor -eq "")

        if (-not $videoHandler -or -not $audioHandler) {
            $failures += "Handler failure: missing handler info"
        } elseif (($videoHandler -match "VideoHandler") -and ($audioHandler -match "SoundHandler") -and 
            -not $videoVendorIsInvalid -and -not $audioVendorIsInvalid) {
            Write-Host "Handler names and vendor IDs are valid." -ForegroundColor Green
        } else {
            $failures += "Handler/Vendor failure"
        }

        Write-Host "`n----------------------------------------"

        # ---- Final Verification ----
        if ($failures.Count -eq 0) {
            return @{ FileName = $fileName; Success = $true }
        } else {
            return @{ FileName = $fileName; Success = $false; Failures = $failures }
        }
    } -ArgumentList $inputFile
}

# Wait for all jobs to finish
$jobs | ForEach-Object { Wait-Job -Job $_ }

# Collect and check results of all jobs
$jobs | ForEach-Object {
    $jobResult = Receive-Job -Job $_
    if ($jobResult.Success) {
        $filesPassedVerification++
    } else {
        $filesFailedVerification++
        $failedFiles += $jobResult
    }
}

# Display the final summary
Write-Host "`n----- Verification Summary -----" -ForegroundColor Yellow
Write-Host "Total files processed: $filesProcessed" -ForegroundColor Magenta
Write-Host "Files passed verification: $filesPassedVerification" -ForegroundColor Green
Write-Host "Files failed verification: $filesFailedVerification" -ForegroundColor Red

# Output the list of failed files with their reasons
Write-Host "`nFailed Files:" -ForegroundColor Red
$failedFiles | ForEach-Object {
    Write-Host "`nFile: $($_.FileName)"
    $_.Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}
Read-Host "Press Enter to exit"