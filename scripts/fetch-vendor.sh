#!/usr/bin/env bash
# Downloads pinned web-ifc and three.js builds from the npm registry (no npm needed)
# and places the files the viewer needs into IFCPreview/Web/vendor/.
set -euo pipefail

WEB_IFC_VERSION="0.0.77"
THREE_VERSION="0.185.1"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$ROOT/vendor/.tmp"
OUT="$ROOT/IFCPreview/Web/vendor"
rm -rf "$TMP"; mkdir -p "$TMP" "$OUT"

echo "== web-ifc $WEB_IFC_VERSION"
curl -fsSL "https://registry.npmjs.org/web-ifc/-/web-ifc-${WEB_IFC_VERSION}.tgz" -o "$TMP/web-ifc.tgz"
tar -xzf "$TMP/web-ifc.tgz" -C "$TMP" package/web-ifc-api.js package/web-ifc.wasm package/LICENSE.md
cp "$TMP/package/web-ifc-api.js" "$TMP/package/web-ifc.wasm" "$OUT/"
cp "$TMP/package/LICENSE.md" "$OUT/LICENSE.web-ifc.md"
rm -rf "$TMP/package"

echo "== three $THREE_VERSION"
curl -fsSL "https://registry.npmjs.org/three/-/three-${THREE_VERSION}.tgz" -o "$TMP/three.tgz"
tar -xzf "$TMP/three.tgz" -C "$TMP" package/build/three.module.js package/build/three.core.js \
  package/examples/jsm/controls/OrbitControls.js package/LICENSE
cp "$TMP/package/build/three.module.js" "$TMP/package/build/three.core.js" \
   "$TMP/package/examples/jsm/controls/OrbitControls.js" "$OUT/"
cp "$TMP/package/LICENSE" "$OUT/LICENSE.three.txt"
# OrbitControls imports the bare specifier 'three'; make it relative so no import map is needed.
sed -i '' "s#from 'three'#from './three.module.js'#" "$OUT/OrbitControls.js"

echo "== checks"
if grep -q "import.meta" "$OUT/web-ifc-api.js"; then
  echo "!! web-ifc-api.js uses import.meta (unexpected for this version)"; exit 1
fi
if grep -q "from 'three'" "$OUT/OrbitControls.js"; then
  echo "!! OrbitControls.js still imports bare 'three'"; exit 1
fi
rm -rf "$TMP"
(cd "$OUT" && shasum -a 256 web-ifc-api.js web-ifc.wasm three.module.js three.core.js OrbitControls.js)
echo "done: $OUT"
