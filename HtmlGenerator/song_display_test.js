// regression_test.js
// Uzycie:
//   node regression_test.js --update   <- zapisz nowe snapshots (golden files)
//   node regression_test.js            <- porownaj z golden files
//   node regression_test.js --update --song "Golf"  <- update tylko jednej piosenki

const { chromium } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const { PNG } = require('pngjs');
const pixelmatch = require('pixelmatch');

const UPDATE = process.argv.includes('--update');
const SONG_FILTER = (() => { const i = process.argv.indexOf('--song'); return i > -1 ? process.argv[i+1] : null; })();
const HTML_PATH = 'file:///' + path.resolve(__dirname, 'spiewnik.html').replace(/\\/g, '/');
const SNAPSHOTS_DIR = path.join(__dirname, 'snapshots');
const DIFF_DIR = path.join(__dirname, 'snapshots_diff');
const THRESHOLD_PX = 30; // max 30 pikseli roznic (antyaliasing), powyzej = fail

const SONGS = [
  { title: 'Chyba już czas',                         artist: 'Adam Drąg' },
  { title: 'Ech muzyka',                             artist: 'Adam Drąg' },
  { title: 'Jesienne wino',                          artist: 'Andrzej Koczewski' },
  { title: 'Jeszcze nie czas',                       artist: 'Andrzej Koczewski' },
  { title: 'W lesie listopadowym',                   artist: 'Andrzej Koczewski' },
  { title: 'Bieszczady',                             artist: 'Andrzej Starzec' },
  { title: 'Hora',                                   artist: 'Beskid' },
  { title: 'Panna Kminkowa',                         artist: 'Browar Żywiec' },
  { title: 'Ballada o wilku',                        artist: 'Bułas' },
  { title: 'Buty idą dwa',                           artist: 'Było Nas Trzech' },
  { title: 'Chrystus Bieszczadzki',                  artist: 'Cisza jak ta' },
  { title: 'Pozegnalny wieczor',                     artist: 'Cisza jak ta' },
  { title: 'Szemkel',                                artist: 'Cisza jak ta' },
  { title: 'Toaleta, wucet, kibel, haziel, sracz',   artist: 'Dawisiek21' },
  { title: 'Kolorowy wiatr',                         artist: 'Disney' },
  { title: 'Niewidzialna plastelina',                artist: 'Dnieje' },
  { title: 'Łemata',                                 artist: 'Dom o Zielonych Progach' },
  { title: 'Bar w Beskidzie',                        artist: 'EKT Gdynia' },
  { title: 'Jesienna droga do Leluchowa',            artist: 'Enigma' },
  { title: 'Pogodne popołudnie kapitana',            artist: 'Grotowski' },
  { title: 'Księżniczka Bieszczadów',                artist: 'Grupa na Swoim' },
  { title: 'Piwo wino',                              artist: 'Grupa na Swoim' },
  { title: 'W pudełeczku mam kółeczko',              artist: 'Grupa na Swoim' },
  { title: 'Barman',                                 artist: 'Grzmiąca Półlitrówa' },
  { title: 'Lekcja historii klasycznej',             artist: 'Jacek Kaczmarski' },
  { title: 'Modlitwa o wschodzie słońca',            artist: 'Jacek Kaczmarski' },
  { title: 'Nocny Kamboj',                           artist: 'Jacek Kaczmarski' },
  { title: 'Zbroja',                                 artist: 'Jacek Kaczmarski' },
  { title: 'Mury',                                   artist: 'Jacek Kaczmarski' },
  { title: 'Do świtu',                               artist: 'Jurkiewicz' },
  { title: 'Kantyczka z lotu ptaka',                 artist: 'Kaczmarski' },
  { title: 'Warchoł',                                artist: 'Kaczmarski' },
  { title: 'Nad Bieliczną',                          artist: 'Kleszcz' },
  { title: 'Kołysanka dla chłopaków',                artist: 'Kuba Nycz' },
  { title: 'Golf',                                   artist: 'Kuśka' },
  { title: 'Piosenka turystyczna',                   artist: 'Kuśka' },
  { title: 'Lisom, lisom',                           artist: 'Łemkowskie' },
  { title: 'Alleluja',                               artist: 'Leonard Cohen' },
  { title: 'Pedro i kury',                           artist: 'Ludowe' },
  { title: 'Lipka',                                  artist: 'Ludowe' },
  { title: 'Rapapara',                               artist: 'Łydka Grubasa' },
  { title: 'Cykady na Cykladach',                    artist: 'Maanam' },
  { title: 'Green Horn',                             artist: 'Mechanicy Shanty' },
  { title: 'Irlandzki wędrowiec',                    artist: 'Mechanicy Shanty' },
  { title: 'Molly Maquires',                         artist: 'Mechanicy Shanty' },
  { title: 'Kamienie',                               artist: 'Myśli Rozczochrane' },
  { title: 'Kolory miasta',                          artist: 'Myśli Rozczochrane Wiatrem Zapisane' },
  { title: 'Ballada o św. Mikołaju',                 artist: 'SETA' },
  { title: 'Blues rybaka',                           artist: 'Słodki Całus od Buby' },
  { title: 'Jak',                                    artist: 'Stare Dobre Małżeństwo' },
  { title: 'Czarny blues o czwartej nad ranem',      artist: 'Stare Dobre Małżeństwo' },
  { title: 'Kim właściwie była ta piękna pani?',     artist: 'Stare Dobre Małżeństwo' },
  { title: 'Piosenka dla Wojtka Bellona',            artist: 'Stare Dobre Małżeństwo' },
  { title: 'Jest już za późno',                      artist: 'Stare Dobre Małżeństwo' },
  { title: 'Leluchów',                               artist: 'Stare Dobre Małżeństwo' },
  { title: 'Bacowanie',                              artist: 'Truś' },
  { title: 'Pechowy dzień',                          artist: 'Waldemar Chyliński' },
  { title: 'Bukowina I',                             artist: 'Wolna Grupa Bukowina' },
  { title: 'Kołysanka dla Joanny I',                 artist: 'Wolna Grupa Bukowina' },
  { title: 'Nocna piosenka o mieście',               artist: 'Wolna Grupa Bukowina' },
  { title: 'Rzeka',                                  artist: 'Wolna Grupa Bukowina' },
  { title: 'Odpowiedź gwiżdże wiatr',               artist: 'Wołosatki' },
  { title: 'Pod słońce',                             artist: 'Zgórmysyny' },
];

