<div align="center">
  <img src="web/static/images/NOVA%20Logo%20With%20BG.png" alt="NOVA logo" width="110">

  # NOVA - Astronomy Beyond Sight

  **Explore the universe through sound, voice guidance, and touch**

  A project built for **HackPHS 2026 - Into the Sky**
</div>

## Why we built NOVA

Astronomy is usually taught through pictures, telescopes, and looking up at the night sky. But not everyone can experience it that way.

We built **NOVA** to make exploring space more accessible, especially for people who are blind or visually impaired. Instead of depending only on what you can see, NOVA uses spoken descriptions, sound, and haptic feedback to help you discover what's above you.

NOVA has two parts: an interactive website and an iPhone app. They offer different ways to explore the same sky.

## What NOVA does

### Website

- **Live sky map** - shows calculated positions of stars, planets, and constellations for a location and time, with updates every 30 seconds in Live mode
- **Constellation tours** - select a constellation from the sidebar to focus on it and take a guided tour of its visible stars
- **Spoken descriptions** - hear information about stars and planets instead of relying only on the map
- **Ask NOVA** - ask astronomy questions by typing or speaking, then get a written or spoken answer
- **Accessible controls** - keyboard navigation, labels for screen readers, and instructions on the How to Listen page
- **Three audio modes** - Full audio (music, effects, and narration), Voice only (narration), and Audio off

### iPhone app

- **Find an object** - choose a star or planet and follow spoken and haptic directions to point toward it
- **Identify the sky** - aim your phone and find out which astronomical object you may be pointing at
- **Explore tonight** - hear about objects above the horizon based on your location
- **Sky camera** - a camera-based view with sky labels for sighted helpers
- **Discoveries and missions** - save what you've found, complete optional goals, and earn achievements
- **Customizable accessibility settings** - adjust narration, vibrations, guidance sounds, and other preferences

The app uses the phone's location and motion sensors to estimate its direction. Accuracy can vary with compass calibration and your surroundings.

## How it works

**On the website**, Python and [Skyfield](https://rhodesmill.org/skyfield/) calculate where astronomical objects should appear at the selected time and location. The map uses star catalog data and constellation connections to draw the sky. It is a calculated view, **not a live telescope feed or camera view**.

**For voice questions**, the website uses ElevenLabs for speech-to-text and text-to-speech, and OpenRouter to generate astronomy answers. Ask NOVA is designed to stay focused on astronomy, although AI answers and topic checks can still make mistakes.

**On iPhone**, NOVA uses native Swift code along with the device's location, compass, and motion information to guide users with speech, sound, and vibration.

## Tech stack

| Website | iPhone app |
| --- | --- |
| Python, Flask | Swift, SwiftUI |
| HTML, CSS, JavaScript | Core Location and device motion |
| Skyfield, NumPy | AVFoundation and haptics |
| HYG star catalog, Stellarium constellation data, Yale Bright Star Catolog, JPL ephemeris | On-device astronomy calculations |
| OpenRouter, ElevenLabs, Google sign-in |

## Run the website locally

### 1. Install the requirements

You will need **Python 3** and an internet connection for the first astronomy data download.

```bash
cd web
python -m pip install -r requirements.txt
```

On Windows, you can use `py` instead of `python`.

### 2. Add your API keys

Copy `web/.env.example` to `web/.env`, then fill in the services you want to use:

```env
ELEVENLABS_API_KEY=
ELEVENLABS_VOICE_ID=
OPENROUTER_API_KEY=
OPENROUTER_MODEL=openrouter/free
NOVA_GUARD_MODEL=openrouter/free
NOVA_SIGNING_KEY=
OPENAI_API_KEY=
```

- **OpenRouter** powers Ask NOVA's text responses
- **ElevenLabs** is used for microphone transcription and spoken narration
- **OpenAI** is optional for enhanced star and planet descriptions on the website
- **NOVA_SIGNING_KEY** should be set to a long, random value before public deployment

The sky map can run without AI keys, but voice and AI features need their respective services configured. Model availability can change on OpenRouter.

**Never commit `.env` or API keys to GitHub.**

### 3. Start NOVA

From inside the `web` folder:

```bash
python app.py
```

Then open **http://127.0.0.1:5000**.

The first sky request may take longer because the site downloads the HYG star catalog, constellation data, and the JPL ephemeris into `web/data/`. Later requests reuse the local files.

### 4. Test audio

Make sure these files exist:

```text
web/static/sounds/ambient.mp3
web/static/sounds/click_effect.mp3
```

Use the audio button in the navigation bar to switch between Full audio, Voice only, and Audio off. Your browser may require a click before it allows music to play.

## Run the iPhone app

The iPhone app is **still in development** and isn't published on the App Store.

1. Open `app/Nova/Nova.xcodeproj` in Xcode on a Mac
2. Let Xcode resolve any required packages and select an iPhone or simulator
3. Check signing, permissions, and any local service configuration
4. Build and run the app

A real iPhone is best for testing pointing directions, compass readings, and haptic feedback. Some features won't behave the same way in a simulator. Google sign-in and premium voice need extra configuration; the core app is designed to work without signing in.

## Project structure

```text
NOVA/
├── app/
│   └── Nova/                 # Swift iPhone app and Xcode project
├── web/
│   ├── app.py                # Flask pages and API routes
│   ├── sky_data.py           # Sky calculations and astronomy data
│   ├── voice_mode.py         # Ask NOVA and voice APIs
│   ├── requirements.txt
│   ├── .env.example
│   ├── data/                 # Downloaded sky data (created locally)
│   ├── templates/            # Home, Explore, Ask NOVA, and Guide pages
│   └── static/
│       ├── images/
│       ├── sounds/
│       ├── audio.js          # Music, clicks, and audio modes
│       ├── main.js           # Interactive sky map
│       └── voice-mode.js     # Ask NOVA browser controls
└── README.md
```

## Things to know

- Sky positions are calculated from astronomical data; the map does not account for clouds, buildings, or light pollution
- Compass and phone orientation measurements can be affected by magnetic interference
- AI-generated explanations should not be treated as guaranteed scientific facts
- Accessibility is an ongoing part of the project, and we want to keep testing it with real users
- The website's Flask development server is for local use, not a production deployment

## Data and services

Thanks to the projects and services that make NOVA possible:

- [Skyfield](https://rhodesmill.org/skyfield/) for astronomical position calculations
- [Yale Bright Star Data}(http://tdc-www.harvard.edu/catalogs/bsc5.html) for star catalog data on mobile
- [HYG Database](https://github.com/astronexus/HYG-Database) for star catalog data
- [Stellarium Sky Cultures](https://github.com/Stellarium/stellarium-skycultures) for constellation connections
- [NASA/JPL ephemerides](https://ssd.jpl.nasa.gov/planets/eph_export.html) for solar system positions
- [ElevenLabs](https://elevenlabs.io/) for voice features
- [OpenRouter](https://openrouter.ai/) for Ask NOVA

## Team

Built by **Raunav and Vihaan** for HackPHS 2026.

**The universe is for everyone**
