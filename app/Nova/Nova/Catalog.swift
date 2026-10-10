//
//  Catalog.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Foundation

enum ObjectKind: String, Codable, CaseIterable {
    case star, planet, moon, deepSky, constellation
    var label: String {
        switch self {
        case .star: return "star"
        case .planet: return "planet"
        case .moon: return "moon"
        case .deepSky: return "deep-sky object"
        case .constellation: return "constellation"
        }
    }
}

enum EphemerisSource: Hashable {
    case fixedJ2000(ra: Double, dec: Double)   // degrees
    case planet(PlanetID)
    case moon
}

struct CelestialObject: Identifiable, Hashable {
    let id: String
    let name: String
    let spokenName: String        // respelling used for text-to-speech
    let kind: ObjectKind
    let source: EphemerisSource?  // nil = educational only; cannot be located with phone sensors
    let magnitude: Double?
    let distance: String
    let constellation: String
    let short: String
    let deeper: String
    let story: String?            // mythology / culture, with origin named
    let didYouKnow: String

    var isLocatable: Bool { source != nil }
}

enum Catalog {
    static func star(_ id: String, _ name: String, _ spoken: String, ra: Double, dec: Double, mag: Double,
                     dist: String, con: String, short: String, deeper: String, story: String?, fact: String) -> CelestialObject {
        CelestialObject(id: id, name: name, spokenName: spoken, kind: .star, source: .fixedJ2000(ra: ra, dec: dec),
                        magnitude: mag, distance: dist, constellation: con, short: short, deeper: deeper,
                        story: story, didYouKnow: fact)
    }

