# Flutter flavors: a complete how-to

A practical guide to building **one Flutter codebase as several separately branded apps** (different
app name, application/bundle ID, icon, splash, colors, Firebase app and signing key). Every file that
has to change is listed, with what to put in it and why.

The examples use two flavors, **`acme`** and **`globex`**. Replace them with your own names
(lowercase letters and digits only, because Gradle and Xcode use them in task and configuration
names).

| | acme | globex |
| --- | --- | --- |
| Flavor name | `acme` | `globex` |
| Android application ID | `com.example.acme` | `com.example.globex` |
| iOS bundle ID | `com.example.acme` | `com.example.globex` |
| App name | `Acme` | `Globex` |

At the end, "How this repository does it" maps every step to the real Avera/Profit7 files.

---

## 1. Concepts

**Flavor**: a build-time variant of the app. You pick it with `--flavor <name>`:

```bash
flutter run --flavor globex
flutter build appbundle --flavor globex
flutter build ipa --flavor globex
```

`--flavor` does three things:

1. **Android:** builds the Gradle product flavor with the same name (`globexDebug`, `globexRelease`).
2. **iOS/macOS:** builds the Xcode **scheme** with the same name, using its build configurations
   (`Debug-globex`, `Release-globex`, …).
3. **Dart:** defines `FLUTTER_APP_FLAVOR`, exposed as the compile-time constant
   `appFlavor` from `package:flutter/services.dart`.

**Flavor vs environment.** Keep them separate:

- *Flavor* = which app (brand, store identity): `acme`, `globex`.
- *Environment* = which backend/settings: `development`, `production`.

So you end up with combinations like `globex + development`. The flavor is chosen with `--flavor`;
the environment is chosen with a config file passed via `--dart-define-from-file`.

**What can differ per flavor:**

| Layer | Examples |
| --- | --- |
| Native identity | application ID, bundle ID, app name, launcher icon, splash |
| Native services | Firebase config file, signing key, push certificates |
| Dart presentation | colors, logos, texts that name the product, optional widget variants |
| Dart config | backend URL and other settings (via config files) |

**Rule of thumb:** business logic should be identical for all flavors. Only presentation and
configuration differ.

**Where flavors work:** Android, iOS and macOS. **Not** web, Windows or Linux. Those platforms build
without a flavor (see section 4 for `default-flavor`).

---

## 2. Target folder layout

```text
config/
  acme/
    development.json
    production.json
  globex/
    development.json
    production.json

assets/
  brands/
    globex/                 # brand-only images bundled into the app
      logo.png
      launcher/             # icon/splash *sources* (sub-folder = not bundled)
        app_icon.png
        app_icon_foreground.png
        splash.png
        android_12_splash.png

android/app/
  google-services.json      # one file can hold the Firebase apps of every flavor
  src/
    main/                   # shared (manifest, Kotlin, default resources)
    acme/res/values/strings.xml
    globex/res/values/strings.xml
    globex/res/mipmap-*/    # generated launcher icons
    globex/res/drawable*/   # generated splash

ios/
  Flutter/
    Debug-acme.xcconfig     Profile-acme.xcconfig     Release-acme.xcconfig
    Debug-globex.xcconfig   Profile-globex.xcconfig   Release-globex.xcconfig
    brands/acme.xcconfig
    brands/globex.xcconfig
  Runner/
    Firebase/acme/GoogleService-Info.plist
    Firebase/globex/GoogleService-Info.plist
    Assets.xcassets/AppIcon-globex.appiconset/
  Runner.xcodeproj/xcshareddata/xcschemes/
    acme.xcscheme
    globex.xcscheme

flutter_launcher_icons-globex.yaml
flutter_native_splash-globex.yaml
lib/
  firebase_options_acme.dart
  firebase_options_globex.dart
  src/brand/                # brand detection + brand config (Dart)
```

---

## 3. Dart side

### 3.1 Detect the flavor (compile-time)

