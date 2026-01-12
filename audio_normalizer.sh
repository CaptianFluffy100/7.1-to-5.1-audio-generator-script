#!/bin/bash

# Script to convert 7.1 audio to 5.1 for video files
# Processes all videos under /mnt/media/video recursively
#
# Usage:
#   chmod +x audio_normalizer.sh
#   ./audio_normalizer.sh
#
# Requirements:
#   - ffmpeg and ffprobe must be installed
#   - Sufficient disk space for temporary files
#
# The script will:
#   - Find all video files recursively in /mnt/media/video
#   - Check if video has 5.1 audio
#   - If not, and it has 7.1 audio, generate 5.1 audio from 7.1
#   - If only stereo exists, skip the file
#   - Replace original file if conversion is successful

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Base directory
BASE_DIR="/mnt/media/video"

# Supported video formats
VIDEO_FORMATS=("mp4" "mkv" "avi" "mov" "m4v" "flv" "wmv" "webm" "mpg" "mpeg")

# Temporary directory for processing
TEMP_DIR="/tmp/video_71_to_51_processing"
mkdir -p "$TEMP_DIR"

# Function to log messages
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Check if ffmpeg and ffprobe are installed
check_dependencies() {
    if ! command -v ffmpeg &> /dev/null; then
        log_error "ffmpeg is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v ffprobe &> /dev/null; then
        log_error "ffprobe is not installed. Please install it first."
        exit 1
    fi
    
    log_success "Dependencies check passed"
}

# Get audio track information
get_audio_info() {
    local video_file="$1"
    local has_51=false
    local has_71=false
    local has_stereo=false
    local first_71_index=""
    
    # Use JSON with jq if available (most reliable)
    if command -v jq &> /dev/null; then
        local audio_info=$(ffprobe -v quiet -select_streams a -show_entries stream=index,channels,codec_name -of json "$video_file" 2>/dev/null)
        if [ -n "$audio_info" ]; then
            local stream_count=$(echo "$audio_info" | jq '.streams | length' 2>/dev/null)
            if [ -n "$stream_count" ] && [ "$stream_count" -gt 0 ]; then
                for ((i=0; i<stream_count; i++)); do
                    local index=$(echo "$audio_info" | jq -r ".streams[$i].index // empty" 2>/dev/null)
                    local channels=$(echo "$audio_info" | jq -r ".streams[$i].channels // empty" 2>/dev/null)
                    
                    if [ -n "$channels" ] && [ "$channels" != "null" ] && [ -n "$index" ] && [ "$index" != "null" ]; then
                        if [ "$channels" -eq 6 ]; then
                            has_51=true
                        elif [ "$channels" -eq 8 ]; then
                            has_71=true
                            if [ -z "$first_71_index" ]; then
                                first_71_index="$index"
                            fi
                        elif [ "$channels" -eq 2 ]; then
                            has_stereo=true
                        fi
                    fi
                done
            fi
        fi
    else
        # Fallback: parse default format
        local line_num=0
        local current_index=""
        local current_channels=""
        
        while IFS= read -r line; do
            line=$(echo "$line" | tr -d '[:space:]')
            if [ -z "$line" ]; then
                continue
            fi
            
            case $((line_num % 3)) in
                0)
                    if [[ "$line" =~ ^[0-9]+$ ]]; then
                        current_index="$line"
                    fi
                    ;;
                1)
                    if [[ "$line" =~ ^[0-9]+$ ]]; then
                        current_channels="$line"
                    fi
                    ;;
                2)
                    if [ -n "$current_index" ] && [ -n "$current_channels" ]; then
                        if [ "$current_channels" -eq 6 ]; then
                            has_51=true
                        elif [ "$current_channels" -eq 8 ]; then
                            has_71=true
                            if [ -z "$first_71_index" ]; then
                                first_71_index="$current_index"
                            fi
                        elif [ "$current_channels" -eq 2 ]; then
                            has_stereo=true
                        fi
                    fi
                    current_index=""
                    current_channels=""
                    ;;
            esac
            line_num=$((line_num + 1))
        done < <(ffprobe -v quiet -select_streams a -show_entries stream=index,channels,codec_name -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
    fi
    
    # Output: has_51|has_71|has_stereo|first_71_index
    echo "$has_51|$has_71|$has_stereo|$first_71_index"
}

