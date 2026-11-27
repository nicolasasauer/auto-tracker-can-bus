import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LineBuffer, pairingCode, isBootBanner, command } from './serial_console.js';

test('LineBuffer setzt Zeilen über Stückgrenzen zusammen', () => {
  const b = new LineBuffer();
  assert.deepEqual(b.push('Kopplungs'), []);
  assert.deepEqual(b.push('fenster offen\r\nBus: '), ['Kopplungsfenster offen']);
  assert.deepEqual(b.push('still\r\n\r\n'), ['Bus: still', '']);
  assert.equal(b.rest, '');
});

test('pairingCode liest den Code mit führenden Nullen', () => {
  // Genau die Ausgabe von main.cpp nach `pair` (printf "%06lu").
  assert.equal(
    pairingCode('Kopplungsfenster offen (2 Minuten). Code: 004711'),
    '004711',
  );
});

test('pairingCode übersieht andere Zeilen', () => {
  assert.equal(pairingCode('Kopplungsfenster: offen'), null);
  assert.equal(pairingCode('Code: 123456'), null);
  assert.equal(pairingCode('Kopplungsfenster offen (2 Minuten). Code: 12345'), null);
});

test('isBootBanner erkennt den Start der Firmware', () => {
  assert.ok(isBootBanner('CAN-Leser (Stufe 1: nur mithoeren)'));
  assert.ok(!isBootBanner('Bus: still'));
});

test('command kennt nur die Befehle der Firmware', () => {
  assert.equal(command('pair'), 'pair\n');
  assert.throws(() => command('send'));
});
