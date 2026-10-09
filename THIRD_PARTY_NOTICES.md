# Third-party notices

The code in this repository is MIT-licensed (see `LICENSE`). The release app bundles the following
unmodified third-party files in `IFCQuickLook.app/Contents/PlugIns/IFCPreview.appex/Contents/Resources/Web/vendor/`,
downloaded by `scripts/fetch-vendor.sh`. Their license texts ship next to them in the same folder.

| Component | Version | License | Source |
|-----------|---------|---------|--------|
| web-ifc (`web-ifc-api.js`, `web-ifc.wasm`) | 0.0.77 | MPL-2.0 | https://github.com/ThatOpen/engine_web-ifc (commit `f26c4beef0a668ebdb180d2b95a94097a1e21cef`), npm `web-ifc@0.0.77` |
| three.js (`three.module.js`, `three.core.js`, `OrbitControls.js`) | 0.185.1 | MIT | https://github.com/mrdoob/three.js, npm `three@0.185.1` |

`OrbitControls.js` is changed in one line: its `from 'three'` import is rewritten to `from './three.module.js'`.

## web-ifc and MPL-2.0

web-ifc is distributed here in executable form (a WebAssembly build) without modifications. As MPL-2.0
section 3.2 requires, its source code is available at the repository and commit listed above, and the
full license text is included as `LICENSE.web-ifc.md`. MPL-2.0 is file-level copyleft: it covers the
web-ifc files only and does not extend to the rest of this project.

The web-ifc WebAssembly build statically includes these libraries, all under permissive licenses:

| Library | License | Source |
|---------|---------|--------|
| fast_float | MIT / Apache-2.0 / BSL-1.0 | https://github.com/fastfloat/fast_float |
| tinynurbs | BSD-3-Clause | https://github.com/QuimMoya/tinynurbs |
| glm | MIT | https://github.com/g-truc/glm |
| earcut.hpp | ISC | https://github.com/mapbox/earcut.hpp |
| CDT | MPL-2.0 | https://github.com/artem-ogre/CDT |
| spdlog (with bundled fmt) | MIT | https://github.com/gabime/spdlog |
| stduuid | MIT | https://github.com/mariusbancila/stduuid |
