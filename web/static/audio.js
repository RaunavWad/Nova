// nova sounds for all pages
// one file for all this stuff is way easier than repeating it everywhere

(() => {
  const btn = document.getElementById('audioToggle');
  if (!btn) return;

  const icon = document.getElementById('audioIcon');
  const label = document.getElementById('audioLabel');
  const errorBox = document.getElementById('audioProblem');
  const modes = ['off', 'full', 'voice'];
  const names = {off:'Audio off', full:'Full audio', voice:'Voice only'};
  const icons = {off:btn.dataset.offSrc, full:btn.dataset.onSrc, voice:btn.dataset.halfSrc};

  // the sounds are in static/sounds, NOT static/sound
  const ambient = new Audio(btn.dataset.ambientUrl);
  ambient.loop = true;
  ambient.preload = 'auto';
  ambient.volume = .18;

  // a few copies let quick clicks overlap a bit
  const clicks = Array.from({length:4}, () => {
    let a = new Audio(btn.dataset.clickUrl);
    a.preload = 'auto';
    a.volume = .7;
    return a;
  });

  let clickIndex = 0;
  let talking = false;
  let warned = new Set();
  let mode = 'off';

  // keep the setting when you go between pages
  try {
    let saved = sessionStorage.getItem('nova_audio_mode');
    if (modes.includes(saved)) mode = saved;
    let oldTime = Number(sessionStorage.getItem('nova_music_time'));
    if (Number.isFinite(oldTime) && oldTime > 0) {
      ambient.addEventListener('loadedmetadata', () => {
        if (Number.isFinite(ambient.duration) && ambient.duration > 0)
          ambient.currentTime = oldTime % ambient.duration;
      }, {once:true});
    }
  } catch (err) {
    // storage might be disabled, its not a big deal
  }

  function problem(file, err) {
    if (err?.name === 'AbortError') return;
    if (err?.name === 'NotAllowedError') {
      // Chrome sometimes blocks music after switching pages
      console.info('NOVA audio waiting for another click');
      return;
    }
    console.warn('NOVA audio failed:', file, err);
    if (warned.has(file)) return;
    warned.add(file);
    errorBox.hidden = false;
    errorBox.textContent = 'Sound could not load: ' + file + '  Check static/sounds and try refreshing';
  }

  ambient.addEventListener('error', () => problem('ambient.mp3', ambient.error));
  clicks.forEach(a => a.addEventListener('error', () => problem('click_effect.mp3', a.error)));

  function music() {
    if (mode !== 'full' || !ambient.paused) return;
    ambient.volume = talking ? .045 : .18;
    let play = ambient.play();
    if (play) play.catch(err => problem('ambient.mp3', err));
  }

  function clickSound() {
    if (mode !== 'full') return;
    let a = clicks[clickIndex];
    clickIndex = (clickIndex + 1) % clicks.length;
    try {
      a.pause();
      a.currentTime = 0;
      let play = a.play();
      if (play) play.catch(err => problem('click_effect.mp3', err));
    } catch (err) {
      problem('click_effect.mp3', err);
    }
  }

  function updateButton() {
    const next = modes[(modes.indexOf(mode) + 1) % modes.length];
    label.textContent = names[mode];
    icon.src = icons[mode];
    btn.setAttribute('aria-label', names[mode] + ', select for ' + names[next]);
    btn.setAttribute('aria-pressed', String(mode !== 'off'));
    btn.title = names[mode] + ' — click for ' + names[next];
  }

  function changeMode(next) {
    if (!modes.includes(next)) return;
    mode = next;
    try { sessionStorage.setItem('nova_audio_mode', mode); } catch (err) {}

    updateButton();
    if (mode === 'full') {
      music();
    } else {
      // no background track or clicks in voice only
      ambient.pause();
    }

    // other pages use this so their narration knows when we're muted
    document.dispatchEvent(new CustomEvent('nova:modechange', {detail:{mode}}));
  }

  // IMPORTANT: clicking this is a user gesture, so the browser lets us play
  btn.addEventListener('click', () => {
    const next = modes[(modes.indexOf(mode) + 1) % modes.length];
    changeMode(next);
    if (next === 'full') clickSound();
  });

  // a basic sound test is handy since the actual mp3 files are on your computer
  document.getElementById('novaTestSound')?.addEventListener('click', () => {
    changeMode('full');
    clickSound();
    document.getElementById('novaTestStatus').textContent =
      'Music and click effect requested  If you hear nothing, check the sound paths above';
  });

  // button effects on every page, not just the sky map
  document.addEventListener('click', e => {
    if (e.target.closest('#audioToggle, #novaTestSound')) return;
    if (mode !== 'full') return;
    music();
    if (e.target.closest('button, a, canvas, summary, select, [role="button"]')) clickSound();
  }, true);

  // if the browser blocked autoplay after navigating, try again on a gesture
  document.addEventListener('pointerdown', e => {
    if (mode === 'full' && !e.target.closest('#audioToggle')) music();
  }, true);
  document.addEventListener('keydown', e => {
    if (mode === 'full' && (e.key === 'Enter' || e.key === ' ')) music();
  }, true);

  // music can restart when a background tab becomes active
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden && mode === 'full') music();
  });

  window.addEventListener('pagehide', () => {
    try { sessionStorage.setItem('nova_music_time', String(ambient.currentTime || 0)); }
    catch (err) {}
  });

  // this is used by the sky page and Ask NOVA
  window.novaAudio = {
    getMode: () => mode,
    setMode: changeMode,
    canSpeak: () => mode !== 'off',
    playClick: clickSound,
    duck: on => {
      talking = Boolean(on);
      ambient.volume = talking ? .045 : .18;
    },
    test: () => {changeMode('full'); clickSound();}
  };

  updateButton();
  // a saved Full audio setting may be blocked after page navigation
  // we'll retry when they click anywhere
  if (mode === 'full') music();
})();
