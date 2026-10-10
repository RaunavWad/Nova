
// nova javascript

// star info and coordinates
// ra and dec are in degrees

const stars = [
  {id:"sirius",name:"Sirius",ra:101.287,dec:-16.716,mag:-1.46,con:"Canis Major",dist:"8.6 light years",fact:"The brightest star in the night sky"},

  {id:"vega",name:"Vega",ra:279.235,dec:38.784,mag:0.03,con:"Lyra",dist:"25 light years",fact:"One of the brightest stars and part of the Summer Triangle"},

  {id:"betelgeuse",name:"Betelgeuse",ra:88.793,dec:7.407,mag:0.45,con:"Orion",dist:"Hundreds of light years",fact:"A massive red supergiant marking one of Orion's shoulders"},

  {id:"rigel",name:"Rigel",ra:78.635,dec:-8.202,mag:0.13,con:"Orion",dist:"Around 860 light years",fact:"A bright blue supergiant marking one of Orion's feet"},

  {id:"polaris",name:"Polaris",ra:37.955,dec:89.264,mag:1.98,con:"Ursa Minor",dist:"Around 430 light years",fact:"Known as the North Star because it appears close to the north celestial pole"},

  {id:"altair",name:"Altair",ra:297.696,dec:8.868,mag:0.77,con:"Aquila",dist:"16.7 light years",fact:"A rapidly rotating star in the Summer Triangle"},

  {id:"deneb",name:"Deneb",ra:310.358,dec:45.280,mag:1.25,con:"Cygnus",dist:"Roughly 2600 light years",fact:"A luminous supergiant in the constellation Cygnus"},

  {id:"bellatrix",name:"Bellatrix",ra:81.283,dec:6.35,mag:1.64,con:"Orion",dist:"Around 250 light years",fact:"A bright star marking Orion's other shoulder"},

  {id:"alnitak",name:"Alnitak",ra:85.190,dec:-1.943,mag:1.77,con:"Orion",dist:"Over 1000 light years",fact:"One of the three stars forming Orion's Belt"},

  {id:"alnilam",name:"Alnilam",ra:84.053,dec:-1.202,mag:1.69,con:"Orion",dist:"Around 2000 light years",fact:"The middle star of Orion's Belt"},

  {id:"mintaka",name:"Mintaka",ra:83.002,dec:-0.299,mag:2.23,con:"Orion",dist:"Around 1200 light years",fact:"One of the three stars forming Orion's Belt"},

  {id:"sheliak",name:"Sheliak",ra:282.520,dec:33.363,mag:3.5,con:"Lyra",dist:"Around 960 light years",fact:"A famous eclipsing binary star system"},

  {id:"sulafat",name:"Sulafat",ra:284.736,dec:32.690,mag:3.25,con:"Lyra",dist:"Around 620 light years",fact:"A blue white star in the constellation Lyra"},

  {id:"dubhe",name:"Dubhe",ra:165.932,dec:61.751,mag:1.81,con:"Ursa Major",dist:"Around 120 light years",fact:"One of the two Big Dipper pointer stars"},

  {id:"merak",name:"Merak",ra:165.460,dec:56.382,mag:2.34,con:"Ursa Major",dist:"Around 80 light years",fact:"Together with Dubhe it points toward Polaris"},

  {id:"alioth",name:"Alioth",ra:193.507,dec:55.96,mag:1.76,con:"Ursa Major",dist:"Around 80 light years",fact:"The brightest star in Ursa Major"},

  {id:"mizar",name:"Mizar",ra:200.981,dec:54.925,mag:2.23,con:"Ursa Major",dist:"Around 83 light years",fact:"Forms a famous star pair with Alcor"},

  {id:"alkaid",name:"Alkaid",ra:206.885,dec:49.313,mag:1.86,con:"Ursa Major",dist:"Around 100 light years",fact:"Marks the end of the Big Dipper handle"}
];


// locations
const places = {
  robbinsville: {lat:40.2146,lon:-74.6193},
  princeton: {lat:40.3573,lon:-74.6672},
  nyc: {lat:40.7128,lon:-74.0060}
};


// tours
const tours = {
  orion: {
    name:"Orion",
    intro:"Explore Orion the Hunter and discover the stars that form this famous constellation",
    ids:["betelgeuse","bellatrix","alnitak","alnilam","mintaka","rigel"]
  },

  lyra: {
    name:"Lyra",
    intro:"Explore Lyra and discover Vega along with its surrounding stars",
    ids:["vega","sheliak","sulafat"]
  },

  ursa: {
    name:"Ursa Major",
    intro:"Follow the Big Dipper through the stars of Ursa Major",
    ids:["dubhe","merak","alioth","mizar","alkaid"]
  }
};


