# Android signing

`lunarcleanup.keystore` is a **public development key** (alias `lunarcleanup`, password
`lunarcleanup`). It is committed on purpose so every automated build is signed with the
same certificate - that is what lets a new APK install *over* the old one and keep your
saves. It protects nothing: anyone can read it. That is fine for a free personal project.

## Switching to a private key (optional, can be done from a phone)

1. Create a keystore (e.g. with the free "APK Signer"/"keytool" apps, or ask Claude).
2. In GitHub: repository **Settings > Secrets and variables > Actions > New repository secret**:
   - `ANDROID_KEYSTORE_BASE64` - the keystore file, base64 encoded
   - `ANDROID_KEYSTORE_ALIAS` - key alias
   - `ANDROID_KEYSTORE_PASSWORD` - store/key password
3. The next build uses it automatically (see `.github/workflows/build-android.yml`).

Changing the signing key means Android will refuse to *update* the installed game: you
would have to uninstall first, which deletes local saves. Decide early.
