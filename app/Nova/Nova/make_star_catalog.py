#
# this is the code to get the database for all the stars!! :D

#!/usr/bin/env python3
"""Build Resources/stars.json for Nova from the HYG star database.

Usage:
    python3 scripts/make_star_catalog.py path/to/hyg.csv Resources/stars.json [--max-mag 4.0] [--limit 400]

Get the HYG database (free, from Hipparcos/Yale/Gliese data) from https://www.astronexus.com/projects/hyg
(also on GitHub as astronexus/HYG-Database). Any HYG version works: columns are read by name.

Keeps every star that has a proper name (Sirius, Vega, ...) and is brighter than --max-mag, plus any star brighter than
2.5 even without a name. Output is a compact list of fixed J2000 positions; Nova works out where they are in YOUR sky.

LICENSE: HYG is CC BY-SA. If you ship stars.json in the app, credit "HYG database (astronexus.com)" and check the license
terms for your release.
"""
import csv, json, sys

CON = {
 "And":"Andromeda","Ant":"Antlia","Aps":"Apus","Aqr":"Aquarius","Aql":"Aquila","Ara":"Ara","Ari":"Aries","Aur":"Auriga",
 "Boo":"Boötes","Cae":"Caelum","Cam":"Camelopardalis","Cnc":"Cancer","CVn":"Canes Venatici","CMa":"Canis Major",
 "CMi":"Canis Minor","Cap":"Capricornus","Car":"Carina","Cas":"Cassiopeia","Cen":"Centaurus","Cep":"Cepheus","Cet":"Cetus",
 "Cha":"Chamaeleon","Cir":"Circinus","Col":"Columba","Com":"Coma Berenices","CrA":"Corona Australis","CrB":"Corona Borealis",
 "Crv":"Corvus","Crt":"Crater","Cru":"Crux","Cyg":"Cygnus","Del":"Delphinus","Dor":"Dorado","Dra":"Draco","Equ":"Equuleus",
 "Eri":"Eridanus","For":"Fornax","Gem":"Gemini","Gru":"Grus","Her":"Hercules","Hor":"Horologium","Hya":"Hydra","Hyi":"Hydrus",
 "Ind":"Indus","Lac":"Lacerta","Leo":"Leo","LMi":"Leo Minor","Lep":"Lepus","Lib":"Libra","Lup":"Lupus","Lyn":"Lynx",
 "Lyr":"Lyra","Men":"Mensa","Mic":"Microscopium","Mon":"Monoceros","Mus":"Musca","Nor":"Norma","Oct":"Octans","Oph":"Ophiuchus",
 "Ori":"Orion","Pav":"Pavo","Peg":"Pegasus","Per":"Perseus","Phe":"Phoenix","Pic":"Pictor","Psc":"Pisces",
 "PsA":"Piscis Austrinus","Pup":"Puppis","Pyx":"Pyxis","Ret":"Reticulum","Sge":"Sagitta","Sgr":"Sagittarius","Sco":"Scorpius",
 "Scl":"Sculptor","Sct":"Scutum","Ser":"Serpens","Sex":"Sextans","Tau":"Taurus","Tel":"Telescopium","Tri":"Triangulum",
 "TrA":"Triangulum Australe","Tuc":"Tucana","UMa":"Ursa Major","UMi":"Ursa Minor","Vel":"Vela","Vir":"Virgo","Vol":"Volans",
 "Vul":"Vulpecula",
}

GREEK = {"Alp":"Alpha","Bet":"Beta","Gam":"Gamma","Del":"Delta","Eps":"Epsilon","Zet":"Zeta","Eta":"Eta","The":"Theta",
         "Iot":"Iota","Kap":"Kappa","Lam":"Lambda","Mu":"Mu","Nu":"Nu","Xi":"Xi","Omi":"Omicron","Pi":"Pi","Rho":"Rho",
         "Sig":"Sigma","Tau":"Tau","Ups":"Upsilon","Phi":"Phi","Chi":"Chi","Psi":"Psi","Ome":"Omega"}

def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    opts = {a.split("=")[0]: a.split("=")[1] for a in argv[1:] if a.startswith("--") and "=" in a}
    flags = argv[1:]
    def opt(name, default):
        if name in flags:
            return flags[flags.index(name) + 1]
        return opts.get(name, default)
    if len(args) < 2:
        print(__doc__); return 1
    src, dst = args[0], args[1]
    max_mag = float(opt("--max-mag", 4.0)); limit = int(opt("--limit", 400))
    stars = []
    with open(src, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            try:
                mag = float(r["mag"]); ra_h = float(r["ra"]); dec = float(r["dec"])
            except (KeyError, ValueError):
                continue
            name = (r.get("proper") or "").strip()
            if name.lower() in ("sol", "sun"): continue
            if not (name and mag <= max_mag) and not (mag <= 2.5): continue
            try:
                dist_pc = float(r.get("dist") or 0)
            except ValueError:
                dist_pc = 0
            ly = round(dist_pc * 3.26156) if 0 < dist_pc < 99999 else None
            if ly is None: continue                       # unknown distance: skip rather than invent one
            if not name:                                  # unnamed bright star: use its Bayer/Flamsteed label
                bayer = (r.get("bayer") or "").strip()
                greek = GREEK.get(bayer.rstrip("0123456789"), "")
                con_name = CON.get((r.get("con") or "").strip(), "")
                if not (greek and con_name): continue
                name = greek + " of " + con_name
            ident = ("hip-" + r["hip"].strip()) if (r.get("hip") or "").strip() else ("hyg-" + r["id"].strip())
            stars.append({"id": ident, "name": name, "ra": round(ra_h * 15, 4), "dec": round(dec, 4), "mag": round(mag, 2),
                          "ly": ly, "con": CON.get((r.get("con") or "").strip(), (r.get("con") or "").strip()),
                          "spect": (r.get("spect") or "").strip()})
    stars.sort(key=lambda s: s["mag"])
    stars = stars[:limit]
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(stars, f, ensure_ascii=False, separators=(",", ":"))
    print("Wrote %d stars to %s (brightest: %s, faintest: %s)" % (len(stars), dst, stars[0]["name"], stars[-1]["name"]))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