function norm(s) {
  if (!s) return '';
  s = s.toLowerCase();
  s = s.replace(/ą/g,'a').replace(/ć/g,'c').replace(/ę/g,'e').replace(/ł/g,'l')
       .replace(/ń/g,'n').replace(/ó/g,'o').replace(/ś/g,'s').replace(/ź/g,'z').replace(/ż/g,'z');
  return s.replace(/[^a-z0-9 ]/g,' ').replace(/ +/g,' ').trim();
}

function safeFilename(s) {
  return s.replace(/[^a-zA-Z0-9_-]/g, '_').replace(/_+/g, '_').toLowerCase();
}

// Porownanie dwoch buforow PNG i generowanie diff z czerwonymi ramkami
function compareImages(buf1, buf2, diffPath) {
  const img1 = PNG.sync.read(buf1);
  const img2 = PNG.sync.read(buf2);
  if (img1.width !== img2.width || img1.height !== img2.height) {
    return { match: false, diffRatio: 1, reason: `rozny rozmiar ${img1.width}x${img1.height} vs ${img2.width}x${img2.height}` };
  }
  const { width, height } = img1;
  const diff = new PNG({ width, height });
  const numDiff = pixelmatch(img1.data, img2.data, diff.data, width, height, { threshold: 0, includeAA: false });
  const diffRatio = numDiff / (width * height);
  if (numDiff > THRESHOLD_PX && diffPath) {
    fs.writeFileSync(diffPath, PNG.sync.write(diff));
  }
  return { match: numDiff <= THRESHOLD_PX, diffRatio, numDiff };
}