```dart
// lib/src/brand/app_brand.dart
import 'package:flutter/services.dart' show appFlavor;

enum AppBrand {
  acme('acme'),
  globex('globex');

  const AppBrand(this.flavor);
  final String flavor;

  static const AppBrand current = kIsGlobex ? AppBrand.globex : AppBrand.acme;
}

/// No flavor (web, desktop, tests) → the default brand.
const String kBrandFlavor = appFlavor ?? 'acme';
const bool kIsGlobex = kBrandFlavor == 'globex';
```

Because `appFlavor` is a `const`, `kIsGlobex` is a `const` too. You can then write
`static const color = kIsGlobex ? Color(0xFF…) : Color(0xFF…);` and keep `const` widgets.

### 3.2 Config files per flavor and environment

```json
// config/globex/production.json
{
  "BRAND": "globex",
  "ENVIRONMENT": "production",
  "API_BASE_URL": "https://api.globex.example"
}
```

Read them with `String.fromEnvironment`:

```dart
abstract final class Config {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const environment = String.fromEnvironment('ENVIRONMENT', defaultValue: 'development');
}
```

Run with both the flavor and its config:

```bash
flutter run --flavor globex --dart-define-from-file=config/globex/development.json
```

Rules:

- Keep **the same keys** in every config file. A missing key silently falls back to the Dart
  default; an empty value is at least visible.
- Put a `BRAND` key in each file and check it at startup (next step). Otherwise
  `--flavor globex` combined with `config/acme/...` builds the Globex app pointing at Acme's server.
- Git-ignore files that hold secrets (often `production.json`) and create them in CI from secrets.

### 3.3 Fail fast on a wrong combination

```dart
void validateBrandBuild() {
  const flavor = appFlavor;
  if (flavor != null && !AppBrand.values.any((b) => b.flavor == flavor)) {
    throw StateError('Unknown flavor "$flavor"');
  }
  const configBrand = String.fromEnvironment('BRAND');
  if (configBrand.isNotEmpty && configBrand != AppBrand.current.flavor) {
    throw StateError('Config is for "$configBrand" but the app is "${AppBrand.current.flavor}"');
  }
}
```

Call it first thing in `main()` (or your initialization sequence).

### 3.4 Brand configuration (names, logos, links)

```dart
@immutable
final class BrandConfig {
  const BrandConfig._({required this.appName, required this.logoAsset});

  static const acme = BrandConfig._(appName: 'Acme', logoAsset: 'assets/brands/acme/logo.png');
  static const globex = BrandConfig._(appName: 'Globex', logoAsset: 'assets/brands/globex/logo.png');

  static const BrandConfig current = kIsGlobex ? globex : acme;

  final String appName;
  final String logoAsset;
}
```

Use it everywhere the product is named or shown, for example
`MaterialApp(title: BrandConfig.current.appName)`, logos and placeholders. Product names inside
translations (ARB) become a placeholder: `"updateTitle": "Update {appName}"`.

### 3.5 Brand colors

```dart
abstract final class BrandColors {
  static const Color primary = kIsGlobex ? Color(0xFF02505A) : Color(0xFF2C6B4F);
  static const Color seed = primary;
}

ThemeData(colorSchemeSeed: BrandColors.seed);
```

Keep **semantic** colors (success green, error red) the same for every brand. Only the brand accent
changes.

### 3.6 Different widgets per brand (optional)

When a brand needs a genuinely different layout, switch in one place and keep the logic shared:

```dart
T brandMaybeWhen<T>({required T Function() orElse, T Function()? globex}) =>
    switch (AppBrand.current) {
      AppBrand.globex => globex?.call() ?? orElse(),
      _ => orElse(),
    };

@override
Widget build(BuildContext context) => brandMaybeWhen(
  globex: () => const HomeTileGlobex(),
  orElse: () => const HomeTile(),
);
```

### 3.7 Firebase options per flavor

```dart
FirebaseOptions brandFirebaseOptions() => switch (AppBrand.current) {
  AppBrand.globex when defaultTargetPlatform == TargetPlatform.android => GlobexOptions.android,
  AppBrand.globex when defaultTargetPlatform == TargetPlatform.iOS => GlobexOptions.ios,
  _ => DefaultFirebaseOptions.currentPlatform,
};

await Firebase.initializeApp(options: brandFirebaseOptions());
```

---

## 4. pubspec.yaml

