# Define the playlist URL and log file
$playlistUrl = "https://www.youtube.com/playlist?list=PL7hXETpMiNVNEI9I0iP2ham5uAm5ViAdW"
$logFile = "playlist_resolution_log.txt"

# Clear the log file if it exists
if (Test-Path $logFile) {
    Clear-Content $logFile
}

# Get all video URLs and their playlist indices
$videoData = yt-dlp --flat-playlist --print "%(playlist_index)s %(title)s %(url)s" $playlistUrl

# Initialize lists to store results
$videosWith4320p = @()
$videosWithout4320p = @()

# Loop through each video data
foreach ($videoEntry in $videoData) {
    # Split the video data into index, title, and URL
    $videoIndex = $videoEntry.Substring(0, 2).Trim()  # Extract the first 2 characters (index)
    $remainingData = $videoEntry.Substring(2).Trim()  # Extract the remaining data
    $lastSpaceIndex = $remainingData.LastIndexOf(" ") # Find the last space (separates title and URL)
    $videoTitle = $remainingData.Substring(0, $lastSpaceIndex).Trim()  # Extract the title
    $videoUrl = $remainingData.Substring($lastSpaceIndex).Trim()       # Extract the URL

    # Display and log the progress message with the video index, title, and URL
    $checkMsg = "Checking: #$videoIndex - $videoTitle - $videoUrl"
    Write-Host $checkMsg -ForegroundColor Cyan
    $checkMsg | Out-File -FilePath $logFile -Append

    # Get the available formats for the video
    $formats = yt-dlp -F $videoUrl

    # Check if 4320p is available
    if ($formats -match "4320p") {
        $result = "[YES] 4320p available for #$videoIndex - $videoTitle - $videoUrl"
        $videosWith4320p += "#$videoIndex - $videoTitle - $videoUrl"
        Write-Host $result -ForegroundColor Green
    } else {
        $result = "[NO]  No 4320p available for #$videoIndex - $videoTitle - $videoUrl"
        $videosWithout4320p += "#$videoIndex - $videoTitle - $videoUrl"
        Write-Host $result -ForegroundColor Red
    }
    $result | Out-File -FilePath $logFile -Append
}

# Log the results to the output file
"Videos with 4320p resolution:" | Out-File -FilePath $logFile -Append
$videosWith4320p | ForEach-Object { $_ | Out-File -FilePath $logFile -Append }

"`nVideos without 4320p resolution:" | Out-File -FilePath $logFile -Append
$videosWithout4320p | ForEach-Object { $_ | Out-File -FilePath $logFile -Append }

Write-Host "Results have been logged to $logFile" -ForegroundColor Yellow