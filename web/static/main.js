// Live sky map for the Explore page

// Flask calculates the sky, and this file draws it on the canvas
const el = id => document.getElementById(id);
const canvas = el('skyCanvas');
const ctx = canvas.getContext('2d');
const cities = {
  robbinsville: [40.2146, -74.6193],
  princeton: [40.3573, -74.6672],
  nyc: [40.7128, -74.0060]
};
let coords = cities.robbinsville;
let everything = [], lines = [], constellationNames = {};
let focusedCon = null, showConLines = true, showConNames = true;
let chosen = null, mode = 'sky', live = true;
let storyCache = {}, storyTimer, requestNum = 0;
let mapSpots = [];
let voiceAvailable = false, currentAudio = null, audioUrl = null;
let talkingRequest = null, speechRun = 0;
let tour = [], tourStep = 0;

// the same audio controls are used on home, sky, ask and guide now
const novaAudio = window.novaAudio;

function narrationOn() { return novaAudio.canSpeak(); }

function soundClick() { novaAudio.playClick(); }

function dateNow() {
  let d = new Date(), pad = n => String(n).padStart(2, '0');
  el('skyDate').value = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  live = true;
}

function compass(a) {
  return ['north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest'][Math.round(a / 45) % 8];
}

// Ask Flask for fresh coordinates, then update the map and lists

async function loadSky() {
  if (live)
    dateNow();
  let t = new Date(el('skyDate').value);
  if (Number.isNaN(t.getTime())) {
    el('skyStatus').textContent = 'Choose a valid date';
    return;
  }
  if (!everything.length)
    el('skyStatus').textContent = 'Loading the sky';
  let p = new URLSearchParams({ lat: coords[0], lon: coords[1], at: t.toISOString() });
  let num = ++requestNum;
  try {
    let res = await fetch('/api/sky?' + p);
    let data = await res.json();
    if (!res.ok)
      throw Error(data.error || 'Sky request failed');
    if (num !== requestNum)
      return;
    everything = data.objects;
    lines = data.lines;
    constellationNames = Object.fromEntries((data.constellations || []).map(c => [c.id, c.name]));
    el('skyCount').textContent = `${data.above} catalog objects above the horizon`;
    let skyMessage = data.daylight
      ? 'Daylight right now  The map still shows where objects are'
      : 'Night sky positions are ready';
    if (el('skyStatus').textContent !== skyMessage && !el('skyStatus').textContent.startsWith('Selected '))
      el('skyStatus').textContent = skyMessage;

    // In Your Sky mode, clear a star after it drops below the horizon
    // In All Objects mode, still let people explore stars that are below it
    if (chosen && !everything.some(x =>
      x.id === chosen && (mode === 'all' || x.alt > 0))) {
      chosen = null;
      stop();
    }
    updateConstellations();
    showList();
    info();
    drawMap();
    el('skyUpdated').textContent = 'Calculated at ' + new Date().toLocaleTimeString();
    el('skyTimeMode').textContent = live ? 'Live sky updates every 30 seconds' : 'Viewing a selected date and time';
  }
  catch (e) {
    console.log(e);
    el('skyStatus').textContent = e.message + '  Check your Flask terminal';
  }
}

function visible() {
  let q = el('starSearch').value.toLowerCase().trim();
  let found = everything.filter(o => (mode === 'all' || o.alt > 0)
    && (o.name.toLowerCase().includes(q) || o.constellation.toLowerCase().includes(q))
    && (!focusedCon || (o.type === 'star' && o.constellation === constellationNames[focusedCon])));

  // bright objects first, planets up front
  found.sort((a, b) => (a.type === 'planet' ? -3 : a.mag) - (b.type === 'planet' ? -3 : b.mag));
  return found;
}

