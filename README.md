# IFC Quick Look

Quick Look preview for IFC building models on macOS. Select an `.ifc` file in Finder, press Space, and
orbit around the model in 3D. No CAD/BIM application needed, and nothing leaves your Mac.

- Opens IFC2x3, IFC4 and IFC4x3 files (ISO 10303-21 STEP).
- Keeps the colours and transparency from the file; unstyled elements get a colour by IFC type.
- Mouse orbit, zoom and pan; follows the system light/dark theme.
- Status line with schema, element and triangle counts, model dimensions and file size.
- Fully offline: parsing and rendering run inside the sandboxed extension.

## Install

1. Download `IFCQuickLook-<version>.zip` from [Releases](../../releases/latest) and unzip it.
2. Move `IFCQuickLook.app` to `/Applications`.
3. Open it once. The window only explains what to do next; you can close it.
4. Select an `.ifc` file in Finder and press Space.

If the 3D preview does not appear, open System Settings → General → Login Items & Extensions → Quick Look
and turn on "IFC Preview". Then run `qlmanage -r` in Terminal, or log out and back in.

Requirements: macOS 14 or newer on Apple Silicon. Release builds are signed with a Developer ID and
notarized by Apple.

Uninstall: delete `/Applications/IFCQuickLook.app`.

## How it works

The Quick Look extension hosts a `WKWebView`. The page is served from the extension bundle over a custom
`ifcql://` URL scheme, so no network access or local server is involved.
[web-ifc](https://github.com/ThatOpen/engine_web-ifc) (WebAssembly) parses the file into triangle meshes, and
[three.js](https://threejs.org/) draws them. The viewer, the scheme handler and the macOS integration are the
code in this repository.

## Build from source

Requirements: Xcode 26 (command line tools are enough) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
scripts/fetch-vendor.sh          # downloads pinned web-ifc and three.js into IFCPreview/Web/vendor
scripts/install.sh [sample.ifc]  # generate project, build, copy to /Applications, register, verify
qlmanage -p path/to/model.ifc
```

Without any configuration the app is signed ad-hoc, which is enough on the Mac that built it. To sign with
your own Apple Development certificate, copy `signing.local.env.example` to `signing.local.env` and set
`TEAM_ID`. That file is git-ignored.

### Release build

`scripts/release.sh` produces `dist/IFCQuickLook-<version>.zip`: signed with a "Developer ID Application"
certificate, notarized and stapled. One-time setup:

1. Create a Developer ID Application certificate (Xcode → Settings → Accounts → Manage Certificates).
2. Store notarization credentials: `xcrun notarytool store-credentials ifcql-notary` (Apple ID, team ID and
   an app-specific password from account.apple.com).
3. Fill in `signing.local.env` (`TEAM_ID`, `NOTARY_PROFILE`).

The version comes from `MARKETING_VERSION` in `project.yml`.

## Layout

```
project.yml                       XcodeGen project definition (targets, Info.plist keys, entitlements)
IFCQuickLook/App.swift            host app: one window with instructions; declares the org.buildingsmart.ifc UTI
IFCPreview/PreviewViewController  QLPreviewingController hosting the WKWebView
IFCPreview/AppSchemeHandler       serves Web/ and the previewed file over ifcql://app/...
IFCPreview/Web/index.html         page shell: overlay (status/errors), HUD, canvas
IFCPreview/Web/viewer.js          web-ifc → merged BufferGeometry → three.js scene
IFCPreview/Web/vendor/            downloaded libraries (git-ignored)
scripts/fetch-vendor.sh           download pinned web-ifc / three.js
scripts/install.sh                build, install, register, verify
scripts/release.sh                Developer ID build, notarize, staple, zip
scripts/ql-test.sh                open a file in Quick Look and print the extension's log lines
scripts/dev-server.py             serve Web/ over HTTP for browser-based development
```

## Development loop for the web part

```bash
scripts/dev-server.py path/to/model.ifc 8765
# open http://localhost:8765/index.html?name=model.ifc&size=<bytes>
```

All URLs in the page are relative, so the same files run under `ifcql://app/` in Quick Look and under
`http://localhost` in a browser (with the browser's dev tools).

## Debugging inside Quick Look

```bash
scripts/ql-test.sh path/to/model.ifc            # prints "viewer ready: N elements ... timings" or the error
/usr/bin/log stream --level info --predicate 'subsystem == "com.ibaranov.IFCQuickLook"'
```

The web view is inspectable: with Safari's Develop menu enabled, open Safari → Develop → (this Mac) →
`ifcql://app/index.html` while a preview is showing.

## Notes and limitations

- The page is not on screen until `preparePreviewOfFile` returns, and `requestAnimationFrame` does not fire
  in an off-screen web view. The viewer therefore yields with `setTimeout`, and the controller returns as soon as
  the page reports `ready` or after 5 s, whichever is first. Large files keep loading with the in-page spinner.
- Elements without a surface style in the file (web-ifc reports them as white) are coloured by IFC type using
  `TYPE_PALETTE` in `viewer.js` (walls beige, slabs grey, windows translucent blue, ...). Elements that do have
  a style keep the file's colour. The HUD shows "Colours: by type" or "from file".
- Files above 250 MB are not parsed; a message is shown instead.
- `.ifczip` and `.ifcxml` are not supported (web-ifc does not parse ifcXML).
- Geometry is merged into two draw calls (opaque + transparent). Per-element selection is not implemented.
- After every rebuild, `install.sh` removes the old app, re-registers and runs `qlmanage -r`; otherwise Quick Look
  may keep using a stale copy.

## License

MIT, see [LICENSE](LICENSE). Use, modify and redistribute it freely, including commercially.
Bundled third-party components keep their own licenses (web-ifc: MPL-2.0, three.js: MIT); see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
