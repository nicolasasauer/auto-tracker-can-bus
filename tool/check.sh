#!/usr/bin/env bash
# Analyse und Tests mit knapper Ausgabe: je Schritt eine Zeile, Einzelheiten
# nur bei Fehlern. Die CI ruft die Befehle weiter einzeln auf.
#
#   tool/check.sh link                         Paket can_link: Analyse + Tests
#   tool/check.sh link test/foo_test.dart      nur diese Tests (ohne Analyse)
#   tool/check.sh firmware                     Kern-Tests der Firmware (C++)
#   tool/check.sh flasher                      Skript des Web-Flashers (Node)
#   tool/check.sh alle                         link, firmware, flasher
#
# Ein fehlgeschlagener Schritt zeigt Anfang und Ende seiner Ausgabe
# (CHECK_HEAD, CHECK_TAIL: Zeilen, Standard 20 und 60).
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

# step <Name> <Befehl…>: führt den Befehl still aus.
step() {
  local name="$1"
  shift
  local log
  log="$(mktemp)"
  if "$@" >"$log" 2>&1; then
    # Letzte nicht leere Zeile als Zusammenfassung (z. B. „All tests passed!“).
    if [ -n "${quiet:-}" ]; then
      echo "ok      $name"
    else
      echo "ok      $name: $(grep -v '^[[:space:]]*$' "$log" | tail -n 1 | cut -c1-120)"
    fi
  else
    echo "FEHLER  $name"
    local head_n="${CHECK_HEAD:-20}" tail_n="${CHECK_TAIL:-60}"
    if [ "$(wc -l <"$log")" -gt $((head_n + tail_n)) ]; then
      # Übersetzungsfehler stehen am Anfang, Testfehler am Ende.
      head -n "$head_n" "$log"
      echo "[… gekürzt, mehr mit CHECK_HEAD/CHECK_TAIL …]"
      tail -n "$tail_n" "$log"
    else
      cat "$log"
    fi
    fail=1
  fi
  rm -f "$log"
}

flutter_check() {
  local dir="$1"
  shift
  cd "$root/$dir" || exit 2
  quiet=1 step "$dir: pub get" flutter pub get
  if [ "$#" -gt 0 ]; then
    step "$dir: Tests ($*)" flutter test --reporter failures-only "$@"
  else
    step "$dir: Analyse" flutter analyze
    step "$dir: Tests" flutter test --reporter failures-only
  fi
}

firmware_check() {
  cd "$root/firmware" || exit 2
  # Unter Windows (Git Bash, MinGW) fehlt dem Compiler die Sanitizer-Laufzeit,
  # und printf kennt %zu nur mit __USE_MINGW_ANSI_STDIO.
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
      export SANITIZE="${SANITIZE:-0}"
      export CXX="${CXX:-c++} -D__USE_MINGW_ANSI_STDIO=1"
      ;;
  esac
  step "firmware: Kern-Tests" ./test/run_tests.sh
}

flasher_check() {
  cd "$root/web" || exit 2
  step "flasher: Tests" node --test
}

target="${1:-}"
[ "$#" -gt 0 ] && shift
case "$target" in
  link) flutter_check packages/can_link "$@" ;;
  firmware) firmware_check ;;
  flasher) flasher_check ;;
  alle)
    flutter_check packages/can_link
    firmware_check
    flasher_check
    ;;
  *)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac

if [ "$fail" -ne 0 ]; then
  echo "Ergebnis: FEHLER"
  exit 1
fi
echo "Ergebnis: alles in Ordnung"
