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

# ---- Condition 01: Container Metadata ----
Write-Host "`n[Container Metadata]" -ForegroundColor Yellow
Write-Host "----------------------------------------"
$metadataOutput = ffprobe -hide_banner "$($inputFile.FullName)" 2>&1

# Get JSON output for more reliable stream metadata parsing
$jsonOutput = ffprobe -v quiet -print_format json -show_format -show_streams "$($inputFile.FullName)" | ConvertFrom-Json

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

# ---- Enhanced Encoder Tag Check ----
$containerEncoder = $jsonOutput.format.tags.encoder
$videoEncoder = $jsonOutput.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -ExpandProperty tags -ErrorAction SilentlyContinue | Select-Object -ExpandProperty encoder -ErrorAction SilentlyContinue
$audioEncoder = $jsonOutput.streams | Where-Object { $_.codec_type -eq "audio" } | Select-Object -ExpandProperty tags -ErrorAction SilentlyContinue | Select-Object -ExpandProperty encoder -ErrorAction SilentlyContinue

Write-Host "`nEncoder Tag Check:" -ForegroundColor Cyan
Write-Host "Container encoder tag: $containerEncoder"
Write-Host "Video stream encoder tag: $videoEncoder"
Write-Host "Audio stream encoder tag: $audioEncoder"

$encoderFailures = @()
if ($containerEncoder) { $encoderFailures += "Container metadata contains encoder tag: $containerEncoder" }
if ($videoEncoder) { $encoderFailures += "Video stream contains encoder tag: $videoEncoder" }
if ($audioEncoder) { $encoderFailures += "Audio stream contains encoder tag: $audioEncoder" }

if ( ($movMajorBrand -and $movMinorVersion -and $movCompatibleBrands) -or
     ($mp4MajorBrand -and $mp4MinorVersion -and $mp4CompatibleBrands) ) {
    Write-Host "Metadata clean: required tags found." -ForegroundColor Green
} else {
    Write-Host "Metadata not clean." -ForegroundColor Red
    $failures += "Metadata failure: missing or incorrect tags"
}

if ($encoderFailures.Count -gt 0) {
    Write-Host "Metadata contains invalid encoder tags." -ForegroundColor Red
    $failures += $encoderFailures
}

# ---- Condition 02: Video Average Framerate & Audio Sample Rate Check ----
	Write-Host "`n[Framerate & Audio Sample Rate Check]" -ForegroundColor Yellow
	Write-Host "----------------------------------------"

	$avgFrameRate = ffprobe -hide_banner -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "$($inputFile.FullName)"
	$audioSampleRate = ffprobe -hide_banner -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$($inputFile.FullName)"

	Write-Host "Detected Average Framerate: $avgFrameRate" -ForegroundColor Cyan
	Write-Host "Detected Audio Sample Rate: $audioSampleRate" -ForegroundColor Cyan

	if ($avgFrameRate -eq "60/1" -and ($audioSampleRate -eq "48000" -or $audioSampleRate -eq "44100")) {
	    Write-Host "Framerate and Sample Rate are correct." -ForegroundColor Green
	} else {
    	Write-Host "Framerate or Sample Rate do not match expected values." -ForegroundColor Red
	    $failures += @{
	        Reason = "Framerate/Sample Rate failure: Expected 60/1 FPS & 48000/44100 Hz"
	        DetectedFramerate = $avgFrameRate
	        DetectedAudioSampleRate = $audioSampleRate
	    }
	}

# ---- Condition 03: Timebase Check ----
Write-Host "`n[Timebase Check]" -ForegroundColor Yellow
Write-Host "----------------------------------------"
$fpsOutput = ffprobe -hide_banner -i "$($inputFile.FullName)" -show_streams 2>&1

# Extract all timebase values found
$timebases = @()
if ($fpsOutput -match "time_base=([^\s]+)") {
    $timebases = $fpsOutput | Select-String "time_base=([^\s]+)" | ForEach-Object { $_.Matches.Groups[1].Value } | Select-Object -Unique
}

Write-Host "Detected Timebases: $($timebases -join ', ')" -ForegroundColor Cyan

