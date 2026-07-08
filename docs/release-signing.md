# Release Signing

YouTubeJack release builds are Developer ID signed and notarized in GitHub Actions. Configure these repository secrets before pushing a release commit to `main`:

- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

## Certificate

Create or download a **Developer ID Application** certificate from Apple Developer, install it in Keychain Access, then export the certificate and private key as a `.p12` file.

If the `.p12` export already exists at `/Users/burakerenoglu/Desktop/Certificates.p12`, configure the GitHub secrets with:

```bash
./scripts/configure-release-secrets.sh
```

The script prompts locally for the `.p12` export password, Apple ID email, and Apple app-specific password. It validates that the `.p12` contains a **Developer ID Application** identity before writing secrets to GitHub.

Convert the `.p12` for GitHub:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Paste that value into `MACOS_CERTIFICATE_P12_BASE64`. Use the `.p12` export password for `MACOS_CERTIFICATE_PASSWORD`. `KEYCHAIN_PASSWORD` can be any strong random password used only by the workflow's temporary keychain.

## Notarization

Create an app-specific password for the Apple ID used by the Developer account, then set:

- `APPLE_ID`: Apple ID email
- `APPLE_TEAM_ID`: Apple Developer Team ID
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password

The release workflow signs the app with hardened runtime, notarizes and staples the app, creates the DMG, signs the DMG, notarizes and staples the DMG, then publishes the release asset.

## Local Signed DMG

If a **Developer ID Application** certificate is installed in Keychain, build a locally signed DMG with:

```bash
./scripts/build-signed-dmg.sh
```

The script:

1. Builds `YouTubeJack.app`
2. Signs bundled runtime executables such as `yt-dlp` and `ffmpeg`
3. Signs the app bundle with hardened runtime
4. Creates the drag-to-Applications DMG
5. Signs and verifies the DMG

Notarization still requires Apple notarization credentials. GitHub Actions handles notarization when the repository secrets above are configured.
