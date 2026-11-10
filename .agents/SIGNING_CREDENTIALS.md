# Android Release Signing Configuration & Credentials

This file documents the official Android release signing configuration for **YallaNews** (`inoov.app.yallanews`) to ensure consistent, reproducible builds across development and CI/CD deployment pipelines.

> [!IMPORTANT]
> **Password (store & key):** `YallaNews_Upload_Reset_2026!_v1`
> This single password unlocks both the keystore file and the signing key alias `upload`.
> Never lose this — without it you cannot sign new releases.

---

## 🔑 Quick Recovery — Restore `key.properties` from Scratch

If `android/key.properties` is ever missing, run this in PowerShell from the project root:

```powershell
@"
storePassword=YallaNews_Upload_Reset_2026!_v1
keyPassword=YallaNews_Upload_Reset_2026!_v1
keyAlias=upload
storeFile=app/upload-keystore.jks
"@ | Set-Content android\key.properties -Encoding UTF8
```

The keystore file itself lives at `android/app/upload-keystore.jks` (committed to git is **NOT** recommended — keep it on disk and back it up separately).

---

## 1. Local Keystore & Key Properties

### `android/key.properties`
Located at: `android/key.properties` (ignored by git for security)
```properties
storePassword=YallaNews_Upload_Reset_2026!_v1
keyPassword=YallaNews_Upload_Reset_2026!_v1
keyAlias=upload
storeFile=app/upload-keystore.jks
```

### Keystore Specifications
* **File Path:** `android/app/upload-keystore.jks` (relative to `android/` root: `app/upload-keystore.jks`)
* **Format:** PKCS12
* **Alias:** `upload`
* **Password:** `YallaNews_Upload_Reset_2026!_v1`
* **Owner / Issuer:** `CN=Yalla News Upload, O=Inoov, C=US`
* **Validity:** Valid until November 2, 2051

### Certificate Fingerprints
* **SHA-1:** `5D:4C:16:89:34:5B:4E:EE:EF:5D:7C:B8:1C:C1:5C:A5:51:58:FF:08`
* **SHA-256:** `0C:F4:2A:67:72:85:17:CE:07:B5:72:52:20:FC:D2:41:04:5B:76:95:F5:BF:DF:6B:87:CF:27:3E:64:31:CE:64`

---

## 2. Google Play Upload Key Reset (PEM Certificate)

* **Public Certificate Path:** `upload_certificate.pem` (in repository root)
* If Google Play rejects an upload bundle due to an upload key mismatch, submit `upload_certificate.pem` to Google Play Console:
  1. Open [Google Play Console](https://play.google.com/console) > Select **YallaNews**.
  2. Navigate to **Setup > App integrity** (or **App signing**).
  3. Under **Upload key certificate**, click **Request upload key reset**.
  4. Select the reason (e.g., lost or compromised upload key) and upload `upload_certificate.pem`.
  5. Once approved by Google, releases signed with this keystore will be accepted.

---

## 3. CI / GitHub Actions Deployment Secrets

Configure the following secrets under repository **Settings > Secrets and variables > Actions**:

| Secret Name | Value |
|---|---|
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | Base64-encoded content of `android/app/upload-keystore.jks` |
| `ANDROID_UPLOAD_STORE_PASSWORD` | `YallaNews_Upload_Reset_2026!_v1` |
| `ANDROID_UPLOAD_KEY_ALIAS` | `upload` |
| `ANDROID_UPLOAD_KEY_PASSWORD` | `YallaNews_Upload_Reset_2026!_v1` |

### Command to generate base64 string on Windows (PowerShell):
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\app\upload-keystore.jks")) | Set-Clipboard
```

---

## 4. How to Generate Signed Release Bundle (.aab)

Run the following command from the project root:

```bash
flutter build appbundle --release
```

The resulting bundle is written to:
`build/app/outputs/bundle/release/app-release.aab`

To verify the signature of the generated `.aab`:
```powershell
jarsigner -verify -verbose -certs "build\app\outputs\bundle\release\app-release.aab"
```

