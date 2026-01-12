# Jellyfin Audio Track Normalizer

## Overview

This script scans a Jellyfin media library and ensures that every movie and TV episode has:

- At least **one stereo (2.0) audio track**
- At least **one 5.1 surround audio track**

If a file already contains both stereo and 5.1 audio, it is **skipped**.  
If one or both are missing, the script **adds only the missing audio tracks** while preserving:

- Original video stream (no re-encoding)
- Original audio tracks (7.1, Atmos, DTS, etc.)
- Subtitle streams

This is designed to prevent playback failures on systems where:

- 7.1-only audio causes Jellyfin Media Player or PipeWire to hang
- Different clients require different audio formats
- Real-time transcoding is unreliable or undesirable

---

## Why This Exists

Some media files contain **only 7.1 audio**.  
On Linux systems (especially with PipeWire, HDMI AVRs, and Jellyfin Media Player), this can result in:

- Video never starting
- Audio device negotiation failure
- Silent playback hangs with no error

By pre-generating **stereo and 5.1 fallback tracks**, playback becomes reliable across:

- Jellyfin Media Player
- TVs
- Phones
- Browsers
- AVRs

---

## What the Script Does (Step-by-Step)

For each video file:

1. Recursively scans all subdirectories under the media root
2. Uses `ffprobe` to inspect existing audio tracks
3. Detects:
   - Stereo audio (2 channels)
   - 5.1 audio (6 channels)
4. Takes one of the following actions:
   - Skip if both stereo and 5.1 already exist
   - Add only missing audio tracks if one or both are absent
5. Writes a new file with `_fixed` appended to the filename
6. Copies the video stream without re-encoding

---

## Audio Formats Added

- **Stereo:** AAC, 2.0 channels, 192 kbps
- **5.1:** AC3, 6 channels, 640 kbps

These formats were chosen for:

- Wide device compatibility
- Jellyfin auto-selection
- AVR friendliness

---

## Requirements

- Linux (tested on Debian / Proxmox CT)
- `ffmpeg`
- `ffprobe`
- Read/write access to your media library
- Jellyfin library stored on a Docker bind mount or host filesystem

### Install dependencies on Debian

```bash
apt update
apt install ffmpeg -y
```
## Library Layout Example

The script assumes a structure like:

```
/mnt/media/video/
├── movies/
│   ├── Movie1.mkv
│   └── Movie2.mp4
└── shows/
    └── ShowName/
        └── Season 01/
            └── Episode01.mkv
```
All folders are scanned recursively.

## Usage

1. Place the script on the host or inside the Jellyfin container
2. Edit the `LIBRARY` variable if needed:

```bash
LIBRARY="/mnt/media/video"
```

3. Make the script executable:
```bash
chmod +x audio_normalizer.sh
```
4. Run it:
```bash
./audio_normalizer.sh
```

---

## Output Behavior

While running, the script prints:

- Files being checked
- Whether a file is skipped
- Which audio tracks are being added
- When processing is complete

## Example Output

```text
Checking: /mnt/media/video/movies/Kingsman2.mkv
  Processing: /mnt/media/video/movies/Kingsman2_fixed.mkv
    Adding 5.1 AC3 track
    Adding stereo AAC track
  Done: /mnt/media/video/movies/Kingsman2_fixed.mkv

Checking: /mnt/media/video/shows/ExampleS01E01.mkv
  Skipping: already has stereo & 5.1
```

---

## File Safety

- Original files are never modified
- New files are created with _fixed appended
- You can verify results before replacing originals
- Safe for incremental runs

---

## Jellyfin Integration Notes

After processing:
1. Replace original files with _fixed versions (optional)
2. Rescan the Jellyfin library
3. Jellyfin will automatically select the best audio track per client

This avoids:
- Live transcoding
- PipeWire negotiation issues
- AVR passthrough failures

---

## Known Limitations

- Does not currently modify existing files in place
- Does not remove duplicate audio tracks
- Assumes FFmpeg supports input codecs



