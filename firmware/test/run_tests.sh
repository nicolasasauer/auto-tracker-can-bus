#!/usr/bin/env bash
# Unit-Tests des plattformunabhängigen Kerns (lib/can_core) auf dem PC.
# Braucht nur einen C++-Compiler; CXX kann von außen gesetzt werden.
set -euo pipefail
cd "$(dirname "$0")/.."
CXX="${CXX:-c++}"
# Speicherfehler-Prüfung (ASan/UBSan), mit SANITIZE=0 abschaltbar
# (z. B. für Compiler ohne diese Laufzeit).
san=""
if [ "${SANITIZE:-1}" = "1" ]; then
  san="-fsanitize=address,undefined -fno-sanitize-recover=all"
fi
out="${TMPDIR:-/tmp}/can_core_tests"
# shellcheck disable=SC2086
$CXX -std=c++17 -Wall -Wextra -Werror -O1 -g -pthread $san \
  -I lib/can_core/src -I test \
  lib/can_core/src/*.cpp test/*.cpp -o "$out"
"$out"
