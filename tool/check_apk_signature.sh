#!/usr/bin/env bash
# Prüft, ob eine APK mit genau dem Schlüssel aus dem Keystore signiert ist.
# Für release.yml; bricht ab, wenn die Signatur ungültig ist, der
# Debug-Schlüssel benutzt wurde oder der Fingerabdruck nicht passt.
#
#   tool/check_apk_signature.sh <apk>
#
# Umgebung: ANDROID_KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS.
# APKSIGNER (optional): Pfad zu apksigner, sonst der neueste unter
# $ANDROID_HOME/build-tools.
#
# Gibt die Ausgabe von apksigner immer aus. Sie enthält nur öffentliche
# Zertifikatsdaten (DN, Fingerabdrücke), die ohnehin in jeder APK stehen.
set -uo pipefail

apk="${1:?Pfad zur APK fehlt}"
: "${ANDROID_KEYSTORE_PATH:?ANDROID_KEYSTORE_PATH fehlt}"
: "${KEYSTORE_PASSWORD:?KEYSTORE_PASSWORD fehlt}"
: "${KEY_ALIAS:?KEY_ALIAS fehlt}"

fail() {
  echo "::error::$1"
  exit 1
}

apksigner="${APKSIGNER:-}"
if [ -z "$apksigner" ]; then
  apksigner=$(ls "${ANDROID_HOME:-}"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -n 1)
fi
[ -x "$apksigner" ] || fail "apksigner nicht gefunden (ANDROID_HOME=${ANDROID_HOME:-leer})."
echo "apksigner: $apksigner"

out=$("$apksigner" verify --print-certs "$apk" 2>&1)
rc=$?
echo "--- apksigner verify --print-certs (Exit-Code $rc) ---"
echo "$out"
echo "---"
[ "$rc" -eq 0 ] || fail "apksigner meldet eine ungültige Signatur (Exit-Code $rc)."

if grep -q 'CN=Android Debug' <<<"$out"; then
  fail "APK ist mit dem Debug-Schlüssel signiert. Abbruch."
fi

# Fingerabdruck des eigenen Schlüssels; das Passwort geht nicht über die
# Kommandozeile (-storepass:env).
expected=$(keytool -list -v -keystore "$ANDROID_KEYSTORE_PATH" -alias "$KEY_ALIAS" \
  -storepass:env KEYSTORE_PASSWORD 2>&1 |
  sed -n 's/^[[:space:]]*SHA256:[[:space:]]*//p' | head -n 1 | tr -d ':' | tr 'A-F' 'a-f')
[ -n "$expected" ] || fail "Fingerabdruck des Schlüssels nicht lesbar (Keystore, Passwort oder Alias falsch?)."
echo "Erwarteter SHA-256: $expected"

# apksigner schreibt Fingerabdrücke als Kleinbuchstaben ohne Doppelpunkte.
normalized=$(tr -d ':' <<<"$out" | tr 'A-F' 'a-f')
grep -q "$expected" <<<"$normalized" ||
  fail "APK ist nicht mit dem Schlüssel aus den Secrets signiert (SHA-256 passt nicht)."

echo "Signatur in Ordnung: eigener Schlüssel."