# Generate 5.1 audio from 7.1
generate_51_from_71() {
    local video_file="$1"
    local output_audio="$2"
    local audio_index="$3"
    
    log "Generating 5.1 audio from 7.1 (track index: $audio_index)..."
    set +e
    
    # Convert 7.1 to 5.1: map FL, FR, FC, LFE, BL, BR (drop SL, SR)
    # Show ffmpeg output directly, replacing the line as progress continues
    # Use -nostdin to prevent ffmpeg from reading from stdin
    ffmpeg -nostdin -i "$video_file" -map 0:a:$audio_index \
        -af "pan=5.1|FL=FL|FR=FR|FC=FC|LFE=LFE|BL=BL|BR=BR" \
        -c:a ac3 -b:a 640k -y "$output_audio" </dev/null 2>&1 | \
    while IFS= read -r line; do
        # Replace the line with ffmpeg progress output
        echo -ne "\r${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $line"
    done
    
    local result=${PIPESTATUS[0]}
    set -e
    echo ""  # New line after progress
    sleep 1  # Give filesystem a moment to sync
    
    if [ $result -eq 0 ] && [ -f "$output_audio" ] && [ -s "$output_audio" ]; then
        local file_size=$(stat -f%z "$output_audio" 2>/dev/null || stat -c%s "$output_audio" 2>/dev/null || echo "0")
        local file_mb=$((file_size / 1024 / 1024))
        log_success "5.1 audio generation complete (${file_mb} MB)"
        return 0
    else
        log_error "5.1 audio generation from 7.1 failed"
        return 1
    fi
}

