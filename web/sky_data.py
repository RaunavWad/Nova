# nova sky data stuff
# star catalog + planets all get worked out here

import csv, json
from pathlib import Path
from urllib.request import urlretrieve
from functools import lru_cache

import numpy as np
from skyfield.api import Loader, Star, wgs84, load_constellation_names

folder = Path(__file__).parent / 'data'
folder.mkdir(exist_ok=True)
load = Loader(str(folder))

hyg_url = 'https://raw.githubusercontent.com/astronexus/HYG-Database/main/hyg/CURRENT/hygdata_v41.csv'
lines_url = 'https://raw.githubusercontent.com/Stellarium/stellarium/2b10b1a3bb534eb4e7586751054bf67b36c22e53/skycultures/modern_st/index.json'

planets = {
    'Mercury':'mercury', 'Venus':'venus', 'Mars':'mars',
    'Jupiter':'jupiter barycenter', 'Saturn':'saturn barycenter',
    'Uranus':'uranus barycenter', 'Neptune':'neptune barycenter',
    'Moon':'moon'
}


def get_file(name, url):
    path = folder / name
    if not path.exists():
        print('getting', name, '- first run only')
        tmp = path.with_suffix(path.suffix + '.part')
        urlretrieve(url, tmp)
        tmp.replace(path)
    return path


@lru_cache(maxsize=1)
def setup():
    file1 = get_file('hygdata_v41.csv', hyg_url)
    file2 = get_file('constellations.json', lines_url)

    with open(file2,encoding='utf8') as f:
        const = json.load(f)['constellations']

    lines = []
    needed = set()
    for c in const:
        short = c['id'].split()[-1]
        for chain in c['lines']:
            for x,y in zip(chain,chain[1:]):
                needed.add(x); needed.add(y)
                lines.append([f'hip-{x}',f'hip-{y}',short])

    const_names = dict(load_constellation_names())
    objects = []
    with open(file1,encoding='utf8',newline='') as f:
        for row in csv.DictReader(f):
            try:
                mag = float(row['mag'])
                ra = float(row['ra'])     # hyg RA is hours
                dec = float(row['dec'])
            except (TypeError,ValueError,KeyError):
                continue

            hip = row.get('hip','').strip()
            hip_num = int(hip) if hip.isdigit() else None
            if mag > 5.5 and hip_num not in needed: continue

            proper = row.get('proper','').strip()
            fallback = row.get('bf','').strip()
            name = proper or fallback or ('HIP '+hip if hip else 'HYG '+row['id'])
            dist = None
            try:
                pc = float(row['dist'])
                if 0 < pc < 100000: dist = round(pc * 3.26156,1)
            except (TypeError,ValueError): pass

            short = row.get('con','').strip()
            objects.append({
                'id': f'hip-{hip}' if hip else 'hyg-'+row['id'],
                'type':'star','name':name,'mag':round(mag,2),
                'constellation':const_names.get(short,short or 'Unknown'),
                'dist_ly':dist,'spect':row.get('spect','').strip(),'ra':ra,'dec':dec
            })

    lookup = {s['id']:s for s in objects}
    lines = [pair for pair in lines if pair[0] in lookup and pair[1] in lookup]

    star_vectors = Star(
        ra_hours=np.array([s['ra'] for s in objects]),
        dec_degrees=np.array([s['dec'] for s in objects])
    )

    timescale = load.timescale()
    eph = load('de421.bsp') # NASA JPL positions, saved locally
    return objects, lookup, lines, star_vectors, timescale, eph


def fact_for(item):
    if item['type']=='planet':
        planet_info = {
            'Mercury':'Mercury is the closest planet to the Sun, with a rocky cratered surface',
            'Venus':'Venus is a rocky planet with a thick atmosphere and extreme surface temperatures',
            'Mars':'Mars is a rocky planet known for its iron oxide rich surface and polar ice caps',
            'Jupiter':'Jupiter is the largest planet in the solar system and has a giant storm called the Great Red Spot',
            'Saturn':'Saturn is a gas giant surrounded by broad rings made mostly of icy particles',
            'Uranus':'Uranus is an ice giant that rotates on an unusually tilted axis',
            'Neptune':'Neptune is a distant ice giant with powerful winds',
            'Moon':'The Moon is Earth’s natural satellite and its changing phases come from the Sun illuminating different portions of its surface'
        }
        return planet_info[item['name']]
    bits = [f"{item['name']} is a star in {item['constellation']}"]
    bits.append(f"Its apparent magnitude is {item['mag']}")
    if item.get('spect'):
        bits.append(f"Its recorded spectral type is {item['spect']}")
    if item.get('dist_ly') is not None:
        bits.append(f"It is about {item['dist_ly']} light years from Earth")
    return ', '.join(bits)


def object_info(id):
    items, lookup, lines, star_vectors, timescale, eph = setup()
    if id.startswith('planet-'):
        name = id[7:].capitalize()
        if name not in planets: return None
        return {'id':id,'name':name,'type':'planet'}
    return lookup.get(id)


def get_sky(lat, lon, when):
    objects, lookup, lines, star_vectors, ts, eph = setup()
    t = ts.from_datetime(when)
    observer = eph['earth'] + wgs84.latlon(lat,lon)
    here = observer.at(t)

    alt, az, _ = here.observe(star_vectors).apparent().altaz()
    answer = []
    for i,s in enumerate(objects):
        answer.append({
            'id':s['id'],'name':s['name'],'type':'star',
            'mag':s['mag'],'constellation':s['constellation'],
            'dist_ly':s['dist_ly'],
            'alt':round(float(alt.degrees[i]),2),
            'az':round(float(az.degrees[i]),2)
        })

    for name, key in planets.items():
        a, z, d = here.observe(eph[key]).apparent().altaz()
        answer.append({
            'id':'planet-'+name.lower(),'name':name,'type':'planet',
            'mag':None,'constellation':'Solar system','dist_ly':None,
            'alt':round(float(a.degrees),2), 'az':round(float(z.degrees),2),
            'distance_au':round(float(d.au),3)
        })

    sun_alt = here.observe(eph['sun']).apparent().altaz()[0].degrees
    return {
        'objects':answer, 'lines':lines,
        'daylight':bool(sun_alt > -0.833),
        'above':sum(s['alt']>0 for s in answer),
        'count':len(answer)
    }


if __name__ == '__main__':
    setup()
    print('NOVA sky files are ready')
