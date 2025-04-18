@echo off
REM Create the "new" and "new\svt" folders if they don't exist
if not exist "new" mkdir "new"
if not exist "new\svt" mkdir "new\svt"

REM Convert all MOV files to MP4 SVT-AV1 and store them in "new"
for %%a in ("*.mov") do (
    ffmpeg -i "%%a" -hide_banner -movflags +faststart -use_editlist 0 -s 7680x4320 -r 60 -fps_mode cfr -video_track_timescale 60000 -c:v libsvtav1 -svtav1-params "keyint=30:profile=0:level=61:color-primaries=bt709:transfer-characteristics=bt709:matrix-coefficients=bt709" -crf 23 -preset 5 -bf 2 -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 -color_trc bt709 -c:a libopus -b:a 384k -ar 48000 -ac 2 -map_metadata -1 -map_chapters -1 -metadata handler_name= -metadata vendor_id= -metadata encoder= -map 0:v:0 -map 0:a:0 -metadata:s:v:0 handler_name= -metadata:s:v:0 vendor_id= -metadata:s:v:0 encoder= -metadata:s:a:0 handler_name= -metadata:s:a:0 vendor_id= -metadata:s:a:0 encoder= -fflags +bitexact -flags:v +bitexact -flags:a +bitexact -strict experimental -f mp4 "new\%%~na.mp4"
)

REM Re-encode the MP4 files in "new" and save them in "new\svt"
for %%a in ("new\*.mp4") do (
    ffmpeg -i "%%a" -hide_banner -movflags +faststart -use_editlist 0 -s 7680x4320 -r 60 -fps_mode cfr -video_track_timescale 60000 -c:v libsvtav1 -svtav1-params "keyint=30:profile=0:level=61:color-primaries=bt709:transfer-characteristics=bt709:matrix-coefficients=bt709" -crf 23 -preset 5 -bf 2 -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 -color_trc bt709 -c:a copy -map_metadata -1 -map_chapters -1 -metadata handler_name= -metadata vendor_id= -metadata encoder= -map 0:v:0 -map 0:a:0 -metadata:s:v:0 handler_name= -metadata:s:v:0 vendor_id= -metadata:s:v:0 encoder= -metadata:s:a:0 handler_name= -metadata:s:a:0 vendor_id= -metadata:s:a:0 encoder= -fflags +bitexact -flags:v +bitexact -flags:a +bitexact -strict experimental -f mp4 "new\svt\%%~na.mp4"
)

echo Process completed.
pause