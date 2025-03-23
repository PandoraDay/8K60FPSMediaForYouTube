@echo off
ffmpeg -i "01a.mov" -hide_banner -movflags +faststart -use_editlist 0 -c:v copy -c:a copy -r 60 -fps_mode cfr -video_track_timescale 60000 -map_metadata -1 -map_chapters -1 -metadata handler_name= -metadata vendor_id= -metadata encoder= -map 0:v:0 -map 0:a:0 -metadata:s:v:0 handler_name= -metadata:s:v:0 vendor_id= -metadata:s:v:0 encoder= -metadata:s:a:0 handler_name= -metadata:s:a:0 vendor_id= -metadata:s:a:0 encoder= -fflags +bitexact -flags:v +bitexact -flags:a +bitexact "01.mov"
pause
