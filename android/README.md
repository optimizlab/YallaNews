# Android upload signing

`upload_certificate.pem` in the repository root is the **public** upload
certificate for the `upload` key. It is the file to submit in Google Play's
upload-key reset form. The current PEM matches the certificate reported for the
release signing configuration.

## Export the certificate again

Run this from PowerShell in the repository:

```powershell
.\android\export_upload_certificate.ps1
```

The script reads the keystore path and alias from the local
`android\key.properties`, then prompts `keytool` for the keystore password
without putting it in the command line. It exports the public certificate to
`upload_certificate.pem`. Do not replace the keystore to perform a certificate
export: the certificate must correspond to the private upload key registered
with Google Play.

## Keep signing credentials safe

Never commit `android\app\upload-keystore.jks`, `android\key.properties`, or
keystore passwords. The Android `.gitignore` excludes the local keystore and
properties file. The PEM certificate is public and can be committed.

The GitHub Actions workflow **Android release bundle** builds a signed
`.aab` when manually run. Configure these repository **Actions secrets** first:

- `ANDROID_UPLOAD_KEYSTORE_BASE64` — base64-encoded contents of
  `android\app\upload-keystore.jks`
- `ANDROID_UPLOAD_STORE_PASSWORD` — keystore password
- `ANDROID_UPLOAD_KEY_ALIAS` — key alias (currently `upload`)
- `ANDROID_UPLOAD_KEY_PASSWORD` — key password

With GitHub CLI authenticated for this repository, the keystore secret can be
set without writing a base64 copy into the repository:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\app\upload-keystore.jks")) |
    gh secret set ANDROID_UPLOAD_KEYSTORE_BASE64
```

Set the three password/alias secrets through the repository's **Settings →
Secrets and variables → Actions** page or `gh secret set`. The workflow restores
the ignored local files only for the build job and uploads the resulting
`app-release.aab` as a workflow artifact.

If the upload key is genuinely lost or compromised, request a reset in Play
Console and generate a replacement key as directed by Google. Do not select a
reset reason that does not describe what happened. Google must approve the
reset before the replacement key can sign new uploads.
