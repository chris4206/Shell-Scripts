#!/bin/bash

# Configuration
BASE_DIR="/Users/nacho-llc/Library/Containers/com.na.istb/Data/Documents/AppData/Downloaded"
FFMPEG_PATH="/Volumes/MC DATA/ffmpeg"
AUTO_CLEANUP=true        # Auto-delete merge file
SHOW_FOLDER_PROMPT=false # Control the folder prompt with this flag
OUTPUT_DIR="/Volumes/MC DATA/Shared"
#OUTPUT_DIR="$PWD"  # ALWAYS save files here

echo "🚀 iSTB Episode Merger"
echo "================================================"

# Create merge file in OUTPUT_DIR to avoid path issues
MERGE_FILE="${OUTPUT_DIR}/season_merge_$(date +%s).txt"

# Step 1: Find ALL episodes with their timestamps
echo "🔍 Collecting episode information..."

# Create a temporary file to store episode info
TEMP_FILE=$(mktemp)

# Find each episode's tracks-v1a1 folder and get its creation time
find "$BASE_DIR" -type d -name "tracks-v1a1" -path "*vod_episode*" | while read ts_dir; do
    ep_folder=$(dirname "$ts_dir")
    ep_name=$(basename "$ep_folder")
    
    # Get the OLDEST .ts file in the folder (most accurate download start time)
    oldest_ts=$(find "$ts_dir" -name "*.ts" -type f -exec ls -t {} + | tail -1)
    
    if [ -n "$oldest_ts" ] && [ -f "$oldest_ts" ]; then
        # Get timestamp of oldest TS file
        timestamp=$(stat -f "%m" "$oldest_ts" 2>/dev/null)
        if [ -n "$timestamp" ]; then
            echo "${timestamp}|${ep_folder}" >> "$TEMP_FILE"
        else
            timestamp=$(stat -f "%m" "$ts_dir" 2>/dev/null)
            echo "${timestamp}|${ep_folder}" >> "$TEMP_FILE"
        fi
    else
        timestamp=$(stat -f "%m" "$ts_dir" 2>/dev/null)
        echo "${timestamp}|${ep_folder}" >> "$TEMP_FILE"
    fi
done

# Check if we found any episodes
if [ ! -s "$TEMP_FILE" ]; then
    echo "❌ No episodes found!"
    rm "$TEMP_FILE"
    exit 1
fi

# Sort by timestamp (oldest first) and extract folder paths
echo "⏰ Sorting episodes by download time..."
EPISODE_FOLDERS=()
while IFS='|' read -r timestamp folder; do
    EPISODE_FOLDERS+=("$folder")
done < <(sort -n "$TEMP_FILE")

rm "$TEMP_FILE"

echo "✅ Found ${#EPISODE_FOLDERS[@]} episodes:"

# Step 2: Display episodes in order
counter=1
total_segments=0
for folder in "${EPISODE_FOLDERS[@]}"; do
    ep_name=$(basename "$folder")
    ts_folder="$folder/tracks-v1a1"
    segment_count=0
    
    if [ -d "$ts_folder" ]; then
        segment_count=$(find "$ts_folder" -name "*.ts" 2>/dev/null | wc -l)
        # Get human-readable time
        oldest_ts=$(find "$ts_folder" -name "*.ts" -type f -exec ls -t {} + | tail -1 2>/dev/null)
        if [ -n "$oldest_ts" ] && [ -f "$oldest_ts" ]; then
            dl_time=$(stat -f "%Sm" -t "%H:%M:%S" "$oldest_ts" 2>/dev/null || echo "Unknown")
        else
            dl_time="Unknown"
        fi
    fi
    
    total_segments=$((total_segments + segment_count))
    
    echo "  $counter. $ep_name"
    echo "     ⏰ Started: $dl_time"
    echo "     📊 Segments: $segment_count"
    ((counter++))
done

echo -e "\n📊 Summary:"
echo "   Total episodes: ${#EPISODE_FOLDERS[@]}"
echo "   Total segments: $total_segments"
estimated_size=$((total_segments * 4500000 / 1000000000))
echo "   Estimated size: ~${estimated_size}GB"
echo "   ⚙️  Automation settings:"
echo "      🧹 Auto-cleanup: $( [ "$AUTO_CLEANUP" = true ] && echo "ENABLED" || echo "DISABLED" )"
echo "      📂 Folder prompt: $( [ "$SHOW_FOLDER_PROMPT" = true ] && echo "ENABLED" || echo "DISABLED" )"
echo "      📁 Output directory: $OUTPUT_DIR"

