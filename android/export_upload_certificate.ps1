param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\upload_certificate.pem")
)

$ErrorActionPreference = "Stop"

$propertiesPath = Join-Path $PSScriptRoot "key.properties"
if (-not (Test-Path -LiteralPath $propertiesPath)) {
    throw "Android signing properties are missing: $propertiesPath"
}

$properties = @{}
Get-Content -LiteralPath $propertiesPath | ForEach-Object {
    if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*)$') {
        $properties[$matches[1].Trim()] = $matches[2].Trim()
    }
}

foreach ($name in @("storeFile", "keyAlias")) {
    if (-not $properties[$name]) {
        throw "Required property '$name' is missing from $propertiesPath"
    }
}

$keystorePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $properties["storeFile"]))
if (-not (Test-Path -LiteralPath $keystorePath)) {
    throw "Configured upload keystore was not found: $keystorePath"
}

$keytool = Get-Command "keytool" -ErrorAction Stop
$outputPath = [System.IO.Path]::GetFullPath($OutputPath)
if ((Test-Path -LiteralPath $outputPath) -and (Read-Host "Overwrite '$outputPath'? Type Y to continue") -notmatch '^(y|yes)$') {
    throw "Certificate export cancelled."
}

$temporaryCertificate = Join-Path $env:TEMP ("upload-certificate-" + [guid]::NewGuid().ToString("N") + ".pem")
try {
    & $keytool.Source -export -rfc -keystore $keystorePath -alias $properties["keyAlias"] -file $temporaryCertificate
    if ($LASTEXITCODE -ne 0) {
        throw "keytool could not export the certificate. Check the keystore password and alias."
    }

    Move-Item -LiteralPath $temporaryCertificate -Destination $outputPath -Force
    Write-Output "Upload certificate exported to $outputPath"
}
finally {
    Remove-Item -LiteralPath $temporaryCertificate -ErrorAction SilentlyContinue
}
