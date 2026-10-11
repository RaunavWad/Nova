// Audio controls used on every NOVA page
// Keep one music player alive when moving between pages

(() => {
  const button = document.getElementById('audioToggle');
  const main = document.getElementById('main');
  const icon = document.getElementById('audioIcon');
  const label = document.getElementById('audioLabel');
  const errorBox = document.getElementById('audioProblem');

  const modes = ['full', 'voice', 'off'];
  const names = {
    full: 'Full audio',
    voice: 'Voice only',
    off: 'Audio off'
  };

  const icons = {
    full: button?.dataset.onSrc || '/static/images/audio.png',
    voice: button?.dataset.halfSrc || '/static/images/audioHalf.png',
    off: button?.dataset.offSrc || '/static/images/audio off.png'
  };

  // This is the same folder used in the Flask project
  const musicFile = button?.dataset.ambientUrl || '/static/sounds/ambient.mp3';
  const clickFile = button?.dataset.clickUrl || '/static/sounds/click_effect.mp3';

  const music = new Audio(musicFile);
  music.loop = true;
  music.volume = 0.3;
  music.preload = 'auto';

  // Several copies allow quick clicks without interrupting each other
  const clickSounds = Array.from({ length: 5 }, () => {
    const audio = new Audio(clickFile);
    audio.volume = 0.8;
    audio.preload = 'auto';
    return audio;
  });

  let clickIndex = 0;
  let mode = 'full';
  let talking = false;

  // Use the visitor's choice if they already changed the setting
  try {
    const saved = sessionStorage.getItem('nova_audio_mode');
    if (modes.includes(saved)) mode = saved;
  } catch (err) {
    // The page still works if browser storage is turned off
  }

  function showProblem(file, err) {
    if (err?.name === 'AbortError') return;
    console.warn('NOVA sound problem:', file, err);
    if (!errorBox) return;

    errorBox.hidden = false;
    errorBox.textContent = err?.name === 'NotAllowedError'
      ? 'Click anywhere to start the audio'
      : 'Could not play ' + file + ' — check /static/sounds/';
  }

  function playMusic() {
    if (mode !== 'full') return;
    music.volume = talking ? 0.08 : 0.3;
    if (!music.paused) return;

    music.play().then(() => {
      if (errorBox) errorBox.hidden = true;
    }).catch(err => showProblem('ambient.mp3', err));
  }

  function playClick() {
    if (mode !== 'full') return;

    const sound = clickSounds[clickIndex];
    clickIndex = (clickIndex + 1) % clickSounds.length;

    try {
      sound.pause();
      sound.currentTime = 0;
      sound.play().catch(err => showProblem('click_effect.mp3', err));
    } catch (err) {
      showProblem('click_effect.mp3', err);
    }
  }

  function updateButton() {
    if (!button) return;

    const next = modes[(modes.indexOf(mode) + 1) % modes.length];
    if (icon) icon.src = icons[mode];
    if (label) label.textContent = names[mode];
    button.title = names[mode];
    button.setAttribute('aria-label', names[mode] + ', switch to ' + names[next]);
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
      // Clicking the audio button counts as a browser sound interaction
      playMusic();
    } else {
      music.pause();
      for (const sound of clickSounds) {
        sound.pause();
        sound.currentTime = 0;
      }
    }

    document.dispatchEvent(new CustomEvent('nova:modechange', {
      detail: { mode }
    }));
  }

  // A delegated listener keeps working even if the navbar is replaced
  document.addEventListener('click', e => {
    if (!(e.target instanceof Element)) return;
    const audioButton = e.target.closest('#audioToggle');
    if (!audioButton) return;

    const next = modes[(modes.indexOf(mode) + 1) % modes.length];
    setMode(next);
    if (next === 'full') playClick();
  });

  function isClickable(target) {
    return target instanceof Element && Boolean(target.closest(
      'button, a, summary, select, canvas, [role="button"]'
    ));
  }

  // Play clicks before following links so navigation can't cut them off
  document.addEventListener('pointerdown', e => {
    if (mode !== 'full' || !(e.target instanceof Element)) return;
    playMusic();
    if (e.target.closest('#audioToggle, #novaTestSound')) return;
    if (isClickable(e.target)) playClick();
  }, true);

  // Enter and Space also work for keyboard users
  document.addEventListener('click', e => {
    if (mode !== 'full' || e.detail !== 0 || !(e.target instanceof Element)) return;
    if (e.target.closest('#audioToggle, #novaTestSound')) return;
    if (isClickable(e.target)) {
      playMusic();
      playClick();
    }
  }, true);

  // Browser autoplay is blocked sometimes — the first interaction resumes it
  document.addEventListener('pointerdown', playMusic, true);
  document.addEventListener('keydown', e => {
    if (e.key === 'Enter' || e.key === ' ') playMusic();
  }, true);

  document.addEventListener('click', e => {
    if (!(e.target instanceof Element) || !e.target.closest('#novaTestSound')) return;
    setMode('full');
    playClick();
    const status = document.getElementById('novaTestStatus');
    if (status) status.textContent = 'Testing music and click effects';
  });

  // The sky map and Ask NOVA already use these functions
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
  // Try right away, then resume after the first click if autoplay is blocked
  if (mode === 'full') playMusic();

  // Switch NOVA pages without reloading the browser
  // We keep old pages hidden in the document so their scripts still find them
  // This also keeps the same background song playing while you move around
  if (!main) return;

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
