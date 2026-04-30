# Building and Distributing BetterSpotlight

## Prerequisites

- Xcode (full install, not just Command Line Tools)
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [go-task](https://taskfile.dev): `brew install go-task`
- Optional (nicer DMG layout): `brew install create-dmg`

## Development build

```sh
task up
```

Regenerates the Xcode project, builds Debug, kills any running instance, and relaunches.

## Regenerating the app icon

The icon is pre-generated at `BetterSpotlight/Resources/AppIcon.icns`. To regenerate from source:

```sh
swift scripts/generate-icon.swift
```

The script draws a 1024×1024 liquid-glass icon with CoreGraphics, slices it into the required macOS sizes (16→512 @1×/2×), and calls `iconutil` to produce the `.icns` file.

## Packaging a DMG

```sh
task package
```

This:
1. Runs `xcodegen` to sync the project file.
2. Builds the **Release** configuration.
3. Creates `dist/BetterSpotlight-<version>.dmg` containing the `.app` and an `/Applications` symlink.

If `create-dmg` is installed the DMG gets a polished Finder window with icon positions. Otherwise `hdiutil` is used as a fallback.

The version string is read from `CFBundleShortVersionString` in the built app's `Info.plist` (set in `project.yml`).

## Notarization (manual steps — not automated)

Before distributing to users outside the Mac App Store you must sign and notarize the build.

### 1. Prerequisites

- An Apple Developer account with a **Developer ID Application** certificate installed in Keychain.
- App-specific password for your Apple ID stored in Keychain:

```sh
xcrun notarytool store-credentials "notarytool-profile" \
  --apple-id "your@email.com" \
  --team-id "YOURTEAMID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

### 2. Build a signed Release archive

```sh
xcodegen
xcodebuild -project BetterSpotlight.xcodeproj \
  -scheme BetterSpotlight \
  -configuration Release \
  -archivePath build/BetterSpotlight.xcarchive \
  archive
```

### 3. Export a Developer ID–signed .app

Create an `ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>YOURTEAMID</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Developer ID Application: Your Name (YOURTEAMID)</string>
</dict>
</plist>
```

```sh
xcodebuild -exportArchive \
  -archivePath build/BetterSpotlight.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export
```

### 4. Notarize

```sh
xcrun notarytool submit build/export/BetterSpotlight.app \
  --keychain-profile "notarytool-profile" \
  --wait
```

Check status with the returned submission ID if `--wait` times out:

```sh
xcrun notarytool info <submission-id> --keychain-profile "notarytool-profile"
```

### 5. Staple the notarization ticket

```sh
xcrun stapler staple build/export/BetterSpotlight.app
```

### 6. Package into a signed DMG

```sh
create-dmg \
  --volname "BetterSpotlight" \
  --window-pos 200 120 --window-size 600 400 \
  --icon-size 128 \
  --icon "BetterSpotlight.app" 150 185 \
  --app-drop-link 450 185 \
  "dist/BetterSpotlight-<version>-release.dmg" \
  "build/export/"

codesign --sign "Developer ID Application: Your Name (YOURTEAMID)" \
  "dist/BetterSpotlight-<version>-release.dmg"

xcrun notarytool submit "dist/BetterSpotlight-<version>-release.dmg" \
  --keychain-profile "notarytool-profile" --wait

xcrun stapler staple "dist/BetterSpotlight-<version>-release.dmg"
```

After stapling, the DMG is ready for distribution.
