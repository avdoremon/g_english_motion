# Releasing the Android app

Release builds are signed from `android/key.properties`. That file and the
keystore are gitignored (`android/key.properties`, `*.jks`, `*.keystore`) and
must never be committed. Without `key.properties` the release build falls back
to the debug key and prints a warning, so CI and contributors can still build;
such an APK cannot be published.

## 1. Create the upload keystore (once, keep it safe)

```
keytool -genkey -v -keystore ~/upload-keystore.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Store the keystore and its passwords somewhere backed up (password manager).
Losing it means losing the ability to update the app unless Play App Signing
is enabled and the upload key can be reset.

## 2. Create `android/key.properties`

```
storePassword=<keystore password>
keyPassword=<key password>
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

## 3. Build

```
flutter build apk --release        # sideload / testing
flutter build appbundle --release  # Play Store
```

R8 minification and resource shrinking are on; the rules live in
`android/app/proguard-rules.pro` (MediaPipe and protobuf are kept). CI job
`build-android-release` builds a release APK on every pull request. If R8
reports missing classes, add the suggestions from
`build/app/outputs/mapping/release/missing_rules.txt`.

## What stays device-only

R8 can only be verified on a real device: install the release build and check
that the camera starts, pose detection works and the motion modes respond.
Pose accuracy and frame rate are also device-only (see
`docs/device-spike-actions.md`).

## Owner decisions still open

The Play Store Families Policy / ads decision is the owner's; nothing in this
repository decides it.
