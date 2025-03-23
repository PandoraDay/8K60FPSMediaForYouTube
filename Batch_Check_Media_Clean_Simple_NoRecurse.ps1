# Ensure the ThreadJob module is loaded
Import-Module ThreadJob

# Get the current directory path
$folderPath = Get-Location

# Get all MOV and MP4 files in the current folder (case-insensitive)
$videoFiles = Get-ChildItem -Path $folderPath -File |
              Where-Object { $_.Extension -match "(?i)\.mp4|\.mov" }

if ($videoFiles.Count -eq 0) {
    Write-Host "No MOV or MP4 files found in the current directory." -ForegroundColor Red
    exit
}

# Start parallel processing jobs
$jobs = @()
foreach ($file in $videoFiles) {
    $jobs += Start-ThreadJob -ScriptBlock {
        param ($filePath)

        # ---------------------------
        # Function: Check-Metadata
        # ---------------------------
        function Check-Metadata {
            $metadataOutput = ffprobe -hide_banner "$filePath" 2>&1
            # Check for MOV metadata
            $movMajorBrand      = $metadataOutput -match "(?i)major_brand\s*:\s*qt"
            $movMinorVersion    = $metadataOutput -match "(?i)minor_version\s*:\s*\d+"
            $movCompatibleBrands= $metadataOutput -match "(?i)compatible_brands\s*:\s*qt"
            # Check for MP4 metadata
            $mp4MajorBrand      = $metadataOutput -match "(?i)major_brand\s*:\s*isom"
            $mp4MinorVersion    = $metadataOutput -match "(?i)minor_version\s*:\s*512"
            $mp4CompatibleBrands= $metadataOutput -match "(?i)compatible_brands\s*:\s*isomav01iso2mp41"
            
            if ((($movMajorBrand -and $movMinorVersion -and $movCompatibleBrands) -or
                 ($mp4MajorBrand -and $mp4MinorVersion -and $mp4CompatibleBrands))) {
                return $true
            }
            return "Fail: Metadata check failed"
        }

        # ---------------------------
        # Function: Check-FPS
        # ---------------------------
        function Check-FPS {
            $fpsOutput = ffprobe -hide_banner -i "$filePath" -show_streams 2>&1
            if ($fpsOutput -match "time_base=1/60000") {
                if ($fpsOutput -match "time_base=1/48000" -or $fpsOutput -match "time_base=1/44100") {
                    return $true
                }
                else {
                    return "Fail: Secondary FPS condition not met"
                }
            }
            return "Fail: FPS check failed (time_base=1/60000 not found)"
        }

        # ---------------------------
        # Function: Check-FastStart
        # ---------------------------
        function Check-FastStart {
            $seeksOutput = ffprobe -hide_banner -v debug "$filePath" 2>&1 | Select-String "seeks"
            $seekCount1 = ($seeksOutput | Select-String "seeks:0").Count
            $seekCount2 = ($seeksOutput | Select-String "0 seeks").Count
            $seekTotal = $seekCount1 + $seekCount2
            if ($seekTotal -ge 3) {
                return $true
            }
            return "Fail: FastStart check failed"
        }

        # ---------------------------
        # Function: Check-MoovBeforeMdat
        # ---------------------------
        function Check-MoovBeforeMdat {
            $moovMdatOutput = ffmpeg -hide_banner -v trace -i "$filePath" 2>&1 |
                              Select-String -Pattern "type:'moov'", "type:'mdat'"
            $moovString = $moovMdatOutput | Select-String "type:'moov'"
            $mdatString = $moovMdatOutput | Select-String "type:'mdat'"
            if ($moovString -and $mdatString) {
                if ($moovString.LineNumber -lt $mdatString.LineNumber) {
                    return $true
                }
                else {
                    return "Fail: 'moov' does not precede 'mdat'"
                }
            }
            return "Fail: Moov/Mdat check inconclusive"
        }

        # ---------------------------
        # Function: Check-Streamability
        # ---------------------------
        function Check-Streamability {
            $streamableOutput = mediainfo -f "$filePath" 2>&1 | Select-String "IsStreamable"
            if ($streamableOutput -match "IsStreamable\s+:\s+Yes") {
                return $true
            }
            return "Fail: Streamability check failed"
        }
        
        # ---------------------------
        # Function: Check-Handlers
        # ---------------------------
        function Check-Handlers {
            $ffprobeOutput = ffprobe -hide_banner -i "$filePath" -show_streams 2>&1
            $videoHandler = ($ffprobeOutput | Select-String -Pattern "handler_name\s*[:=]\s*VideoHandler" |
                             Select-Object -First 1).Line
            $audioHandler = ($ffprobeOutput | Select-String -Pattern "handler_name\s*[:=]\s*SoundHandler" |
                             Select-Object -First 1).Line
            if ($videoHandler -match "VideoHandler" -and $audioHandler -match "SoundHandler") {
                return $true
            }
            return "Fail: Handlers check failed"
        }
        
        # ---------------------------
        # Function: Check-VendorID
        # ---------------------------
        function Check-VendorID {
            $ffprobeOutput = ffprobe -hide_banner -i "$filePath" -show_streams 2>&1
            $vendorIDPattern = "vendor_id\s*[:=]\s*



\[0\]







\[0\]







\[0\]







\[0\]



"
            $videoVendor = ($ffprobeOutput | Select-String -Pattern $vendorIDPattern |
                            Select-Object -First 1).Line
            $audioVendor = ($ffprobeOutput | Select-String -Pattern $vendorIDPattern |
                            Select-Object -Last 1).Line
            # Allow for either an empty vendor or one equal to "[0][0][0][0]"
            if ((($videoVendor -eq "[0][0][0][0]") -or (-not $videoVendor)) -and
                (($audioVendor -eq "[0][0][0][0]") -or (-not $audioVendor))) {
                return $true
            }
            return "Fail: VendorID check failed"
        }

        # ---------------------------
        # Function: Perform-FileCheck
        # ---------------------------
        function Perform-FileCheck {
            $failures = @()
            $metadata = Check-Metadata;         if ($metadata -ne $true) { $failures += $metadata }
            $fps      = Check-FPS;              if ($fps -ne $true)      { $failures += $fps }
            $fastStart= Check-FastStart;        if ($fastStart -ne $true){ $failures += $fastStart }
            $moov     = Check-MoovBeforeMdat;    if ($moov -ne $true)    { $failures += $moov }
            $stream   = Check-Streamability;     if ($stream -ne $true)   { $failures += $stream }
            $handlers = Check-Handlers;          if ($handlers -ne $true) { $failures += $handlers }
            $vendor   = Check-VendorID;          if ($vendor -ne $true)   { $failures += $vendor }
            
            if ($failures.Count -eq 0) {
                return "Passed"
            }
            else {
                return $failures -join ", "
            }
        }

        # Optional: output progress inside the thread (output from thread jobs may be interleaved)
        Write-Host "`nProcessing file: $(Split-Path $filePath -Leaf)" -ForegroundColor Cyan

        $fileCheck = Perform-FileCheck
        
        # Return an object with the file results
        [PSCustomObject]@{
            FileName    = (Split-Path $filePath -Leaf)
            FullName    = $filePath
            CheckResult = $fileCheck
        }
    } -ArgumentList $file.FullName
}

