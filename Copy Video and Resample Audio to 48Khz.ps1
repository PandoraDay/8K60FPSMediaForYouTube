Get-ChildItem -Path . -Filter "*.mov" -File | ForEach-Object {
    $inputFile = $_.FullName
    $outputFile = $_.BaseName + " 48.mov"

    ffmpeg -i "$inputFile" -hide_banner -movflags +faststart -use_editlist 0 -c:v copy -c:a pcm_s16le -ar 48000 -ac 2 -af "aresample=resampler=soxr:precision=33" -r 60 -fps_mode cfr -video_track_timescale 60000 -map_metadata -1 -map_chapters -1 -metadata handler_name= -metadata vendor_id= -metadata encoder= -map 0:v:0 -map 0:a:0 -metadata:s:v:0 handler_name= -metadata:s:v:0 vendor_id= -metadata:s:v:0 encoder= -metadata:s:a:0 handler_name= -metadata:s:a:0 vendor_id= -metadata:s:a:0 encoder= -fflags +bitexact -flags:v +bitexact -flags:a +bitexact -strict experimental -f mov "$outputFile"
}
