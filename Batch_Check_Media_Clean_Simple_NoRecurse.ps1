# Get the current directory path
$folderPath = Get-Location

# Get all MOV and MP4 files in the current folder
$videoFiles = Get-ChildItem -Path $folderPath | Where-Object { $_.Extension -match "(?i)\.mp4|\.mov" }

# Check if there are MOV or MP4 files in the folder
if ($videoFiles.Count -eq 0) {
    Write-Host "No MOV or MP4 files found in the current directory." -ForegroundColor Red
    exit
}

# Initialize counters and an array for failed files
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

        # Condition 01: Container Metadata
$metadataOutput = ffprobe -hide_banner "$($inputFile.FullName)" 2>&1
$jsonOutput = ffprobe -v quiet -print_format json -show_format -show_streams "$($inputFile.FullName)" | ConvertFrom-Json

# Check required metadata tags
$movMajorBrand = $metadataOutput -match "(?i)major_brand\s*:\s*qt"
$movMinorVersion = $metadataOutput -match "(?i)minor_version\s*:\s*\d+"
$movCompatibleBrands = $metadataOutput -match "(?i)compatible_brands\s*:\s*qt"

$mp4MajorBrand = $metadataOutput -match "(?i)major_brand\s*:\s*isom"
$mp4MinorVersion = $metadataOutput -match "(?i)minor_version\s*:\s*512"
$mp4CompatibleBrands = $metadataOutput -match "(?i)compatible_brands\s*:\s*isomav01iso2mp41"

# Check for forbidden encoder tags
$containerEncoder = $jsonOutput.format.tags.encoder
$videoEncoder = ($jsonOutput.streams | Where-Object { $_.codec_type -eq 'video' }).tags.encoder
$audioEncoder = ($jsonOutput.streams | Where-Object { $_.codec_type -eq 'audio' }).tags.encoder

# Add failures if needed
if (-not ( ($movMajorBrand -and $movMinorVersion -and $movCompatibleBrands) -or
     ($mp4MajorBrand -and $mp4MinorVersion -and $mp4CompatibleBrands) )) {
    $failures += "Metadata failure: missing or incorrect tags"
}

if ($containerEncoder) { $failures += "Container contains encoder tag: $containerEncoder" }
if ($videoEncoder) { $failures += "Video stream contains encoder tag: $videoEncoder" }
if ($audioEncoder) { $failures += "Audio stream contains encoder tag: $audioEncoder" }

        # Condition 02: Video Average Framerate & Audio Sample Rate Check
        $avgFrameRate = ffprobe -hide_banner -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$($inputFile.FullName)"
        $audioSampleRate = ffprobe -hide_banner -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$($inputFile.FullName)"

        if (-not ($avgFrameRate -eq "60/1" -and ($audioSampleRate -eq "48000" -or $audioSampleRate -eq "44100"))) {
            $failures += @{
                Reason = "Framerate/Sample Rate failure: Expected 60/1 FPS & 48000/44100 Hz"
                DetectedFramerate = $avgFrameRate
                DetectedAudioSampleRate = $audioSampleRate
            }
        }

        # ---- Condition 03: Timebase Check ----
$fpsOutput = ffprobe -hide_banner -i "$($inputFile.FullName)" -show_streams 2>&1
$timebases = @($fpsOutput | Select-String "time_base=([^\s]+)" | ForEach-Object { $_.Matches.Groups[1].Value } | Select-Object -Unique)

if (-not ($timebases -contains "1/60000")) {
    $failures += @{
        Reason = "Timebase failure: Expected 1/60000 not found"
        DetectedTimebases = if ($timebases.Count -gt 0) { $timebases -join ', ' } else { "No timebases found" }
        ExpectedTimebases = "1/60000 and either 1/48000 or 1/44100"
    }
} elseif (-not ($timebases -contains "1/48000" -or $timebases -contains "1/44100")) {
    $failures += @{
        Reason = "Timebase failure: Missing secondary time_base (1/48000 or 1/44100)"
        DetectedTimebases = $timebases -join ', '
        ExpectedTimebases = "1/60000 and either 1/48000 or 1/44100"
    }
}

        # Condition 04: Fast Start (Seeks) Check
        $seeksOutput = ffprobe -hide_banner -v debug "$($inputFile.FullName)" 2>&1 | Select-String "seeks"
        $seekCount1 = ($seeksOutput | Select-String "seeks:0").Count
        $seekCount2 = ($seeksOutput | Select-String "0 seeks").Count
        $seekTotal = $seekCount1 + $seekCount2
        if ($seekTotal -lt 3) {
            $failures += "Fast Start failure: insufficient seek occurrences"
        }

        # Condition 05: 'moov' Before 'mdat' Check
        $moovMdatOutput = ffmpeg -hide_banner -v trace -i "$($inputFile.FullName)" 2>&1 |
                          Select-String -Pattern "type:'moov'", "type:'mdat'"
        $moovString = $moovMdatOutput | Select-String "type:'moov'"
        $mdatString = $moovMdatOutput | Select-String "type:'mdat'"
        if ($moovString -and $mdatString) {
            if ($moovString.LineNumber -ge $mdatString.LineNumber) {
                $failures += "Moov/Mdat failure: 'moov' not before 'mdat'"
            }
        } else {
            $failures += "Moov/Mdat check inconclusive"
        }

        # Condition 06: Streamability Check
        $streamableOutput = mediainfo -f "$($inputFile.FullName)" 2>&1 | Select-String "IsStreamable"
        if (-not ($streamableOutput -match "IsStreamable\s+:\s+Yes")) {
            $failures += "Streamability failure"
        }

        # ---- Condition 07: Handler Names ----