```yaml
flutter:
  # Builds without --flavor (web, desktop, plain `flutter run`) use this flavor.
  default-flavor: acme

  assets:
    - assets/icons/                 # shared
    # Bundled only into the globex app:
    - path: assets/brands/globex/
      flavors:
        - globex
```

Notes:

- `default-flavor` keeps `flutter run` working once Android has product flavors. Without it, Gradle
  doesn't know which variant to build.
- Flavor-conditional assets are left out of other flavors' builds. Builds without a flavor (web,
  desktop, `flutter test`) use `default-flavor`, so a `globex`-only asset is **missing** there. Run
  tests that need it with `flutter test --flavor globex`.
- Asset directories are **not recursive**. Put icon and splash *sources* in a sub-folder
  (`launcher/`) so they are not shipped inside the app.

---

## 5. Android

### 5.1 `android/app/build.gradle.kts`: product flavors

```kotlin
android {
    defaultConfig {
        applicationId = "com.example.acme"   // overridden per flavor
        // …
    }

    flavorDimensions += "brand"
    productFlavors {
        create("acme") {
            dimension = "brand"
            applicationId = "com.example.acme"
        }
        create("globex") {
            dimension = "brand"
            applicationId = "com.example.globex"
        }
    }
}
```

- The **flavor name must match** the `--flavor` value.
- `namespace` (the Kotlin/Java package) can stay shared. Store identity comes from `applicationId`.

### 5.2 App name per flavor

In `android/app/src/main/AndroidManifest.xml` replace the hard-coded label:

```xml
<application android:label="@string/app_name" …>
```

Create one strings file per flavor:

```xml
<!-- android/app/src/globex/res/values/strings.xml -->
<resources>
    <string name="app_name">Globex</string>
</resources>
```

Gradle merges `src/<flavor>/` over `src/main/`, so any resource (icons, strings, colors) placed in a
flavor folder replaces the main one for that flavor only.

(`resValue("string", "app_name", "…")` in Gradle also works, but newer Android Gradle Plugin versions
turn `resValues` off by default. Plain `strings.xml` files always work.)

### 5.3 Signing per flavor

Each store app should have its own upload key. Put the signing config **on the flavor** and none on
the release build type. A build-type `signingConfig` overrides the flavor's.

```kotlin
import java.util.Properties
import java.io.FileInputStream


// Each brand signs its release with its own upload key: android/key-<flavor>.properties.
// Avera also accepts the original android/key.properties. A brand without a key file
// builds an unsigned release, which Google Play rejects, so it can never be signed
// with another brand's key by accident.
val brandFlavors = listOf("acme", "globex")

fun keystoreFor(flavor: String): Properties? {
    val file = rootProject.file("key-$flavor.properties")
    if (!file.exists()) return null
    return Properties().apply { FileInputStream(file).use { load(it) } }
}

android {
    signingConfigs {
        brandFlavors.forEach { flavor ->
            val p = keystoreFor(flavor) ?: return@forEach
            create("${flavor}Release") {
                keyAlias = p["keyAlias"] as String?
                keyPassword = p["keyPassword"] as String?
                storeFile = p["storeFile"]?.let { file(it) }
                storePassword = p["storePassword"] as String?
            }
        }
    }

    productFlavors {
        create("acme") {
            // …
            signingConfig = signingConfigs.findByName("acmeRelease")
        }
        create("globex") {
            // …
            signingConfig = signingConfigs.findByName("globexRelease")
        }
    }

    buildTypes {
        release {
            // no signingConfig here
        }
    }
}
```

Key file (git-ignored, e.g. `key-*.properties` and `*.jks` in `android/.gitignore`):

```properties
# android/key-globex.properties
storePassword=…
keyPassword=…
keyAlias=globex-upload
storeFile=globex-upload-keystore.jks   # relative to android/app/
```

Create a key:

```bash
keytool -genkey -v -keystore android/app/globex-upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias globex-upload
```

The signing config must be declared **before** `productFlavors`, because `findByName` runs when the
flavor is configured.

### 5.4 Firebase on Android

- Register an Android app per application ID in Firebase (same project or separate projects).
- The **Google Services Gradle plugin fails the build** if `google-services.json` has no client for
  the variant's application ID.
