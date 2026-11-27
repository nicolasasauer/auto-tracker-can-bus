// Koppeln im Browser: öffnet den Leser über Web Serial, schickt `pair` und
// zeigt den Kopplungscode groß an. Ersetzt die serielle Konsole am PC.
// Die Logik ohne Browser steht in serial_console.js.
import { LineBuffer, pairingCode, isBootBanner, command } from './serial_console.js';

const ESPRESSIF_USB_VENDOR = 0x303a; // USB-Serial-JTAG des ESP32-C6
const BAUD = 115200;
const RETRY_MS = 3000;
const MAX_TRIES = 4;

const $ = (id) => document.getElementById(id);
const t = (key) => window.i18n.text(key);

let port = null;
let reader = null;
let writer = null;
let retryTimer = null;
let tries = 0;
let gotCode = false;

function setStatus(key) {
  $('pair-status').textContent = t(key);
}

function log(line) {
  const out = $('pair-log');
  out.textContent += `${line}\n`;
  out.scrollTop = out.scrollHeight;
}

async function send(word) {
  if (!writer) return;
  log(`> ${word}`);
  await writer.write(new TextEncoder().encode(command(word)));
}

function onLine(line) {
  log(line);
  const code = pairingCode(line);
  if (code) {
    gotCode = true;
    clearTimeout(retryTimer);
    $('pair-code').textContent = `${code.slice(0, 3)} ${code.slice(3)}`;
    $('pair-code-box').hidden = false;
    setStatus('pairOpen');
  } else if (isBootBanner(line) && !gotCode) {
    // Der Chip ist neu gestartet (beim Öffnen der Schnittstelle möglich):
    // `pair` nach dem Start noch einmal.
    scheduleTry(1500);
  }
}

function scheduleTry(delay) {
  clearTimeout(retryTimer);
  retryTimer = setTimeout(async () => {
    if (gotCode || !writer) return;
    if (tries >= MAX_TRIES) {
      setStatus('pairNoAnswer');
      return;
    }
    tries += 1;
    await send('pair');
    scheduleTry(RETRY_MS);
  }, delay);
}

async function readLoop() {
  const lines = new LineBuffer();
  const decoder = new TextDecoder();
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      for (const line of lines.push(decoder.decode(value, { stream: true }))) {
        onLine(line);
      }
    }
  } catch (e) {
    // Leser abgezogen oder Schnittstelle geschlossen.
    log(`(${e.message})`);
  }
}

async function connect() {
  try {
    port = await navigator.serial.requestPort({
      filters: [{ usbVendorId: ESPRESSIF_USB_VENDOR }],
    });
  } catch {
    return; // Auswahl abgebrochen
  }
  try {
    await port.open({ baudRate: BAUD });
  } catch (e) {
    setStatus('pairBusy');
    log(`(${e.message})`);
    port = null;
    return;
  }
  reader = port.readable.getReader();
  writer = port.writable.getWriter();
  gotCode = false;
  tries = 0;
  $('pair-log').textContent = '';
  $('pair-code-box').hidden = true;
  $('pair-connect').hidden = true;
  $('pair-controls').hidden = false;
  setStatus('pairWaiting');
  readLoop().finally(disconnect);
  scheduleTry(1000);
}

async function disconnect() {
  clearTimeout(retryTimer);
  const p = port;
  port = null;
  try {
    await reader?.cancel();
  } catch {}
  reader?.releaseLock();
  writer?.releaseLock();
  reader = null;
  writer = null;
  try {
    await p?.close();
  } catch {}
  $('pair-connect').hidden = false;
  $('pair-controls').hidden = true;
  if (!gotCode) setStatus('pairIdle');
}

export function initPairing() {
  if (!('serial' in navigator)) {
    $('pair-connect').disabled = true;
    setStatus('unsupported');
    return;
  }
  setStatus('pairIdle');
  $('pair-connect').addEventListener('click', connect);
  $('pair-again').addEventListener('click', () => {
    gotCode = false;
    tries = 0;
    $('pair-code-box').hidden = true;
    setStatus('pairWaiting');
    scheduleTry(0);
  });
  $('pair-status-cmd').addEventListener('click', () => send('status'));
  $('pair-disconnect').addEventListener('click', disconnect);
}