// stuff we're keeping track of
let locationNow = {...places.robbinsville};
let allPositions = [];
let selectedStar = null;
let skyType = "sky";

let audioEnabled = false;
let currentVoice = null;

let activeTour = null;
let tourIndex = 0;


// html stuff
const list = document.getElementById("starList");
const place = document.getElementById("place");
const dateInput = document.getElementById("skyDate");

const audioButton = document.getElementById("audioToggle");

const skyBtn = document.getElementById("yourSkyBtn");
const allBtn = document.getElementById("allStarsBtn");

const search = document.getElementById("starSearch");

const nameBox = document.getElementById("starName");
const metaBox = document.getElementById("starMeta");
const factBox = document.getElementById("starFacts");
const directionBox = document.getElementById("starDirection");

const statusBox = document.getElementById("skyStatus");


// small math functions
function rad(n) {
  return n * Math.PI / 180;
}

function deg(n) {
  return n * 180 / Math.PI;
}

function wrap(n) {
  return ((n % 360) + 360) % 360;
}


// set date input to now
function setNow() {
  let d = new Date();

  let pad = n => String(n).padStart(2,"0");

  dateInput.value =
    d.getFullYear() + "-" +
    pad(d.getMonth()+1) + "-" +
    pad(d.getDate()) + "T" +
    pad(d.getHours()) + ":" +
    pad(d.getMinutes());

  updateSky();
}


// where the star is in the sky
// simple approximate astronomy calculation
function getStarPosition(star,date) {

  let jd = date.getTime() / 86400000 + 2440587.5;

  let sidereal = wrap(
    280.46061837 +
    360.98564736629 * (jd - 2451545) +
    locationNow.lon
  );

  let angle = rad(wrap(sidereal - star.ra + 180) - 180);
  let latitude = rad(locationNow.lat);
  let declination = rad(star.dec);

  let sinAlt =
    Math.sin(latitude) * Math.sin(declination) +
    Math.cos(latitude) * Math.cos(declination) * Math.cos(angle);

  let altitude = deg(
    Math.asin(Math.max(-1,Math.min(1,sinAlt)))
  );

  let east = -Math.cos(declination) * Math.sin(angle);

  let north =
    Math.sin(declination) * Math.cos(latitude) -
    Math.cos(declination) * Math.sin(latitude) * Math.cos(angle);

  let azimuth = wrap(deg(Math.atan2(east,north)));

  return {
    ...star,
    altitude:altitude,
    azimuth:azimuth
  };
}


// compass direction in words
function compass(angle) {
  let dirs = [
    "north","northeast","east","southeast",
    "south","southwest","west","northwest"
  ];

  return dirs[Math.round(angle/45)%8];
}


// get stars for current filter
function getStars() {

  let available = skyType === "sky"
    ? allPositions.filter(s => s.altitude > 0)
    : [...allPositions];

  let query = search.value.toLowerCase().trim();

  if(query) {
    available = available.filter(s =>
      s.name.toLowerCase().includes(query) ||
      s.con.toLowerCase().includes(query)
    );
  }

  // brightest stars first
  available.sort((a,b) => a.mag - b.mag);

  return available;
}


// update everything when location or time changes
function updateSky() {

  let time = new Date(dateInput.value);

  if(isNaN(time.getTime())) {
    statusBox.textContent = "Choose a valid date and time";
    return;
  }

  allPositions = stars.map(star => getStarPosition(star,time));

  let above = allPositions.filter(s => s.altitude > 0);

  document.getElementById("skyCount").textContent =
    above.length + " catalog stars above the horizon";

  statusBox.textContent =
    "Sky updated for your selected location and time";

  renderStars();
}


// put stars on the page
function renderStars() {

  let available = getStars();

  list.innerHTML = "";

  if(available.length === 0) {
    list.textContent = "No stars found in this collection";
    selectedStar = null;
    showStar();
    drawMap();
    return;
  }

  if(!available.some(s => s.id === selectedStar)) {
    selectedStar = available[0].id;
  }

  available.forEach(star => {

    let btn = document.createElement("button");

    btn.type = "button";
    btn.textContent = "✦ " + star.name;
    btn.dataset.id = star.id;

    btn.setAttribute("aria-label",
      star.name + " in " + star.con);

    btn.setAttribute("aria-pressed",
      String(star.id === selectedStar));

    btn.addEventListener("click",function() {
      chooseStar(star.id,true);
    });

    list.appendChild(btn);

  });

  showStar();
  drawMap();
}


// when star is clicked
function chooseStar(id,read) {
  selectedStar = id;

  list.querySelectorAll("button").forEach(btn => {
    btn.setAttribute("aria-pressed",
      String(btn.dataset.id === id));
  });

  showStar();
  drawMap();

  if(read && audioEnabled) {
    speak(starDescription());
  }
}


