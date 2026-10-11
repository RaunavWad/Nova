<div align="center">
  <img src="web/static/images/NOVA%20Logo%20No%20BG.png" alt="NOVA logo" width="110">

  # NOVA - The Universe Is For Everyone

  **Explore the universe through sound, voice guidance, and touch**

  A project built for **HackPHS 2026 - Into the Skies**
</div>

## Visit NOVA online

**Website:** `https://base2nova.dpdns.org/`

NOVA is live!

## Why we built NOVA

Astronomy is usually taught through pictures, telescopes, and looking up at the night sky. But not everyone can experience it that way.

We built **NOVA** to make exploring space more accessible, especially for people who are blind or visually impaired. Instead of depending only on what you can see, NOVA uses spoken descriptions, sound, and haptic feedback to help you discover what's above you.

NOVA has two parts: an interactive website and an iPhone app. They offer different ways to explore the same sky.

## What NOVA does

### Website

- **Live sky map** — shows calculated positions of stars, planets, and constellations for a location and time, with updates every 30 seconds in Live mode
- **Constellation tours** — select a constellation from the sidebar to focus on it and take a guided tour of its visible stars
- **Spoken descriptions** — hear information about stars and planets instead of relying only on the map
- **Ask NOVA** — ask astronomy questions by typing or speaking, then get a written or spoken answer
- **Accessible controls** — keyboard navigation, labels for screen readers, and instructions on the How to Listen page
- **Three audio modes** — Full audio (music, effects, and narration), Voice only (narration), and Audio off

### iPhone app

- **Find an object** — choose a star or planet and follow spoken and haptic directions to point toward it
- **Identify the sky** — aim your phone and find out which astronomical object you may be pointing at
- **Explore tonight** — hear about objects above the horizon based on your location
- **Sky camera** — a camera-based view with sky labels for sighted helpers
- **Discoveries and missions** — save what you've found, complete optional goals, and earn achievements
- **Customizable accessibility settings** — adjust narration, vibrations, guidance sounds, and other preferences

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
| HYG star catalog, Stellarium constellation data, JPL ephemeris | On-device astronomy calculations, Yale Bright Star Catalogue |
| OpenRouter, ElevenLabs | OpenRouter, ElevenLabs, Google Firebass |

## Things to know

- Sky positions are calculated from astronomical data; the map does not account for clouds, buildings, or light pollution
- Compass and phone orientation measurements can be affected by magnetic interference
- AI-generated explanations should not be treated as guaranteed scientific facts
  
## Data and services

Thanks to the projects and services that make NOVA possible:

- [Skyfield](https://rhodesmill.org/skyfield/) for astronomical position calculations
- [Yale Bright Star Data](http://tdc-www.harvard.edu/catalogs/bsc5.html) for star catalog data on mobile
- [HYG Database](https://github.com/astronexus/HYG-Database) for star catalog data
- [Stellarium Sky Cultures](https://github.com/Stellarium/stellarium-skycultures) for constellation connections
- [NASA/JPL ephemerides](https://ssd.jpl.nasa.gov/planets/eph_export.html) for solar system positions
- [ElevenLabs](https://elevenlabs.io/) for voice features
- [OpenRouter](https://openrouter.ai/) for Ask NOVA

## Team

Built by **Raunav and Vihaan** for HackPHS 2026.

**The universe is for everyone**