- One `android/app/google-services.json` can hold several clients. Download it after adding all apps
  and the plugin picks the right one. Alternatively put one file per flavor in
  `android/app/src/<flavor>/google-services.json`.

### 5.5 Outputs

```text
build/app/outputs/flutter-apk/app-globex-release.apk
build/app/outputs/bundle/globexRelease/app-globex-release.aab
```

Update CI and scripts. The unflavored path `bundle/release/app-release.aab` no longer exists.

### 5.6 Check the result

```bash
aapt2 dump badging build/app/outputs/flutter-apk/app-globex-debug.apk | grep -E "package:|application-label"
```

Expected: `package: name='com.example.globex'` and `application-label:'Globex'`. Install both
flavors on one device. They must sit side by side as two apps.

---

## 6. iOS

iOS needs four things per flavor: **build configurations**, a **scheme**, **xcconfig** files, and
**Podfile** entries. Flutter looks for a scheme named exactly like the flavor, and that scheme's
configurations must be named `Debug-<flavor>`, `Profile-<flavor>` and `Release-<flavor>`.

### 6.1 Build configurations

In Xcode: open `ios/Runner.xcworkspace` → select the **Runner project** (not the target) → **Info**
tab → **Configurations** → `+` → *Duplicate "Debug" Configuration* → name it `Debug-globex`. Repeat
for `Profile-globex` (duplicate *Profile*) and `Release-globex` (duplicate *Release*), and for every
flavor.

Keep the original `Debug`/`Profile`/`Release`. Unflavored tools still use them.

### 6.2 xcconfig per configuration

Create one xcconfig per configuration:

```text
// ios/Flutter/Release-globex.xcconfig
#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.release-globex.xcconfig"
#include "Generated.xcconfig"
#include "brands/globex.xcconfig"
```

and one per brand with the brand values:

```text
// ios/Flutter/brands/globex.xcconfig
APP_BRAND = globex
APP_DISPLAY_NAME = Globex
LAUNCH_SCREEN_STORYBOARD = LaunchScreenGlobex
```

Then, in Xcode → Runner project → Info → Configurations, set the **Runner target**'s base
configuration file for `Release-globex` to `Release-globex.xcconfig` (and so on for each).

Notes:

- The Pods file name is the configuration name **lower-cased**: `Pods-Runner.release-globex.xcconfig`.
- Also add `#include "brands/acme.xcconfig"` to the original `Debug.xcconfig`/`Release.xcconfig`, so
  unflavored builds have the variables too.
- `Profile-*` includes the Pods `profile-*` file.

### 6.3 Per-configuration target settings

In the Runner target → **Build Settings**, set per configuration:

| Setting | Debug/Profile/Release-acme | Debug/Profile/Release-globex |
| --- | --- | --- |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.example.acme` | `com.example.globex` |
| `ASSETCATALOG_COMPILER_APPICON_NAME` | `AppIcon` | `AppIcon-globex` |

### 6.4 Info.plist uses the variables

```xml
<key>CFBundleDisplayName</key>
<string>$(APP_DISPLAY_NAME)</string>
<key>CFBundleName</key>
<string>$(APP_DISPLAY_NAME)</string>
<key>UILaunchStoryboardName</key>
<string>$(LAUNCH_SCREEN_STORYBOARD)</string>
```

`CFBundleIdentifier` normally already is `$(PRODUCT_BUNDLE_IDENTIFIER)`.

### 6.5 Schemes

In Xcode: **Product → Scheme → Manage Schemes** → duplicate `Runner` → rename it to `globex` → tick
**Shared** (otherwise it is not committed and CI/Flutter cannot see it). Edit the scheme and set
each action to the flavor's configuration:

| Action | Configuration |
| --- | --- |
| Run | `Debug-globex` |
| Test | `Debug-globex` |
| Profile | `Profile-globex` |
| Analyze | `Debug-globex` |
| Archive | `Release-globex` |

Shared schemes live in `ios/Runner.xcodeproj/xcshareddata/xcschemes/<flavor>.xcscheme`.

### 6.6 Podfile

CocoaPods must know every configuration and whether it is debug or release:

```ruby
project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
  'Debug-acme' => :debug,
  'Profile-acme' => :release,
  'Release-acme' => :release,
  'Debug-globex' => :debug,
  'Profile-globex' => :release,
  'Release-globex' => :release,
}
```

Then run `cd ios && pod install`. CocoaPods prints "did not set the base configuration…" for the
new configurations. That is expected, because your xcconfig files already include the Pods files.

### 6.7 Firebase plist per flavor

A `GoogleService-Info.plist` describes exactly one iOS app, so you need one per flavor:

```text
ios/Runner/Firebase/acme/GoogleService-Info.plist
ios/Runner/Firebase/globex/GoogleService-Info.plist
```

Remove the plist from *Copy Bundle Resources*. Add a **Run Script** build phase right after
*Copy Bundle Resources* that copies the right one:

```bash
set -e
BRAND="${APP_BRAND:-acme}"
cp "${PROJECT_DIR}/Runner/Firebase/${BRAND}/GoogleService-Info.plist" \
   "${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"