// update the selected star info
function showStar() {

  let star = allPositions.find(s => s.id === selectedStar);

  if(!star) {
    nameBox.textContent = "Choose a star";
    metaBox.textContent = "Select a star to begin";
    factBox.textContent = "";
    directionBox.textContent = "";
    return;
  }

  nameBox.textContent = star.name;

  metaBox.textContent =
    star.con + "  ·  " + star.dist;

  factBox.textContent = star.fact;

  if(star.altitude > 0) {
    directionBox.textContent =
      "Toward " + compass(star.azimuth) +
      "  ·  " + Math.round(star.altitude) +
      " degrees above the horizon";
  } else {
    directionBox.textContent =
      "Currently below the horizon at your selected location";
  }
}


// text to read out loud
function starDescription() {

  let star = allPositions.find(s => s.id === selectedStar);

  if(!star) return "Choose a star to begin exploring";

  let position;

  if(star.altitude > 0) {
    position =
      "Look toward the " + compass(star.azimuth) +
      " about " + Math.round(star.altitude) +
      " degrees above the horizon";
  } else {
    position = "This star is currently below your horizon";
  }

  return star.name + " in " + star.con +
    "  " + position +
    "  " + star.fact +
    "  It is " + star.dist + " away";
}


// browser narration for now
// later we'll add elevenlabs here

function speak(text) {

  if(!("speechSynthesis" in window)) {
    statusBox.textContent = "Audio is unavailable in this browser";
    return;
  }

  stopSpeech();

  let voice = new SpeechSynthesisUtterance(text);

  voice.rate = 0.9;
  voice.pitch = 1;
  voice.volume = 1;

  currentVoice = voice;

  speechSynthesis.speak(voice);
}


function stopSpeech() {
  if("speechSynthesis" in window) {
    speechSynthesis.cancel();
  }

  currentVoice = null;
}


// enable audio button
function setAudio(on) {
  audioEnabled = on;

  audioButton.setAttribute("aria-pressed",String(on));

  audioButton.textContent = on
    ? "◖ Audio enabled"
    : "◖ Enable audio";

  if(!on) stopSpeech();
}

audioButton.addEventListener("click",function() {

  setAudio(!audioEnabled);

  if(audioEnabled) {
    speak("Welcome to Nova  Your journey through the stars begins here");
  }

});


// hear selected star
document.getElementById("playBtn").addEventListener("click",function() {

  setAudio(true);
  speak(starDescription());

});


// stop audio
document.getElementById("stopBtn").addEventListener("click",stopSpeech);


// your sky / all stars
skyBtn.addEventListener("click",function() {

  skyType = "sky";

  skyBtn.setAttribute("aria-pressed","true");
  allBtn.setAttribute("aria-pressed","false");

  renderStars();
});

allBtn.addEventListener("click",function() {

  skyType = "all";

  skyBtn.setAttribute("aria-pressed","false");
  allBtn.setAttribute("aria-pressed","true");

  renderStars();
});


// search
search.addEventListener("input",renderStars);


// change location
place.addEventListener("change",function() {

  if(places[place.value]) {
    locationNow = {...places[place.value]};
  }

  updateSky();
});


// now button
document.getElementById("nowBtn").addEventListener("click",setNow);


// date changed
dateInput.addEventListener("change",updateSky);


// gps
document.getElementById("locateBtn").addEventListener("click",function() {

  if(!navigator.geolocation) {
    statusBox.textContent = "Location is not available";
    return;
  }

  statusBox.textContent = "Getting your location";

  navigator.geolocation.getCurrentPosition(

    function(pos) {

      locationNow = {
        lat:pos.coords.latitude,
        lon:pos.coords.longitude
      };

      if(!place.querySelector('[value="current"]')) {
        place.add(new Option("Current location","current"));
      }

      place.value = "current";

      updateSky();
    },

    function() {
      statusBox.textContent =
        "Could not access your location  Choose a city instead";
    },

    {enableHighAccuracy:false,timeout:12000}
  );

});


// arrow keys when using the star buttons
list.addEventListener("keydown",function(e) {

  let keys = ["ArrowRight","ArrowLeft","ArrowUp","ArrowDown"];

  if(!keys.includes(e.key)) return;

  let buttons = [...list.querySelectorAll("button")];

  let index = buttons.indexOf(document.activeElement);

  if(index === -1 || buttons.length === 0) return;

  e.preventDefault();

  let forward = e.key === "ArrowRight" || e.key === "ArrowDown";

  let next = forward
    ? (index + 1) % buttons.length
    : (index - 1 + buttons.length) % buttons.length;

  buttons[next].focus();
  buttons[next].click();
});


// constellation tours

