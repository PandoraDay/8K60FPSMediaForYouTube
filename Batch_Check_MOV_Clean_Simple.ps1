# Ensure ThreadJob module is loaded
Import-Module ThreadJob

# Get the current directory path
$folderPath = Get-Location

# Get all MOV files in the current folder
$movFiles = Get-ChildItem -Path $folderPath -Filter "*.MOV"

# Check if there are MOV files in the folder
if ($movFiles.Count -eq 0) {
    Write-Host "No MOV files found in the current directory." -ForegroundColor Red
    exit
}

# Start parallel processing jobs
$jobs = @()
foreach ($file in $movFiles) {
    $jobs += Start-ThreadJob -ScriptBlock {
        param ($inputFile)

        # Define the file validation functions inside the script block
        function Check-Metadata {
            param ($file)
            try {
                $metadataOutput = ffprobe -hide_banner "$file" 2>&1
                if (-not ($metadataOutput -match "(?i)major_brand\s*:\s*qt")) {
                    return "Fail: Metadata check failed - major_brand not 'qt'"
                }
                if (-not ($metadataOutput -match "(?i)minor_version\s*:\s*\d+")) {
                    return "Fail: Metadata check failed - minor_version not a digit"
                }
                if (-not ($metadataOutput -match "(?i)compatible_brands\s*:\s*qt")) {
                    return "Fail: Metadata check failed - compatible_brands not 'qt'"
                }
                return $true
            } catch {
                return "Error in Check-Metadata for file: $file"
            }
        }

        function Check-FPS {
            param ($file)
            try {
                $fpsOutput = ffprobe -hide_banner -i "$file" -show_streams 2>&1
                if (-not ($fpsOutput -match "time_base=1/60000")) {
                    return "Fail: FPS check failed - time_base not 1/60000"
                }
                if (-not ($fpsOutput -match "time_base=1/44100")) {
                    return "Fail: FPS check failed - time_base not 1/44100"
                }
                return $true
            } catch {
                return "Error in Check-FPS for file: $file"
            }
        }

        function Check-FastStart {
            param ($file)
            try {
                $seeksOutput = ffprobe -hide_banner -v debug "$file" 2>&1 | Select-String "seeks"
                $seekCount1 = ($seeksOutput | Select-String "seeks:0").Count
                $seekCount2 = ($seeksOutput | Select-String "0 seeks").Count
                $seekTotal = $seekCount1 + $seekCount2
                if ($seekTotal -lt 3) {
                    return "Fail: FastStart check failed - less than 3 seeks"
                }
                return $true
            } catch {
                return "Error in Check-FastStart for file: $file"
            }
        }

        function Check-MoovBeforeMdat {
            param ($file)
            try {
                $moovMdatOutput = ffmpeg -hide_banner -v trace -i "$file" 2>&1 | Select-String -Pattern "type:'moov'", "type:'mdat'"
                $moovIndex = ($moovMdatOutput | Select-String "type:'moov'").LineNumber
                $mdatIndex = ($moovMdatOutput | Select-String "type:'mdat'").LineNumber
                if ($moovIndex -ge $mdatIndex) {
                    return "Fail: MoovBeforeMdat check failed - moov not before mdat"
                }
                return $true
            } catch {
                return "Error in Check-MoovBeforeMdat for file: $file"
            }
        }

        function Check-Streamability {
            param ($file)
            try {
                $streamableOutput = mediainfo -f "$file" 2>&1 | Select-String "IsStreamable"
                if (-not ($streamableOutput -match "IsStreamable\s+:\s+Yes")) {
                    return "Fail: Streamability check failed - not streamable"
                }
                return $true
            } catch {
                return "Error in Check-Streamability for file: $file"
            }
        }

        # Helper function to perform file check
        function Perform-FileCheck {
            param ($inputFile)

            $metadataResult = Check-Metadata $inputFile
            if ($metadataResult -ne $true) {
                return $metadataResult
            }

            $fpsResult = Check-FPS $inputFile
            if ($fpsResult -ne $true) {
                return $fpsResult
            }

            $fastStartResult = Check-FastStart $inputFile
            if ($fastStartResult -ne $true) {
                return $fastStartResult
            }

            $moovBeforeMdatResult = Check-MoovBeforeMdat $inputFile
            if ($moovBeforeMdatResult -ne $true) {
                return $moovBeforeMdatResult
            }

            $streamabilityResult = Check-Streamability $inputFile
            if ($streamabilityResult -ne $true) {
                return $streamabilityResult
            }

            return "Passed"
        }

        # Perform file check
        $fileCheck = Perform-FileCheck $inputFile

        return [PSCustomObject]@{
            FileName = [System.IO.Path]::GetFileName($inputFile)
            FileCheck = $fileCheck
        }
    } -ArgumentList $file.FullName
}

# Wait for all jobs to complete
$jobs | ForEach-Object { Wait-Job $_ | Out-Null }

# Collect results
$results = $jobs | ForEach-Object { Receive-Job $_ }

# Process the results of parallel execution and display each file's verification result
$filesProcessed = $results.Count
$filesPassedVerification = 0
$filesFailedVerification = 0

foreach ($result in $results) {
    if ($result.FileCheck -eq "Passed") {
        Write-Host "$($result.FileName) passed." -ForegroundColor Green
        $filesPassedVerification++
    } else {
        Write-Host "$($result.FileName) failed: $($result.FileCheck)" -ForegroundColor Red
        $filesFailedVerification++
    }
}

# Final Summary
Write-Host "----------------------------------------"
Write-Host "All checks completed!" -ForegroundColor Green
Write-Host "$filesPassedVerification files passed." -ForegroundColor Green
Write-Host "$filesFailedVerification files failed." -ForegroundColor Red
Write-Host "----------------------------------------"
Read-Host "Press Enter to exit"