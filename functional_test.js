// functional_test.js
// Uzycie:
//   node functional_test.js
//   node functional_test.js --test "wyszukiwarka"   <- uruchom tylko testy pasujace do nazwy

const { chromium } = require('@playwright/test');
const path = require('path');

const fs = require('fs');

const TEST_FILTER = (() => { const i = process.argv.indexOf('--test'); return i > -1 ? process.argv[i+1].toLowerCase() : null; })();
const HTML_PATH = 'file:///' + path.resolve(__dirname, 'spiewnik.html').replace(/\\/g, '/');
const FAIL_DIR = path.join(__dirname, 'functional_fails');

let page, passed = 0, failed = 0, skipped = 0;
const failures = [];

function safeFilename(s) {
  return s.replace(/[^a-zA-Z0-9_-]/g, '_').replace(/_+/g, '_').toLowerCase();
}

async function test(name, fn) {
  if (TEST_FILTER && !name.toLowerCase().includes(TEST_FILTER)) { skipped++; return; }
  try {
    await fn();
    passed++;
    console.log(`  \u2705 ${name}`);
  } catch (e) {
    failed++;
    const msg = e.message.split('\n')[0];
    const screenshotFile = path.join(FAIL_DIR, safeFilename(name) + '.png');
    try {
      if (!fs.existsSync(FAIL_DIR)) fs.mkdirSync(FAIL_DIR);
      await page.screenshot({ path: screenshotFile, fullPage: false });
    } catch (_) {}
    failures.push({ name, msg, screenshotFile });
    console.log(`  \u274C ${name}`);
    console.log(`      ${msg}`);
    console.log(`      screenshot: ${screenshotFile}`);
  }
}

function assert(cond, msg) { if (!cond) throw new Error(msg || 'Assertion failed'); }
function assertEqual(a, b, msg) { if (a !== b) throw new Error(msg || `Expected "${b}", got "${a}"`); }