    // RA/Dec: J2000, degrees. Magnitudes: approximate visual.
    static let all: [CelestialObject] = [
        CelestialObject(id: "moon", name: "the Moon", spokenName: "the Moon", kind: .moon, source: .moon, magnitude: -12.7,
                        distance: "about 384,000 kilometers, varying by roughly 5 percent through its orbit", constellation: "varies night to night",
                        short: "Earth's only natural satellite, and the brightest thing in the night sky.",
                        deeper: "The Moon shines by reflected sunlight, and its phase depends on how much of its sunlit half faces us. It is about a quarter of Earth's diameter. Its gravity drives our ocean tides, and it always shows us the same face.",
                        story: "Many cultures track time by the Moon. Lunar calendars, such as the Islamic and traditional Chinese calendars, begin months with the new Moon.",
                        didYouKnow: "The Moon drifts away from Earth by about 3.8 centimeters every year."),
        CelestialObject(id: "jupiter", name: "Jupiter", spokenName: "Jupiter", kind: .planet, source: .planet(.jupiter), magnitude: -2.0,
                        distance: "between about 590 and 970 million kilometers from Earth, depending on where both planets are in their orbits", constellation: "varies over the years",
                        short: "The largest planet, a giant ball of hydrogen and helium that outshines every star.",
                        deeper: "Jupiter has more than twice the mass of all other planets combined. Its Great Red Spot is a storm wider than Earth that has lasted for centuries. Even a small telescope shows its four biggest moons.",
                        story: "The Romans named it for Jupiter, king of their gods. Babylonian astronomers tracked its motion as early as the first millennium BCE.",
                        didYouKnow: "A day on Jupiter lasts just under ten hours."),
        CelestialObject(id: "saturn", name: "Saturn", spokenName: "Saturn", kind: .planet, source: .planet(.saturn), magnitude: 0.8,
                        distance: "between about 1.2 and 1.7 billion kilometers from Earth", constellation: "varies over the years",
                        short: "The ringed planet, shining with a steady golden light.",
                        deeper: "Saturn's rings are mostly water ice, from dust grains to house-sized chunks, spread over a span wider than the distance from Earth to the Moon yet extremely thin. Saturn is less dense than water.",
                        story: "Named by the Romans for Saturn, god of agriculture, whose festival Saturnalia was celebrated in December.",
                        didYouKnow: "Saturn's rings look different from Earth over the years because we see them from changing angles."),
        star("sirius", "Sirius", "SEER-ee-us", ra: 101.287, dec: -16.716, mag: -1.46, dist: "about 8.6 light-years", con: "Canis Major",
             short: "The brightest star in the night sky.",
             deeper: "Sirius is really two stars: a bright white main star and a faint, dense white dwarf companion. It looks so bright mostly because it is one of our nearest neighbors.",
             story: "Its name comes from the Greek for scorching. Ancient Egyptians watched its first dawn appearance each year to anticipate the Nile flood.",
             fact: "Sirius is sometimes called the Dog Star because it sits in the Greater Dog."),
        star("arcturus", "Arcturus", "ark-TOO-rus", ra: 213.915, dec: 19.182, mag: -0.05, dist: "about 37 light-years", con: "Boötes",
             short: "A bright orange giant, the brightest star of the northern sky in spring.",
             deeper: "Arcturus is an aging red-orange giant about 25 times wider than the Sun. It is moving fast relative to the Sun and comes from the older stars of our galaxy's halo.",
             story: "Its name comes from ancient Greek and means guardian of the bear.",
             fact: "You can find it by following the curve of the Big Dipper's handle."),
        star("vega", "Vega", "VAY-guh", ra: 279.235, dec: 38.784, mag: 0.03, dist: "about 25 light-years", con: "Lyra",
             short: "One of the brightest stars in the night sky, blue-white and burning brightly in summer.",
             deeper: "Vega is about twice the mass of the Sun and spins so fast that it bulges at its equator. A disk of dust orbits it. Vega was the north star about 12,000 years ago and will be again in about 13,000.",
             story: "The name comes from Arabic, and relates to a swooping eagle or vulture. In East Asian tradition Vega is the weaver girl, who meets the cowherd Altair across the Milky Way once a year.",
             fact: "Vega was the first star other than the Sun to be photographed."),
        star("capella", "Capella", "kuh-PELL-uh", ra: 79.172, dec: 45.998, mag: 0.08, dist: "about 43 light-years", con: "Auriga",
             short: "A bright yellow star, actually two pairs of stars.",
             deeper: "Capella is made of four stars in two pairs. The brightest pair are two yellow giants orbiting each other every 104 days.",
             story: "The name is Latin for little she-goat. In Greek tradition the goat Amalthea nursed the infant Zeus.",
             fact: "It is one of the northernmost bright stars, so it stays visible for much of the year from northern latitudes."),
        star("rigel", "Rigel", "RYE-jel", ra: 78.634, dec: -8.202, mag: 0.13, dist: "roughly 860 light-years", con: "Orion",
             short: "A brilliant blue-white supergiant marking Orion's foot.",
             deeper: "Rigel is tens of thousands of times more luminous than the Sun. It is massive and young, and will end its life in a supernova.",
             story: "The name comes from the Arabic for foot. Orion is the hunter of Greek mythology.",
             fact: "Rigel is far more distant than most bright stars, yet still among the brightest."),
        star("procyon", "Procyon", "PRO-see-on", ra: 114.825, dec: 5.225, mag: 0.34, dist: "about 11.5 light-years", con: "Canis Minor",
             short: "A bright white star, one of our closest neighbors.",
             deeper: "Procyon is slightly larger and hotter than the Sun, with a faint white dwarf companion.",
             story: "Its name comes from Greek and means before the dog, because it rises before Sirius.",
             fact: "Along with Sirius and Betelgeuse it forms the Winter Triangle."),
        star("betelgeuse", "Betelgeuse", "BEET-el-jooz", ra: 88.793, dec: 7.407, mag: 0.5, dist: "roughly 550 to 700 light-years", con: "Orion",
             short: "A giant red supergiant at Orion's shoulder, with a reddish glow.",
             deeper: "Betelgeuse is so large that it would reach beyond the orbit of Mars if placed where the Sun is. Its brightness varies, and in 2019 and 2020 it dimmed dramatically after ejecting a cloud of dust. It will eventually explode as a supernova, but probably not for a very long time.",
             story: "The name comes from Arabic, and its exact meaning is debated.",
             fact: "It is a variable star, so its brightness changes from season to season."),
        star("altair", "Altair", "al-TAIR", ra: 297.696, dec: 8.868, mag: 0.76, dist: "about 17 light-years", con: "Aquila",
             short: "A white star that spins incredibly fast, one corner of the Summer Triangle.",
             deeper: "Altair rotates once in about nine hours, much faster than the Sun, so it is flattened into an oval.",
             story: "The name comes from Arabic for the flying eagle. In East Asian legend Altair is the cowherd, separated from the weaver Vega by the Milky Way.",
             fact: "Vega, Deneb and Altair form the Summer Triangle."),
        star("aldebaran", "Aldebaran", "al-DEB-uh-ran", ra: 68.980, dec: 16.509, mag: 0.86, dist: "about 65 light-years", con: "Taurus",
             short: "An orange giant, the glowing eye of Taurus the bull.",
             deeper: "Aldebaran appears near the Hyades star cluster but is not part of it; it is much closer to us than the cluster.",
             story: "The name comes from Arabic and means the follower, as it follows the Pleiades across the sky.",
             fact: "It is one of the easiest bright stars to find by extending Orion's belt to the upper right."),
        star("spica", "Spica", "SPY-kuh", ra: 201.298, dec: -11.161, mag: 0.97, dist: "about 250 light-years", con: "Virgo",
             short: "A hot blue-white star, the brightest in Virgo.",
             deeper: "Spica is actually two stars orbiting each other closely, so close that they are stretched into egg shapes by gravity.",
             story: "Its name is Latin for ear of grain. In Greek and Roman tradition Virgo is linked with the harvest.",
             fact: "You can find it by following the curve of the Big Dipper's handle, through Arcturus, and onward."),
        star("pollux", "Pollux", "POL-luks", ra: 116.329, dec: 28.026, mag: 1.14, dist: "about 34 light-years", con: "Gemini",
             short: "An orange giant, one of the Twins of Gemini.",
             deeper: "Pollux has a confirmed planet, a giant world more than twice the mass of Jupiter.",
             story: "In Greek myth Castor and Pollux are twin brothers. Pollux was immortal and shared his immortality with his mortal brother.",
             fact: "Pollux is the nearest giant star to the Sun."),
        star("deneb", "Deneb", "DEN-eb", ra: 310.358, dec: 45.280, mag: 1.25, dist: "roughly 2,600 light-years", con: "Cygnus",
             short: "A distant, enormously luminous star at the tail of the Swan.",
             deeper: "Deneb is among the most luminous stars visible to the naked eye, shining with the light of well over fifty thousand Suns.",
             story: "Its name comes from Arabic for tail.",
             fact: "Because it is so far away, light we see from Deneb left it many centuries ago."),
        star("regulus", "Regulus", "REG-yoo-lus", ra: 152.093, dec: 11.967, mag: 1.35, dist: "about 79 light-years", con: "Leo",
             short: "A blue-white star at the heart of Leo the lion.",
             deeper: "Regulus spins so fast it is flattened, and it has a hidden companion star too faint to see with the naked eye.",
             story: "The name is Latin for little king.",
             fact: "It lies almost exactly on the ecliptic, so the Moon and planets pass close to it."),
        star("polaris", "Polaris", "poh-LAIR-iss", ra: 37.955, dec: 89.264, mag: 1.98, dist: "about 430 light-years", con: "Ursa Minor",
             short: "The North Star. It stays nearly fixed in the sky, marking true north.",
             deeper: "Polaris sits less than one degree from the north celestial pole, so it barely moves while other stars wheel around it. Its altitude above your horizon is roughly your latitude, which makes it useful for finding north.",
             story: "Many navigators and cultures have used the pole star for direction. It is not especially bright; it ranks around the fiftieth brightest star.",
             fact: "In about 12,000 years the north star will be Vega."),
        star("dubhe", "Dubhe", "DOO-bee", ra: 165.932, dec: 61.751, mag: 1.79, dist: "about 123 light-years", con: "Ursa Major",
             short: "A star in the bowl of the Big Dipper, one of the two pointer stars.",
             deeper: "A line through Dubhe and Merak, the bottom of the Dipper's bowl, points to Polaris.",
             story: "The name comes from Arabic for bear. Many Indigenous North American peoples and ancient Greeks also saw a bear in this region.",
             fact: "Dubhe is a binary star system."),
        star("fomalhaut", "Fomalhaut", "FOH-mul-hawt", ra: 344.413, dec: -29.622, mag: 1.16, dist: "about 25 light-years", con: "Piscis Austrinus",
             short: "A lonely white star low in the southern sky, visible in autumn.",
             deeper: "Fomalhaut is surrounded by a vast ring of dust and debris, and astronomers have imaged a planet candidate near it.",
             story: "The name comes from Arabic and means mouth of the fish.",
             fact: "Few other bright stars are nearby, so it is nicknamed the Loneliest Star."),

        // Educational only: not locatable with this app.
        CelestialObject(id: "andromeda", name: "Andromeda Galaxy", spokenName: "an-DROM-ih-duh Galaxy", kind: .deepSky, source: nil, magnitude: 3.4,
                        distance: "about 2.5 million light-years", constellation: "Andromeda",
                        short: "The nearest large galaxy to ours, containing about a trillion stars.",
                        deeper: "Andromeda is the farthest thing most people can see with the naked eye, under dark skies. It is approaching the Milky Way and will merge with it in about four to five billion years.",
                        story: "The constellation honors Andromeda, a princess in Greek myth. The galaxy was recorded by the Persian astronomer Al-Sufi around 964 CE.",
                        didYouKnow: "The light you would see left Andromeda before humans existed."),
        CelestialObject(id: "orion_nebula", name: "Orion Nebula", spokenName: "Orion Nebula", kind: .deepSky, source: nil, magnitude: 4.0,
                        distance: "about 1,350 light-years", constellation: "Orion",
                        short: "A glowing cloud of gas where new stars are being born.",
                        deeper: "The Orion Nebula is a stellar nursery, hundreds of young stars lighting up gas and dust. It is visible as a faint fuzzy patch in Orion's sword.",
                        story: nil,
                        didYouKnow: "It is the closest massive star-forming region to Earth."),

        CelestialObject(id: "orion", name: "Orion", spokenName: "Orion", kind: .constellation, source: nil, magnitude: nil,
                        distance: "its stars range from about 250 to over 1,000 light-years away", constellation: "Orion",
                        short: "The hunter, recognizable by three stars in a row forming his belt.",
                        deeper: "Orion contains bright Betelgeuse at one shoulder and Rigel at one foot. The stars are not near each other in space; they only line up from our viewpoint. Orion is visible from nearly everywhere on Earth in winter evenings.",
                        story: "In Greek myth Orion was a giant hunter. Many other cultures saw different figures in these same stars.",
                        didYouKnow: "Orion's belt points toward Sirius to the lower left and Aldebaran to the upper right."),
        CelestialObject(id: "lyra", name: "Lyra", spokenName: "LYE-ruh", kind: .constellation, source: nil, magnitude: nil,
                        distance: "Vega, its brightest star, is about 25 light-years away", constellation: "Lyra",
                        short: "A small constellation shaped like a little parallelogram with brilliant Vega at one corner.",
                        deeper: "Lyra is home to the Ring Nebula, a shell of gas thrown off by a dying star, visible through a small telescope.",
                        story: "In Greek myth the lyre belonged to Orpheus, a musician whose songs moved even the gods.",
                        didYouKnow: "Lyra is one of the smallest constellations but one of the easiest to recognize in summer."),
        CelestialObject(id: "ursa_major", name: "Ursa Major", spokenName: "ER-suh MAY-jer", kind: .constellation, source: nil, magnitude: nil,
                        distance: "most of the Big Dipper stars are 80 to 125 light-years away", constellation: "Ursa Major",
                        short: "The Great Bear, which contains the famous Big Dipper.",
                        deeper: "The Big Dipper is part of the bear, not the whole thing. It is circumpolar from northern mid-latitudes, so you can see it all year.",
                        story: "Many cultures saw a bear here, including the ancient Greeks and numerous Indigenous peoples of North America.",
                        didYouKnow: "The two end stars of the bowl point toward Polaris."),
        CelestialObject(id: "cassiopeia", name: "Cassiopeia", spokenName: "kass-ee-oh-PEE-uh", kind: .constellation, source: nil, magnitude: nil,
                        distance: "its brightest stars are 55 to 230 light-years away", constellation: "Cassiopeia",
                        short: "A zigzag W or M shape of five bright stars, opposite the Big Dipper around Polaris.",
                        deeper: "Cassiopeia is circumpolar for northern observers. Dark-sky observers can see the Milky Way running through it.",
                        story: "In Greek myth Cassiopeia was a boastful queen, doomed to circle the pole of the sky.",
                        didYouKnow: "When the Big Dipper is low, Cassiopeia is high, and vice versa.")
    ]

    static var locatable: [CelestialObject] { all.filter { $0.isLocatable } }
    static func object(id: String) -> CelestialObject? { all.first { $0.id == id } }
}
