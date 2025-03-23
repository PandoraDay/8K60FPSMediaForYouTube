# 8K60FPSMediaForYouTube
Scripts that I used for working and preparing media to upload 8K 7680x4320 60FPS (4320p60) to YouTube.

Here, I share some scripts I used to work and upload 8K 7680x4320 60FPS Media to YouTube. Some of them are Windows CMD BATS, some of them are Powershell 7.5.0 PS1 Scripts. I am not by all means an expert.  I did this with help of Internet (AskUbuntu, Reddit, Stack Overflow, Super User, VideoHelp Forum, etc.) and AI such as Kimi AI, DeepSeek, ChatGPT and Microsoft Copilot  

For Audio and Video technical details and workflow, please check my Reddit post (I got banned from Reddit after that post, for some reason)  
[Part 02 - My experience uploading 8K resolution videos to YouTube](https://www.reddit.com/r/videography/comments/1jg89z7)

**Dependencies**  
Optional: [ffpb - A Terminal Progress Bar for ffmpeg](https://github.com/althonos/ffpb)  
ffmpeg 2025-03-20  
ffprobe 2025-03-20  
mediainfo 2025-03-20  
Python 3.13  
yt-dlp  
Windows CMD  
Windows PowerShell 7.5.0  
Important for PS1 Files that invoke `Start-Job` for parallell processing. These PS1 Scripts might not work with PowerShell 5.0 included in Windows by default  


**Directory Tree**  
Some of these scripts require the following Directory Tree: `Current Directory\new\svt`

**Quick Description of Files**  

**8K Availability Check.py**  
Checks and prints the exact date and time when a video is available for viewing in 8K 4320p60 resolution in YouTube. It invokes yt-dlp with th -F Parameter and looks for the String 4320p every 5 minutes. Ideally, when YouTube finishes processing the video up to 4320p60, the Script prints the exact Date and Time when the video gets processed by YouTube in 8K, and logs the info both in ther Terminal and a Log File.  

**Notes:** Do NOT use. This automatic check seems to "lock" the video as "occupied", so YouTube refuses to process 4320p60 videos checked with this script.  

**8kyoutubecheck.ps1**  
Checks and logs which videos from a YouTube Playlist are available to watch in 4320p60. In the log, a final summary of which videos are available to watch in 4320p60 and which videos are not available to watch in 4320p is printed with YouTube Links and Video Names.  

**Batch_Check_MOV_Clean_Each.ps1**  
Scans for MOV Files in the current directory non recursively and checks if the media is clean and uploadable by verifying the following conditions, prompting each check on the Terminal.

```
Condition 01 - Metadata Clean Check

Metadata is keep at minimum

Video

handler_name: VideoHandler

vendor_id: [0][0][0][0]

Audio

handler_name: SoundHandler

vendor_id: [0][0][0][0]

ffprobe -hide_banner -i "input.mov"

Condition 02 - Check Media Time Stamps

There should be 2 results in the output

Video Time Stamp

time_base=1/60000

Audio Time Stamp

time_base=1/48000

If working with 44100Hz, Audio Time Stamp can be 1/44100 as well.

ffprobe -i "input.mov" -hide_banner -show_streams | Select-String "time_base"

Condition 03 - Check is Fast Start is Enabled

#If seeks 0 means Fast Start is Enabled

ffprobe -hide_banner -v debug "input.mov" 2>&1 | Select-String seeks

Condition 04 - Check is Fast Start is Enabled - 2nd Method

#If mov is at the beggining, Fast Start is Enabled

ffmpeg -hide_banner -v trace -i "input.mov" 2>&1 | Select-String -Pattern "type:'mdat'", "type:'moov'"

Condition 05 - Check is Fast Start is Enabled - 3rd Method - Streamability Check

#If 'Yes' Fast Start is Enabled

mediainfo -f "input.mov" | Select-String IsStreamable
```

**Batch_Check_MOV_Clean_Simple.ps1**  
Same logic as `Batch_Check_MOV_Clean_Each.ps1`. Performs all the checks and simplifies the Terminal Output nice, clean and without clutter. PowerShell 7.5.0 is recommended, as it invokes `Start-Job` for Parallel Processing and performs the checks on multiple files at once. Without `Start-Job`, each file will be processed sequentially, which might take a long time if working with numerous files.   

**Batch_Check_MP4_Clean_Each.ps1**  
Same as `Batch_Check_MOV_Clean_Each.ps1`, but for MP4 Files instead of MOV Files.  

**Batch_Check_Media_Clean_Each_NoRecurse.ps1**  
Refined script for checking MOV and MP4 files if they are clean and uploadable with the same original conditions. Scans the current directory non recursively and prompts each check for each file in the Terminal.  

**Batch_Check_Media_Clean_Each_Recurse.ps1**  
Same as `Batch_Check_Media_Clean_Each_NoRecurse.ps1`. The only difference is that the script scans the current directory recursively with `Get-ChildItem -Recurse`  

**Batch_Check_Media_Clean_Simple_NoRecurse.ps1**  
Same logic as `Batch_Check_Media_Clean_Each_NoRecurse.ps1`. Performs all the checks and simplifies the Terminal Output nice, clean and without clutter. PowerShell 7.5.0 is recommended, as it invokes `Start-Job` for Parallel Processing and performs the checks on multiple files at once. Without `Start-Job`, each file will be processed sequentially, which might take a long time if working with numerous files.

**Batch_Check_Media_Clean_Simple_Recurse.ps1**  
Same as `Batch_Check_Media_Clean_Simple_NoRecurse.ps1`. The only difference is that the script scans the current directory recursively with `Get-ChildItem -Recurse`

**Clean Faststart MKV to MP4 60fps.bat**  
Scans current directory non recursively for MKV Files. Takes MKV, remux it to MP4 with ffmpeg and the clean remuxed file is put on the directory called `new`. Check the file's code for details about ffmpeg parameters.  

**Clean MOV Only.bat**  
Scans current directory non recursively for MOV Files. Takes MOV, remux it to MOV with ffmpeg and the clean remuxed file is put on the directory called `new`. Check the file's code for details about ffmpeg parameters.  

**Clean MP4 Only.bat**  
Scans current directory non recursively for MP4 Files. Takes MP4, remux it to MP4 with ffmpeg and the clean remuxed file is put on the directory called `new`. Check the file's code for details about ffmpeg parameters.  

**Copy Video and Resample Audio to 48Khz.ps1**  
Resamples MOV 44100Hz Audio to Stereo PCM S16LE 48000Hz. Copies Video and cleans the MOV.  

**MOV to SVT-AV1 MP4 to SVT-AV1 MP4.bat**
This script performs two lossy encodings automatically: MOV→MP4A→MP4B  

First Step  
Scans for MOV Files in the currect directory non recursively.   
Using ffmpeg, it converts MOV Apple ProRes 422 PCM S16LE 48000Hz Stereo to MP4 SVT-AV1 Opus 48000Hz Stereo and puts the MP4 A file in the `new` directory. All MOV Files are converted to MP4 A first in order for the second part of the script to run.  

Second Step  
Scans for MP4 A Files in the currect directory non recursively.  
Then, it takes all the MP4 A encoded videos from the first lossy encoding in `new` directory, copies the audio stream and performs another lossy converstion using SVT-AV1. The resulting MP4 B of this second lossy encoding is stored in `new\svt` directory.  

**MP4 AV1→MP4 AV1 SVT-AV1 60FPS.bat**  
Scans for MP4 Files in the currect directory non recursively. 
Then, it takes all the MP4 files from current directory, copies the audio stream and performs another lossy converstion using SVT-AV1. The resulting MP4 of this lossy encoding is stored in `new` directory.  

**ProRes→LibAOM AV1 Lossless.bat**  
Scans for MOV Files in the currect directory non recursively.  
It performs a lossless encoding using ffmpeg LibAOM and Opus Audio and storages the resulting file in `new`. Script made for testing purposes only. Use with caution, taking special consideration with the `-cpu-used` parameter value.  

**ProRes→SVT-AV1.bat**
Scans for MOV Files in the currect directory non recursively.  
It performs an encoding using ffmpeg SVT-AV1 and Opus Audio and storages the resulting file in `new`.  

**Single_File_Check_MOV_Clean.ps1**  
Scans for the specified single MOV File in the current directory and checks if the MOV is clean and uploadable by verifying the original conditions, prompting each check on the Terminal. This script is legacy and has and old logic, so it is not caught up with the refined scripts. This means it might prompt a MOV File as "Not Clean", even if the same file passes all verification as being "Clean" with the other refined scripts.

**clean.bat**  
Legacy Single File version of `Clean MOV Only.bat`  

**commands.txt**  
Reference commands used in some of these scripts  

**convert.bat**  
Legacy Single File version of `ProRes→SVT-AV1.bat`

**ffpb Progress Bug Fixed.py**  
ffpb fork polished with AI to refine the number rounding calculations. This is because, in the original version of ffpb, when running a batch for several files, sometimes for some files the progress bar showed something like: `998/999 frames` and then continued processing the next file with no warning nor problem nor prompt. This lead me to think that ffmpeg was not performing correctly, when in fact, there is no problem with ffmpeg encoding progress per se at all. Seems it just was a problem on how ffpb makes its number calculations for showing the progress bar, as well as the processed frames.  

**ffpb With Squares.py**  
Just a aesthetics change. ffpb by default uses a series of number from 0-9, and then a hastag `#` for displaying the progress bar. This version just replaces the 0-9 numbers scale and `#` with a nice ASCII Square ■ Alt+254 