# Get raw ffprobe output in JSON format for more reliable parsing
$ffprobeOutput = ffprobe -v quiet -print_format json -show_streams "$($inputFile.FullName)" | ConvertFrom-Json

# Initialize variables
$videoHandler = $null
$audioHandler = $null

# Process each stream
foreach ($stream in $ffprobeOutput.streams) {
    if ($stream.codec_type -eq "video") {
        $videoHandler = $stream.tags.handler_name
    }
    elseif ($stream.codec_type -eq "audio") {
        $audioHandler = $stream.tags.handler_name
    }
}

# Clean up handler names if they exist
if ($videoHandler) { $videoHandler = $videoHandler.Trim() }
if ($audioHandler) { $audioHandler = $audioHandler.Trim() }

if (-not $videoHandler -or -not $audioHandler) {
    $failures += @{
        Reason = "Handler failure: missing handler info"
        DetectedVideoHandler = if ($videoHandler) { $videoHandler } else { "NOT FOUND" }
        DetectedAudioHandler = if ($audioHandler) { $audioHandler } else { "NOT FOUND" }
    }
} elseif ($videoHandler -ne "VideoHandler" -or $audioHandler -ne "SoundHandler") {
    $failures += @{
        Reason = "Handler failure: incorrect handler names"
        DetectedVideoHandler = $videoHandler
        DetectedAudioHandler = $audioHandler
    }
}

        # Condition 08: Vendor ID Check (Corrected version)
$videoVendorID = ffprobe -hide_banner -v error -select_streams v:0 -show_entries stream_tags=vendor_id -of default=noprint_wrappers=1:nokey=1 "$($inputFile.FullName)"
$soundVendorID = ffprobe -hide_banner -v error -select_streams a:0 -show_entries stream_tags=vendor_id -of default=noprint_wrappers=1:nokey=1 "$($inputFile.FullName)"

if ($videoVendorID -ne "" -and $videoVendorID -ne "[0][0][0][0]") {
    $failures += @{
        Reason = "Vendor ID failure: VideoHandler contains invalid ID"
        DetectedVideoVendorID = $videoVendorID
    }
}
if ($soundVendorID -ne "" -and $soundVendorID -ne "[0][0][0][0]") {
    $failures += @{
        Reason = "Vendor ID failure: SoundHandler contains invalid ID"
        DetectedSoundVendorID = $soundVendorID
    }
}

        # Final Verification
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

# Output the list of failed files with their reasons and detected values
Write-Host "`nFailed Files:" -ForegroundColor Red
$failedFiles | ForEach-Object {
    Write-Host "`nFile: $($_.FileName)" -ForegroundColor Red
    $_.Failures | ForEach-Object {
        if ($_ -is [Hashtable]) {
            Write-Host "  - $($_.Reason)" -ForegroundColor Red
            if ($_.ContainsKey("DetectedFramerate")) {
                Write-Host "    Detected Framerate: $($_.DetectedFramerate)" -ForegroundColor Cyan
            }
            if ($_.ContainsKey("DetectedAudioSampleRate")) {
                Write-Host "    Detected Audio Sample Rate: $($_.DetectedAudioSampleRate)" -ForegroundColor Cyan
            }
            if ($_.ContainsKey("DetectedTimebases")) {
                Write-Host "    Detected Timebases: $($_.DetectedTimebases)" -ForegroundColor Cyan
            }
            if ($_.ContainsKey("ExpectedTimebases")) {
                Write-Host "    Expected Timebases: $($_.ExpectedTimebases)" -ForegroundColor Cyan
            }
            if ($_.ContainsKey("DetectedVideoHandler")) {
                Write-Host "    Detected Video Handler: $($_.DetectedVideoHandler)" -ForegroundColor Cyan
            }
            if ($_.ContainsKey("DetectedAudioHandler")) {
                Write-Host "    Detected Audio Handler: $($_.DetectedAudioHandler)" -ForegroundColor Cyan
            }
            if ($_.ContainsKey("DetectedVideoVendorID")) {
                Write-Host "    Detected VideoHandler Vendor ID: $($_.DetectedVideoVendorID)" -ForegroundColor Cyan
            }
            if ($_.ContainsKey("DetectedSoundVendorID")) {
                Write-Host "    Detected SoundHandler Vendor ID: $($_.DetectedSoundVendorID)" -ForegroundColor Cyan
            }
        } else {
            Write-Host "  - $_" -ForegroundColor Red
        }
    }
}

# Prevent terminal from closing prematurely
Read-Host "`nPress Enter to exit"