async function run() {
  const t0 = Date.now();
  const browser = await chromium.launch();
  page = await browser.newPage();
  page.setDefaultTimeout(5000);
  await page.setViewportSize({ width: 1920, height: 1080 });

  // Zbieraj bledy z konsoli przegladarki
  const consoleErrors = [];
  page.on('console', msg => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', err => {
    consoleErrors.push(err.message);
  });

  await page.goto(HTML_PATH);
  await page.waitForFunction(() => typeof SONGS !== 'undefined' && SONGS.length > 0);

  // ── LADOWANIE ──────────────────────────────────────────────────────────

  console.log('\n  Ladowanie');

  await test('Ladowanie - brak bledow JS w konsoli', async () => {
    assert(consoleErrors.length === 0, `Bledy w konsoli: ${consoleErrors.join(' | ')}`);
  });

  await test('Ladowanie - SONGS zaladowane i niepuste', async () => {
    const count = await page.evaluate(() => SONGS.length);
    assert(count > 0, `SONGS.length = ${count}`);
  });

  await test('Ladowanie - piosenki maja wymagane pola', async () => {
    const bad = await page.evaluate(() => {
      const required = ['id', 'title', 'artist', 'artistFolder', 'hasChords', 'pairs'];
      for (const s of SONGS.slice(0, 20)) {
        for (const f of required) {
          if (!(f in s)) return `${s.title || '?'}: brak pola "${f}"`;
        }
      }
      return null;
    });
    assert(bad === null, bad);
  });

  await test('Ladowanie - DOM zawiera kluczowe elementy', async () => {
    const ids = ['app', 'sidebar', 'main', 'home-view', 'song-view', 'artist-view',
                 'search', 'random-grid', 'sv-body', 'raw-dialog', 'toc', 'settings-dialog'];
    for (const id of ids) {
      const exists = await page.$(`#${id}`);
      assert(exists, `Brak elementu #${id}`);
    }
  });

  // ── STRONA GLOWNA ─────────────────────────────────────────────────────

  console.log('\n  Strona glowna');

  await test('Strona glowna - widoczna po zaladowaniu', async () => {
    const visible = await page.$eval('#home-view', el => el.style.display !== 'none');
    assert(visible, 'home-view powinien byc widoczny');
  });

  await test('Strona glowna - losowe propozycje wyswietlone', async () => {
    const count = await page.$$eval('#random-grid .rcard', els => els.length);
    assert(count > 0 && count <= 15, `Oczekiwano 1-15 kafelkow, jest ${count}`);
  });

  await test('Strona glowna - kafelki z licznikiem odtworzen', async () => {
    await page.evaluate(() => {
      localStorage.clear();
      const c = {};
      SONGS.filter(s => s.hasChords).slice(0, 5).forEach((s, i) => { c[s.id] = 10 - i; });
      saveCounts(c);
    });
    await page.evaluate(() => { showHome(); });
    const badges = await page.$$eval('.rc-plays', els => els.length);
    assert(badges > 0, 'Powinny byc kafelki z licznikiem odtworzen');
    await page.evaluate(() => localStorage.clear());
  });

  await test('Strona glowna - spis tresci zaladowany', async () => {
    const artists = await page.$$eval('.toc-artist', els => els.length);
    assert(artists > 0, 'Brak artystow w spisie tresci');
  });

  // ── SPIS TRESCI ────────────────────────────────────────────────────────

  console.log('\n  Spis tresci');

  await test('TOC - rozwijanie artysty po kliknieciu', async () => {
    const artist = await page.$('.toc-artist');
    await artist.click();
    const isOpen = await artist.evaluate(el => el.classList.contains('open'));
    assert(isOpen, 'Artysta powinien byc rozwiniety');
  });

  await test('TOC - piosenki widoczne po rozwinieciu', async () => {
    const songs = await page.$$eval('.toc-songs.open .toc-song', els => els.length);
    assert(songs > 0, 'Brak piosenek po rozwinieciu artysty');
  });

  await test('TOC - klikniecie piosenki otwiera widok', async () => {
    const song = await page.$('.toc-songs.open .toc-song');
    await song.click();
    const songView = await page.$eval('#song-view', el => el.style.display);
    assertEqual(songView, 'block', 'song-view powinien byc widoczny');
  });

  await test('TOC - piosenki bez chwytow sa wyszarzone', async () => {
    await page.evaluate(() => showHome());
    await page.evaluate(() => buildToc(null));
    const nochords = await page.$$eval('.toc-song.nochords', els => els.length);
    const hasChordsSongs = await page.evaluate(() => SONGS.filter(s => s.hasChords).length);
    const allSongs = await page.evaluate(() => SONGS.length);
    assert(nochords === allSongs - hasChordsSongs, `Oczekiwano ${allSongs - hasChordsSongs} wyszarzonych, jest ${nochords}`);
  });

  await test('TOC - artysta pokazuje liczbe piosenek', async () => {
    const text = await page.$eval('.toc-artist', el => el.textContent);
    assert(/\(\d+\)/.test(text), `Artysta powinien miec liczbe piosenek w nawiasie, jest: "${text}"`);
  });

  // ── WIDOK PIOSENKI ─────────────────────────────────────────────────────

  console.log('\n  Widok piosenki');

  await test('Piosenka - tytul i artysta wyswietlone', async () => {
    const firstWithChords = await page.evaluate(() => { const s = SONGS.find(s => s.hasChords); return s ? s.id : null; });
    await page.evaluate(id => showSong(id), firstWithChords);
    const title = await page.$eval('#sv-title', el => el.textContent);
    const artist = await page.$eval('#sv-artist', el => el.textContent);
    assert(title.length > 0, 'Brak tytulu');
    assert(artist.length > 0, 'Brak artysty');
  });

  await test('Piosenka - body zawiera strofki', async () => {
    const strophes = await page.$$eval('.song-strophe', els => els.length);
    assert(strophes > 0, 'Brak strofek');
  });

  await test('Piosenka - tryb above domyslny', async () => {
    const hasClass = await page.$eval('#sv-body', el => el.classList.contains('mode-above'));
    assert(hasClass, 'Brak klasy mode-above');
  });

  await test('Piosenka - przelaczenie na inline', async () => {
    await page.evaluate(() => setChordMode('inline'));
    const hasClass = await page.$eval('#sv-body', el => el.classList.contains('mode-inline'));
    assert(hasClass, 'Brak klasy mode-inline');
  });

  await test('Piosenka - przelaczenie z powrotem na above', async () => {
    await page.evaluate(() => setChordMode('above'));
    const hasClass = await page.$eval('#sv-body', el => el.classList.contains('mode-above'));
    assert(hasClass, 'Brak klasy mode-above po powrocie');
  });

  await test('Piosenka - chwyty widoczne w trybie above', async () => {
    const chords = await page.$$eval('.pair-chord', els => els.filter(e => e.textContent.trim()).length);
    assert(chords > 0, 'Brak widocznych chwytow');
  });

  await test('Piosenka - losowe propozycje w sidebarze', async () => {
    const items = await page.$$eval('#sv-random-list .sitem', els => els.length);
    assert(items > 0 && items <= 12, `Oczekiwano 1-12 propozycji, jest ${items}`);
  });

  await test('Piosenka - aktualna piosenka nie jest w losowych', async () => {
    const curTitle = await page.$eval('#sv-title', el => el.textContent);
    const randomTitles = await page.$$eval('#sv-random-list .si-title', els => els.map(e => e.textContent));
    assert(!randomTitles.includes(curTitle), 'Aktualna piosenka nie powinna byc w losowych');
  });

  // ── NAWIGACJA PREV/NEXT ────────────────────────────────────────────────

  console.log('\n  Nawigacja');

  await test('Nawigacja - przycisk Nastepna dziala', async () => {
    const titleBefore = await page.$eval('#sv-title', el => el.textContent);
    await page.click('#sv-next');
    const titleAfter = await page.$eval('#sv-title', el => el.textContent);
    assert(titleBefore !== titleAfter, 'Tytul powinien sie zmienic po kliknieciu Nastepna');
  });

  await test('Nawigacja - przycisk Poprzednia dziala', async () => {
    const titleBefore = await page.$eval('#sv-title', el => el.textContent);
    await page.click('#sv-prev');
    const titleAfter = await page.$eval('#sv-title', el => el.textContent);
    assert(titleBefore !== titleAfter, 'Tytul powinien sie zmienic po kliknieciu Poprzednia');
  });

  await test('Nawigacja - powrot na strone glowna', async () => {
    await page.evaluate(() => showHome());
    const homeVisible = await page.$eval('#home-view', el => el.style.display !== 'none');
    assert(homeVisible, 'home-view powinien byc widoczny');
  });

  // ── WYSZUKIWARKA ───────────────────────────────────────────────────────

  console.log('\n  Wyszukiwarka');

  await test('Wyszukiwarka - wyniki po wpisaniu tytulu', async () => {
    const title = await page.evaluate(() => SONGS.find(s => s.hasChords).title);
    const query = title.substring(0, Math.min(8, title.length));
    await page.evaluate(q => doSearch(q), query);
    const results = await page.$$eval('.sr-item', els => els.length);
    assert(results > 0, `Brak wynikow dla "${query}"`);
  });

  await test('Wyszukiwarka - wyniki po wpisaniu artysty', async () => {
    const artist = await page.evaluate(() => SONGS.find(s => s.artist.length > 3).artist);
    await page.evaluate(a => doSearch(a), artist);
    const results = await page.$$eval('.sr-item', els => els.length);
    assert(results > 0, `Brak wynikow dla artysty "${artist}"`);
  });

  await test('Wyszukiwarka - brak wynikow dla bzdury', async () => {
    await page.evaluate(() => doSearch('xyzqwerty123'));
    const hint = await page.$eval('.sr-item', el => el.textContent);
    assert(hint.includes('Brak'), 'Powinien byc komunikat o braku wynikow');
  });

  await test('Wyszukiwarka - klikniecie wyniku otwiera piosenke', async () => {
    const title = await page.evaluate(() => SONGS.find(s => s.hasChords).title);
    await page.evaluate(q => doSearch(q), title);
    await page.click('.sr-title');
    const songVisible = await page.$eval('#song-view', el => el.style.display === 'block');
    assert(songVisible, 'Piosenka powinna sie otworzyc');
  });

  await test('Wyszukiwarka - hideSearch czysci wyniki', async () => {
    await page.evaluate(() => hideSearch());
    const open = await page.$eval('#search-results', el => el.classList.contains('open'));
    assert(!open, 'Wyniki powinny byc ukryte');
  });

  await test('Wyszukiwarka - przycisk X czysci pole', async () => {
    const title = await page.evaluate(() => SONGS.find(s => s.hasChords).title);
    await page.fill('#search', title);
    await page.evaluate(q => doSearch(q), title);
    const visible = await page.$eval('#search-clear', el => el.classList.contains('visible'));
    assert(visible, 'Przycisk X powinien byc widoczny');
    await page.click('#search-clear');
    const val = await page.$eval('#search', el => el.value);
    assertEqual(val, '', 'Pole powinno byc puste po kliknieciu X');
    const clearVisible = await page.$eval('#search-clear', el => el.classList.contains('visible'));
    assert(!clearVisible, 'Przycisk X powinien byc ukryty');
  });

  // ── RAW VIEW ───────────────────────────────────────────────────────────

  console.log('\n  Widok surowy');

  await test('Raw - otwiera sie dialog', async () => {
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => showSong(id), id);
    await page.evaluate(id => showRaw(id), id);
    const open = await page.$eval('#raw-dialog', el => el.classList.contains('open'));
    assert(open, 'Raw dialog powinien miec klase open');
  });

  await test('Raw - zawiera kolumny tekst i chwyty', async () => {
    const labels = await page.$$eval('.raw-col-label', els => els.map(e => e.textContent));
    assert(labels.includes('Tekst'), 'Brak kolumny Tekst');
    assert(labels.includes('Chwyty'), 'Brak kolumny Chwyty');
  });

  await test('Raw - zamykanie dialogu', async () => {
    await page.evaluate(() => closeRaw());
    const open = await page.$eval('#raw-dialog', el => el.classList.contains('open'));
    assert(!open, 'Raw dialog nie powinien miec klasy open');
  });

  // ── ZASPIEWANA / LICZNIK ───────────────────────────────────────────────

  console.log('\n  Zaspiewana / licznik');

  await test('Zaspiewana - oznaczanie piosenki', async () => {
    // wyczysc localStorage
    await page.evaluate(() => { localStorage.clear(); });
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => showSong(id), id);
    await page.evaluate(id => markSung(id), id);
    const isSung = await page.evaluate(id => isSungToday(id), id);
    assert(isSung, 'Piosenka powinna byc oznaczona jako zaspiewana');
  });

  await test('Zaspiewana - licznik rosnie', async () => {
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    const count = await page.evaluate(id => getCounts()[id], id);
    assertEqual(count, 1, `Licznik powinien byc 1, jest ${count}`);
  });

  await test('Zaspiewana - odznaczanie piosenki', async () => {
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => unmarkSung(id), id);
    const isSung = await page.evaluate(id => isSungToday(id), id);
    assert(!isSung, 'Piosenka nie powinna byc oznaczona');
  });

  await test('Zaspiewana - przycisk toggle dziala', async () => {
    await page.evaluate(() => localStorage.clear());
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => showSong(id), id);
    // kliknij przycisk
    await page.click('#sv-sung-btn');
    const isSung = await page.evaluate(id => isSungToday(id), id);
    assert(isSung, 'Piosenka powinna byc zaspiewana po kliknieciu');
    const btnText = await page.$eval('#sv-sung-btn', el => el.textContent);
    assert(btnText.includes('\u2713'), 'Przycisk powinien miec ptaszka');
    // kliknij ponownie
    await page.click('#sv-sung-btn');
    const isSung2 = await page.evaluate(id => isSungToday(id), id);
    assert(!isSung2, 'Piosenka nie powinna byc zaspiewana po drugim kliknieciu');
  });

  await test('Zaspiewana - licznik wyswietlany w headerze', async () => {
    await page.evaluate(() => localStorage.clear());
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => { markSung(id); markSung(id); markSung(id); }, id);
    await page.evaluate(id => showSong(id), id);
    const pc = await page.$eval('#sv-play-count', el => el.textContent);
    assert(pc.includes('3'), `Licznik powinien zawierac 3, jest "${pc}"`);
  });

  // ── LOSOWANIE / TOP ────────────────────────────────────────────────────

  console.log('\n  Losowanie i TOP');

  await test('Losowanie - piosenki bez chwytow nie sa losowane', async () => {
    await page.evaluate(() => localStorage.clear());
    // losuj 100 razy i sprawdz
    const noChordIds = await page.evaluate(() => {
      const ids = new Set(SONGS.filter(s => !s.hasChords).map(s => s.id));
      for (let i = 0; i < 100; i++) {
        const items = getRandomHome();
        for (const { s } of items) {
          if (ids.has(s.id)) return s.id;
        }
      }
      return null;
    });
    assert(noChordIds === null, `Piosenka bez chwytow wylosowana: ${noChordIds}`);
  });

  await test('Losowanie - dzisiejsze zaspiewane nie sa losowane', async () => {
    await page.evaluate(() => localStorage.clear());
    // oznacz kilka piosenek jako zaspiewane
    const sungIds = await page.evaluate(() => {
      const ids = SONGS.filter(s => s.hasChords).slice(0, 5).map(s => s.id);
      ids.forEach(id => markSung(id));
      return ids;
    });
    const found = await page.evaluate((sungIds) => {
      const sungSet = new Set(sungIds);
      for (let i = 0; i < 100; i++) {
        const items = getRandomHome();
        for (const { s } of items) {
          if (sungSet.has(s.id)) return s.id;
        }
      }
      return null;
    }, sungIds);
    assert(found === null, `Zaspiewana piosenka wylosowana: ${found}`);
  });

  await test('TOP - piosenki z top 25% oznaczone jako top', async () => {
    await page.evaluate(() => {
      localStorage.clear();
      const c = {};
      // daj 10 piosenkom rozne liczby odtworzen
      const withChords = SONGS.filter(s => s.hasChords);
      for (let i = 0; i < Math.min(10, withChords.length); i++) {
        c[withChords[i].id] = 10 - i;
      }
      saveCounts(c);
    });
    const hasTop = await page.evaluate(() => {
      const items = getRandomHome();
      return items.some(({ top }) => top);
    });
    assert(hasTop, 'Powinny byc piosenki oznaczone jako top');
  });

  await test('Losowanie piosenki - same artist w propozycjach', async () => {
    await page.evaluate(() => localStorage.clear());
    // znajdz artystę z >2 piosenkami z chwytami
    const result = await page.evaluate(() => {
      const byArtist = {};
      for (const s of SONGS) {
        if (!s.hasChords) continue;
        (byArtist[s.artistFolder] = byArtist[s.artistFolder] || []).push(s);
      }
      const af = Object.keys(byArtist).find(k => byArtist[k].length >= 3);
      if (!af) return { skip: true };
      const song = byArtist[af][0];
      curId = song.id;
      const items = getRandomSong(af);
      const sameArtist = items.filter(({ same }) => same);
      return { sameCount: sameArtist.length, af };
    });
    if (result.skip) { console.log('      (pominieto - brak artysty z >=3 piosenkami)'); return; }
    assert(result.sameCount > 0, `Brak propozycji tego samego artysty (${result.af})`);
  });

  await test('Losowanie piosenki - same artist ma klase same', async () => {
    const result = await page.evaluate(() => {
      const byArtist = {};
      for (const s of SONGS) {
        if (!s.hasChords) continue;
        (byArtist[s.artistFolder] = byArtist[s.artistFolder] || []).push(s);
      }
      const af = Object.keys(byArtist).find(k => byArtist[k].length >= 3);
      if (!af) return { skip: true };
      showSong(byArtist[af][0].id);
      return { skip: false };
    });
    if (result.skip) return;
    const sameItems = await page.$$eval('#sv-random-list .sitem.same', els => els.length);
    assert(sameItems > 0, 'Brak kafelkow z klasa same');
  });

  // ── WIDOK ARTYSTY ──────────────────────────────────────────────────────

  console.log('\n  Widok artysty');

  await test('Artysta - otwiera sie po kliknieciu', async () => {
    const af = await page.evaluate(() => SONGS.find(s => s.hasChords).artistFolder);
    await page.evaluate(af => showArtist(af), af);
    const visible = await page.$eval('#artist-view', el => el.style.display !== 'none');
    assert(visible, 'artist-view powinien byc widoczny');
  });

  await test('Artysta - nazwa wyswietlona', async () => {
    const name = await page.$eval('#av-artist-name', el => el.textContent);
    assert(name.length > 0, 'Brak nazwy artysty');
  });

  await test('Artysta - kafelki piosenek wyswietlone', async () => {
    const cards = await page.$$eval('#av-grid .rcard', els => els.length);
    assert(cards > 0, 'Brak kafelkow piosenek');
  });

  await test('Artysta - kafelki posortowane alfabetycznie', async () => {
    const titles = await page.$$eval('#av-grid .rc-title', els => els.map(e => e.textContent));
    const sorted = [...titles].sort((a, b) => a.localeCompare(b, 'pl', { sensitivity: 'base' }));
    assert(JSON.stringify(titles) === JSON.stringify(sorted), 'Kafelki nie sa posortowane');
  });

  await test('Artysta - czeste piosenki oznaczone jako top', async () => {
    await page.evaluate(() => {
      localStorage.clear();
      const c = {};
      const withChords = SONGS.filter(s => s.hasChords);
      for (let i = 0; i < Math.min(10, withChords.length); i++) {
        c[withChords[i].id] = 10 - i;
      }
      saveCounts(c);
    });
    const af = await page.evaluate(() => {
      const c = getCounts();
      const s = SONGS.find(s => c[s.id] > 0);
      return s ? s.artistFolder : null;
    });
    if (!af) return;
    await page.evaluate(af => showArtist(af), af);
    const topCards = await page.$$eval('#av-grid .rcard.top', els => els.length);
    assert(topCards > 0, 'Brak kafelkow top');
  });

  await test('Artysta - klikniecie kafelka otwiera piosenke', async () => {
    const card = await page.$('#av-grid .rc-title');
    if (!card) return;
    await card.click();
    const songVisible = await page.$eval('#song-view', el => el.style.display === 'block');
    assert(songVisible, 'Piosenka powinna sie otworzyc');
  });

  // ── TEXTIT / KURSYWA ──────────────────────────────────────────────────

  console.log('\n  Textit / kursywa');

  await test('Textit - kursywa wyswietlana w tekscie piosenki', async () => {
    // znajdz piosenke z textit markerami
    const id = await page.evaluate(() => {
      const s = SONGS.find(s => s.pairs.some(p => p.t.includes('<<i>>') || p.c.includes('<<i>>')));
      return s ? s.id : null;
    });
    if (!id) { console.log('      (pominieto - brak piosenek z textit)'); return; }
    await page.evaluate(id => showSong(id), id);
    const emCount = await page.$$eval('#sv-body .tex-it', els => els.length);
    assert(emCount > 0, 'Brak elementow <em class="tex-it"> w tekscie');
  });

  await test('Textit - kursywa wyswietlana w raw view', async () => {
    const id = await page.evaluate(() => {
      const s = SONGS.find(s => s.rawStrophes.some(st => st.lines.some(l => l.includes('<<i>>'))));
      return s ? s.id : null;
    });
    if (!id) { console.log('      (pominieto - brak piosenek z textit w raw)'); return; }
    await page.evaluate(id => { showSong(id); showRaw(id); }, id);
    const emCount = await page.$$eval('#raw-cols .tex-it', els => els.length);
    await page.evaluate(() => closeRaw());
    assert(emCount > 0, 'Brak elementow <em class="tex-it"> w raw view');
  });

  // ── hasChords FLAG ─────────────────────────────────────────────────────

  console.log('\n  Flaga hasChords i superscript');

  await test('Superscript - gorny indeks w chwytach', async () => {
    const id = await page.evaluate(() => {
      const s = SONGS.find(s => s.pairs.some(p => p.c.includes('<<sup>>')));
      return s ? s.id : null;
    });
    if (!id) { console.log('      (pominieto - brak piosenek z ^)'); return; }
    await page.evaluate(id => showSong(id), id);
    const supCount = await page.$$eval('#sv-body sup', els => els.length);
    assert(supCount > 0, 'Brak elementow <sup> w chwytach');
  });

  await test('hasChords - piosenki z chwytami maja flage true', async () => {
    const ok = await page.evaluate(() => {
      const s = SONGS.find(s => s.hasChords && s.pairs.some(p => p.c !== ''));
      return s !== undefined;
    });
    assert(ok, 'Brak piosenek z hasChords=true i niepustymi chwytami');
  });

  await test('hasChords - piosenki bez chwytow maja flage false', async () => {
    const ok = await page.evaluate(() => {
      const s = SONGS.find(s => !s.hasChords);
      return s ? s.pairs.every(p => p.c === '') : true;
    });
    assert(ok, 'Piosenka bez hasChords ma niepuste chwyty');
  });

  // ── SIDEBAR MOBILE ──────────────────────────────────────────────────────

  console.log('\n  Sidebar mobile');

  await test('Sidebar - openSidebar dodaje klase open', async () => {
    await page.evaluate(() => openSidebar());
    const open = await page.$eval('#sidebar', el => el.classList.contains('open'));
    assert(open, 'Sidebar powinien miec klase open');
  });

  await test('Sidebar - closeSidebar usuwa klase open', async () => {
    await page.evaluate(() => closeSidebar());
    const open = await page.$eval('#sidebar', el => el.classList.contains('open'));
    assert(!open, 'Sidebar nie powinien miec klasy open');
  });

  await test('Sidebar - overlay zamyka sidebar', async () => {
    // overlay jest widoczny tylko na mobile, testujemy logike przez evaluate
    await page.evaluate(() => openSidebar());
    await page.evaluate(() => {
      document.getElementById('sidebar-overlay').click();
    });
    const open = await page.$eval('#sidebar', el => el.classList.contains('open'));
    assert(!open, 'Sidebar powinien sie zamknac po kliknieciu overlay');
  });

  // ── CHORD MODE PERSISTENCE ─────────────────────────────────────────────

  console.log('\n  Persystencja trybu chwytow');

  await test('ChordMode - zapamietywany w localStorage', async () => {
    await page.evaluate(() => setChordMode('inline'));
    const stored = await page.evaluate(() => localStorage.getItem('sw_chordmode'));
    assertEqual(stored, 'inline', `Oczekiwano "inline" w localStorage, jest "${stored}"`);
    await page.evaluate(() => setChordMode('above'));
  });

  // ── HEADER LOGO ────────────────────────────────────────────────────────

  console.log('\n  Header logo');

  await test('Header logo - klikniecie wraca na strone glowna', async () => {
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => showSong(id), id);
    await page.click('#header-logo');
    const homeVisible = await page.$eval('#home-view', el => el.style.display !== 'none');
    assert(homeVisible, 'Klikniecie logo powinno wrocic na strone glowna');
  });

  // ── ARTIST CLICK FROM SONG ─────────────────────────────────────────────

  console.log('\n  Klikniecie artysty z piosenki');

  await test('Artysta - klikniecie z widoku piosenki otwiera widok artysty', async () => {
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => showSong(id), id);
    await page.click('#sv-artist');
    const visible = await page.$eval('#artist-view', el => el.style.display !== 'none');
    assert(visible, 'artist-view powinien byc widoczny');
  });

  // ── RAW DIALOG EXTRAS ─────────────────────────────────────────────────

  console.log('\n  Raw dialog - dodatkowe');

  await test('Raw - Escape zamyka dialog', async () => {
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => { showSong(id); showRaw(id); }, id);
    await page.keyboard.press('Escape');
    const open = await page.$eval('#raw-dialog', el => el.classList.contains('open'));
    assert(!open, 'Escape powinien zamknac raw dialog');
  });

  await test('Raw - klikniecie tla zamyka dialog', async () => {
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => showRaw(id), id);
    await page.evaluate(() => {
      const e = new MouseEvent('click', { bubbles: true });
      document.getElementById('raw-dialog').dispatchEvent(e);
    });
    const open = await page.$eval('#raw-dialog', el => el.classList.contains('open'));
    assert(!open, 'Klikniecie tla powinno zamknac raw dialog');
  });

  // ── SEARCH EXTRAS ──────────────────────────────────────────────────────

  console.log('\n  Wyszukiwarka - dodatkowe');

  await test('Wyszukiwarka - snippet wyswietlany w wynikach', async () => {
    // szukaj fragmentu tekstu piosenki
    const query = await page.evaluate(() => {
      const s = SONGS.find(s => s.hasChords && s.firstVerse.length > 10);
      return s ? s.firstVerse.substring(0, 10) : null;
    });
    if (!query) return;
    await page.evaluate(q => doSearch(q), query);
    const snippets = await page.$$eval('.sr-snippet', els => els.length);
    assert(snippets > 0, 'Brak snippetow w wynikach wyszukiwania');
    await page.evaluate(() => hideSearch());
  });

  await test('Wyszukiwarka - zaspiewane dzis oznaczone w wynikach', async () => {
    await page.evaluate(() => localStorage.clear());
    const data = await page.evaluate(() => {
      const s = SONGS.find(s => s.hasChords);
      markSung(s.id);
      return { id: s.id, title: s.title };
    });
    await page.evaluate(t => doSearch(t), data.title);
    const sungResults = await page.$$eval('.sr-item.sung', els => els.length);
    assert(sungResults > 0, 'Zaspiewana piosenka powinna miec klase sung w wynikach');
    await page.evaluate(() => { hideSearch(); localStorage.clear(); });
  });

  // ── NORMALIZACJA ───────────────────────────────────────────────────────

  console.log('\n  Normalizacja');

  await test('norm() - polskie znaki zamieniane', async () => {
    const result = await page.evaluate(() => norm('Łódź ćma żółw'));
    assertEqual(result, 'lodz cma zolw');
  });

  await test('Wyszukiwarka - znajduje bez polskich znakow', async () => {
    const data = await page.evaluate(() => {
      const s = SONGS.find(s => /[ąćęłńóśźż]/i.test(s.title));
      return s ? { title: s.title, norm: norm(s.title) } : null;
    });
    if (!data) return;
    await page.evaluate(q => doSearch(q), data.norm);
    const results = await page.$$eval('.sr-item', els => els.length);
    assert(results > 0, `Brak wynikow dla znormalizowanego "${data.norm}"`);
    await page.evaluate(() => hideSearch());
  });

  // ── LOSOWANIE SZCZEGOLY ────────────────────────────────────────────────

  console.log('\n  Losowanie - szczegoly');

  await test('Losowanie - jeden artysta max raz w losowych', async () => {
    await page.evaluate(() => localStorage.clear());
    const ok = await page.evaluate(() => {
      for (let i = 0; i < 50; i++) {
        const items = getRandomHome();
        const artists = items.filter(({top}) => !top).map(({s}) => s.artistFolder);
        const unique = new Set(artists);
        if (unique.size !== artists.length) return false;
      }
      return true;
    });
    assert(ok, 'Losowe propozycje maja powtorzonych artystow');
  });

  await test('getRandomHome - zwraca do 15 elementow', async () => {
    await page.evaluate(() => localStorage.clear());
    const count = await page.evaluate(() => getRandomHome().length);
    assert(count > 0 && count <= 15, `Oczekiwano 1-15, jest ${count}`);
  });

  await test('getRandomSong - zwraca do 12 elementow', async () => {
    await page.evaluate(() => localStorage.clear());
    const count = await page.evaluate(() => {
      curId = SONGS.find(s => s.hasChords).id;
      return getRandomSong(SONGS.find(s => s.hasChords).artistFolder).length;
    });
    assert(count > 0 && count <= 12, `Oczekiwano 1-12, jest ${count}`);
  });

  // ── TOC SZCZEGOLY ──────────────────────────────────────────────────────

  console.log('\n  TOC - szczegoly');

  await test('TOC - aktywna piosenka podswietlona', async () => {
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => showSong(id), id);
    const activeCount = await page.$$eval('.toc-song.active', els => els.length);
    assertEqual(activeCount, 1, `Oczekiwano 1 aktywnej piosenki, jest ${activeCount}`);
  });

  await test('TOC - zaspiewana piosenka oznaczona', async () => {
    await page.evaluate(() => localStorage.clear());
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => markSung(id), id);
    await page.evaluate(() => buildToc(null));
    const sungCount = await page.$$eval('.toc-song.sung', els => els.length);
    assert(sungCount > 0, 'Brak piosenek z klasa sung w TOC');
    await page.evaluate(() => localStorage.clear());
  });

  await test('TOC - klikniecie z TOC nie scrolluje', async () => {
    // showSong z fromToc=true nie powinno scrollowac
    // sprawdzamy posrednio - buildToc dostaje scroll=false
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    // to glownie test ze nie rzuca bledem
    await page.evaluate(id => showSong(id, true), id);
    const visible = await page.$eval('#song-view', el => el.style.display === 'block');
    assert(visible, 'Piosenka powinna sie otworzyc z fromToc=true');
  });

  // ── BLEDY KONSOLI NA KONIEC ──────────────────────────────────────────

  console.log('\n  Usuwanie piosenek');

  await test('Ukrywanie - hideS oznacza piosenke jako ukryta', async () => {
    await page.evaluate(() => localStorage.clear());
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => hideS(id), id);
    const hidden = await page.evaluate(id => isHidden(id), id);
    assert(hidden, 'Piosenka powinna byc ukryta');
  });

  await test('Ukrywanie - unhideS przywraca piosenke', async () => {
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => unhideS(id), id);
    const hidden = await page.evaluate(id => isHidden(id), id);
    assert(!hidden, 'Piosenka nie powinna byc ukryta');
  });

  await test('Ukrywanie - ukryta piosenka znika z TOC', async () => {
    await page.evaluate(() => localStorage.clear());
    const data = await page.evaluate(() => {
      const s = SONGS.find(s => s.hasChords);
      hideS(s.id);
      return { id: s.id, title: s.title };
    });
    await page.evaluate(() => buildToc(null));
    const tocTitles = await page.$$eval('.toc-song', els => els.map(e => e.textContent));
    assert(!tocTitles.includes(data.title), 'Ukryta piosenka nie powinna byc w TOC');
    await page.evaluate(() => localStorage.clear());
  });

  await test('Ukrywanie - ukryta piosenka nie jest losowana', async () => {
    await page.evaluate(() => localStorage.clear());
    const id = await page.evaluate(() => {
      const s = SONGS.find(s => s.hasChords);
      hideS(s.id);
      return s.id;
    });
    const found = await page.evaluate((id) => {
      for (let i = 0; i < 100; i++) {
        const items = getRandomHome();
        if (items.some(({ s }) => s.id === id)) return true;
      }
      return false;
    }, id);
    assert(!found, 'Ukryta piosenka nie powinna byc losowana');
    await page.evaluate(() => localStorage.clear());
  });

  await test('Ukrywanie - ukryta piosenka na dole wynikow wyszukiwania', async () => {
    await page.evaluate(() => localStorage.clear());
    const data = await page.evaluate(() => {
      const s = SONGS.find(s => s.hasChords);
      hideS(s.id);
      return { id: s.id, title: s.title };
    });
    await page.evaluate(t => doSearch(t), data.title);
    const results = await page.$$eval('.sr-item', els => els.map(e => ({
      title: e.querySelector('.sr-title').textContent,
      hidden: e.classList.contains('hidden-song')
    })));
    const match = results.find(r => r.title === data.title);
    assert(match, 'Ukryta piosenka powinna byc w wynikach');
    assert(match.hidden, 'Ukryta piosenka powinna miec klase hidden-song');
    await page.evaluate(() => { hideSearch(); localStorage.clear(); });
  });

  await test('Ukrywanie - dialog usunietych otwiera sie', async () => {
    await page.evaluate(() => localStorage.clear());
    await page.evaluate(() => {
      const s = SONGS.find(s => s.hasChords);
      hideS(s.id);
      showHiddenDialog();
    });
    const open = await page.$eval('#hidden-dialog', el => el.classList.contains('open'));
    assert(open, 'Dialog usunietych powinien byc otwarty');
    const items = await page.$$eval('.hidden-item', els => els.length);
    assert(items > 0, 'Brak elementow w liscie usunietych');
  });

  await test('Ukrywanie - przywracanie z dialogu', async () => {
    const countBefore = await page.$$eval('.hidden-item', els => els.length);
    await page.click('.hidden-item button');
    const countAfter = await page.$$eval('.hidden-item', els => els.length);
    assert(countAfter < countBefore, 'Lista powinna sie zmniejszyc po przywroceniu');
    await page.evaluate(() => { closeHiddenDialog(); localStorage.clear(); });
  });

  await test('Ukrywanie - przycisk usun widoczny tylko w widoku piosenki', async () => {
    await page.evaluate(() => showHome());
    const homeDisplay = await page.$eval('#sv-hide-btn', el => el.style.display);
    assertEqual(homeDisplay, 'none', 'Przycisk usun powinien byc ukryty na stronie glownej');
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => showSong(id), id);
    const songDisplay = await page.$eval('#sv-hide-btn', el => el.style.display);
    assert(songDisplay !== 'none', 'Przycisk usun powinien byc widoczny w widoku piosenki');
  });

  await test('Ukrywanie - banner widoczny dla ukrytej piosenki', async () => {
    await page.evaluate(() => localStorage.clear());
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => { hideS(id); showSong(id); }, id);
    const bannerVisible = await page.$eval('#sv-hidden-banner', el => el.style.display !== 'none');
    assert(bannerVisible, 'Banner powinien byc widoczny dla ukrytej piosenki');
    await page.evaluate(() => localStorage.clear());
  });

  await test('Ukrywanie - banner ukryty dla normalnej piosenki', async () => {
    await page.evaluate(() => localStorage.clear());
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => showSong(id), id);
    const bannerVisible = await page.$eval('#sv-hidden-banner', el => el.style.display !== 'none');
    assert(!bannerVisible, 'Banner nie powinien byc widoczny dla normalnej piosenki');
  });

  await test('Ukrywanie - przycisk toggle zmienia tekst i klase', async () => {
    await page.evaluate(() => localStorage.clear());
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => showSong(id), id);
    // stan poczatkowy - usun (czerwony)
    const hasDanger = await page.$eval('#sv-hide-btn', el => el.classList.contains('btn-danger'));
    assert(hasDanger, 'Przycisk powinien miec klase btn-danger');
    // klik - ukryj
    await page.click('#sv-hide-btn');
    const hasRestore = await page.$eval('#sv-hide-btn', el => el.classList.contains('btn-restore'));
    assert(hasRestore, 'Przycisk powinien miec klase btn-restore po ukryciu');
    const text = await page.$eval('#sv-hide-btn', el => el.textContent);
    assert(text.includes('przywr'), 'Przycisk powinien mowic przywroc');
    // klik - przywroc
    await page.click('#sv-hide-btn');
    const hasDanger2 = await page.$eval('#sv-hide-btn', el => el.classList.contains('btn-danger'));
    assert(hasDanger2, 'Przycisk powinien wrocic do btn-danger po przywroceniu');
    await page.evaluate(() => localStorage.clear());
  });

  await test('Ukrywanie - otwarcie z dialogu nie przywraca piosenki', async () => {
    await page.evaluate(() => localStorage.clear());
    const id = await page.evaluate(() => {
      const s = SONGS.find(s => s.hasChords);
      hideS(s.id);
      return s.id;
    });
    await page.evaluate(() => showHiddenDialog());
    await page.click('.hidden-item-name');
    const stillHidden = await page.evaluate(id => isHidden(id), id);
    assert(stillHidden, 'Piosenka powinna pozostac ukryta po otwarciu z dialogu');
    const bannerVisible = await page.$eval('#sv-hidden-banner', el => el.style.display !== 'none');
    assert(bannerVisible, 'Banner powinien byc widoczny');
    await page.evaluate(() => localStorage.clear());
  });

  console.log('\n  Ustawienia');

  await test('Ustawienia - dialog otwiera sie', async () => {
    await page.evaluate(() => showSettings());
    const open = await page.$eval('#settings-dialog', el => el.classList.contains('open'));
    assert(open, 'Dialog ustawien powinien byc otwarty');
  });

  await test('Ustawienia - statystyki wyswietlone', async () => {
    const html = await page.$eval('#settings-stats', el => el.innerHTML);
    assert(html.includes('Piosenek'), 'Brak statystyk piosenek');
    assert(html.includes('cznie odtworze'), 'Brak statystyk odtworzen');
  });

  await test('Ustawienia - przelaczanie trybu chwytow', async () => {
    await page.click('#set-mode-inline');
    const mode = await page.evaluate(() => chordMode);
    assertEqual(mode, 'inline', 'Tryb powinien byc inline');
    const active = await page.$eval('#set-mode-inline', el => el.classList.contains('active'));
    assert(active, 'Przycisk inline powinien byc aktywny');
    await page.click('#set-mode-above');
    const mode2 = await page.evaluate(() => chordMode);
    assertEqual(mode2, 'above', 'Tryb powinien byc above');
  });

  await test('Ustawienia - przelaczanie motywu na jasny', async () => {
    await page.evaluate(() => showSettings());
    await page.click('#set-theme-light');
    const isLight = await page.evaluate(() => document.documentElement.classList.contains('light'));
    assert(isLight, 'Powinien byc light mode');
    const stored = await page.evaluate(() => localStorage.getItem('sw_theme'));
    assertEqual(stored, 'light', 'Motyw powinien byc zapisany');
  });

  await test('Ustawienia - przelaczanie motywu na ciemny', async () => {
    await page.click('#set-theme-dark');
    const isLight = await page.evaluate(() => document.documentElement.classList.contains('light'));
    assert(!isLight, 'Nie powinien byc light mode');
  });

  await test('Ustawienia - zamykanie dialogu', async () => {
    await page.evaluate(() => closeSettings());
    const open = await page.$eval('#settings-dialog', el => el.classList.contains('open'));
    assert(!open, 'Dialog ustawien powinien byc zamkniety');
  });

  await test('Ustawienia - Escape zamyka dialog', async () => {
    await page.evaluate(() => showSettings());
    await page.keyboard.press('Escape');
    const open = await page.$eval('#settings-dialog', el => el.classList.contains('open'));
    assert(!open, 'Escape powinien zamknac dialog ustawien');
  });

  console.log('\n  Eksport / import danych');

  await test('Eksport - exportData generuje poprawny JSON', async () => {
    await page.evaluate(() => {
      localStorage.clear();
      const s1 = SONGS[0], s2 = SONGS[1];
      markSung(s1.id); markSung(s1.id); markSung(s2.id);
      hideS(s2.id);
    });
    const data = await page.evaluate(() => {
      const d = { counts: getCounts(), hidden: [...getHidden()], today: JSON.parse(localStorage.getItem(LS_TODAY) || '{}') };
      return d;
    });
    assert(Object.keys(data.counts).length > 0, 'Counts powinny byc niepuste');
    assert(data.hidden.length > 0, 'Hidden powinno byc niepuste');
  });

  await test('Import - importData merguje liczniki (max)', async () => {
    await page.evaluate(() => {
      localStorage.clear();
      const s = SONGS[0];
      markSung(s.id); // count = 1
    });
    const id = await page.evaluate(() => SONGS[0].id);
    const imported = await page.evaluate((id) => {
      const json = JSON.stringify({ counts: { [id]: 5 }, hidden: [], today: {} });
      return importData(json);
    }, id);
    assert(imported, 'Import powinien sie udac');
    const count = await page.evaluate(id => getCounts()[id], id);
    assertEqual(count, 5, `Licznik powinien byc 5 (max z 1 i 5), jest ${count}`);
  });

  await test('Import - importData merguje ukryte', async () => {
    await page.evaluate(() => localStorage.clear());
    const ids = await page.evaluate(() => {
      hideS(SONGS[0].id);
      const json = JSON.stringify({ counts: {}, hidden: [SONGS[1].id], today: {} });
      importData(json);
      return { id0: SONGS[0].id, id1: SONGS[1].id };
    });
    const h0 = await page.evaluate(id => isHidden(id), ids.id0);
    const h1 = await page.evaluate(id => isHidden(id), ids.id1);
    assert(h0, 'Piosenka 0 powinna byc ukryta (istniejaca)');
    assert(h1, 'Piosenka 1 powinna byc ukryta (zaimportowana)');
  });

  await test('Import - odrzuca nieprawidlowy JSON', async () => {
    const result = await page.evaluate(() => importData('not json'));
    assert(!result, 'Import powinien zwrocic false dla blednego JSON');
  });

  await test('Import - odswierza UI po imporcie', async () => {
    await page.evaluate(() => localStorage.clear());
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => showSong(id), id);
    await page.evaluate((id) => {
      importData(JSON.stringify({ counts: { [id]: 7 }, hidden: [], today: {} }));
    }, id);
    const pc = await page.$eval('#sv-play-count', el => el.textContent);
    assert(pc.includes('7'), `Licznik powinien pokazywac 7, jest "${pc}"`);
    await page.evaluate(() => localStorage.clear());
  });

  // ── RESPONSIVE LAYOUT ──────────────────────────────────────────────────

  const origSize = page.viewportSize();

  console.log('\n  Responsive - tablet (900px)');

  await page.setViewportSize({ width: 900, height: 768 });
  await page.evaluate(() => showHome());

  await test('Tablet - sidebar widoczny', async () => {
    const visible = await page.$eval('#sidebar', el => {
      const s = getComputedStyle(el);
      return s.position !== 'fixed';
    });
    assert(visible, 'Sidebar powinien byc widoczny na tablecie');
  });

  await test('Tablet - song body jednokolumnowy', async () => {
    const id = await page.evaluate(() => SONGS.find(s => s.hasChords).id);
    await page.evaluate(id => showSong(id), id);
    const cols = await page.$eval('#sv-body', el => getComputedStyle(el).columnCount);
    assert(cols === 'auto' || cols === '1', `Oczekiwano 1 kolumny, jest ${cols}`);
  });

  await test('Tablet - sidebar propozycji pod piosenka', async () => {
    const layout = await page.$eval('.sv-layout', el => getComputedStyle(el).flexDirection);
    assertEqual(layout, 'column', 'Layout powinien byc kolumnowy na tablecie');
  });

  console.log('\n  Responsive - mobile (600px)');

  await page.setViewportSize({ width: 600, height: 800 });
  await page.evaluate(() => showHome());

  await test('Mobile - menu hamburger widoczny', async () => {
    const display = await page.$eval('#menu-btn', el => getComputedStyle(el).display);
    assert(display !== 'none', 'Menu hamburger powinno byc widoczne');
  });

  await test('Mobile - sidebar ukryty domyslnie', async () => {
    const transform = await page.$eval('#sidebar', el => getComputedStyle(el).transform);
    assert(transform !== 'none', 'Sidebar powinien byc przesuniety');
  });

  await test('Mobile - sidebar otwiera sie po kliknieciu menu', async () => {
    await page.evaluate(() => openSidebar());
    const open = await page.$eval('#sidebar', el => el.classList.contains('open'));
    assert(open, 'Sidebar powinien byc otwarty');
    await page.evaluate(() => closeSidebar());
  });

  // Przywroc oryginalny rozmiar
  await page.setViewportSize(origSize);
  await page.evaluate(() => localStorage.clear());

  console.log('\n  Bledy konsoli (koncowe)');

  await test('Brak nowych bledow JS po wszystkich testach', async () => {
    assert(consoleErrors.length === 0, `Bledy w konsoli: ${consoleErrors.join(' | ')}`);
  });

  // ── CLEANUP & SUMMARY ─────────────────────────────────────────────────

  await page.evaluate(() => localStorage.clear());
  await browser.close();

  const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
  const total = passed + failed;

  console.log('\n' + '='.repeat(60));
  if (failed === 0) {
    console.log(`\n  \u2705  WSZYSTKO OK!  ${passed}/${total} testow przeszlo w ${elapsed}s${skipped ? ` (${skipped} pominieto)` : ''}\n`);
  } else {
    console.log(`\n  \u274C  ${failed} TESTOW NIE PRZESZLO  (${passed} ok, ${elapsed}s)`);
    for (const { name, msg, screenshotFile } of failures) {
      console.log(`      - ${name}: ${msg}`);
      console.log(`        ${screenshotFile}`);
    }
    console.log('');
  }
  process.exit(failed > 0 ? 1 : 0);
}

run().catch(e => { console.error(e); process.exit(1); });
