# Local development builds

Run `bash scripts/build-dev-app.sh release open` to build the isolated developer app at `dist-dev/Status Trio Dev.app`. The developer bundle identifier and output location remain separate from production, and the build disables production Sparkle updates.

By default, the script runs `security find-identity -v -p codesigning` and selects the SHA-1 only when exactly one valid `Developer ID Application` identity is available. No match or multiple matches stop the build with an instruction to choose explicitly; the script never falls back silently to Apple Development or ad-hoc signing.

Set `CODE_SIGN_IDENTITY` to choose an identity by SHA-1 or signing name. Set it to `-` only when an ad-hoc developer build is intentional. `codesign` may still show a keychain authorization prompt; the build does not suppress or bypass that prompt.

## Local DIY package

The DIY build keeps its own bundle ID and all seven status-strip layouts. The
default version in `Support/Info.plist` follows the upstream source baseline;
use a higher build number for local DIY packages. The upstream appcast is not
used or updated by this process.

The DIY 1.10.6 baseline ports app and monitoring changes through upstream
`4e387e5`: per-group panel refresh, hardware detail updates, Bluetooth battery
charging state, and settings migration. The DIY footer supports memory
pressure as a discrete level in all three styles. The four hardware panel
meters keep their linear tracks; split progress fills from the center.

After local verification, run `bash scripts/package-diy.sh 75 ./dist` to build
the native-architecture DMG. The script ad-hoc signs the app, checks its identity,
version, architecture and disabled updater, and verifies the disk image. It does
not open or install the app, publish a release, or notarize the package. The
privileged Low Power Mode helper is not usable with an ad-hoc signature.

On a machine without Homebrew, put the supported native build tools on `PATH`
and set `MOBILE_BATTERY_TOOLCHAIN_SOURCE=local` for both verification and packaging.
When a pinned source download is unavailable, set `STATUS_TRIO_DIY_REUSE_MOBILE_BATTERY=1`
to reuse the existing local MobileBattery package in `.build/mobile-battery/package`.
The same flag selects the isolated DIY bundle identity in `verify-local.sh full`.
Use only a trusted local build. This checks the manifest and reviewed licenses,
then re-signs and verifies the bundled helper; it is not a fresh helper build
and is not available for upstream releases.
