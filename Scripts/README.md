# OptClicker bundle-identity bridge release

OptClicker uses the same two-release migration flow as DesktopRenamer:

1. Publish a legacy `michaelqiu.OptClicker` bridge release through the shared
   Sparkle appcast.
2. The bridge downloads a checksum-pinned migration `.pkg`, which stages the
   finalized `dev.mqiu.OptClicker` app at
   `/Applications/OptClicker-Migration.app`.
3. The staged app replaces the legacy app at its original path and launches
   the current bundle ID.
4. Only after successful acknowledgement are the staged app, backup, legacy
   defaults, and migration state removed.

The bridge app hides automatic update controls and changes **Check for
updates** to **Migrate**. Current-ID releases retain automatic updates and
show **Check Now**.

## Build the migration package

The package version is the app build number (`CFBundleVersion`), not the
marketing version:

```sh
CURRENT_APP="$HOME/Downloads/OptClick 2026-09-09 20-24-37/OptClicker.app"
CURRENT_BUILD=10
APPCAST_URL="https://raw.githubusercontent.com/gitmichaelqiu/OptClicker/main/appcast.xml"
MIGRATION_PACKAGE="tmp/OptClicker-migration-${CURRENT_BUILD}.pkg"

Scripts/build-migration-package.sh \
  --app "$CURRENT_APP" \
  --version "$CURRENT_BUILD" \
  --update-feed-url "$APPCAST_URL" \
  --output "$MIGRATION_PACKAGE" \
  --manual-approval
```

Upload the package to its final HTTPS GitHub release asset URL before building
the bridge. The URL and checksum must not change after the bridge is built.

## Build the legacy bridge

For version `1.5.2`, build number `10`, and release tag `bridge`:

```sh
MIGRATION_PACKAGE_SHA256="$(shasum -a 256 "$MIGRATION_PACKAGE" | awk '{print $1}')"
MIGRATION_PACKAGE_URL="https://github.com/gitmichaelqiu/OptClicker/releases/download/v1.5.2-bridge/OptClicker-migration-10.pkg"

Scripts/build-bridge-release.sh \
  --version 1.5.2 \
  --build-number 10 \
  --release-tag bridge \
  --feed-url "$APPCAST_URL" \
  --migration-package-url "$MIGRATION_PACKAGE_URL" \
  --migration-package-sha256 "$MIGRATION_PACKAGE_SHA256" \
  --migration-package-version 10 \
  --output-dir tmp/OptClicker-bridge-release \
  --manual-approval
```

The bridge output is `OptClicker-1.5.2-bridge.dmg`. Verify both artifacts
before publishing:

```sh
Scripts/verify-bridge-release.sh \
  --bridge-dmg tmp/OptClicker-bridge-release/OptClicker-1.5.2-bridge.dmg \
  --migration-package "$MIGRATION_PACKAGE" \
  --version 1.5.2 \
  --build-number 10 \
  --release-tag bridge \
  --feed-url "$APPCAST_URL" \
  --migration-package-url "$MIGRATION_PACKAGE_URL" \
  --migration-package-sha256 "$MIGRATION_PACKAGE_SHA256" \
  --migration-package-version 10
```

The final current-ID DMG is the supplied `OptClicker 1.5.2.dmg` and should be
published as `OptClicker.1.5.2.dmg`. The bridge DMG should be published as
`OptClicker-1.5.2-bridge.dmg`; the migration package should be published as
`OptClicker-migration-10.pkg` in the `v1.5.2-bridge` release.

Before publishing the appcast, sign both DMGs with the OptClicker Sparkle
Ed25519 key and put the resulting `sparkle:edSignature` values on their
`enclosure` elements. `sign_update` reads the private key from the local
keychain; it must not be committed:

```sh
sign_update -p tmp/OptClicker-bridge-release/OptClicker-1.5.2-bridge.dmg
sign_update -p "$HOME/Downloads/OptClick 2026-09-09 20-24-37/OptClicker 1.5.2.dmg"
```

Do not commit generated apps, packages, DMGs, checksums, signing credentials,
or notarization profiles.