```

Set the phase's *Input Files* to `$(PROJECT_DIR)/Runner/Firebase/$(APP_BRAND)/GoogleService-Info.plist`
and *Output Files* to
`$(BUILT_PRODUCTS_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist`.

If you use the FlutterFire Crashlytics upload script, give `firebase.json` an entry per build
configuration (`platforms.ios.buildConfigurations`). Then call the script with
`--build-configuration=${CONFIGURATION}` instead of `--default-config=default`. Otherwise every
flavor uploads symbols to the same Firebase app.

### 6.8 Signing

Each bundle ID needs its own App ID in the Apple Developer portal and its own App Store Connect app.
With *Automatically manage signing* and your Apple ID added in Xcode, Xcode can register the App ID
and create profiles on the first archive (**Product → Archive** with the flavor scheme selected).

### 6.9 Scripting it instead of clicking

Everything in 6.1–6.7 can be scripted with the `xcodeproj` Ruby gem (it ships with CocoaPods). Doing
it once by hand in Xcode is the best way to learn what each piece does.

### 6.10 Check the result

```bash
flutter build ios --simulator --debug --flavor globex
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" build/ios/iphonesimulator/Runner.app/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" build/ios/iphonesimulator/Runner.app/Info.plist
/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" build/ios/iphonesimulator/Runner.app/GoogleService-Info.plist
```

All three must show the Globex values.

---

## 7. Launcher icons and native splash

### 7.1 Icons: `flutter_launcher_icons`

One file per flavor named `flutter_launcher_icons-<flavor>.yaml`:

```yaml
# flutter_launcher_icons-globex.yaml
flutter_launcher_icons:
  android: true
  image_path_android: "assets/brands/globex/launcher/app_icon.png"
  adaptive_icon_background: "#FFFFFF"
  adaptive_icon_foreground: "assets/brands/globex/launcher/app_icon_foreground.png"
  min_sdk_android: 24
  ios: true
  image_path_ios: "assets/brands/globex/launcher/app_icon.png"
  remove_alpha_ios: true      # App Store rejects icons with transparency
```

```bash
dart run flutter_launcher_icons
```

- Android icons go to `android/app/src/globex/res/mipmap-*`.
- The iOS icon set goes to `ios/Runner/Assets.xcassets/AppIcon-globex.appiconset`, and the tool sets
  `ASSETCATALOG_COMPILER_APPICON_NAME` for configurations whose name contains `-globex`. That is why
  the Xcode configurations must exist first.
- **Gotcha:** once any `flutter_launcher_icons-*.yaml` exists, the tool processes **only** flavor
  files and ignores `flutter_launcher_icons.yaml`.

Source images: 1024×1024 PNG. The iOS icon must have no transparency. The adaptive foreground should
keep the artwork inside the central ~66% safe zone.

### 7.2 Splash: `flutter_native_splash`

```yaml
# flutter_native_splash-globex.yaml
flutter_native_splash:
  color: "#FFFFFF"
  image: assets/brands/globex/launcher/splash.png
  android_12:
    image: assets/brands/globex/launcher/android_12_splash.png
    color: "#FFFFFF"
  web: false
```

```bash
dart run flutter_native_splash:create --flavor globex
```

- Android: writes `android/app/src/globex/res/drawable*/` and `values*/styles.xml`.
- iOS: creates `LaunchScreenGlobex.storyboard` and image sets. **Add the storyboard to the Runner
  target** and point `UILaunchStoryboardName` at it per flavor (section 6.4).
- The tool may **re-indent `Info.plist`**. Check the diff and keep only the real changes.

---

## 8. Firebase (multiple apps)

You do not need a new Firebase project per flavor. One project can hold one app per application/
bundle ID. Separate projects give cleaner ownership and data separation.

```bash
firebase apps:create ANDROID "Globex (android)" --package-name com.example.globex --project my-project
firebase apps:create IOS "Globex (ios)" --bundle-id com.example.globex --project my-project
firebase apps:sdkconfig ANDROID <android-app-id> --project my-project -o android/app/google-services.json
firebase apps:sdkconfig IOS <ios-app-id> --project my-project -o ios/Runner/Firebase/globex/GoogleService-Info.plist
```

The Android `sdkconfig` output contains **all** Android apps of the project, so it can replace the
single `google-services.json`. Write `lib/firebase_options_globex.dart` from the plist/JSON values (or
run `flutterfire configure --out=lib/firebase_options_globex.dart …`) and select it at runtime
(section 3.7).

---

## 9. Commands, Makefile and IDE

### 9.1 Commands

```bash
flutter run --flavor globex --dart-define-from-file=config/globex/development.json
flutter build apk --flavor globex --release --dart-define-from-file=config/globex/production.json
flutter build appbundle --flavor globex --release --dart-define-from-file=config/globex/production.json
flutter build ipa --flavor globex --release --dart-define-from-file=config/globex/production.json
flutter test --flavor globex     # only needed if tests use globex-only assets
```

### 9.2 Makefile

```make
FLAVOR ?= acme
BRANDS := acme globex

.PHONY: run
run:
	flutter run --flavor $(FLAVOR) --dart-define-from-file=config/$(FLAVOR)/development.json

.PHONY: _appbundle
_appbundle:
	flutter build appbundle --release --flavor $(FLAVOR) \
		--dart-define-from-file=config/$(FLAVOR)/production.json
	mkdir -p build/release/$(FLAVOR)
	cp build/app/outputs/bundle/$(FLAVOR)Release/app-$(FLAVOR)-release.aab build/release/$(FLAVOR)/

.PHONY: build-appbundle-all
build-appbundle-all:
	@for brand in $(BRANDS); do $(MAKE) _appbundle FLAVOR=$$brand || exit 1; done
```

Usage: `make run FLAVOR=globex`, `make build-appbundle-all`. Copy each artifact to a per-flavor
folder, because the next flavor's build cleans or overwrites the shared output directories.

### 9.3 VS Code `launch.json`

```json
{
  "name": "Globex (dev)",
  "type": "dart",
  "request": "launch",
  "program": "lib/main.dart",
  "args": ["--flavor=globex", "--dart-define-from-file=config/globex/development.json"]
}
```

Android Studio: *Run → Edit Configurations → Build flavor* = `globex`, *Additional run args* =
`--dart-define-from-file=config/globex/development.json`.

---

## 10. CI (GitHub Actions)

### 10.1 Workflow sketch

Use a matrix with one job per flavor, and keep secrets per flavor in GitHub Environments under the
same names:

```yaml
jobs:
  release:
    strategy:
      fail-fast: false            # one brand failing must not cancel the other
      matrix:
        include:
          - flavor: acme
            package: com.example.acme
          - flavor: globex
            package: com.example.globex
    environment: ${{ matrix.flavor }}-production
    steps:
      - uses: actions/checkout@v4
      # … setup Flutter …
      - run: echo "$KEY_PROPERTIES" | base64 --decode > android/key-${{ matrix.flavor }}.properties
        env: { KEY_PROPERTIES: "${{ secrets.KEY_PROPERTIES }}" }
      - run: echo "$UPLOAD_KEYSTORE" | base64 --decode > android/app/upload-keystore.jks
        env: { UPLOAD_KEYSTORE: "${{ secrets.UPLOAD_KEYSTORE }}" }
      - run: >
          flutter build appbundle --release --flavor ${{ matrix.flavor }}
          --dart-define-from-file=config/${{ matrix.flavor }}/production.json
      - uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJson: …
          packageName: ${{ matrix.package }}
          releaseFiles: build/app/outputs/bundle/${{ matrix.flavor }}Release/app-${{ matrix.flavor }}-release.aab
          track: production
          status: draft           # lands as a draft; roll it out by hand in Play Console
```

### 10.2 How secrets are resolved

GitHub has two places for Actions secrets:

| Kind | Where | Read by |
| --- | --- | --- |
| Repository secrets | Settings → Secrets and variables → Actions | every job |
| Environment secrets | Settings → Environments → *environment* | only jobs with `environment:` set to it |

For `${{ secrets.X }}`, a job uses the **environment** secret `X` if it exists, otherwise the
**repository** secret `X`. This gives a clean setup:

- Values shared by every flavor (one Firebase project's service account, one Play Console service
  account) stay as **repository** secrets, set once.
- Values that differ per flavor (`KEY_PROPERTIES`, `UPLOAD_KEYSTORE`, the production config) go into
  each flavor's **environment** under the same names.
- Never put one flavor's values into repository secrets when another flavor already uses those
  names: they would replace them.

The fallback is also a risk: if a flavor's environment lacks its config secret, the job silently
reads another flavor's repository config. Check the `BRAND` key in CI before building (and at
startup, section 3.3) so a wrong config fails the job instead of shipping.

### 10.3 Keystore path in CI

CI usually writes the keystore under one fixed name (here `android/app/upload-keystore.jks`). The
`KEY_PROPERTIES` secret must then say `storeFile=upload-keystore.jks`, even if your local
`key-globex.properties` points at `globex-upload-keystore.jks`. Keep a separate CI copy of the
properties file for the secret.

### 10.4 Parallel jobs

Matrix jobs start **at the same time**, each on its **own fresh virtual machine**. They don't share
RAM or disk, so adding a flavor never makes a build run out of memory. GitHub bills the minutes each
job runs, so running them one after another (`max-parallel: 1` under `strategy:`) costs the same and
only takes longer. On a private repository, each extra flavor adds its build minutes to the monthly
free quota.

### 10.5 Release rules

- Google Play cannot receive an API upload for an app that has never had a build. Upload the first
  bundle of a new flavor by hand in Play Console.
- Each upload needs a **higher version code** (`version: x.y.z+N` in `pubspec.yaml`) than that app
  already has. Bump it before every release push, or every flavor's upload fails.
- With `status: draft`, a push uploads but nothing goes live until someone rolls out each app in
  Play Console.
- Gate a new flavor behind a repository **variable** (e.g. `GLOBEX_RELEASE_ENABLED=true`) that the
  workflow reads when building the matrix. Turn it on only once its Play app, first upload and
  secrets exist.
- iOS uploads need a macOS runner and Apple signing in CI. Building IPAs locally
  (`flutter build ipa --flavor x`) and uploading with Transporter is a simpler start.

---

## 11. Pitfalls (all real)

| Symptom | Cause / fix |
| --- | --- |
| `flutter run` fails after adding Android flavors | Add `default-flavor:` to `pubspec.yaml`, or always pass `--flavor`. |
| Android build: "No matching client found for package name" | `google-services.json` has no entry for this flavor's application ID. Register the app in Firebase and re-download. |
| Release bundle signed with the wrong key | A `signingConfig` on the release **build type** overrides the flavor's. Remove it. |
| iOS: "The Xcode project does not define custom schemes" / wrong app built | The scheme name must equal the flavor name and be **Shared**. |
| iOS: plugin/Pods link errors only in flavor builds | Podfile is missing the new configurations. Add them and run `pod install`. |
| iOS: still shows the old name/icon | `CFBundleDisplayName` hard-coded, or `ASSETCATALOG_COMPILER_APPICON_NAME`/bundle ID not set per configuration. |
| iOS: crashes report to the wrong Firebase app | One plist copied for all flavors, or the Crashlytics script pinned to `default`. |
| Flavor-only image missing in tests or web | Flavor-conditional assets are excluded from other flavors. Use `flutter test --flavor x`. Web has no flavors. |
| Running `flutter_launcher_icons` no longer updates the default icons | With flavor files present, the default yaml is ignored. |
| `Info.plist` diff is the whole file | The splash tool re-indented it. Restore it and re-apply only the real changes. |
| Second flavor build "deletes" the first artifact | Shared output folders. Copy artifacts per flavor right after each build. |
| Wrong backend in a flavor build | Config file of another brand passed. Add a `BRAND` key and validate at startup. |
| CI: a flavor's values replaced another flavor's | Per-flavor values were added as repository secrets. Put them in that flavor's environment. |
| CI: release signing fails, keystore not found | `storeFile` in the `KEY_PROPERTIES` secret doesn't match the name CI writes the keystore to. |
| CI: Play upload rejected, version code already used | `pubspec.yaml` version `+N` not bumped since the last upload. |
| CI: Play API says the app/package was not found | No build was ever uploaded for that app. Upload the first one by hand. |

---

## 12. Learning exercise in a fresh project

1. `flutter create flavors_demo` and add two flavors on **Android** only (sections 5.1–5.2). Run
   `flutter run --flavor acme` and `--flavor globex` and install both side by side.
2. Add `default-flavor` and the Dart detection (3.1). Print `AppBrand.current` and show
   `BrandConfig.current.appName` in the app bar.
3. Add config files (3.2) with a different `API_BASE_URL` each, plus the `BRAND` check (3.3). Try the
   wrong combination and watch it fail.
4. Do **iOS by hand in Xcode** (6.1–6.6): configurations, xcconfigs, schemes, Podfile. Verify with
   section 6.10.
5. Generate a different icon and splash per flavor (section 7).
6. Add brand colors (3.5) and one brand-specific widget (3.6).
7. Optional: Firebase (section 8) and per-flavor signing (5.3), then a release build of each.

---

## How this repository does it

| Step | Files in this repo |
| --- | --- |
| Flavor detection, validation, widget switch | `lib/src/common/brand/app_brand.dart` |
| Brand names, logos, placeholders | `lib/src/common/brand/brand_config.dart` |
| Brand colors | `lib/src/common/brand/brand_colors.dart`, `lib/src/common/widget/avera_card_kit.dart` |
| Firebase per flavor | `lib/src/common/brand/brand_firebase_options.dart`, `lib/firebase_options_profit7.dart`, `firebase.json` |
| Brand widget overrides | `lib/src/feature/home/widget/brands/profit7/`, `lib/src/feature/home/widget/mobile/home_module_tile.dart` |
| Config per flavor | `config/avera/`, `config/profit7/` (`production.json` git-ignored) |
| pubspec | `default-flavor: avera`, flavor-conditional `assets/brands/profit7/` |
| Android | `android/app/build.gradle.kts`, `android/app/src/{avera,profit7}/res/`, `android/app/google-services.json` |
| iOS | `ios/Flutter/{Debug,Profile,Release}-{avera,profit7}.xcconfig`, `ios/Flutter/brands/`, `ios/Podfile`, `ios/Runner/Info.plist`, `ios/Runner/Firebase/`, schemes in `ios/Runner.xcodeproj/xcshareddata/xcschemes/` |
| Icons and splash | `flutter_launcher_icons-profit7.yaml`, `flutter_native_splash-profit7.yaml`, `assets/brands/profit7/launcher/` |
| Makefile | `FLAVOR=` variable, `build-android-appBundle[-all]`, `build-ios-ipa[-all]`, `build-store-all` |
| CI | `.github/workflows/android-cd.yml` (per-brand matrix, `PROFIT7_RELEASE_ENABLED` gate, environments `avera-production`/`profit7-production`) |
| CI secrets setup | `docs/PROFIT7_RELEASE_SETUP.md` → "CI releases (GitHub Actions)" |
| Background and decisions | `docs/AVERA_PROFIT7_FLAVOR_PLAN.md`, `docs/PROFIT7_RELEASE_SETUP.md` |