# Merge 5.1 audio into video
merge_51_audio() {
    local video_file="$1"
    local audio_file="$2"
    local output_file="$3"
    
    log "Merging 5.1 audio into video..."
    set +e
    
    # Get all audio stream numbers (not indices) to map all existing audio tracks
    local audio_streams=()
    if command -v jq &> /dev/null; then
        local audio_info=$(ffprobe -v quiet -select_streams a -show_entries stream=index -of json "$video_file" 2>/dev/null)
        local stream_count=$(echo "$audio_info" | jq '.streams | length' 2>/dev/null)
        if [ -n "$stream_count" ] && [ "$stream_count" -gt 0 ]; then
            for ((i=0; i<stream_count; i++)); do
                audio_streams+=("$i")
            done
        fi
    else
        # Fallback: count audio streams using default format
        local stream_count=$(ffprobe -v quiet -select_streams a -show_entries stream=index -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null | wc -l)
        if [ "$stream_count" -gt 0 ]; then
            for ((i=0; i<stream_count; i++)); do
                audio_streams+=("$i")
            done
        fi
    fi
    
    # If no audio streams found, default to first one
    if [ ${#audio_streams[@]} -eq 0 ]; then
        audio_streams=("0")
    fi
    
    log "Found ${#audio_streams[@]} audio track(s) to preserve"
    
    # Get all subtitle stream numbers to preserve all subtitle tracks
    local subtitle_streams=()
    if command -v jq &> /dev/null; then
        local subtitle_info=$(ffprobe -v quiet -select_streams s -show_entries stream=index -of json "$video_file" 2>/dev/null)
        local subtitle_count=$(echo "$subtitle_info" | jq '.streams | length' 2>/dev/null)
        if [ -n "$subtitle_count" ] && [ "$subtitle_count" -gt 0 ]; then
            for ((i=0; i<subtitle_count; i++)); do
                subtitle_streams+=("$i")
            done
        fi
    else
        # Fallback: count subtitle streams using default format
        local subtitle_count=$(ffprobe -v quiet -select_streams s -show_entries stream=index -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null | wc -l)
        if [ "$subtitle_count" -gt 0 ]; then
            for ((i=0; i<subtitle_count; i++)); do
                subtitle_streams+=("$i")
            done
        fi
    fi
    
    if [ ${#subtitle_streams[@]} -gt 0 ]; then
        log "Found ${#subtitle_streams[@]} subtitle track(s) to preserve"
    fi
    
    # Build ffmpeg command array
    local ffmpeg_args=(-i "$video_file" -i "$audio_file" -map "0:v:0")
    
    # Map all existing audio tracks
    for stream_num in "${audio_streams[@]}"; do
        ffmpeg_args+=(-map "0:a:$stream_num")
    done
    
    # Map the new 5.1 audio track
    ffmpeg_args+=(-map "1:a:0")
    
    # Map all existing subtitle tracks
    for stream_num in "${subtitle_streams[@]}"; do
        ffmpeg_args+=(-map "0:s:$stream_num")
    done
    
    # Set codecs: copy video, copy all existing audio tracks, encode new 5.1 track, copy all subtitles
    ffmpeg_args+=(-c:v "copy")
    for ((i=0; i<${#audio_streams[@]}; i++)); do
        ffmpeg_args+=(-c:a:$i "copy")
    done
    ffmpeg_args+=(-c:a:${#audio_streams[@]} "ac3" -b:a:${#audio_streams[@]} "640k")
    # Copy all subtitle tracks
    for ((i=0; i<${#subtitle_streams[@]}; i++)); do
        ffmpeg_args+=(-c:s:$i "copy")
    done
    ffmpeg_args+=(-y "$output_file")
    
    # Merge video with all original audio tracks and new 5.1 audio
    # Show ffmpeg output directly, replacing the line as progress continues
    # Use -nostdin to prevent ffmpeg from reading from stdin
    ffmpeg -nostdin "${ffmpeg_args[@]}" </dev/null 2>&1 | \
    while IFS= read -r line; do
        # Replace the line with ffmpeg progress output
        echo -ne "\r${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $line"
    done
    
    local result=${PIPESTATUS[0]}
    set -e
    echo ""  # New line after progress
    
    if [ $result -eq 0 ] && [ -f "$output_file" ] && [ -s "$output_file" ]; then
        log_success "Merge complete"
        return 0
    else
        log_error "Merge failed"
        return 1
    fi
}

# Process a single video file
process_video() {
    local video_file="$1"
    local video_name=$(basename "$video_file")
    
    log "Processing: $video_name"
    
    # Get audio track information
    local audio_info=$(get_audio_info "$video_file" 2>/dev/null)
    if [ -z "$audio_info" ]; then
        log_warning "Skipping $video_name (no audio tracks or failed to parse)"
        return 1
    fi
    
    local has_51=$(echo "$audio_info" | cut -d'|' -f1)
    local has_71=$(echo "$audio_info" | cut -d'|' -f2)
    local has_stereo=$(echo "$audio_info" | cut -d'|' -f3)
    local first_71_index=$(echo "$audio_info" | cut -d'|' -f4)
    
    log "Audio track analysis: has_5.1=$has_51, has_7.1=$has_71, has_stereo=$has_stereo"
    
    # If already has 5.1, skip
    if [ "$has_51" = "true" ]; then
        log_success "$video_name already has 5.1 audio - skipping"
        return 2
    fi
    
    # If only stereo, skip
    if [ "$has_stereo" = "true" ] && [ "$has_71" = "false" ]; then
        log_success "$video_name only has stereo - skipping"
        return 2
    fi
    
    # If no 7.1, skip
    if [ "$has_71" = "false" ]; then
        log_warning "$video_name has no 7.1 audio to convert - skipping"
        return 2
    fi
    
    # Need to convert 7.1 to 5.1
    if [ -z "$first_71_index" ]; then
        log_error "Found 7.1 audio but could not determine track index"
        return 1
    fi
    
    # Convert audio stream index to audio stream number (for -map 0:a:X)
    # We need to find which audio stream number corresponds to this index
    local audio_stream_num="0"  # Default to first audio stream
    if command -v jq &> /dev/null; then
        local audio_info_json=$(ffprobe -v quiet -select_streams a -show_entries stream=index,channels -of json "$video_file" 2>/dev/null)
        local stream_count=$(echo "$audio_info_json" | jq '.streams | length' 2>/dev/null)
        if [ -n "$stream_count" ] && [ "$stream_count" -gt 0 ]; then
            for ((i=0; i<stream_count; i++)); do
                local idx=$(echo "$audio_info_json" | jq -r ".streams[$i].index // empty" 2>/dev/null)
                if [ "$idx" = "$first_71_index" ]; then
                    audio_stream_num="$i"
                    break
                fi
            done
        fi
    fi
    
    log "Using 7.1 audio stream $audio_stream_num (index: $first_71_index) to generate 5.1"
    
    # Create temporary files
    local temp_51="${TEMP_DIR}/temp_51_${video_name%.*}.ac3"
    local temp_video="${TEMP_DIR}/temp_${video_name}"
    local backup_file="${video_file}.backup"
    
    # Create backup
    log "Creating backup of original file..."
    local file_size=$(stat -f%z "$video_file" 2>/dev/null || stat -c%s "$video_file" 2>/dev/null || echo "0")
    if [ "$file_size" -eq 0 ]; then
        log_error "Cannot determine file size or file is empty"
        return 1
    fi
    
    local file_size_mb=$((file_size / 1024 / 1024))
    local file_size_gb=$((file_size / 1024 / 1024 / 1024))
    if [ "$file_size_gb" -gt 0 ]; then
        log "File size: ${file_size_gb}.$(( (file_size / 1024 / 1024) % 1024 )) GB - copying backup..."
    else
        log "File size: ${file_size_mb} MB - copying backup..."
    fi
    
    set +e
    cp "$video_file" "$backup_file"
    local cp_result=$?
    set -e
    
    if [ $cp_result -ne 0 ] || [ ! -f "$backup_file" ]; then
        log_error "Failed to create backup"
        return 1
    fi
    
    sleep 1  # Give filesystem a moment to sync
    local backup_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null || echo "0")
    if [ "$backup_size" -ne "$file_size" ]; then
        log_error "Backup file size mismatch. Expected: $file_size, Got: $backup_size"
        rm -f "$backup_file"
        return 1
    fi
    
    log_success "Backup created successfully"
    
    # Step 1: Generate 5.1 audio from 7.1
    if ! generate_51_from_71 "$video_file" "$temp_51" "$audio_stream_num"; then
        log_error "Failed to generate 5.1 audio for: $video_name"
        rm -f "$backup_file" "$temp_51"
        return 1
    fi
    
    # Step 2: Merge 5.1 audio into video
    if ! merge_51_audio "$video_file" "$temp_51" "$temp_video"; then
        log_error "Failed to merge 5.1 audio for: $video_name"
        rm -f "$backup_file" "$temp_51" "$temp_video"
        return 1
    fi
    
    # Verify output file
    sleep 1
    if [ ! -f "$temp_video" ] || [ ! -s "$temp_video" ]; then
        log_error "Output file is missing or empty"
        rm -f "$backup_file" "$temp_51" "$temp_video"
        return 1
    fi
    
    # Replace original with processed file
    log "Replacing original file..."
    mv "$temp_video" "$video_file"
    log_success "Successfully processed: $video_name"
    
    # Clean up temporary files
    rm -f "$temp_51"
    
    # Remove backup after successful processing
    rm -f "$backup_file"
    log "Removed backup file"
    
    return 0
}

# Find and process all video files
find_and_process() {
    local processed=0
    local skipped=0
    local failed=0
    
    log "Starting video processing in: $BASE_DIR"
    
    # Check if base directory exists
    if [ ! -d "$BASE_DIR" ]; then
        log_error "Base directory does not exist: $BASE_DIR"
        exit 1
    fi
    
    # Find all video files recursively
    log "Searching for video files in: $BASE_DIR"
    
    local file_count=0
    for format in "${VIDEO_FORMATS[@]}"; do
        while IFS= read -r -d '' video_file; do
            file_count=$((file_count + 1))
            set +e  # Temporarily disable exit on error to capture return code
            process_video "$video_file"
            local result=$?
            set -e  # Re-enable exit on error
            if [ $result -eq 0 ]; then
                processed=$((processed + 1))
            elif [ $result -eq 2 ]; then
                skipped=$((skipped + 1))
            else
                failed=$((failed + 1))
            fi
        done < <(find "$BASE_DIR" -type f -iname "*.${format}" -print0 2>/dev/null)
    done
    
    if [ $file_count -eq 0 ]; then
        log_warning "No video files found in $BASE_DIR"
    else
        log "Found $file_count video file(s) to process"
    fi
    
    log_success "Processing complete!"
    log "Processed: $processed"
    log "Skipped: $skipped"
    log "Failed: $failed"
}

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Main execution
main() {
    log "=== 7.1 to 5.1 Audio Converter ==="
    check_dependencies
    find_and_process
    cleanup
    log_success "All done!"
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Run main function
main

