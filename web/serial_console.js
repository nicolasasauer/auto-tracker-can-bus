// Reine Logik für die Konsole des CAN-Lesers im Browser, ohne Web Serial:
// Zeilen zerlegen und den Kopplungscode erkennen. Läuft auch unter Node
// (Tests: serial_console.test.js, `node --test`).

/// Zerlegt eintreffende Textstücke in ganze Zeilen. Die Firmware endet
/// Zeilen mit "\r\n"; "\r" wird verworfen.
export class LineBuffer {
  constructor() {
    this.rest = '';
  }

  /// Hängt [chunk] an und gibt die nun vollständigen Zeilen zurück.
  push(chunk) {
    const text = (this.rest + chunk).replace(/\r/g, '');
    const parts = text.split('\n');
    this.rest = parts.pop();
    return parts;
  }
}

/// Kopplungscode aus einer Zeile der Firmware, sonst null. Die Firmware
/// schreibt nach `pair`: "Kopplungsfenster offen (2 Minuten). Code: 012345".
export function pairingCode(line) {
  const m = /Kopplungsfenster offen.*Code:\s*(\d{6})\b/.exec(line);
  return m ? m[1] : null;
}

/// Erkennt den Startgruß der Firmware (nach einem Neustart, etwa weil das
/// Öffnen der Schnittstelle den Chip zurückgesetzt hat).
export function isBootBanner(line) {
  return line.startsWith('CAN-Leser (Stufe 1');
}

/// Befehl für die Konsole: ein Wort aus der Liste, mit Zeilenende.
const COMMANDS = new Set(['pair', 'status', 'unpair', 'help']);
export function command(word) {
  if (!COMMANDS.has(word)) throw new Error(`Unbekannter Befehl: ${word}`);
  return `${word}\n`;
}
