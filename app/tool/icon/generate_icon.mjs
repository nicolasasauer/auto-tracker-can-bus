// Erzeugt das App-Icon der CAN-Werkbank: adaptives Android-Icon (Vektor) und
// PNGs für ältere Android-Versionen.
//
// Motiv: CAN-Signal (Rechteckwelle) unter einer Lupe – „Bus mithören“.
//
// Aufruf (im Ordner apps/can_werkbank):
//   NODE_PATH=$(npm root -g) node tool/icon/generate_icon.mjs
//
// Benötigt Playwright mit Chromium zum Rendern der PNGs.
import { mkdirSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const { chromium } = createRequire(import.meta.url)('playwright');

const res = 'android/app/src/main/res';
const out = 'assets/icon';

// Farben: Indigo.
const bgStart = '#6366F1';
const bgEnd = '#1E1B4B';
const fg = '#FFFFFF';
const accent = '#FB923C';

// 108×108-Raster des adaptiven Icons, sichtbar ist ein Kreis mit r=33 um
// (54,54). Rechteckwelle über die Breite, Lupe rechts oben darüber.
const sw = 5; // Strichstärke der Welle
// Welle links, sie läuft in die Lupe hinein.
const wave = 'M29,62 H36 V46 H44 V62 H51';
// Lupe: Ring um die Fortsetzung der Welle, Griff nach rechts unten.
// Alles bleibt im sichtbaren Kreis (Griffende ca. 25 vom Mittelpunkt).
const lx = 62, ly = 50, lr = 12, lw = 4.5;
const ring = `M${lx - lr},${ly} a${lr},${lr} 0 1 0 ${2 * lr},0 a${lr},${lr} 0 1 0 ${-2 * lr},0 Z`;
const d = lr / Math.SQRT2;
const handle = `M${(lx + d + 2.5).toFixed(2)},${(ly + d + 2.5).toFixed(2)} L${lx + 15},${ly + 15}`;
// In der Lupe: das Stück Welle, das „vergrößert“ betrachtet wird.
const lensWave = `M${lx - 7},${ly + 4} H${lx - 2.5} V${ly - 4} H${lx + 2.5} V${ly + 4} H${lx + 7}`;

const fgSvg = (mono = false) => `
  <path d="${wave}" fill="none" stroke="${fg}" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="${ring}" fill="none" stroke="${mono ? fg : accent}" stroke-width="${lw}"/>
  <path d="${lensWave}" fill="none" stroke="${mono ? fg : accent}" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="${handle}" fill="none" stroke="${mono ? fg : accent}" stroke-width="6.5" stroke-linecap="round"/>`;

const bgDefs = `<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="${bgStart}"/><stop offset="1" stop-color="${bgEnd}"/>
</linearGradient></defs>`;

// Vollständiges Icon (abgerundetes Quadrat), Ausschnitt 18…90 des Rasters.
const legacySvg = (size) => `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="18 18 72 72">
${bgDefs}<rect x="18" y="18" width="72" height="72" rx="16" fill="url(#bg)"/>${fgSvg()}</svg>`;

const vector = (body, extraNs = '') => `<?xml version="1.0" encoding="utf-8"?>
<!-- Erzeugt von tool/icon/generate_icon.mjs, nicht von Hand ändern. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"${extraNs}
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
${body}
</vector>
`;
const stroke = (path, color, width, join = false) => `    <path
        android:pathData="${path}"
        android:strokeColor="${color}"
        android:strokeWidth="${width}"
        android:strokeLineCap="round"${join ? '\n        android:strokeLineJoin="round"' : ''} />`;
const fgBody = (mono) => [
  stroke(wave, fg, sw, true),
  `    <path
        android:pathData="${ring}"
        android:strokeColor="${mono ? fg : accent}"
        android:strokeWidth="${lw}" />`,
  stroke(lensWave, mono ? fg : accent, 3.5, true),
  stroke(handle, mono ? fg : accent, 6.5),
].join('\n');
const bgVector = vector(`    <path android:pathData="M0,0h108v108h-108z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="linear"
                android:startX="0"
                android:startY="0"
                android:endX="108"
                android:endY="108">
                <item android:offset="0" android:color="${bgStart}" />
                <item android:offset="1" android:color="${bgEnd}" />
            </gradient>
        </aapt:attr>
    </path>`, '\n    xmlns:aapt="http://schemas.android.com/aapt"');

mkdirSync(`${res}/mipmap-anydpi-v26`, { recursive: true });
mkdirSync(`${res}/drawable`, { recursive: true });
mkdirSync(out, { recursive: true });
writeFileSync(`${res}/drawable/ic_launcher_background.xml`, bgVector);
writeFileSync(`${res}/drawable/ic_launcher_foreground.xml`, vector(fgBody(false)));
writeFileSync(`${res}/drawable/ic_launcher_monochrome.xml`, vector(fgBody(true)));
writeFileSync(`${res}/mipmap-anydpi-v26/ic_launcher.xml`, `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
`);
writeFileSync(`${out}/icon.svg`, legacySvg(1024));

const browser = await chromium.launch();
const page = await browser.newPage();
async function render(svg, size, file) {
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(`<html><body style="margin:0">${svg}</body></html>`);
  await page.locator('svg').screenshot({ path: file, omitBackground: true });
}
const densities = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 };
for (const [dpi, size] of Object.entries(densities)) {
  await render(legacySvg(size), size, `${res}/mipmap-${dpi}/ic_launcher.png`);
}
await render(legacySvg(512), 512, `${out}/icon_512.png`);
await browser.close();
console.log('Icon erzeugt.');
