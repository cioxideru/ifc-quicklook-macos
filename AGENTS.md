# AGENTS.md

Guidance for coding agents working in this repository. Read `README.md` first for what the project is.

## Project shape

- macOS Quick Look preview extension for `.ifc` files. Two targets defined in `project.yml` (XcodeGen):
  `IFCQuickLook` (host app, declares the `org.buildingsmart.ifc` UTI) and `IFCPreview` (the extension).
- The Xcode project is generated and git-ignored. Change `project.yml`, never `*.xcodeproj`.
- The viewer is plain ES modules in `IFCPreview/Web/` with no bundler and no npm. Third-party files live in
  `IFCPreview/Web/vendor/`, are downloaded by `scripts/fetch-vendor.sh` at pinned versions and are git-ignored.

## Commands

```bash
scripts/fetch-vendor.sh                 # once, or after changing pinned versions
scripts/install.sh path/to/model.ifc    # build + install to /Applications + register
scripts/ql-test.sh path/to/model.ifc    # run Quick Look and print the extension log
scripts/dev-server.py model.ifc 8765    # iterate on Web/ in a normal browser
```

After every rebuild Quick Look may keep a stale copy; `install.sh` already re-registers and resets it.

## Rules

- Signing: never commit a team ID, certificate name or notarization profile. `project.yml` stays ad-hoc
  (`CODE_SIGN_IDENTITY: "-"`, empty `DEVELOPMENT_TEAM`). Real values come from the git-ignored
  `signing.local.env`.
- Keep the extension offline. All page URLs are relative so the same files work under `ifcql://app/` and
  `http://localhost`.
- The off-screen web view gets no `requestAnimationFrame` before `preparePreviewOfFile` returns; yield with
  `setTimeout` in loading code (see "Notes and limitations" in `README.md`).
- Bumping web-ifc or three.js: change the versions in `scripts/fetch-vendor.sh` and update
  `THIRD_PARTY_NOTICES.md` (versions, web-ifc commit).
- Release: bump `MARKETING_VERSION` in `project.yml`, run `scripts/release.sh`, attach the zip to a GitHub
  release tagged `v<version>`.