function showList() {
  let results = visible();
  let box = el('starList');
  let hadFocus = box.contains(document.activeElement) ? document.activeElement?.dataset?.id : null;
  box.innerHTML = '';

  // don't make the user tab through thousands of star buttons
  results.slice(0, 100).forEach(o => {
    let b = document.createElement('button');
    b.type = 'button';
    b.dataset.id = o.id;

    // using our own icons instead of the random symbols
    let pic = document.createElement('img');
    pic.src = o.type === 'planet' ? '/static/images/planet.png' : '/static/images/star.png';
    pic.className = 'sky-object-icon';
    pic.alt = '';
    pic.setAttribute('aria-hidden', 'true');
    let name = document.createElement('span');
    name.textContent = o.name;
    b.append(pic, name);
    b.setAttribute('aria-label', o.name + (o.name === 'Moon' ? ' moon' : o.type === 'planet' ? ' planet' : ' star'));
    b.setAttribute('aria-pressed', String(o.id === chosen));
    b.addEventListener('click', () => select(o.id, true));
    box.appendChild(b);
  });
  el('collectionLabel').textContent = `Showing ${Math.min(100, results.length)} of ${results.length} objects`;
  if (hadFocus)
    [...box.querySelectorAll('button')].find(b => b.dataset.id === hadFocus)?.focus();
}

function summary(o) {
  if (!o)
    return 'Choose a star or planet to begin';
  let place = o.alt > 0
    ? `toward ${compass(o.az)} at ${Math.round(o.alt)} degrees above the horizon`
    : 'currently below your horizon';
  if (o.type === 'planet')
    return `${o.name} is a solar system object, ${place}`;
  let dist = o.dist_ly ? `, about ${o.dist_ly} light years away` : '';
  return `${o.name} in ${o.constellation}, ${place}${dist}`;
}

function info() {
  let o = everything.find(x => x.id === chosen);
  let conName = focusedCon ? (constellationNames[focusedCon] || focusedCon) : null;
  el('starName').textContent = o?.name || conName || 'Choose a star or planet';
  el('starMeta').textContent = o ? (o.type === 'planet' ? 'Planet or moon' : o.constellation) : (conName ? 'Constellation' : '');
  el('starFacts').textContent = o ? (storyCache[chosen] || summary(o)) : (conName ? 'Choose a star in this constellation or start the guided tour from the sidebar' : 'Choose a star or planet to begin');
  el('playBtn').disabled = !o;
  el('starDirection').textContent = o ?
    (o.alt > 0 ? `${compass(o.az)}  ·  ${Math.round(o.alt)} degrees above the horizon` : 'Below the horizon') : '';
  let askLink = el('askAboutStar');
  if (askLink) {
    askLink.href = o ? '/ask?about=' + encodeURIComponent(o.name) : '/ask';
    askLink.textContent = o ? 'Ask NOVA about this ↗' : 'Ask NOVA ↗';
  }
  el('starList').querySelectorAll('button').forEach(b => {
    b.setAttribute('aria-pressed', String(b.dataset.id === chosen));
  });
}

// browser voice backup if elevenlabs isn't ready

function browserVoice(t) {
  if (!('speechSynthesis' in window)) {
    el('skyStatus').textContent = 'This browser cannot play speech';
    return;
  }
  speechSynthesis.cancel();
  let v = new SpeechSynthesisUtterance(t);
  v.rate = .9;
  v.onend = () => novaAudio.duck(false);
  v.onerror = () => novaAudio.duck(false);
  speechSynthesis.speak(v);
}

// get elevenlabs audio from flask