if ($timebases -contains "1/60000") {
    if ($timebases -contains "1/48000" -or $timebases -contains "1/44100") {
        Write-Host "Time_base matches requirements." -ForegroundColor Green
    } else {
        Write-Host "Secondary time_base mismatch." -ForegroundColor Red
        $failures += @{
            Reason = "Timebase failure: Missing secondary time_base (1/48000 or 1/44100)"
            DetectedTimebases = $timebases -join ', '
            ExpectedTimebases = "1/60000 and either 1/48000 or 1/44100"
        }
    }
} else {
    Write-Host "Time_base=1/60000 not found." -ForegroundColor Red
    $failures += @{
        Reason = "Timebase failure: Expected 1/60000 not found"
        DetectedTimebases = if ($timebases.Count -gt 0) { $timebases -join ', ' } else { "No timebases found" }
        ExpectedTimebases = "1/60000 and either 1/48000 or 1/44100"
    }
}

# ---- Condition 04: Fast Start (Seeks) Check ----
        Write-Host "`n[Fast Start Check (Seeks)]" -ForegroundColor Yellow
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

# ---- Condition 05: 'moov' Before 'mdat' Check ----
        Write-Host "`n[Moov before Mdat Check]" -ForegroundColor Yellow
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

# ---- Condition 06: Streamability Check ----
        Write-Host "`n[Streamability Check]" -ForegroundColor Yellow
        Write-Host "----------------------------------------"
        $streamableOutput = mediainfo -f "$($inputFile.FullName)" 2>&1 | Select-String "IsStreamable"
        if ($streamableOutput -match "IsStreamable\s+:\s+Yes") {
            Write-Host "File is streamable." -ForegroundColor Green
        } else {
            Write-Host "File is not streamable." -ForegroundColor Red
            $failures += "Streamability failure"
        }

# ---- Condition 07: Handler Names ----
Write-Host "`n[Handler Names Check]" -ForegroundColor Yellow
Write-Host "----------------------------------------"

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

Write-Host "Video Handler Found: [$videoHandler]"
Write-Host "Audio Handler Found: [$audioHandler]"

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

        Write-Host "`n----------------------------------------"

# ---- Condition 08: Vendor ID Check ----
	Write-Host "`n[Vendor ID Check]" -ForegroundColor Yellow
	Write-Host "----------------------------------------"

	# Extract Vendor ID values for both VideoHandler and SoundHandler
	$videoVendorID = ffprobe -hide_banner -v error -select_streams v:0 -show_entries stream_tags=vendor_id -of default=noprint_wrappers=1:nokey=1 	"$($inputFile.FullName)"
	$soundVendorID = ffprobe -hide_banner -v error -select_streams a:0 -show_entries stream_tags=vendor_id -of default=noprint_wrappers=1:nokey=1 	"$($inputFile.FullName)"

	# Debugging output
	Write-Host "Extracted Vendor IDs:"
	Write-Host "VideoHandler Vendor ID: $videoVendorID" -ForegroundColor Cyan
	Write-Host "SoundHandler Vendor ID: $soundVendorID" -ForegroundColor Cyan

	# Condition: Both VideoHandler and SoundHandler must have empty or [0][0][0][0] vendor IDs
	if (($videoVendorID -eq "" -or $videoVendorID -eq "[0][0][0][0]") -and 
	    ($soundVendorID -eq "" -or $soundVendorID -eq "[0][0][0][0]")) {
	    Write-Host "Verification PASSED: Both Video and Sound Vendor IDs are valid." -ForegroundColor Green
	} else {
	    Write-Host "Verification FAILED: Invalid Vendor IDs detected." -ForegroundColor Red
	    if ($videoVendorID -eq "FFMP" -or $videoVendorID -ne "[0][0][0][0]" -and $videoVendorID -ne "") {
	        Write-Host "  - VideoHandler Vendor ID issue: $videoVendorID" -ForegroundColor Red
	        $failures += @{
	            Reason = "Vendor ID failure: VideoHandler contains invalid ID"
	            DetectedVideoVendorID = $videoVendorID
	        }
	    }
	    if ($soundVendorID -eq "FFMP" -or $soundVendorID -ne "[0][0][0][0]" -and $soundVendorID -ne "") {
	        Write-Host "  - SoundHandler Vendor ID issue: $soundVendorID" -ForegroundColor Red
	        $failures += @{
	            Reason = "Vendor ID failure: SoundHandler contains invalid ID"
	            DetectedSoundVendorID = $soundVendorID
	        }
	    }
	}

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
	Read-Host "Press Enter to exit"