# Google Drive setup

Kover can browse your Google Drive and download EPUB, PDF and CBZ/ZIP books to the
on-device library. Google requires every app to identify itself with OAuth client
IDs, so Drive is **disabled until you create them**. Without them Kover builds and
runs normally and the Google Drive page shows "isn't set up in this build". Google
Sign-In is never called in that case.

Drive is available on Android and iOS only. Kover requests the read-only scope
`https://www.googleapis.com/auth/drive.readonly`.

## 1. Create a Google Cloud project

1. Open <https://console.cloud.google.com/> and create a project (for example "Kover").
2. Go to **APIs & Services > Library**, search for **Google Drive API** and click **Enable**.

## 2. Configure the OAuth consent screen

1. Go to **APIs & Services > OAuth consent screen** (Google Auth Platform > Branding / Audience) and
   choose **External**.
2. Fill in the app name, support email and developer contact email.
3. Under **Data Access (Scopes)** add `.../auth/drive.readonly`.
4. `drive.readonly` is a **restricted scope**:
   - While the publishing status is **Testing**, only the accounts listed under
     **Audience > Test users** can sign in (up to 100). Add your own Google account
     there. Test-user authorizations expire after 7 days, so you will have to sign in
     again weekly.
   - To let anyone sign in, the app must be published and pass Google's OAuth
     verification and, for restricted scopes, a security assessment. For personal use,
     staying in Testing is enough.

## 3. Create the OAuth clients

Create these under **APIs & Services > Credentials > Create credentials > OAuth client ID**.

### Web application (required on Android)

Create a client of type **Web application**. Copy its client ID (ends in
`.apps.googleusercontent.com`). This is `GOOGLE_SERVER_CLIENT_ID`. Android signs in
through Google Play services and needs it as the server client ID.

### Android

Create a client of type **Android**:

- Package name: `com.gemsinal.kover`
- SHA-1 certificate fingerprint: one Android client per signing key, or add each key's
  SHA-1 (Google allows one SHA-1 per client, so create one client per key).

You need the SHA-1 of **both** keys:

```sh
# Debug keystore (used by `fvm flutter run`)
keytool -list -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android

# Release keystore (used by tools/build_android.sh)
source ~/keys/kover-release.env   # exports KEYSTORE_PATH, KEY_ALIAS, ...
keytool -list -v -keystore "$KEYSTORE_PATH" -alias "$KEY_ALIAS"
```

Copy the `SHA1:` line. The Android client has no ID to copy into the app; Google matches
it by package name and signature. No `google-services.json` is needed.

### iOS

Create a client of type **iOS** with bundle ID `com.rodonisi.kover` (check it in Xcode
under Runner > Signing & Capabilities). Copy:

- **Client ID** into `GOOGLE_IOS_CLIENT_ID`.
- **iOS URL scheme** (the reversed client ID, `com.googleusercontent.apps.<prefix>`) into
  `ios/Runner/Info.plist`, replacing the placeholder
  `com.googleusercontent.apps.REPLACE_WITH_IOS_CLIENT_ID_PREFIX` under
  `CFBundleURLTypes > CFBundleURLSchemes`.

Always update the URL scheme whenever you set the iOS client ID: signing in on iOS with a
missing scheme raises a native exception.

## 4. Provide the IDs to the build

```sh
cp config/google_drive.example.json config/google_drive.json
```

Edit `config/google_drive.json`:

```json
{
  "GOOGLE_IOS_CLIENT_ID": "<ios client id>.apps.googleusercontent.com",
  "GOOGLE_SERVER_CLIENT_ID": "<web client id>.apps.googleusercontent.com"
}
```

`config/google_drive.json` is git-ignored. Only the value for the platform you build is
needed (`GOOGLE_SERVER_CLIENT_ID` for Android, `GOOGLE_IOS_CLIENT_ID` for iOS).

## 5. Run and build

```sh
fvm flutter run --dart-define-from-file=config/google_drive.json
fvm flutter build ios --dart-define-from-file=config/google_drive.json
```

`tools/build_android.sh` passes the file automatically when it exists.

## Troubleshooting

- **"Not set up" in the add books sheet**: the build has no client ID for this platform.
  Pass `--dart-define-from-file`.
- **Android: sign-in fails with `Developer console is not set up correctly` / error 10**:
  the SHA-1 of the key that signed the installed build is not registered on an Android
  client (debug and release keys differ), or the package name is wrong.
- **"Access blocked: app has not completed verification"**: add your account as a test user.
- **Signed in earlier, now asked again after a week**: Testing-mode authorizations expire.
