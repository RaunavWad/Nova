"""Loads the astronomy data and works out what's in the sky."""

import csv
import json
from functools import lru_cache
from pathlib import Path
from urllib.request import urlretrieve

import numpy as np
from skyfield.api import Loader, Star, load_constellation_names, wgs84

DATA_FOLDER = Path(__file__).parent / 'data'
DATA_FOLDER.mkdir(exist_ok=True)
load = Loader(str(DATA_FOLDER))

HYG_URL = 'https://raw.githubusercontent.com/astronexus/HYG-Database/main/hyg/CURRENT/hygdata_v41.csv'
LINES_URL = 'https://raw.githubusercontent.com/Stellarium/stellarium-skycultures/master/western/index.json'

# Skyfield needs these names to find the planets in the JPL data file.
planets = {
    'Mercury': 'mercury',
    'Venus': 'venus',
    'Mars': 'mars',
    'Jupiter': 'jupiter barycenter',
    'Saturn': 'saturn barycenter',
    'Uranus': 'uranus barycenter',
    'Neptune': 'neptune barycenter',
    'Moon': 'moon'
}


def get_file(name, url):
    """Download a data file the first time NOVA needs it."""
    path = DATA_FOLDER / name
    if not path.exists():
        print('Downloading', name, '(first run only)')
        temp_path = path.with_suffix(path.suffix + '.part')
        urlretrieve(url, temp_path)
        temp_path.replace(path)
    return path


@lru_cache(maxsize=1)
def setup():
    """Load stars and constellation lines once so the map can refresh quickly."""
    star_file = get_file('hygdata_v41.csv', HYG_URL)
    line_file = get_file('constellations.json', LINES_URL)

    with open(line_file, encoding='utf8') as file:
        constellations = json.load(file)['constellations']

    lines = []
    needed_stars = set()
    for constellation in constellations:
        short_name = constellation['id'].split()[-1]
        for chain in constellation.get('lines', []):
            # Some Stellarium chains start with a style like "thin" or "bold".
            hip_numbers = [
                int(number) for number in chain
                if isinstance(number, int) or (isinstance(number, str) and number.isdigit())
            ]
            for first, second in zip(hip_numbers, hip_numbers[1:]):
                needed_stars.add(first)
                needed_stars.add(second)
                lines.append([f'hip-{first}', f'hip-{second}', short_name])

    constellation_names = dict(load_constellation_names())
    stars = []
    with open(star_file, encoding='utf8', newline='') as file:
        for row in csv.DictReader(file):
            try:
                magnitude = float(row['mag'])
                ra = float(row['ra'])  # HYG stores right ascension in hours.
                dec = float(row['dec'])
            except (TypeError, ValueError, KeyError):
                continue

            hip = row.get('hip', '').strip()
            hip_number = int(hip) if hip.isdigit() else None
            if magnitude > 5.5 and hip_number not in needed_stars:
                continue

            proper_name = row.get('proper', '').strip()
            fallback_name = row.get('bf', '').strip()
            name = proper_name or fallback_name or ('HIP ' + hip if hip else 'HYG ' + row['id'])

            distance = None
            try:
                parsecs = float(row['dist'])
                if 0 < parsecs < 100000:
                    distance = round(parsecs * 3.26156, 1)
            except (TypeError, ValueError):
                pass

            short_name = row.get('con', '').strip()
            stars.append({
                'id': f'hip-{hip}' if hip else 'hyg-' + row['id'],
                'type': 'star',
                'name': name,
                'mag': round(magnitude, 2),
                'constellation': constellation_names.get(short_name, short_name or 'Unknown'),
                'dist_ly': distance,
                'spect': row.get('spect', '').strip(),
                'ra': ra,
                'dec': dec
            })

    lookup = {star['id']: star for star in stars}
    lines = [edge for edge in lines if edge[0] in lookup and edge[1] in lookup]

    # Skyfield can calculate all the star positions in one batch.
    star_vectors = Star(
        ra_hours=np.array([star['ra'] for star in stars]),
        dec_degrees=np.array([star['dec'] for star in stars])
    )

    timescale = load.timescale()
    ephemeris = load('de421.bsp')  # JPL planet positions, saved locally.
    return stars, lookup, lines, star_vectors, timescale, ephemeris


