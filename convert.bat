@echo off
ffmpeg -i "01.mov" -movflags +faststart -r 60 -fps_mode cfr -c:v libsvtav1 -svtav1-params "keyint=30:profile=0:level=61" -crf 24 -preset 8 -bf 2 -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 -color_trc bt709 -c:a libopus -b:a 384k -ar 48000 -ac 2 -map_metadata -1 -use_editlist 0 -fflags +bitexact -flags:v +bitexact -flags:a +bitexact -f mp4 "02.mp4"
pause
