#!/bin/bash
# Generates Nova's sound effects with the ElevenLabs Sound Effects API and saves them in Resources/Sounds.
# Run once on your Mac, then commit the .mp3 files. The app needs no key to PLAY them.
#   export ELEVENLABS_API_KEY="your key"      (keep it out of git and out of shell history files if you can)
#   bash generate_sfx.sh
# Re-run a single effect by deleting its file first. Listen to each one; regenerate any you don't like.
set -euo pipefail
: "${ELEVENLABS_API_KEY:?Set ELEVENLABS_API_KEY first (export ELEVENLABS_API_KEY=...)}"
OUT="$(cd "$(dirname "$0")" && pwd)/Sounds"
mkdir -p "$OUT"

gen() {  # name seconds prompt
  local name="$1" secs="$2" prompt="$3" file="$OUT/sfx_$1.mp3"
  if [ -s "$file" ]; then echo "Skipping $name (already exists)"; return; fi
  echo "Generating $name ..."
  local body
  body=$(python3 -c 'import json,sys; print(json.dumps({"text":sys.argv[1],"duration_seconds":float(sys.argv[2]),"prompt_influence":0.5}))' "$prompt" "$secs")
  curl -sS -f -X POST "https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" -H "Content-Type: application/json" -d "$body" -o "$file"
}

# File names must match the app's effect names exactly (sfx_<name>.mp3).
gen star          1.5 "A single delicate crystal chime with a soft shimmering sparkle, gentle, magical and clean"
gen planet        2.0 "A warm resonant synth bell with a slow gentle swell, calm, spacey and smooth"
gen moon          2.5 "A deep soft hollow tone with a faint airy shimmer, serene, lunar and peaceful"
gen deepSky       3.0 "An ethereal rising cosmic shimmer with a soft airy harp glissando, vast and dreamy"
gen constellation 2.0 "Four gentle ascending bell notes like stars connecting, clear and soft"
gen aligned       1.5 "Two confident soft thuds followed by a bright positive chime, short success confirmation"
gen achievement   3.0 "A short sparkling fanfare with bells and a shimmering glissando, celebratory but gentle"
gen warning       1.5 "Two low gentle descending tones, a soft alert that is not harsh or alarming"
gen confirm       0.5 "A tiny soft interface tick with a light bell, very short"
echo "Done. Files are in $OUT"