function updateTour() {

  if(!activeTour) return;

  let id = activeTour.ids[tourIndex];

  let star = allPositions.find(s => s.id === id);

  if(!star) return;

  document.getElementById("tourProgress").textContent =
    activeTour.name.toUpperCase() +
    "  ·  STAR " + (tourIndex + 1) +
    " OF " + activeTour.ids.length;

  document.getElementById("tourStar").textContent = star.name;

  document.getElementById("tourText").textContent =
    star.fact + "  ·  " + star.dist;

  document.getElementById("prevTour").disabled = tourIndex === 0;

  document.getElementById("nextTour").disabled =
    tourIndex === activeTour.ids.length - 1;

  selectedStar = id;

  showStar();
  drawMap();

  if(audioEnabled) {
    speak(star.name + "  " + star.fact +
      "  It is " + star.dist + " away");
  }
}


// start selected tour
document.querySelectorAll("[data-tour]").forEach(btn => {

  btn.addEventListener("click",function() {

    activeTour = tours[btn.dataset.tour];
    tourIndex = 0;

    document.getElementById("tourPlayer").hidden = false;

    setAudio(true);

    updateTour();

    document.getElementById("tourPlayer").scrollIntoView({
      behavior:"smooth",
      block:"center"
    });

    document.getElementById("prevTour").focus();

  });

});


// next star in tour
document.getElementById("nextTour").addEventListener("click",function() {

  if(activeTour && tourIndex < activeTour.ids.length - 1) {
    tourIndex++;
    updateTour();
  }

});


// previous star
document.getElementById("prevTour").addEventListener("click",function() {

  if(activeTour && tourIndex > 0) {
    tourIndex--;
    updateTour();
  }

});


// repeat tour audio
document.getElementById("repeatTour").addEventListener("click",function() {

  if(!activeTour) return;

  let star = allPositions.find(s =>
    s.id === activeTour.ids[tourIndex]);

  if(star) {
    setAudio(true);
    speak(star.name + "  " + star.fact +
      "  It is " + star.dist + " away");
  }

});


// finish tour
document.getElementById("endTour").addEventListener("click",function() {

  stopSpeech();

  activeTour = null;
  document.getElementById("tourPlayer").hidden = true;

  document.querySelector('[data-tour]')?.focus();

});


// optional visual sky map

const canvas = document.getElementById("skyCanvas");
const ctx = canvas.getContext("2d");

function drawMap() {

  let w = canvas.width;
  let h = canvas.height;

  let cx = w / 2;
  let cy = h / 2;

  let radius = 185;

  ctx.clearRect(0,0,w,h);

  ctx.fillStyle = "#0B1423";
  ctx.fillRect(0,0,w,h);

  // sky circles
  ctx.strokeStyle = "#30425C";
  ctx.lineWidth = 1;

  [radius,radius*.66,radius*.33].forEach(r => {
    ctx.beginPath();
    ctx.arc(cx,cy,r,0,Math.PI*2);
    ctx.stroke();
  });


  // compass lines
  ctx.beginPath();

  ctx.moveTo(cx-radius,cy);
  ctx.lineTo(cx+radius,cy);

  ctx.moveTo(cx,cy-radius);
  ctx.lineTo(cx,cy+radius);

  ctx.stroke();


  ctx.fillStyle = "#A8B6CA";
  ctx.font = "15px Instrument Sans";
  ctx.textAlign = "center";

  ctx.fillText("N",cx,cy-radius-15);
  ctx.fillText("S",cx,cy+radius+25);
  ctx.fillText("E",cx+radius+20,cy+5);
  ctx.fillText("W",cx-radius-20,cy+5);


  // put the stars on the map
  allPositions.filter(s => s.altitude > 0).forEach(star => {

    let r = (90 - star.altitude) / 90 * radius;
    let a = rad(star.azimuth);

    let x = cx + Math.sin(a)*r;
    let y = cy - Math.cos(a)*r;

    let chosen = star.id === selectedStar;

    ctx.beginPath();

    ctx.fillStyle = chosen ? "#B7A4FF" : "#68E1FF";

    let size = Math.max(2,5 - star.mag*.6);

    ctx.arc(x,y,size,0,Math.PI*2);
    ctx.fill();

    if(chosen) {

      ctx.strokeStyle = "#B7A4FF";

      ctx.beginPath();
      ctx.arc(x,y,12,0,Math.PI*2);
      ctx.stroke();

      ctx.fillStyle = "#F4F7FF";
      ctx.fillText(star.name,x,y-20);
    }

  });
}


// visual map show / hide
document.getElementById("mapToggle").addEventListener("click",function() {

  let area = document.getElementById("mapArea");

  area.hidden = !area.hidden;

  let isOpen = !area.hidden;

  this.setAttribute("aria-expanded",String(isOpen));

  this.textContent = isOpen
    ? "Hide visual star map"
    : "Show visual star map";

  if(isOpen) drawMap();
});


// load everything
setNow();