async function run() {
  if (!fs.existsSync(SNAPSHOTS_DIR)) fs.mkdirSync(SNAPSHOTS_DIR);
  if (!UPDATE && !fs.existsSync(DIFF_DIR)) fs.mkdirSync(DIFF_DIR);

  const t0 = Date.now();
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.setViewportSize({ width: 1920, height: 1080 });
  await page.goto(HTML_PATH);
  await page.waitForFunction(() => typeof SONGS !== 'undefined' && SONGS.length > 0);

  const results = [];
  let done = 0;

  for (const song of SONGS) {
    if (SONG_FILTER && !norm(song.title).includes(norm(SONG_FILTER))) continue;

    const found = await page.evaluate(({ t, a }) => {
      function norm(s) {
        if (!s) return '';
        s = s.toLowerCase().replace(/ł/g, 'l').replace(/Ł/g, 'l');
        s = s.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
        return s.replace(/[^a-z0-9 ]/g, ' ').replace(/ +/g, ' ').trim();
      }
      const nt = norm(t), na = norm(a);
      const tWords = nt.split(' ').filter(w => w.length > 1);
      let best = null, bestScore = 0;
      for (const s of SONGS) {
        const st = norm(s.title), sa = norm(s.artist);
        let score = 0;
        if (tWords.every(w => st.includes(w))) score += 10;
        if (na) { const aWords = na.split(' ').filter(w => w.length > 2); if (aWords.every(w => sa.includes(w))) score += 20; }
        if (score > bestScore) { bestScore = score; best = s; }
      }
      return best ? { id: best.id, title: best.title, artist: best.artist } : null;
    }, { t: song.title, a: song.artist });

    if (!found) {
      console.log(`  [??] "${song.artist} - ${song.title}" — nie znaleziono`);
      results.push({ song: song.title, status: 'not_found' });
      continue;
    }

    const slug = safeFilename(found.artist + '_' + found.title);
    const songResults = { song: found.title, artist: found.artist, views: [] };
    const viewIssues = [];

    // above
    await page.evaluate(id => { showSong(id); setChordMode('above'); }, found.id);
    await page.waitForSelector('#sv-body .song-pair', { timeout: 500 }).catch(()=>{});
    await snap('above', '#sv-body');

    // inline (just CSS switch, no wait needed)
    await page.evaluate(() => setChordMode('inline'));
    await snap('inline', '#sv-body');

    // raw
    await page.evaluate(id => showRaw(id), found.id);
    await page.waitForSelector('#raw-cols .raw-col-label', { timeout: 500 }).catch(()=>{});
    await snap('raw', '#raw-cols');
    await page.evaluate(() => { if (typeof closeRaw === 'function') closeRaw(); });

    async function snap(name, selector) {
      const el = await page.$(selector);
      if (!el) { viewIssues.push(`${name}:BRAK`); return; }
      const screenshot = await el.screenshot({ type: 'png' });
      const snapshotPath = path.join(SNAPSHOTS_DIR, `${slug}_${name}.png`);
      if (UPDATE) {
        fs.writeFileSync(snapshotPath, screenshot);
        songResults.views.push({ view: name, status: 'updated' });
      } else if (!fs.existsSync(snapshotPath)) {
        viewIssues.push(`${name}:BRAK_SNAPSHOTA`);
        songResults.views.push({ view: name, status: 'missing' });
      } else {
        const golden = fs.readFileSync(snapshotPath);
        const { match, diffRatio, numDiff } = compareImages(golden, screenshot, null);
        if (match) {
          songResults.views.push({ view: name, status: 'ok' });
        } else {
          viewIssues.push(`${name}:${numDiff}px`);
          fs.writeFileSync(path.join(DIFF_DIR, `${slug}_${name}_golden.png`), golden);
          fs.writeFileSync(path.join(DIFF_DIR, `${slug}_${name}_actual.png`), screenshot);
          songResults.views.push({ view: name, status: 'diff', numDiff });
        }
      }
    }

    done++;
    const num = String(done).padStart(2);
    if (UPDATE) {
      console.log(`  ${num}. [OK] ${found.artist} - ${found.title} (snapshots zapisane)`);
    } else if (viewIssues.length === 0) {
      console.log(`  ${num}. [OK] ${found.artist} - ${found.title}`);
    } else {
      console.log(`  ${num}. [!!] ${found.artist} - ${found.title}  >>  ${viewIssues.join(', ')}`);
    }

    results.push(songResults);
  }

  await browser.close();
  const elapsed = ((Date.now() - t0) / 1000).toFixed(1);

  // Podsumowanie
  console.log('\n' + '='.repeat(60));
  if (UPDATE) {
    console.log(`\n  \u2705  Snapshots zaktualizowane: ${done} piosenek (${done*3} obrazkow) w ${elapsed}s\n`);
  } else {
    const ok = results.filter(r => r.views && r.views.every(v => v.status === 'ok')).length;
    const diff = results.filter(r => r.views && r.views.some(v => v.status === 'diff')).length;
    const missing = results.filter(r => r.views && r.views.some(v => v.status === 'missing')).length;
    const notFound = results.filter(r => r.status === 'not_found').length;
    const total = ok + diff + missing + notFound;

    if (diff === 0 && missing === 0 && notFound === 0) {
      console.log(`\n  \u2705  WSZYSTKO OK!  ${ok}/${total} piosenek przeszlo (${ok*3} obrazkow) w ${elapsed}s\n`);
    } else {
      console.log(`\n  \u274C  WYKRYTO PROBLEMY  (${elapsed}s)`);
      console.log(`      OK: ${ok}  |  ROZNICE: ${diff}  |  BRAK SNAPSHOTA: ${missing}  |  NIE ZNALEZIONO: ${notFound}`);
      if (diff > 0) {
        console.log(`\n      Pliki diff w: snapshots_diff/`);
        console.log('        *_golden.png = poprzedni stan');
        console.log('        *_actual.png = aktualny stan');
      }
      console.log('');
    }
    process.exit(diff > 0 || missing > 0 ? 1 : 0);
  }
}

run().catch(e => { console.error(e); process.exit(1); });