# Wait for all jobs to complete
$jobs | ForEach-Object { Wait-Job $_ | Out-Null }

# Collect the results from all jobs
$results = $jobs | ForEach-Object { Receive-Job $_ }

# Aggregate final counts
$filesProcessed = $results.Count
$filesPassedVerification = ($results | Where-Object { $_.CheckResult -eq "Passed" }).Count
$filesFailedVerification = $filesProcessed - $filesPassedVerification

# Final Summary
Write-Host ""
Write-Host "Final Summary:" -ForegroundColor Magenta
Write-Host "$filesProcessed/$filesProcessed Files Processed" -ForegroundColor Magenta
Write-Host "$filesPassedVerification/$filesProcessed Files Passed Verification" -ForegroundColor Green
Write-Host "$filesFailedVerification/$filesProcessed Files Failed Verification" -ForegroundColor Red
Write-Host "----------------------------------------"

# List details of files that failed verification (only name and reason)
if ($filesFailedVerification -gt 0) {
    Write-Host "Files that did NOT pass verification:" -ForegroundColor Red
    $results | Where-Object { $_.CheckResult -ne "Passed" } | ForEach-Object {
        $fileResult = $_
        Write-Host "File: $($fileResult.FileName)"
        
        # Split the failure reasons and display each one
        $failureReasons = $fileResult.CheckResult -split ", "
        foreach ($reason in $failureReasons) {
            $formattedReason = ""
            switch -Wildcard ($reason) {
                "*FPS*"      { $formattedReason = "  - FPS failure: $reason" }
                "*FastStart*" { $formattedReason = "  - Fast Start failure: $reason" }
                "*Handlers*"  { $formattedReason = "  - Handler failure: $reason" }
                "*Moov*"      { $formattedReason = "  - Moov/Mdat failure: $reason" }
                "*Streamability*" { $formattedReason = "  - Streamability failure: $reason" }
                "*VendorID*"  { $formattedReason = "  - VendorID failure: $reason" }
                default       { $formattedReason = "  - $reason" }
            }
            Write-Host $formattedReason -ForegroundColor Red
        }

        # Add a blank line after each file's failure reasons
        Write-Host ""
    }
}

Write-Host ""
Write-Host "All checks completed!" -ForegroundColor Green
Read-Host "Press Enter to exit"