# Step 3: Ask for output filename (BUT NOT LOCATION)
DEFAULT_OUTPUT="Season_$(date +%Y%m%d_%H%M%S).mp4"
echo -e "\n📁 Output filename [default: $DEFAULT_OUTPUT]:"
echo "   File will be saved to: $OUTPUT_DIR"
read -p "   > " custom_name

if [ -z "$custom_name" ]; then
    OUTPUT_FILENAME="$DEFAULT_OUTPUT"
else
    if [[ "$custom_name" != *.mp4 ]]; then
        OUTPUT_FILENAME="${custom_name}.mp4"
    else
        OUTPUT_FILENAME="$custom_name"
    fi
fi

# Construct full output path
OUTPUT_FILE="${OUTPUT_DIR}/${OUTPUT_FILENAME}"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

if [ -f "$OUTPUT_FILE" ]; then
    read -p "⚠️  File exists. Overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Cancelled."
        exit 0
    fi
fi

# Step 4: Confirm
echo -e "\n⚠️  Will merge ${#EPISODE_FOLDERS[@]} episodes in this order:"
for i in "${!EPISODE_FOLDERS[@]}"; do
    idx=$((i+1))
    ep_name=$(basename "${EPISODE_FOLDERS[$i]}")
    echo "   $idx. $ep_name"
done

echo -e "\n📁 Output: $OUTPUT_FILENAME"
echo "   📍 Location: $OUTPUT_DIR"
echo "   📊 Size: ~${estimated_size}GB"

read -p "✅ Proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cancelled."
    exit 0
fi

# Step 5: Create merge file IN OUTPUT DIRECTORY
echo -e "\n📝 Creating merge file..."
> "$MERGE_FILE"
for folder in "${EPISODE_FOLDERS[@]}"; do
    ts_folder="$folder/tracks-v1a1"
    if [ -d "$ts_folder" ]; then
        ep_name=$(basename "$folder")
        echo "  ➕ $ep_name"
        
        # Sort TS files numerically
        find "$ts_folder" -name "*.ts" | sort -V | while read ts_file; do
            echo "file '$ts_file'" >> "$MERGE_FILE"
        done
    fi
done

echo "   Created $MERGE_FILE with $(wc -l < "$MERGE_FILE") entries."

# Step 6: Merge - NO NEED TO CHANGE DIRECTORIES
echo -e "\n🔄 Merging with FFmpeg..."
echo "   This may take a while. System will stay awake during merge."
echo "   ==========================================================="

# Keep system awake during merge - use absolute paths
caffeinate -i sh -c "\"$FFMPEG_PATH\" -f concat -safe 0 -i \"$MERGE_FILE\" -c copy -stats \"$OUTPUT_FILE\""

# Step 7: Results and automated cleanup
if [ -f "$OUTPUT_FILE" ]; then
    echo -e "\n✅ Success! Created: $OUTPUT_FILENAME"
    file_size=$(du -h "$OUTPUT_FILE" | cut -f1)
    echo "   Size: $file_size"
    echo "   Location: $OUTPUT_FILE"

     # Force kill any leftover caffeinate processes
    pkill -f "caffeinate.*ffmpeg" 2>/dev/null
    pkill -f "caffeinate.*$FFMPEG_PATH" 2>/dev/null
    
    # AUTO-CLEANUP: Delete merge file
    if [ "$AUTO_CLEANUP" = true ] && [ -f "$MERGE_FILE" ]; then
        rm "$MERGE_FILE"
        echo "   🧹 Merge file auto-deleted"
    fi
    
    # Verify caffeinate is gone
    if pgrep -f "caffeinate.*ffmpeg" >/dev/null; then
        echo "   ⚠️  Warning: caffeinate process still running (killing now)..."
        pkill -f "caffeinate.*ffmpeg"
    fi
   
    # FOLDER PROMPT: Controlled by SHOW_FOLDER_PROMPT flag
    if [ "$SHOW_FOLDER_PROMPT" = true ]; then
        read -p "📂 Open output folder? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            open "$OUTPUT_DIR"
            echo "   Folder opened."
        fi
    fi
    
else
    echo "❌ Merge failed!"

     # KILL CAFFEINATE even on failure
    pkill -f "caffeinate.*ffmpeg" 2>/dev/null
    pkill -f "caffeinate.*$FFMPEG_PATH" 2>/dev/null

    if [ -f "$MERGE_FILE" ]; then
        echo "   Merge file kept for debugging: $MERGE_FILE"
    fi
    exit 1
fi

echo -e "\n🎉 All done! System can now sleep safely."
