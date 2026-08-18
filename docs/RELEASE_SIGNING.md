# Release APK signing

Building a release APK:

```powershell
cd frontend\agrisense_app
flutter build apk --release
```

The APK lands at `build\app\outputs\flutter-apk\app-release.apk`.

## Why you might see `SigningConfig "release" is missing required property "storeFile"`

This error means `android\app\build.gradle.kts` points the release build at a
`release` signing config whose keystore cannot be resolved. The usual causes:

1. `android\key.properties` does not exist (the `storeFile` value is then null).
2. `android\key.properties` exists, but the `storeFile` path points to a
   keystore file that is not there (typo, moved file, or `\` backslashes in the
   path — see below).
3. The keystore file exists but is not where the Gradle script looks for it.

The Gradle script in this repo is configured to handle this gracefully:

- **No `android\key.properties`** → release builds are signed with the **debug
  key**. The build succeeds; the APK is installable on devices for testing, but
  it is **not** Play-Store-ready.
- **`android\key.properties` present and valid** → release builds are signed
  with your keystore.
- **`key.properties` present but broken** (missing entry, keystore not found) →
  the build fails with a descriptive message instead of the cryptic
  "missing required property" error.

## Option A — just need an installable APK right now (no keystore)

Do nothing: with no `key.properties` the build signs with the debug key and
succeeds. Note that a debug-signed APK cannot be installed over a properly
signed one (and vice versa) without uninstalling first.

## Option B — proper release signing (required for the Play Store)

### 1. Generate a keystore (one time)

`keytool` ships with the JDK bundled inside Android Studio:

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" `
  -genkey -v -keystore upload-keystore.jks `
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Keep the keystore **outside the repository** (e.g. `C:\Users\<you>\keystores\`)
and back it up. If you lose it, you can never update the app under the same
signature. Never commit it — the repo's `.gitignore` already excludes
`*.jks` / `*.keystore` / `key.properties`.

### 2. Create `android\key.properties`

In `frontend\agrisense_app\android\` create `key.properties`:

```properties
storePassword=<keystore password from step 1>
keyPassword=<key password from step 1>
keyAlias=upload
storeFile=C:/Users/<you>/keystores/upload-keystore.jks
```

**Use forward slashes (`/`) in `storeFile`, even on Windows.** `key.properties`
is a Java properties file, so a Windows path like `C:\Users\greys\...` would
have its backslashes eaten as escape characters. Relative paths are resolved
against `android/app/` and `android/`.

### 3. Rebuild

```powershell
flutter build apk --release
```

You should see `Release build will be signed with the keystore from
android/key.properties` in the Gradle output.

### 4. Verify the signature (optional)

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\apksigner.bat" `
  verify --print-certs build\app\outputs\flutter-apk\app-release.apk
```

or

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\jarsigner.exe" `
  -verify -verbose -certs build\app\outputs\flutter-apk\app-release.apk
```

A debug-signed APK shows a certificate with `CN=Android Debug`; a proper one
shows the details you entered in step 1.

## Notes

- **Play App Signing**: Google re-signs with its own key on upload, so the
  keystore above is your *upload key*. It still must be kept safe.
- Changing the signing key (e.g. going from debug to release signing) means
  uninstalling the old APK on test devices first — Android refuses signature
  changes on update.
- `flutter run --release` uses the same signing config as `flutter build apk
  --release`.
