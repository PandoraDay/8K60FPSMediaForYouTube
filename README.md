# 8K60FPSMediaForYouTube  

Here, I share some scripts I used to work, prepare and upload 8K 7680x4320 60FPS Media to YouTube, so YouTube actually process it in 4320p60. Some of them are Windows CMD BATS, some of them are Powershell 7.5.0 PS1 Scripts. I am not by all means an expert. I did this with help of Internet (AskUbuntu, Reddit, Stack Overflow, Super User, VideoHelp Forum, etc.) and AI such as Kimi AI, DeepSeek, ChatGPT and Microsoft Copilot. Please, feel free to use and adapt these scripts to your convenience.  

For context, Audio/Video technical details and workflow, please check my Reddit post (I got banned from Reddit after that post, for some reason)  
[Part 02 - My experience uploading 8K resolution videos to YouTube](https://www.reddit.com/r/videography/comments/1jg89z7)

### **Dependencies**  
Optional: [ffpb - A Terminal Progress Bar for ffmpeg](https://github.com/althonos/ffpb)  
ffmpeg 2025-03-20  
ffprobe 2025-03-20  
mediainfo v24.12  
Python 3.13  
yt-dlp 2025.02.19  
Windows CMD  
Windows PowerShell 7.5.0  
Important for PS1 Files that invoke `Start-Job` for parallell processing. These PS1 Scripts might not work with PowerShell 5.0 included in Windows by default  

### **Directory Tree**  
Some of these scripts require the following Directory Tree: `Current Directory\new\svt`

## **Description of Files**  

### **8K Availability Check.py**  
Checks and prints the exact date and time when a video becomes available for viewing in 8K 4320p60 resolution in YouTube. It invokes yt-dlp with th -F Parameter and looks for the String 4320p every 5 minutes. Ideally, when YouTube finishes processing the video up to 4320p60, the Script prints the exact Date and Time when the video gets processed by YouTube in 8K, and logs the info both in ther Terminal and a Log File.  

> [!CAUTION]
> Do **NOT** use. This automatic check seems to "lock" the video as "occupied", making YouTube to refuse processing 4320p60 videos checked with this script.  

### **8kyoutubecheck.ps1**  
Checks and logs which videos from a YouTube Playlist are available to watch in 4320p60. In the log, a final summary of which videos are available to watch in 4320p60 and which videos are not available to watch in 4320p is printed with YouTube Links and Video Names.  

### **Batch_Check_Media_Clean_Each_NoRecurse.ps1**  
Refined script for checking MOV and MP4 files if they are clean and uploadable with the following conditions. Scans the current directory non recursively and prompts each check for each file in the Terminal.

- #### **Condition 01 - Metadata Clean Check**

      ffprobe -hide_banner -i "input"

  > Metadata is kept at minimum. "Encoder" tag is non-existent neither in Container, Video, nor Audio Stream Metadata. For Video and Audio, only the absolutely essential "handler_name" and "vendor_id" are present, and even so, "vendor_id" is empty (Reported as [0][0][0][0] in ffmpeg). This is because seems like these tags are intrinsec of MOV/MP4 file's structure.

      Video

        handler_name: VideoHandler

        vendor_id: [0][0][0][0]

      Audio

        handler_name: SoundHandler

        vendor_id: [0][0][0][0]

- #### **Condition 02 - Check Framerate and Audio Sampe Rate**

      ffprobe -hide_banner -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=noprint_wrappers=1:nokey=1 "input" && ffprobe -hide_banner -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "input"  

  > There should be 2 results in the output. If working with 44100Hz, Audio Sample Rate can be 44100 as well. It prompts the Average Framerate of a video, by actually analysing the frames of the video with `stream=avg_frame_rate`. This is different from just reading the Framerate information in the container with `stream=r_frame_rate`, which might report 60FPS, but the video might actually have a different framerate value, leading to discrepancies.

      Video Average Framerate

      60/1

      Audio Sample Rate

      48000

- #### **Condition 03 - Check Media Time Stamps**

      ffprobe -i "input.mov" -hide_banner -show_streams | Select-String "time_base"

  > There should be 2 results in the output. If working with 44100Hz, Audio Time Stamp can be 1/44100 as well.

      Video Time Stamp

      time_base=1/60000

      Audio Time Stamp

      time_base=1/48000

- #### **Condition 04 - Check if Fast Start is Enabled**

      ffprobe -hide_banner -v debug "input.mov" 2>&1 | Select-String seeks

  > If seeks 0 means Fast Start is Enabled


- #### **Condition 05 - Check is Fast Start is Enabled - 2nd Method**

      ffmpeg -hide_banner -v trace -i "input.mov" 2>&1 | Select-String -Pattern "type:'mdat'", "type:'moov'"

  > If moov is at the beggining before mdat, Fast Start is Enabled

- #### **Condition 06 - Check is Fast Start is Enabled - 3rd Method - Streamability Check**

      mediainfo -f "input.mov" | Select-String IsStreamable

  > If 'Yes' Fast Start is Enabled

- #### **Condition 07 - Handler Names Check**

      ffprobe -v quiet -print_format json -show_streams "input"

  > The value for the tag "handler_name" in Video Stream must be "VideoHandler" and in Audio Stream it must be "SoundHandler". If other values are found, it fails the verification.

- #### **Condition 08 - Vendor ID Check**

      ffprobe -hide_banner -v error -select_streams v:0 -show_entries stream_tags=vendor_id -of default=noprint_wrappers=1:nokey=1 "input" && ffprobe -hide_banner -v error -select_streams a:0 -show_entries stream_tags=vendor_id -of default=noprint_wrappers=1:nokey=1 "input"
  
  > The value for the tag "vendor_id" in both Video Stream and Audio Stream must be [0][0][0][0] which means "empty". FFMPEG reports [0][0][0][0] when the value is actually empty (00 00 00 00 values in Hexadecimal Analysing Program called HxD). If other values are found, it fails the verification. This includes cases when the vendor_id value seems empty, but it is actually populated by blank spaces (20 20 20 20 values in Hexadecimal Analysing Program called HxD). For some reason, FFMPEG always writes the value "FFMP" in the Video vendor_id, which has to be manually replaced by 00 00 00 00 in Hexadecimal Analysing Program.

### **Batch_Check_Media_Clean_Each_Recurse.ps1**  
Same as `Batch_Check_Media_Clean_Each_NoRecurse.ps1`. The only difference is that the script scans the current directory recursively with `Get-ChildItem -Recurse`  

### **Batch_Check_Media_Clean_Simple_NoRecurse.ps1**  
Same logic as `Batch_Check_Media_Clean_Each_NoRecurse.ps1`. Performs all the checks and simplifies the Terminal Output nice, clean and without clutter. PowerShell 7.5.0 is recommended, as it invokes `Start-Job` for Parallel Processing and performs the checks on multiple files at once. Without `Start-Job`, each file will be processed sequentially, which might take a long time if working with numerous files.

### **Batch_Check_Media_Clean_Simple_Recurse.ps1**  
Same as `Batch_Check_Media_Clean_Simple_NoRecurse.ps1`. The only difference is that the script scans the current directory recursively with `Get-ChildItem -Recurse`

### **Clean Faststart MKV to MP4 60fps.bat**  
Scans current directory non recursively for MKV Files. Takes MKV, remux it to MP4 with ffmpeg and the clean remuxed file is put on the directory called `new`. Check the file's code for details about ffmpeg parameters.  

### **Clean MOV Only.bat**  
Scans current directory non recursively for MOV Files. Takes MOV, remux it to MOV with ffmpeg and the clean remuxed file is put on the directory called `new`. Check the file's code for details about ffmpeg parameters.  

### **Clean MP4 Only.bat**  
Scans current directory non recursively for MP4 Files. Takes MP4, remux it to MP4 with ffmpeg and the clean remuxed file is put on the directory called `new`. Check the file's code for details about ffmpeg parameters.  

### **Copy Video and Resample Audio to 48Khz.ps1**  
Resamples MOV 44100Hz Audio to Stereo PCM S16LE 48000Hz. Copies Video and cleans the MOV.  

### **MOV to SVT-AV1 MP4 to SVT-AV1 MP4.bat**
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

### **clean.bat**  
Legacy Single File version of `Clean MOV Only.bat`  

### **commands.txt**  
Reference commands used in some of these scripts  

### **convert.bat**  
Legacy Single File version of `ProRes→SVT-AV1.bat`

### **ffpb Progress Bug Fixed.py**  
ffpb fork polished with AI to refine the number rounding calculations. This is because, in the original version of ffpb, when running a batch for several files, sometimes for some files the progress bar showed something like: `998/999 frames` and then continued processing the next file with no warning nor problem nor prompt. This lead me to think that ffmpeg was not performing correctly, when in fact, there is no problem with ffmpeg encoding progress per se at all. Seems it just was a problem on how ffpb makes its number calculations for showing the progress bar, as well as the processed frames.  

### **ffpb With Squares.py**  
Just a aesthetics change. ffpb by default uses a series of number from 0-9, and then a hastag `#` for displaying the progress bar. This version just replaces the 0-9 numbers scale and `#` with a nice ASCII Square ■ Alt+254 
