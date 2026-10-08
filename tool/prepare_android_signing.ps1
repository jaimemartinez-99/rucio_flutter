$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$signingRoot = Join-Path $env:USERPROFILE '.rucio/signing'
$releaseKey = Join-Path $signingRoot 'rucio-release.keystore'
$originalKey = Join-Path $env:USERPROFILE '.android/debug.keystore'
$certificateFile = Join-Path $projectRoot 'android/release-certificate.sha256'
$keytool = Join-Path $env:LOCALAPPDATA 'Android/jdk17/jdk-17.0.20.1+1/bin/keytool.exe'
if (-not (Test-Path -LiteralPath $keytool)) { $keytool = (Get-Command keytool -ErrorAction Stop).Source }
if (-not (Test-Path -LiteralPath $releaseKey)) {
    if (-not (Test-Path -LiteralPath $originalKey)) { throw 'Restaura la clave original de Rucio antes de preparar la firma.' }
    New-Item -ItemType Directory -Path $signingRoot -Force | Out-Null
    Copy-Item -LiteralPath $originalKey -Destination $releaseKey
}
$certificate = & $keytool '-J-Duser.language=en' -list -v -keystore $releaseKey -storepass android -alias androiddebugkey 2>&1
if ($LASTEXITCODE -ne 0) { throw 'No se pudo verificar la clave de firma de Rucio.' }
$fingerprintLine = ($certificate | Select-String 'SHA256:').Line
if (-not $fingerprintLine) { throw 'No se encontró el certificado de firma.' }
$fingerprint = ($fingerprintLine -replace '.*SHA256:\s*', '' -replace ':', '').Trim().ToLowerInvariant()
if ((Test-Path -LiteralPath $certificateFile) -and (Get-Content -LiteralPath $certificateFile -Raw).Trim() -ne $fingerprint) {
    throw 'Esta clave no coincide con la firma original de Rucio. Restaura la copia de seguridad.'
}
Set-Content -LiteralPath $certificateFile -Value $fingerprint -Encoding utf8
$backupRoot = Join-Path $signingRoot 'backup'
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
$backupKey = Join-Path $backupRoot 'rucio-release.keystore'
if (-not (Test-Path -LiteralPath $backupKey)) { Copy-Item -LiteralPath $releaseKey -Destination $backupKey }
$properties = "storeFile=$($releaseKey.Replace('\', '/'))`nstorePassword=android`nkeyAlias=androiddebugkey`nkeyPassword=android`n"
Set-Content -LiteralPath (Join-Path $projectRoot 'android/key.properties') -Value $properties -Encoding ascii
Write-Output "Firma preparada y respaldada. Certificado: $fingerprint"
