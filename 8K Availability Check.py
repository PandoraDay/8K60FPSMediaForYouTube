import subprocess
import time
from datetime import datetime

# List of video URLs to monitor
VIDEO_URLS = [
    "https://www.youtube.com/watch?v=CdyWcKaFAqU",
    "https://www.youtube.com/watch?v=F0cwPiOahQY",
    "https://www.youtube.com/watch?v=p-hZmEFkXXo",
]

LOG_FILE = "8k3_status_log.txt"
CHECK_INTERVAL = 300  # 5 minutes in seconds

def get_video_title(video_url):
    """Retrieve the video title using yt-dlp."""
    try:
        cmd = ["yt-dlp", "--get-title", video_url]
        result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
        return result.stdout.strip()
    except Exception as e:
        print(f"Error retrieving video title for {video_url}: {e}")
        return "Unknown Video Title"

# Retrieve and store titles for all videos
video_titles = {url: get_video_title(url) for url in VIDEO_URLS}

def log_8k_completion(video_url, video_title):
    """Logs the exact time and video title when 8K processing is complete."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_entry = f"[{timestamp}] '{video_title}' (URL: {video_url}) has finished 8K processing.\n"
    print(log_entry.strip())  # Print to console
    with open(LOG_FILE, "a", encoding="utf-8") as log_file:
        log_file.write(log_entry)

def check_8k_status(video_url):
    """Checks if 8K (4320p) resolution is available on YouTube."""
    try:
        cmd = ["yt-dlp", "-F", video_url]
        result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
        output = result.stdout
        return "4320p" in output  # Returns True if 8K is found
    except Exception as e:
        print(f"Error checking video {video_url}: {e}")
        return False

# Keep track of which videos have completed 8K processing
videos_to_monitor = set(VIDEO_URLS)

while videos_to_monitor:
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] Checking 8K availability for {len(videos_to_monitor)} videos...")

    completed_videos = set()
    
    for video_url in videos_to_monitor:
        video_title = video_titles[video_url]
        print(f"[{timestamp}] Checking '{video_title}'...")

        if check_8k_status(video_url):
            log_8k_completion(video_url, video_title)
            completed_videos.add(video_url)

    # Remove completed videos from monitoring list
    videos_to_monitor -= completed_videos

    if videos_to_monitor:
        print(f"[{timestamp}] 8K still processing for {len(videos_to_monitor)} videos. Checking again in 5 minutes...\n")
        time.sleep(CHECK_INTERVAL)
    else:
        print(f"[{timestamp}] All monitored videos have finished 8K processing.")