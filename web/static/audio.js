// Sounds and page switching for NOVA
// The navbar stays on the page, so the music doesn't start over when you switch tabs

(() => {
  const button = document.getElementById('audioToggle');
  const main = document.getElementById('main');
  if (!button || !main) return;

  const icon = document.getElementById('audioIcon');
  const label = document.getElementById('audioLabel');
  const errorBox = document.getElementById('audioProblem');

  const modes = ['off', 'full', 'voice'];
  const modeNames = {
    off: 'Audio off',
    full: 'Full audio',
    voice: 'Voice only'
  };

  const images = {
    off: button.dataset.offSrc || '/static/images/audio off.png',
    full: button.dataset.onSrc || '/static/images/audio.png',
    voice: button.dataset.halfSrc || '/static/images/audioHalf.png'
  };

  const musicPath = button.dataset.ambientUrl || '/static/sounds/ambient.mp3';
  const clickPath = button.dataset.clickUrl || '/static/sounds/click_effect.mp3';

  // Only make one music player, even when someone switches pages
  const music = new Audio(musicPath);
  music.loop = true;
  music.volume = 0.3;
  music.preload = 'auto';

  // A few click players make repeated clicks sound better
  const clickSounds = [];
  for (let i = 0; i < 5; i++) {
    const sound = new Audio(clickPath);
    sound.volume = 0.85;
    sound.preload = 'auto';
    clickSounds.push(sound);
  }

  let clickIndex = 0;
  let mode = 'off';
  let talking = false;

  try {
    const saved = sessionStorage.getItem('nova_audio_mode');
    if (modes.includes(saved)) mode = saved;
  } catch (err) {
    // Storage can be disabled in some browsers, which is fine
  }

  function showError(file, err) {
    if (err?.name === 'AbortError') return;
    console.warn('NOVA audio problem:', file, err);
    if (!errorBox) return;

    errorBox.hidden = false;
    errorBox.textContent = err?.name === 'NotAllowedError'
      ? 'Click the page once to allow audio'
      : 'Could not play ' + file + ' — check static/sounds';
  }

  music.addEventListener('error', () => showError('ambient.mp3', music.error));
  clickSounds[0].addEventListener('error', () => {
    showError('click_effect.mp3', clickSounds[0].error);
  });

  function playMusic() {
    if (mode !== 'full') return;
    music.volume = talking ? 0.08 : 0.3;
    if (!music.paused) return;

    music.play().then(() => {
      if (errorBox) errorBox.hidden = true;
    }).catch(err => showError('ambient.mp3', err));
  }

  function playClick() {
    if (mode !== 'full') return;

    const sound = clickSounds[clickIndex];
    clickIndex = (clickIndex + 1) % clickSounds.length;

    try {
      sound.pause();
      sound.currentTime = 0;
      sound.play().catch(err => showError('click_effect.mp3', err));
    } catch (err) {
      showError('click_effect.mp3', err);
    }
  }

  function updateButton() {
    const next = modes[(modes.indexOf(mode) + 1) % modes.length];
    if (icon) icon.src = images[mode];
    if (label) label.textContent = modeNames[mode];
    button.title = modeNames[mode];
    button.setAttribute('aria-label', modeNames[mode] + ', switch to ' + modeNames[next]);
    button.setAttribute('aria-pressed', String(mode !== 'off'));
  }

  function setMode(next) {
    if (!modes.includes(next)) return;
    mode = next;

    try {
      sessionStorage.setItem('nova_audio_mode', mode);
    } catch (err) {}

    updateButton();

    if (mode === 'full') {
      playMusic();
    } else {
      music.pause();
      clickSounds.forEach(sound => {
        sound.pause();
        sound.currentTime = 0;
      });
    }

    // Explore and Ask NOVA use this when their narration is muted
    document.dispatchEvent(new CustomEvent('nova:modechange', {
      detail: { mode }
    }));
  }

  button.addEventListener('click', () => {
    const next = modes[(modes.indexOf(mode) + 1) % modes.length];
    setMode(next);
    if (next === 'full') playClick();
  });

  // Play effects on pointer DOWN so links can't interrupt the sound
  // The click event below is for people using a keyboard
  function clickable(target) {
    return target instanceof Element && target.closest(
      'button, a, summary, select, canvas, [role="button"]'
    );
  }

  document.addEventListener('pointerdown', e => {
    if (mode !== 'full') return;
    playMusic();
    if (e.target.closest('#audioToggle, #novaTestSound')) return;
    if (clickable(e.target)) playClick();
  }, true);

  document.addEventListener('click', e => {
    if (mode !== 'full' || e.detail !== 0 || !e.isTrusted) return;
    if (e.target.closest('#audioToggle, #novaTestSound')) return;
    if (clickable(e.target)) playClick();
  }, true);

  // After a refresh, some browsers want one click before music can play
  document.addEventListener('keydown', e => {
    if (mode === 'full' && (e.key === 'Enter' || e.key === ' ')) {
      playMusic();
    }
  }, true);

  // The Guide page might get loaded later, so use one shared listener
  document.addEventListener('click', e => {
    if (!e.target.closest('#novaTestSound')) return;
    setMode('full');
    playMusic();
    playClick();

    const status = document.getElementById('novaTestStatus');
    if (status) status.textContent = 'Playing ambient music and a click effect';
  });

  window.novaAudio = {
    getMode: () => mode,
    setMode,
    canSpeak: () => mode !== 'off',
    playClick,
    duck: isTalking => {
      talking = Boolean(isTalking);
      music.volume = talking ? 0.08 : 0.3;
    },
    test: () => {
      setMode('full');
      playClick();
    }
  };

  updateButton();
  if (mode === 'full') playMusic();

  // Switch NOVA pages without reloading the browser
  // We keep old pages hidden in the document so their scripts still find them
  // This also keeps the same background song playing while you move around
  const pageCache = document.createElement('div');
  pageCache.hidden = true;
  pageCache.style.display = 'none';
  pageCache.setAttribute('aria-hidden', 'true');
  document.body.appendChild(pageCache);

  const pages = new Map();
  const loadedScripts = new Set();
  let navigationNumber = 0;
  const routes = ['/', '/explore', '/ask', '/guide'];

  function pagePath(url) {
    const path = url.pathname.replace(/\/$/, '') || '/';
    return routes.includes(path) ? path : null;
  }

  // Save whichever page opened first
  pages.set(pagePath(new URL(location.href)), Array.from(main.childNodes));
  document.querySelectorAll('script[src]').forEach(script => {
    loadedScripts.add(new URL(script.src, location.href).pathname);
  });

  function loadScript(src) {
    const path = new URL(src, location.href).pathname;
    if (loadedScripts.has(path)) return Promise.resolve();
    loadedScripts.add(path);

    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = src;
      script.onload = resolve;
      script.onerror = () => {
        loadedScripts.delete(path);
        reject(new Error('Could not load ' + path));
      };
      document.body.appendChild(script);
    });
  }

  function updateNav(path) {
    document.querySelectorAll('.site-nav a').forEach(link => {
      const current = pagePath(new URL(link.href)) === path;
      if (current) link.setAttribute('aria-current', 'page');
      else link.removeAttribute('aria-current');
    });
  }

  async function switchPage(address, addHistory = true) {
    const url = new URL(address, location.href);
    const path = pagePath(url);
    if (!path) {
      location.href = url.href;
      return;
    }

    const number = ++navigationNumber;
    let files = [];
    let styles = [];

    if (!pages.has(path)) {
      try {
        const res = await fetch(url.pathname + url.search);
        if (!res.ok) throw new Error('Page not found');

        const html = new DOMParser().parseFromString(await res.text(), 'text/html');
        const newMain = html.getElementById('main');
        if (!newMain) throw new Error('Page content missing');

        pages.set(path, Array.from(newMain.childNodes));
        files = [...html.querySelectorAll('script[src]')]
          .map(script => script.getAttribute('src'));
        styles = [...html.querySelectorAll('link[rel="stylesheet"]')]
          .map(link => link.getAttribute('href'));
      } catch (err) {
        console.warn('NOVA page loading problem:', err);
        location.href = url.href;
        return;
      }
    }

    if (number !== navigationNumber) return;

    // Stop the mic and any answer if someone leaves Ask NOVA
    if (pagePath(new URL(location.href)) === '/ask' && path !== '/ask') {
      document.getElementById('novaCancel')?.click();
      document.getElementById('novaStop')?.click();
    }

    // Park the old page instead of deleting it
    // It stays in the DOM but isn't visible anymore
    for (const node of Array.from(main.childNodes)) {
      pageCache.appendChild(node);
    }

    if (addHistory) history.pushState({}, '', url.href);
    main.replaceChildren(...pages.get(path));
    document.title = {
      '/': 'NOVA | Home',
      '/explore': 'NOVA | Explore Sky',
      '/ask': 'NOVA | Ask NOVA',
      '/guide': 'NOVA | How to Listen'
    }[path];
    updateNav(path);

    // Ask NOVA has its own CSS. Only add each stylesheet once
    for (const href of styles) {
      const fullUrl = new URL(href, location.href).href;
      const exists = [...document.querySelectorAll('link[rel="stylesheet"]')]
        .some(link => link.href === fullUrl);
      if (!exists) {
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = fullUrl;
        document.head.appendChild(link);
      }
    }

    // Run the sky / voice script when its page is first opened
    try {
      for (const file of files) await loadScript(file);
    } catch (err) {
      console.warn('NOVA could not start this page:', err);
      location.href = url.href;
      return;
    }

    // Used by "Ask NOVA about this" on the star map
    if (path === '/ask') {
      const star = url.searchParams.get('about');
      const question = document.getElementById('novaQuestion');
      if (star && star.length < 90 && question) {
        question.value = 'Tell me about ' + star;
      }
    }

    if (url.hash) {
      const anchor = document.getElementById(decodeURIComponent(url.hash.slice(1)));
      if (anchor) anchor.scrollIntoView();
    } else {
      window.scrollTo(0, 0);
    }

    document.dispatchEvent(new CustomEvent('nova:pagechange', {
      detail: { page: path }
    }));
  }

  // Only handle NOVA's own page links, not outside links or downloads
  document.addEventListener('click', e => {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    const link = e.target instanceof Element ? e.target.closest('a[href]') : null;
    if (!link || link.target || link.hasAttribute('download') || link.hasAttribute('data-reload')) return;

    const url = new URL(link.href, location.href);
    if (url.origin !== location.origin || !pagePath(url)) return;
    if (url.pathname === location.pathname && url.search === location.search && url.hash) return;

    e.preventDefault();
    switchPage(url.href);
  });

  // Browser Back and Forward should still work normally
  window.addEventListener('popstate', () => {
    switchPage(location.href, false);
  });
})();
