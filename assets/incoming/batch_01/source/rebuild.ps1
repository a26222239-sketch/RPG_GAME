$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$artRoot = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'battle_ui_atlas.png'))) { throw 'Rebuild requires source/battle_ui_atlas.png from the delivery package. Production PNGs are ready to use.' }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $artRoot '../../..'))
$artInput = Join-Path ([IO.Path]::GetTempPath()) ('rpg-battle-ui-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $artInput | Out-Null
$artFiles = @('ui/panel.png','ui/hp_track.png','ui/hp_fill.png','backgrounds/battle/tianmo_hall.jpg')
foreach ($artId in @('yanhui_peak','shen_peak','huo_peak','wen_peak','tianmo')) {
 $artFiles += "characters/$artId/frames/stand.png"
 if ($artId -ne 'tianmo') { $artFiles += "characters/$artId/portrait/head.png" }
}
foreach ($artFile in $artFiles) {
 Copy-Item -LiteralPath (Join-Path $repoRoot ('assets/' + $artFile)) -Destination (Join-Path $artInput ($artFile.Replace('/','_')))
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'assets/ui/button.png') -Destination (Join-Path $artInput 'button.png')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'battle_ui_atlas.png') -Destination (Join-Path $artInput 'ui-generated.png')
$artRefs = @([Drawing.Bitmap].Assembly.Location,[Drawing.Color].Assembly.Location) + @(Get-ChildItem -LiteralPath $PSHOME -Filter 'System.Private.Windows*.dll' | Select-Object -ExpandProperty FullName)
Add-Type -ReferencedAssemblies $artRefs -Path (Join-Path $PSScriptRoot 'build.cs')
Add-Type -ReferencedAssemblies $artRefs -Path (Join-Path $PSScriptRoot 'verify.cs')
$artManifest = Get-Content -LiteralPath (Join-Path $artRoot 'manifest.json') -Raw | ConvertFrom-Json
[BattleUiArt]::Run($artInput,$artRoot)
$artMetrics = [UiVerify]::Run($artRoot,(Join-Path $artInput 'button.png'))
foreach ($artAsset in $artManifest.assets) {
 $artHash = (Get-FileHash -LiteralPath (Join-Path $artRoot $artAsset.path) -Algorithm SHA256).Hash.ToLowerInvariant()
 if ($artHash -ne $artAsset.sha256) { throw ('Hash mismatch: ' + $artAsset.path) }
}
Write-Output ('PASS: ' + $artMetrics.Count + ' assets; expected SHA256 matched.')
Write-Output ('Temporary source copies: ' + $artInput)