async function say(t, id = null) {
  if (!narrationOn())
    return;
  stop();
  if (novaAudio.getMode() === 'full')
    novaAudio.duck(true);
  let myTurn = speechRun;
  if (!id || !voiceAvailable) {
    browserVoice(t);
    return;
  }
  talkingRequest = new AbortController();
  try {
    el('skyStatus').textContent = 'Getting NOVA voice';
    let r = await fetch('/api/speak', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: id }), signal: talkingRequest.signal
    });
    if (!r.ok)
      throw Error('ElevenLabs request failed');
    let file = await r.blob();
    if (myTurn !== speechRun)
      return;
    audioUrl = URL.createObjectURL(file);
    currentAudio = new Audio(audioUrl);
    let clip = currentAudio, url = audioUrl;
    currentAudio.onended = () => {
      novaAudio.duck(false);
      if (currentAudio === clip)
        currentAudio = null;
      URL.revokeObjectURL(url);
      if (audioUrl === url)
        audioUrl = null;
    };
    await currentAudio.play();
    if (myTurn === speechRun)
      el('skyStatus').textContent = 'Playing NOVA narration';
  }
  catch (e) {
    if (myTurn !== speechRun)
      return;
    console.log('Voice unavailable, using browser speech', e.message);
    el('skyStatus').textContent = 'Using browser speech for this description';
    browserVoice(t);
  }
}

function stop() {
  speechRun++;
  if (talkingRequest) {
    talkingRequest.abort();
    talkingRequest = null;
  }
  if (currentAudio) {
    currentAudio.pause();
    currentAudio = null;
  }
  if (audioUrl) {
    URL.revokeObjectURL(audioUrl);
    audioUrl = null;
  }
  if ('speechSynthesis' in window)
    speechSynthesis.cancel();
  novaAudio.duck(false);
}

// Mouse, keyboard, and tours all use the same selection function

function select(id, tell = false, fromTour = false) {
  if (!fromTour && tour.length)
    finishTour();
  chosen = id;
  clearTimeout(storyTimer);
  info();
  showList();
  drawMap();
  let obj = everything.find(o => o.id === id);
  if (!obj)
    return;
  el('skyStatus').textContent = `Selected ${obj.name}`;
  stop();

  // wait before sending a request so arrow keys don't waste voice credits
  storyTimer = setTimeout(() => getStory(id, tell && narrationOn()), 850);
}

async function getStory(id, readOut = false) {
  let myTurn = speechRun;
  if (storyCache[id]) {
    if (readOut && id === chosen && myTurn === speechRun)
      say(storyCache[id], id);
    return;
  }
  try {
    let r = await fetch('/api/describe', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: id })
    });
    let d = await r.json();
    if (!r.ok)
      throw Error(d.error || 'Could not describe');
    storyCache[id] = d.text;
    if (id === chosen)
      info();
    if (readOut && id === chosen && myTurn === speechRun)
      say(d.text, id);
  }
  catch (e) {
    console.log('description error', e);
  }
}

// drawing a circle sky, north is up, east is right

function spot(o) {
  let radius = 188;
  let r = (90 - o.alt) / 90 * radius, angle = o.az * Math.PI / 180;
  return { x: canvas.width / 2 + Math.sin(angle) * r,
    y: canvas.height / 2 - Math.cos(angle) * r };
}

// the lines stay connected to the same stars, their position moves
// pull the positions from /api/sky again every 30 seconds

function liveGroups() {
  let byId = new Map(everything.map(o => [o.id, o]));
  let groups = new Map();
  for (let edge of lines) {
    let a = byId.get(edge[0]), b = byId.get(edge[1]), code = edge[2];
    if (!a || !b || (a.alt <= 0 && b.alt <= 0))
      continue;
    if (!groups.has(code))
      groups.set(code, { id: code, name: constellationNames[code] || code, edges: 0, stars: new Set() });
    let group = groups.get(code);
    group.edges++;
    if (a.alt > 0)
      group.stars.add(a.id);
    if (b.alt > 0)
      group.stars.add(b.id);
  }
  return [...groups.values()].sort((a, b) => b.edges - a.edges || a.name.localeCompare(b.name));
}

function finishTour() {
  tour = [];
  tourStep = 0;
  el('tourPlayer').hidden = true;
}

function clearSelections() {
  focusedCon = null;
  chosen = null;
  finishTour();
  clearTimeout(storyTimer);
  stop();
  updateConstellations();
  showList();
  info();
  drawMap();
  el('skyStatus').textContent = 'Selection cleared';
}

