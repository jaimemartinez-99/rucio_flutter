$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot 'build/native_audio_tests'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $installation) { throw 'Visual Studio C++ tools were not found.' }
$developerCommand = Join-Path $installation 'Common7/Tools/VsDevCmd.bat'
$includeDirectory = Join-Path $projectRoot 'windows/flutter/ephemeral/cpp_client_wrapper/include'
$sourceFile = Join-Path $projectRoot 'test/native/audio_event_thread_test.cpp'
$executable = Join-Path $outputDirectory 'audio_event_thread_test.exe'
$objectFile = Join-Path $outputDirectory 'audio_event_thread_test.obj'
$batchFile = Join-Path $outputDirectory 'run.cmd'
$commands = @"
@call "$developerCommand" -arch=x64 -host_arch=x64 >nul
@if errorlevel 1 exit /b 1
@cl /nologo /std:c++20 /EHsc /W4 /WX /wd4100 /DUNICODE /D_UNICODE /I"$includeDirectory" "$sourceFile" /Fe:"$executable" /Fo:"$objectFile" user32.lib
@if errorlevel 1 exit /b 1
@"$executable"
"@
Set-Content -LiteralPath $batchFile -Value $commands -Encoding ascii
& cmd.exe /d /c $batchFile
if ($LASTEXITCODE -ne 0) { throw 'Native audio event tests failed.' }