def fact_for(item):
    """A short description we can use even if the AI service is down."""
    if item['type'] == 'planet':
        planet_info = {
            'Mercury': 'Mercury is the closest planet to the Sun, with a rocky cratered surface',
            'Venus': 'Venus is a rocky planet with a thick atmosphere and extreme surface temperatures',
            'Mars': 'Mars is a rocky planet known for its iron oxide rich surface and polar ice caps',
            'Jupiter': 'Jupiter is the largest planet in the solar system and has a giant storm called the Great Red Spot',
            'Saturn': 'Saturn is a gas giant surrounded by broad rings made mostly of icy particles',
            'Uranus': 'Uranus is an ice giant that rotates on an unusually tilted axis',
            'Neptune': 'Neptune is a distant ice giant with powerful winds',
            'Moon': 'The Moon is Earth’s natural satellite and its changing phases come from the Sun illuminating different portions of its surface'
        }
        return planet_info[item['name']]

    details = [f"{item['name']} is a star in {item['constellation']}"]
    details.append(f"Its apparent magnitude is {item['mag']}")
    if item.get('spect'):
        details.append(f"Its recorded spectral type is {item['spect']}")
    if item.get('dist_ly') is not None:
        details.append(f"It is about {item['dist_ly']} light years from Earth")
    return ', '.join(details)


def object_info(object_id):
    """Find a known star or planet by its map ID."""
    stars, lookup, lines, star_vectors, timescale, ephemeris = setup()
    if object_id.startswith('planet-'):
        name = object_id[7:].capitalize()
        if name not in planets:
            return None
        return {'id': object_id, 'name': name, 'type': 'planet'}
    return lookup.get(object_id)


def get_sky(lat, lon, when):
    """Get the altitude and compass direction of all our stars and planets."""
    stars, lookup, lines, star_vectors, timescale, ephemeris = setup()
    time = timescale.from_datetime(when)
    observer = ephemeris['earth'] + wgs84.latlon(lat, lon)
    here = observer.at(time)

    altitudes, azimuths, _ = here.observe(star_vectors).apparent().altaz()
    objects = []
    for index, star in enumerate(stars):
        objects.append({
            'id': star['id'],
            'name': star['name'],
            'type': 'star',
            'mag': star['mag'],
            'constellation': star['constellation'],
            'dist_ly': star['dist_ly'],
            'alt': round(float(altitudes.degrees[index]), 2),
            'az': round(float(azimuths.degrees[index]), 2)
        })

    for name, key in planets.items():
        altitude, azimuth, distance = here.observe(ephemeris[key]).apparent().altaz()
        objects.append({
            'id': 'planet-' + name.lower(),
            'name': name,
            'type': 'planet',
            'mag': None,
            'constellation': 'Solar system',
            'dist_ly': None,
            'alt': round(float(altitude.degrees), 2),
            'az': round(float(azimuth.degrees), 2),
            'distance_au': round(float(distance.au), 3)
        })

    sun_altitude = here.observe(ephemeris['sun']).apparent().altaz()[0].degrees
    constellation_names = dict(load_constellation_names())

    return {
        'objects': objects,
        'lines': lines,
        'constellations': [
            {'id': code, 'name': constellation_names.get(code, code)}
            for code in sorted({edge[2] for edge in lines})
        ],
        'updated_at': when.isoformat(),
        'daylight': bool(sun_altitude > -0.833),
        'above': sum(obj['alt'] > 0 for obj in objects),
        'count': len(objects)
    }


if __name__ == '__main__':
    setup()
    print('NOVA sky files are ready')