function chooseConstellation(code) {
  if (focusedCon === code) {
    clearSelections();
    return;
  }
  focusedCon = code;
  chosen = null; // don't keep the star from the previous selection
  finishTour();
  clearTimeout(storyTimer);
  stop();
  updateConstellations();
  showList();
  info();
  drawMap();
  el('skyStatus').textContent = 'Focused on ' + (constellationNames[code] || code);
}

function updateConstellations() {
  let groups = liveGroups();
  let box = el('constellationList');
  let focus = document.activeElement?.dataset?.constellation;
  let oldScroll = box.scrollTop;
  box.innerHTML = '';
  el('constellationCount').textContent = `${groups.length} patterns have stars above the horizon`;
  if (focusedCon && !groups.some(g => g.id === focusedCon)) {
    focusedCon = null;
    chosen = null;
    finishTour();
    clearTimeout(storyTimer);
    stop();
  }
  for (let group of groups) {
    let b = document.createElement('button');
    b.type = 'button';
    b.className = 'constellation-option';
    b.dataset.constellation = group.id;
    b.setAttribute('aria-pressed', String(focusedCon === group.id));
    b.textContent = group.name + '  ·  ' + group.stars.size + ' stars';
    b.addEventListener('click', () => chooseConstellation(group.id));
    box.appendChild(b);
  }
  box.scrollTop = oldScroll;
  if (focus)
    [...box.querySelectorAll('button')].find(b => b.dataset.constellation === focus)?.focus();
  let current = groups.find(g => g.id === focusedCon);
  el('clearCon').hidden = !current;
  el('conFocus').hidden = !current;
  if (current) {
    el('conFocusName').textContent = current.name;
    el('conFocusInfo').textContent = `${current.stars.size} catalog stars above the horizon  Choose a guided tour or click any star in the constellation`;
    el('startConTour').disabled = current.stars.size < 2;
    el('startConTour').textContent = current.stars.size < 2 ? 'Not enough visible stars' : 'Start guided tour ↗';
  }
}

// the map moves when python gives us new star positions

