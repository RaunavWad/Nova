// nova sky map stuff
// data comes from python now so we don't have to type every star by hand

const el = id => document.getElementById(id);
const canvas = el('skyCanvas');
const ctx = canvas.getContext('2d');

const cities = {
  robbinsville:[40.2146,-74.6193],
  princeton:[40.3573,-74.6672],
  nyc:[40.7128,-74.0060]
};

let coords = cities.robbinsville;
let everything = [], lines = [], constellationNames = {};
let focusedCon = null, showConLines = true, showConNames = true;
let chosen = null, mode = 'sky', audio = false, live = true;
let storyCache = {}, storyTimer, requestNum = 0;
let mapSpots = [];
let voiceAvailable = false, currentAudio = null, audioUrl = null;
let talkingRequest = null, speechRun = 0;
let tour = null, tourStep = 0;

const tours = {
  orion:['Betelgeuse','Bellatrix','Alnitak','Alnilam','Mintaka','Rigel'],
  lyra:['Vega','Sheliak','Sulafat'],
  ursa:['Dubhe','Merak','Alioth','Mizar','Alkaid']
};

function dateNow() {
  let d = new Date(), pad=n=>String(n).padStart(2,'0');
  el('skyDate').value = `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  live = true;
}

function compass(a) {
  return ['north','northeast','east','southeast','south','southwest','west','northwest'][Math.round(a/45)%8];
}

// fetch the actual sky from flask
async function loadSky() {
  if(live) dateNow();
  let t = new Date(el('skyDate').value);
  if(isNaN(t)) { el('skyStatus').textContent='Choose a valid date';return }

  if(!everything.length) el('skyStatus').textContent='Loading the sky';

  let p = new URLSearchParams({lat:coords[0],lon:coords[1],at:t.toISOString()});
  let num = ++requestNum;

  try {
    let res = await fetch('/api/sky?'+p);
    let data = await res.json();
    if(!res.ok) throw Error(data.error || 'Sky request failed');
    if(num !== requestNum) return;

    everything = data.objects;
    lines = data.lines;
    constellationNames = Object.fromEntries((data.constellations || []).map(c=>[c.id,c.name]));
    el('skyCount').textContent = `${data.above} catalog objects above the horizon`;
    let skyMessage = data.daylight
      ? 'Daylight right now  The map still shows where objects are'
      : 'Night sky positions are ready';
    if(el('skyStatus').textContent!==skyMessage && !el('skyStatus').textContent.startsWith('Selected ')) el('skyStatus').textContent=skyMessage;

    if(!chosen || !everything.some(x=>x.id===chosen)) {
      chosen = visible()[0]?.id || everything[0]?.id;
    }

    showList(); info(); updateConstellations(); drawMap();
    el('skyUpdated').textContent = 'Calculated at '+new Date().toLocaleTimeString();
    el('skyTimeMode').textContent = live ? 'Live sky updates every 30 seconds' : 'Viewing a selected date and time';
  } catch(e) {
    console.log(e);
    el('skyStatus').textContent = e.message + '  Check your Flask terminal';
  }
}

function visible() {
  let q = el('starSearch').value.toLowerCase().trim();
  let found = everything.filter(o => (mode==='all' || o.alt>0)
    && (o.name.toLowerCase().includes(q) || o.constellation.toLowerCase().includes(q))
    && (!focusedCon || (o.type==='star' && o.constellation===constellationNames[focusedCon])));

  // bright objects first, planets up front
  found.sort((a,b)=>(a.type==='planet'?-3:a.mag)-(b.type==='planet'?-3:b.mag));
  return found;
}

function showList() {
  let results = visible();
  let box = el('starList');
  let hadFocus=box.contains(document.activeElement) ? document.activeElement?.dataset?.id : null;
  box.innerHTML='';

  // don't make a screen reader tab through thousands of buttons
  results.slice(0,100).forEach(o=>{
    let b = document.createElement('button');
    b.type='button';
    b.dataset.id=o.id;

    // using our own icons instead of the random symbols
    let pic=document.createElement('img');
    pic.src=o.type==='planet'?'/static/images/planet.png':'/static/images/star.png';
    pic.className='sky-object-icon';
    pic.alt='';
    pic.setAttribute('aria-hidden','true');

    let name=document.createElement('span');
    name.textContent=o.name;

    b.append(pic,name);
    b.setAttribute('aria-label',o.name + (o.name==='Moon'?' moon':o.type==='planet'?' planet':' star'));
    b.setAttribute('aria-pressed',String(o.id===chosen));
    b.addEventListener('click',()=>select(o.id,true));
    box.appendChild(b);
  });

  el('collectionLabel').textContent = `Showing ${Math.min(100,results.length)} of ${results.length} objects`;
  if(hadFocus) [...box.querySelectorAll('button')].find(b=>b.dataset.id===hadFocus)?.focus();
}

function summary(o) {
  if(!o) return 'Choose a star or planet to begin';
  let place = o.alt>0
    ? `toward ${compass(o.az)} at ${Math.round(o.alt)} degrees above the horizon`
    : 'currently below your horizon';
  if(o.type==='planet') return `${o.name} is a solar system object, ${place}`;
  let dist = o.dist_ly ? `, about ${o.dist_ly} light years away` : '';
  return `${o.name} in ${o.constellation}, ${place}${dist}`;
}

function info() {
  let o = everything.find(x=>x.id===chosen);
  el('starName').textContent=o?.name || 'Choose a star';
  el('starMeta').textContent = o ? (o.type==='planet'?'Planet or moon':o.constellation) : '';
  el('starFacts').textContent = storyCache[chosen] || summary(o);
  el('starDirection').textContent = o ?
    (o.alt>0 ? `${compass(o.az)}  ·  ${Math.round(o.alt)} degrees above the horizon` : 'Below the horizon') : '';
  let askLink=el('askAboutStar');
  if(o && askLink)askLink.href='/ask?about='+encodeURIComponent(o.name);
  el('starList').querySelectorAll('button').forEach(b=>{
    b.setAttribute('aria-pressed',String(b.dataset.id===chosen));
  });
}

// quick local fallback when no ElevenLabs key or voice API fails
function browserVoice(t) {
  if(!('speechSynthesis' in window)) {
    el('skyStatus').textContent='This browser cannot play speech'; return
  }
  speechSynthesis.cancel();
  let v=new SpeechSynthesisUtterance(t);
  v.rate=.9; speechSynthesis.speak(v);
}

// play an actual ElevenLabs mp3 from flask
async function say(t,id=null) {
  if(!audio)return;
  stop();
  let myTurn=speechRun;

  if(!id || !voiceAvailable) {browserVoice(t);return}

  talkingRequest=new AbortController();
  try {
    el('skyStatus').textContent='Getting NOVA voice';
    let r=await fetch('/api/speak',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({id:id}),signal:talkingRequest.signal
    });
    if(!r.ok)throw Error('ElevenLabs request failed');
    let file=await r.blob();
    if(myTurn!==speechRun)return;

    audioUrl=URL.createObjectURL(file);
    currentAudio=new Audio(audioUrl);
    let clip=currentAudio, url=audioUrl;
    currentAudio.onended=()=>{
      if(currentAudio===clip)currentAudio=null;
      URL.revokeObjectURL(url);
      if(audioUrl===url)audioUrl=null;
    };
    await currentAudio.play();
    if(myTurn===speechRun)el('skyStatus').textContent='Playing NOVA narration';
  } catch(e) {
    if(myTurn!==speechRun)return;
    console.log('Voice unavailable, using browser speech',e.message);
    el('skyStatus').textContent='Using browser speech for this description';
    browserVoice(t);
  }
}

function stop() {
  speechRun++;
  if(talkingRequest){talkingRequest.abort();talkingRequest=null}
  if(currentAudio){currentAudio.pause();currentAudio=null}
  if(audioUrl){URL.revokeObjectURL(audioUrl);audioUrl=null}
  if('speechSynthesis' in window)speechSynthesis.cancel();
}

// selecting with mouse or arrow keys
function select(id, tell=false) {
  chosen = id;
  clearTimeout(storyTimer);
  info(); drawMap();

  let obj=everything.find(o=>o.id===id);
  if(!obj) return;
  el('skyStatus').textContent = `Selected ${obj.name}`;

  stop();
  // wait a bit before asking AI and voice so arrow keys don't burn credits
  storyTimer=setTimeout(()=>getStory(id,tell && audio),850);
}

async function getStory(id, readOut=false) {
  let myTurn=speechRun;
  if(storyCache[id]) {
    if(readOut && id===chosen && myTurn===speechRun) say(storyCache[id],id);
    return;
  }
  try {
    let r=await fetch('/api/describe',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({id:id})
    });
    let d=await r.json();
    if(!r.ok) throw Error(d.error || 'Could not describe');
    storyCache[id]=d.text;
    if(id===chosen) info();
    if(readOut && id===chosen && myTurn===speechRun) say(d.text,id);
  } catch(e) { console.log('description error',e); }
}

// drawing a circle sky, north is up, east is right
function spot(o) {
  let radius = 188;
  let r=(90-o.alt)/90*radius, angle=o.az*Math.PI/180;
  return {x:canvas.width/2+Math.sin(angle)*r,
          y:canvas.height/2-Math.cos(angle)*r};
}

// a line pattern is fixed but its STARS move with location and time
// pull the positions from /api/sky again every 30 seconds
function liveGroups() {
  let byId = new Map(everything.map(o=>[o.id,o]));
  let groups = new Map();
  for(let edge of lines) {
    let a=byId.get(edge[0]),b=byId.get(edge[1]),code=edge[2];
    if(!a || !b || (a.alt<=0 && b.alt<=0))continue;
    if(!groups.has(code))groups.set(code,{id:code,name:constellationNames[code]||code,edges:0,stars:new Set()});
    let group=groups.get(code);
    group.edges++;
    if(a.alt>0)group.stars.add(a.id);
    if(b.alt>0)group.stars.add(b.id);
  }
  return [...groups.values()].sort((a,b)=>b.edges-a.edges || a.name.localeCompare(b.name));
}

function updateConstellations() {
  let groups=liveGroups();
  let box=el('constellationList');
  let focus=document.activeElement?.dataset?.constellation;
  box.innerHTML='';
  el('constellationCount').textContent=`${groups.length} patterns have stars above the horizon`;
  for(let group of groups) {
    let b=document.createElement('button');
    b.type='button';
    b.className='constellation-option';
    b.dataset.constellation=group.id;
    b.setAttribute('aria-pressed',String(focusedCon===group.id));
    b.textContent=group.name+'  ·  '+group.stars.size+' stars';
    b.addEventListener('click',()=>{
      focusedCon=focusedCon===group.id ? null : group.id;
      el('clearCon').hidden=!focusedCon;
      updateConstellations();showList();drawMap();
    });
    box.appendChild(b);
  }
  if(focusedCon && !groups.some(g=>g.id===focusedCon)) {
    focusedCon=null;
    el('clearCon').hidden=true;
  }
  if(focus) box.querySelector(`[data-constellation="${focus}"]`)?.focus();
}

function drawMap() {
  let w=canvas.width,h=canvas.height,cx=w/2,cy=h/2,R=188;
  ctx.fillStyle='#0B1423';ctx.fillRect(0,0,w,h);
  ctx.strokeStyle='#30425C';ctx.lineWidth=1;
  for(let r of [R,R*2/3,R/3]) {
    ctx.beginPath();ctx.arc(cx,cy,r,0,Math.PI*2);ctx.stroke();
  }
  ctx.beginPath();ctx.moveTo(cx-R,cy);ctx.lineTo(cx+R,cy);
  ctx.moveTo(cx,cy-R);ctx.lineTo(cx,cy+R);ctx.stroke();

  let allById=new Map(everything.map(o=>[o.id,o]));
  let pos=new Map();
  mapSpots=[];
  for(let o of everything) {
    if(o.alt<=0)continue;
    let p=spot(o);pos.set(o.id,p);
    mapSpots.push({...p,id:o.id});
  }

  // crop constellation segments right at the horizon
  // even if only one endpoint is up, the visible part is still drawn
  if(showConLines) {
    ctx.save();
    ctx.beginPath();ctx.arc(cx,cy,R,0,Math.PI*2);ctx.clip();
    for(let edge of lines) {
      let a=allById.get(edge[0]),b=allById.get(edge[1]);
      if(!a||!b||(a.alt<=0&&b.alt<=0))continue;
      if(focusedCon && edge[2]!==focusedCon)continue;
      let p1=spot(a),p2=spot(b);
      ctx.strokeStyle=focusedCon?'#68E1FF':'#B7A4FF';
      ctx.globalAlpha=focusedCon?.95:.46;
      ctx.lineWidth=focusedCon?2.6:1.15;
      ctx.beginPath();ctx.moveTo(p1.x,p1.y);ctx.lineTo(p2.x,p2.y);ctx.stroke();
    }
    ctx.restore();
  }

  // star / planet dots
  for(let o of everything) {
    let p=pos.get(o.id);
    if(!p||o.id===chosen)continue;
    ctx.globalAlpha=(focusedCon && o.type==='star' && o.constellation!==constellationNames[focusedCon])?.26:.88;
    ctx.fillStyle=o.type==='planet'?'#B7A4FF':'#68E1FF';
    ctx.beginPath();ctx.arc(p.x,p.y,o.type==='planet'?5:Math.max(1.1,3.8-(o.mag||0)*.4),0,Math.PI*2);ctx.fill();
    if(o.type==='planet'||(o.mag!==null&&o.mag<.4)) {
      ctx.font='12px "Instrument Sans",sans-serif';
      ctx.fillStyle='#F4F7FF';ctx.textAlign='center';ctx.fillText(o.name,p.x,p.y-13);
    }
  }
  ctx.globalAlpha=1;

  // show a few names, not 88 labels on top of each other
  if(showConNames) {
    let visibleNames=liveGroups().filter(g=>!focusedCon || g.id===focusedCon);
    for(let group of visibleNames.slice(0,focusedCon?1:9)) {
      let pts=[...group.stars].map(id=>pos.get(id)).filter(Boolean);
      if(!pts.length)continue;
      let x=pts.reduce((n,p)=>n+p.x,0)/pts.length;
      let y=pts.reduce((n,p)=>n+p.y,0)/pts.length;
      ctx.font='12px "Instrument Sans",sans-serif';ctx.textAlign='center';
      ctx.fillStyle=focusedCon?'#68E1FF':'#B7A4FF';
      ctx.fillText(group.name,x,Math.max(24,y-14));
    }
  }

  ctx.font='14px "Instrument Sans",sans-serif';ctx.textAlign='center';ctx.fillStyle='#A8B6CA';
  ctx.fillText('N',cx,cy-R-12);ctx.fillText('S',cx,cy+R+21);
  ctx.fillText('E',cx+R+18,cy+4);ctx.fillText('W',cx-R-18,cy+4);

  // selected star is huge so you can actually see it
  let picked=everything.find(o=>o.id===chosen);
  let p=pos.get(chosen);
  if(picked&&p) {
    ctx.save();
    ctx.beginPath();ctx.arc(p.x,p.y,18,0,Math.PI*2);
    ctx.fillStyle='rgba(104,225,255,.16)';ctx.shadowColor='#68E1FF';ctx.shadowBlur=24;ctx.fill();
    ctx.shadowBlur=0;
    ctx.beginPath();ctx.arc(p.x,p.y,21,0,Math.PI*2);
    ctx.strokeStyle='#B7A4FF';ctx.lineWidth=3;ctx.stroke();
    ctx.beginPath();ctx.arc(p.x,p.y,13,0,Math.PI*2);
    ctx.strokeStyle='#F4F7FF';ctx.lineWidth=2;ctx.stroke();
    ctx.beginPath();ctx.arc(p.x,p.y,6.5,0,Math.PI*2);
    ctx.fillStyle=picked.type==='planet'?'#B7A4FF':'#68E1FF';ctx.fill();
    ctx.font='600 15px "Instrument Sans",sans-serif';
    let name=picked.name;
    let boxW=ctx.measureText(name).width+26,boxH=32;
    let x=Math.max(8,Math.min(w-boxW-8,p.x-boxW/2));
    let y=p.y-61;
    if(y<8)y=p.y+29;
    ctx.fillStyle='#131D30';ctx.fillRect(x,y,boxW,boxH);
    ctx.strokeStyle='#68E1FF';ctx.lineWidth=2;ctx.strokeRect(x,y,boxW,boxH);
    ctx.fillStyle='#F4F7FF';ctx.textAlign='center';ctx.textBaseline='middle';
    ctx.fillText(name,x+boxW/2,y+boxH/2);
    ctx.restore();
  }
}

canvas.addEventListener('click',e=>{
  let r=canvas.getBoundingClientRect();
  let x=(e.clientX-r.left)*canvas.width/r.width;
  let y=(e.clientY-r.top)*canvas.height/r.height;
  let hits=mapSpots.map(p=>({...p,d:Math.hypot(x-p.x,y-p.y)})).sort((a,b)=>a.d-b.d);
  if(hits[0] && hits[0].d<22) select(hits[0].id,true);
});

// little hand cursor when the mouse is near a star
canvas.addEventListener('mousemove',e=>{
  let r=canvas.getBoundingClientRect();
  let x=(e.clientX-r.left)*canvas.width/r.width;
  let y=(e.clientY-r.top)*canvas.height/r.height;
  canvas.style.cursor=mapSpots.some(p=>Math.hypot(x-p.x,y-p.y)<22)?'pointer':'default';
});

// keyboard on the map itself, goes to next nearest star in that direction
canvas.addEventListener('keydown',e=>{
  if(!['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Enter',' '].includes(e.key)) return;
  e.preventDefault();
  if(e.key==='Enter'||e.key===' ') {
    audio=true;updateAudioButton();
    if(chosen)getStory(chosen,true);return;
  }
  if(!mapSpots.length) return;

  let current=mapSpots.find(p=>p.id===chosen) || {x:canvas.width/2,y:canvas.height/2};
  let dx= e.key==='ArrowRight'?1:e.key==='ArrowLeft'?-1:0;
  let dy= e.key==='ArrowDown'?1:e.key==='ArrowUp'?-1:0;
  let next=mapSpots.filter(p=>p.id!==chosen).map(p=>{
    let x=p.x-current.x,y=p.y-current.y;
    let front=x*dx+y*dy;
    return {...p,score:front>1?Math.hypot(x,y)+Math.abs(x*dy-y*dx)*1.5:1e9};
  }).sort((a,b)=>a.score-b.score)[0];

  if(next && next.score<1e9) select(next.id,true);
});

// keyboard in button list
el('starList').addEventListener('keydown',e=>{
  if(!['ArrowUp','ArrowDown','ArrowLeft','ArrowRight'].includes(e.key)) return;
  let bs=[...el('starList').querySelectorAll('button')];
  let i=bs.indexOf(document.activeElement);if(i<0)return;
  e.preventDefault();
  let step=(e.key==='ArrowDown'||e.key==='ArrowRight')?1:-1;
  let next=bs[(i+step+bs.length)%bs.length];next.focus();next.click();
});

// image + text update when audio changes
function updateAudioButton() {
  let btn=el('audioToggle');
  el('audioIcon').src=audio ? btn.dataset.onSrc : btn.dataset.offSrc;
  el('audioLabel').textContent=audio ? 'Audio enabled' : 'Enable audio';
  btn.setAttribute('aria-pressed',String(audio));
  btn.setAttribute('aria-label',audio ? 'Disable audio' : 'Enable audio');
  btn.title=audio ? 'Disable audio' : 'Enable audio';
}

el('audioToggle').addEventListener('click',()=>{
  audio=!audio;
  updateAudioButton();
  if(audio) say('Welcome to Nova, choose a star or planet to begin');else stop();
});

el('playBtn').addEventListener('click',()=>{
  audio=true;updateAudioButton();
  if(chosen) getStory(chosen,true);
});
el('stopBtn').addEventListener('click',()=>{
  clearTimeout(storyTimer);stop();
  el('skyStatus').textContent='Audio stopped';
});

el('yourSkyBtn').addEventListener('click',()=>{
  mode='sky';el('yourSkyBtn').setAttribute('aria-pressed','true');
  el('allStarsBtn').setAttribute('aria-pressed','false');showList();
});
el('allStarsBtn').addEventListener('click',()=>{
  mode='all';el('allStarsBtn').setAttribute('aria-pressed','true');
  el('yourSkyBtn').setAttribute('aria-pressed','false');showList();
});

el('starSearch').addEventListener('input',showList);
el('place').addEventListener('change',()=>{
  if(cities[el('place').value]) coords=cities[el('place').value];
  loadSky();
});
el('skyDate').addEventListener('change',()=>{live=false;loadSky()});
el('nowBtn').addEventListener('click',()=>{dateNow();loadSky()});

el('locateBtn').addEventListener('click',()=>{
  if(!navigator.geolocation) {el('skyStatus').textContent='GPS is unavailable';return}
  navigator.geolocation.getCurrentPosition(p=>{
    coords=[p.coords.latitude,p.coords.longitude];
    if(!el('place').querySelector('[value="current"]'))
      el('place').add(new Option('Current location','current'));
    el('place').value='current';loadSky();
  },()=>el('skyStatus').textContent='Could not get location');
});

// map is now visible all the time on Explore
el('showLines').addEventListener('change',e=>{showConLines=e.target.checked;drawMap()});
el('showLabels').addEventListener('change',e=>{showConNames=e.target.checked;drawMap()});
el('clearCon').addEventListener('click',()=>{
  focusedCon=null;el('clearCon').hidden=true;updateConstellations();showList();drawMap();
});

// old tour cards still work, but now using real catalog star names
function showTour() {
  if(!tour)return;
  let name=tour[tourStep];
  let obj=everything.find(s=>s.name.toLowerCase()===name.toLowerCase());
  if(!obj)return;
  el('tourProgress').textContent=`STAR ${tourStep+1} OF ${tour.length}`;
  el('tourStar').textContent=obj.name;
  el('tourText').textContent=summary(obj);
  el('prevTour').disabled=tourStep===0;
  el('nextTour').disabled=tourStep===tour.length-1;
  select(obj.id,true);
}

document.querySelectorAll('[data-tour]').forEach(b=>b.addEventListener('click',()=>{
  tour=tours[b.dataset.tour];tourStep=0;
  el('tourPlayer').hidden=false;showTour();
  el('tourPlayer').scrollIntoView({block:'center',behavior:'smooth'});
}));
el('nextTour').addEventListener('click',()=>{if(tour&&tourStep<tour.length-1){tourStep++;showTour()}});
el('prevTour').addEventListener('click',()=>{if(tour&&tourStep>0){tourStep--;showTour()}});
el('repeatTour').addEventListener('click',()=>{if(chosen)getStory(chosen,true)});
el('endTour').addEventListener('click',()=>{tour=null;clearTimeout(storyTimer);stop();el('tourPlayer').hidden=true});

// find out which services you actually connected
fetch('/api/services').then(r=>r.json()).then(d=>{
  voiceAvailable=d.elevenlabs;
  console.log('NOVA services', d);
}).catch(()=>console.log('Could not check service setup'));

dateNow();loadSky();
setInterval(()=>{if(live && !document.hidden)loadSky()},30000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&live)loadSky()});