function drawMap() {
  let w = canvas.width, h = canvas.height, cx = w / 2, cy = h / 2, R = 188;
  ctx.fillStyle = '#0B1423';
  ctx.fillRect(0, 0, w, h);
  ctx.strokeStyle = '#30425C';
  ctx.lineWidth = 1;
  for (let r of [R, R * 2 / 3, R / 3]) {
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();
  }
  ctx.beginPath();
  ctx.moveTo(cx - R, cy);
  ctx.lineTo(cx + R, cy);
  ctx.moveTo(cx, cy - R);
  ctx.lineTo(cx, cy + R);
  ctx.stroke();
  let allById = new Map(everything.map(o => [o.id, o]));
  let pos = new Map();
  mapSpots = [];
  for (let o of everything) {
    if (o.alt <= 0)
      continue;

    // selecting a constellation hides everything outside it, even planets
    if (focusedCon && (o.type !== 'star' || o.constellation !== constellationNames[focusedCon]))
      continue;
    let p = spot(o);
    pos.set(o.id, p);
    mapSpots.push({ ...p, id: o.id });
  }

  // crop the lines at the edge of the sky circle
  // even if one star is below the horizon
  if (showConLines) {
    ctx.save();
    ctx.beginPath();
    ctx.arc(cx, cy, R, 0, Math.PI * 2);
    ctx.clip();
    for (let edge of lines) {
      let a = allById.get(edge[0]), b = allById.get(edge[1]);
      if (!a || !b || (a.alt <= 0 && b.alt <= 0))
        continue;
      if (focusedCon && edge[2] !== focusedCon)
        continue;
      let p1 = spot(a), p2 = spot(b);
      ctx.strokeStyle = focusedCon ? '#68E1FF' : '#B7A4FF';
      ctx.globalAlpha = focusedCon ? .95 : .46;
      ctx.lineWidth = focusedCon ? 2.6 : 1.15;
      ctx.beginPath();
      ctx.moveTo(p1.x, p1.y);
      ctx.lineTo(p2.x, p2.y);
      ctx.stroke();
    }
    ctx.restore();
  }

  // the star and planet dots
  for (let o of everything) {
    let p = pos.get(o.id);
    if (!p || o.id === chosen)
      continue;
    ctx.globalAlpha = .88;
    ctx.fillStyle = o.type === 'planet' ? '#B7A4FF' : '#68E1FF';
    ctx.beginPath();
    ctx.arc(p.x, p.y, o.type === 'planet' ? 5 : Math.max(1.1, 3.8 - (o.mag || 0) * .4), 0, Math.PI * 2);
    ctx.fill();
    if (o.type === 'planet' || (o.mag !== null && o.mag < .4)) {
      ctx.font = '12px "Instrument Sans",sans-serif';
      ctx.fillStyle = '#F4F7FF';
      ctx.textAlign = 'center';
      ctx.fillText(o.name, p.x, p.y - 13);
    }
  }
  ctx.globalAlpha = 1;

  // too many names would overlap
  if (showConNames) {
    let visibleNames = liveGroups().filter(g => !focusedCon || g.id === focusedCon);
    for (let group of visibleNames.slice(0, focusedCon ? 1 : 9)) {
      let pts = [...group.stars].map(id => pos.get(id)).filter(Boolean);
      if (!pts.length)
        continue;
      let x = pts.reduce((n, p) => n + p.x, 0) / pts.length;
      let y = pts.reduce((n, p) => n + p.y, 0) / pts.length;
      ctx.font = '12px "Instrument Sans",sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = focusedCon ? '#68E1FF' : '#B7A4FF';
      ctx.fillText(group.name, x, Math.max(24, y - 14));
    }
  }
  ctx.font = '14px "Instrument Sans",sans-serif';
  ctx.textAlign = 'center';
  ctx.fillStyle = '#A8B6CA';
  ctx.fillText('N', cx, cy - R - 12);
  ctx.fillText('S', cx, cy + R + 21);
  ctx.fillText('E', cx + R + 18, cy + 4);
  ctx.fillText('W', cx - R - 18, cy + 4);

  // make the chosen star really easy to see
  let picked = everything.find(o => o.id === chosen);
  let p = pos.get(chosen);
  if (picked && p) {
    ctx.save();
    ctx.beginPath();
    ctx.arc(p.x, p.y, 18, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(104,225,255,.16)';
    ctx.shadowColor = '#68E1FF';
    ctx.shadowBlur = 24;
    ctx.fill();
    ctx.shadowBlur = 0;
    ctx.beginPath();
    ctx.arc(p.x, p.y, 21, 0, Math.PI * 2);
    ctx.strokeStyle = '#B7A4FF';
    ctx.lineWidth = 3;
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(p.x, p.y, 13, 0, Math.PI * 2);
    ctx.strokeStyle = '#F4F7FF';
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(p.x, p.y, 6.5, 0, Math.PI * 2);
    ctx.fillStyle = picked.type === 'planet' ? '#B7A4FF' : '#68E1FF';
    ctx.fill();
    ctx.font = '600 15px "Instrument Sans",sans-serif';
    let name = picked.name;
    let boxW = ctx.measureText(name).width + 26, boxH = 32;
    let x = Math.max(8, Math.min(w - boxW - 8, p.x - boxW / 2));
    let y = p.y - 61;
    if (y < 8)
      y = p.y + 29;
    ctx.fillStyle = '#131D30';
    ctx.fillRect(x, y, boxW, boxH);
    ctx.strokeStyle = '#68E1FF';
    ctx.lineWidth = 2;
    ctx.strokeRect(x, y, boxW, boxH);
    ctx.fillStyle = '#F4F7FF';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(name, x + boxW / 2, y + boxH / 2);
    ctx.restore();
  }
}
canvas.addEventListener('click', e => {
  let r = canvas.getBoundingClientRect();
  let x = (e.clientX - r.left) * canvas.width / r.width;
  let y = (e.clientY - r.top) * canvas.height / r.height;
  let hits = mapSpots.map(p => ({ ...p, d: Math.hypot(x - p.x, y - p.y) })).sort((a, b) => a.d - b.d);
  if (hits[0] && hits[0].d < 22)
    select(hits[0].id, true);
  else
    clearSelections(); // click outside a star or constellation to reset
});

// show a hand cursor if you're near a star
canvas.addEventListener('mousemove', e => {
  let r = canvas.getBoundingClientRect();
  let x = (e.clientX - r.left) * canvas.width / r.width;
  let y = (e.clientY - r.top) * canvas.height / r.height;
  canvas.style.cursor = mapSpots.some(p => Math.hypot(x - p.x, y - p.y) < 22) ? 'pointer' : 'default';
});

// Arrow keys choose the closest star in that direction
canvas.addEventListener('keydown', e => {
  if (!['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Enter', ' ', 'Escape'].includes(e.key))
    return;
  e.preventDefault();
  if (e.key === 'Escape') {
    clearSelections();
    return;
  }
  if (e.key === 'Enter' || e.key === ' ') {
    if (novaAudio.getMode() === 'off') {
      el('skyStatus').textContent = 'Audio is off  Use the audio button above to turn on narration';
      return;
    }
    if (chosen)
      getStory(chosen, true);
    return;
  }
  if (!mapSpots.length)
    return;
  let current = mapSpots.find(p => p.id === chosen) || { x: canvas.width / 2, y: canvas.height / 2 };
  let dx = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
  let dy = e.key === 'ArrowDown' ? 1 : e.key === 'ArrowUp' ? -1 : 0;
  let next = mapSpots.filter(p => p.id !== chosen).map(p => {
    let x = p.x - current.x, y = p.y - current.y;
    let front = x * dx + y * dy;
    return { ...p, score: front > 1 ? Math.hypot(x, y) + Math.abs(x * dy - y * dx) * 1.5 : 1e9 };
  }).sort((a, b) => a.score - b.score)[0];
  if (next && next.score < 1e9) {
    soundClick();
    select(next.id, true);
  }
});

// keyboard in button list
el('starList').addEventListener('keydown', e => {
  if (!['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key))
    return;
  let bs = [...el('starList').querySelectorAll('button')];
  let i = bs.indexOf(document.activeElement);
  if (i < 0)
    return;
  e.preventDefault();
  let step = (e.key === 'ArrowDown' || e.key === 'ArrowRight') ? 1 : -1;
  let next = bs[(i + step + bs.length) % bs.length];
  next.focus();
  next.click();
});

// if the user mutes NOVA, stop any star narration in progress
document.addEventListener('nova:modechange', e => {
  if (e.detail.mode === 'off') {
    clearTimeout(storyTimer);
    stop();
  }
});
el('playBtn').addEventListener('click', () => {
  if (novaAudio.getMode() === 'off') {
    el('skyStatus').textContent = 'Audio is off  Use the audio button above to turn on narration';
    return;
  }
  if (chosen)
    getStory(chosen, true);
});
el('stopBtn').addEventListener('click', () => {
  clearTimeout(storyTimer);
  stop();
  el('skyStatus').textContent = 'Narration stopped';
});
el('yourSkyBtn').addEventListener('click', () => {
  mode = 'sky';
  el('yourSkyBtn').setAttribute('aria-pressed', 'true');
  el('allStarsBtn').setAttribute('aria-pressed', 'false');
  showList();
});
el('allStarsBtn').addEventListener('click', () => {
  mode = 'all';
  el('allStarsBtn').setAttribute('aria-pressed', 'true');
  el('yourSkyBtn').setAttribute('aria-pressed', 'false');
  showList();
});
el('starSearch').addEventListener('input', showList);
el('place').addEventListener('change', () => {
  if (cities[el('place').value])
    coords = cities[el('place').value];
  loadSky();
});
el('skyDate').addEventListener('change', () => { live = false; loadSky(); });
el('nowBtn').addEventListener('click', () => { dateNow(); loadSky(); });
el('locateBtn').addEventListener('click', () => {
  if (!navigator.geolocation) {
    el('skyStatus').textContent = 'GPS is unavailable';
    return;
  }
  navigator.geolocation.getCurrentPosition(p => {
    coords = [p.coords.latitude, p.coords.longitude];
    if (!el('place').querySelector('[value="current"]'))
      el('place').add(new Option('Current location', 'current'));
    el('place').value = 'current';
    loadSky();
  }, () => el('skyStatus').textContent = 'Could not get location');
});

// show the map on the explore page
el('showLines').addEventListener('change', e => { showConLines = e.target.checked; drawMap(); });
el('showLabels').addEventListener('change', e => { showConNames = e.target.checked; drawMap(); });
el('clearCon').addEventListener('click', clearSelections);

// tour any visible constellation, not only 3 hardcoded ones
// use the brightest connected stars to keep the tour a useful length

function showTour() {
  if (!tour.length)
    return;
  let obj = everything.find(x => x.id === tour[tourStep]);
  if (!obj)
    return;
  el('tourProgress').textContent = `${constellationNames[focusedCon] || 'CONSTELLATION'}  ·  STAR ${tourStep + 1} OF ${tour.length}`;
  el('tourStar').textContent = obj.name;
  el('tourText').textContent = summary(obj);
  el('prevTour').disabled = tourStep === 0;
  el('nextTour').disabled = tourStep === tour.length - 1;
  select(obj.id, true, true);
}
el('startConTour').addEventListener('click', () => {
  if (!focusedCon)
    return;
  let group = liveGroups().find(g => g.id === focusedCon);
  if (!group)
    return;
  tour = [...group.stars].map(id => everything.find(o => o.id === id))
    .filter(o => o && o.alt > 0).sort((a, b) => a.mag - b.mag).slice(0, 10).map(o => o.id);
  if (tour.length < 2) {
    el('skyStatus').textContent = 'Not enough stars are above the horizon for a guided tour';
    finishTour();
    return;
  }
  tourStep = 0;

  // tour still works as text if sound is off
  el('tourPlayer').hidden = false;
  showTour();
  el('tourPlayer').scrollIntoView({ block: 'nearest', behavior: 'smooth' });
});
el('nextTour').addEventListener('click', () => {
  if (tour.length && tourStep < tour.length - 1) {
    tourStep++;
    showTour();
  }
});
el('prevTour').addEventListener('click', () => {
  if (tour.length && tourStep > 0) {
    tourStep--;
    showTour();
  }
});
el('repeatTour').addEventListener('click', () => {
  if (!chosen)
    return;
  if (novaAudio.getMode() === 'off') {
    el('skyStatus').textContent = 'Audio is off  Use the audio button above to turn on narration';
    return;
  }
  getStory(chosen, true);
});
el('endTour').addEventListener('click', () => {
  finishTour();
  clearTimeout(storyTimer);
  stop();
  chosen = null;
  showList();
  info();
  drawMap();
  el('skyStatus').textContent = 'Guided tour ended';
});

// Check whether the server has an ElevenLabs voice configured
fetch('/api/services').then(r => r.json()).then(d => {
  voiceAvailable = d.elevenlabs;
  console.log('NOVA services', d);
}).catch(() => console.log('Could not check service setup'));
dateNow();
loadSky();
setInterval(() => { if (live && !document.hidden)
  loadSky(); }, 30000);
document.addEventListener('visibilitychange', () => { if (!document.hidden && live)
  loadSky(); });
