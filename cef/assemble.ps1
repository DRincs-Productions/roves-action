# Assembles the Windows CEF player package from an extracted roves_shell_windows[_steam|_mcp].zip
# release asset (see ../README.md, "Desktop: the CEF player"; macOS/Linux: assemble.sh). Kept in
# step with roves-packmaster's src-tauri/src/cef_player.rs:
#
#   1. Locate the base package (the folder with play.exe, or its only such subfolder).
#   2. Verify it against its own SHA256SUMS.txt: every file listed, every listed file present
#      with that hash, nothing unlisted.
#   3. EnableMcp: require a complete MCP-enabled base (mcp\enabled, mcp\server.mjs,
#      mcp\README.md, the @modelcontextprotocol/server dependency, and the MCP section the
#      engine CI writes into PROVENANCE.txt). Never add MCP files of our own.
#   4. Copy the base without game\, without the sample game's provenance and, unless
#      EnableMcp, without mcp\ and provenance\mcp-*; copy ContentDir to game\.
#   5. Project icon (IconDir, from project_icon.py): the base's icon.png (the sample game's
#      window icon) is never copied; the resolved icon.png is added when the game has one and
#      play.exe's icon resource is patched with the resolved play.ico (rcedit).
#   6. Rewrite PROVENANCE.txt (MCP section dropped when off, a "game replaced" note
#      appended) and regenerate SHA256SUMS.txt.
param(
  [Parameter(Mandatory)] [string] $BaseDir,
  [Parameter(Mandatory)] [string] $ContentDir,
  [Parameter(Mandatory)] [string] $OutDir,
  [Parameter(Mandatory)] [ValidateSet('true', 'false')] [string] $EnableMcp,
  [string] $BaseNote = '',
  [string] $IconDir = '',
  [string] $Rcedit = '',
  [string] $IconNote = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$mcpOn = $EnableMcp -eq 'true'
$mcpHeader = 'MCP-enabled development package'
$mcpRequired = @('mcp/enabled', 'mcp/server.mjs', 'mcp/README.md', 'mcp/node_modules/@modelcontextprotocol/server/package.json')

function Get-Rel([string] $root, [string] $path) { $path.Substring($root.Length).TrimStart('\', '/').Replace('\', '/') }
function Get-Sha([string] $path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() }

# 1. Locate.
$BaseDir = (Resolve-Path -LiteralPath $BaseDir).Path
$base = if (Test-Path -LiteralPath (Join-Path $BaseDir 'play.exe') -PathType Leaf) { $BaseDir } else {
  $found = @(Get-ChildItem -LiteralPath $BaseDir -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'play.exe') -PathType Leaf })
  if ($found.Count -ne 1) { throw "$BaseDir does not contain exactly one CEF player package (folders with play.exe: $($found.Count))" }
  $found[0].FullName
}
foreach ($required in @('play.exe', 'play.dll', 'play.exe.manifest', 'libcef.dll', 'PROVENANCE.txt', 'SHA256SUMS.txt')) {
  if (-not (Test-Path -LiteralPath (Join-Path $base $required) -PathType Leaf)) { throw "the CEF base package lacks $required" }
}

# 2. Verify.
$listed = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $base 'SHA256SUMS.txt') -Encoding utf8) {
  if (-not $line.Trim()) { continue }
  $line = $line.TrimStart([char]0xFEFF)
  $at = $line.IndexOf('  ')
  if ($at -lt 0) { throw "malformed SHA256SUMS.txt line: $line" }
  $rel = $line.Substring($at + 2).TrimEnd()
  if ($rel -match '(^|/)\.\.?(/|$)' -or $rel -match '^[/\\]|:') { throw "SHA256SUMS.txt lists an unsafe path: $rel" }
  $listed[$rel] = $line.Substring(0, $at).ToLowerInvariant()
}
foreach ($file in Get-ChildItem -LiteralPath $base -Recurse -File) {
  $rel = Get-Rel $base $file.FullName
  if ($rel -ne 'SHA256SUMS.txt' -and -not $listed.ContainsKey($rel)) { throw "the CEF base package contains $rel, which its SHA256SUMS.txt does not list" }
}
foreach ($rel in $listed.Keys) {
  $path = Join-Path $base $rel
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "the CEF base package lacks $rel, listed in its SHA256SUMS.txt" }
  if ((Get-Sha $path) -ne $listed[$rel]) { throw "$rel does not match the CEF base package's SHA256SUMS.txt" }
}
Write-Output "::notice::CEF base package verified against its SHA256SUMS.txt ($($listed.Count) files)"

# 3. MCP capability.
$provenance = Get-Content -LiteralPath (Join-Path $base 'PROVENANCE.txt') -Encoding utf8
$mcpCapable = (@($mcpRequired | Where-Object { -not (Test-Path -LiteralPath (Join-Path $base $_) -PathType Leaf) }).Count -eq 0) -and
  [bool]($provenance | Where-Object { $_.StartsWith($mcpHeader) })
if ($mcpOn -and -not $mcpCapable) {
  throw 'enable-mcp is true, but the CEF base package is not a complete MCP-enabled package (it needs the roves_shell_windows_mcp.zip release asset)'
}
if (-not (Test-Path -LiteralPath (Join-Path $ContentDir 'index.html') -PathType Leaf)) { throw "$ContentDir has no index.html at its root" }

# 4. Copy.
if (Test-Path -LiteralPath $OutDir) { throw "$OutDir already exists" }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
foreach ($file in Get-ChildItem -LiteralPath $base -Recurse -File) {
  $rel = Get-Rel $base $file.FullName
  $first = $rel.Split('/')[0]
  if ($first -eq 'game' -or $rel -in @('SHA256SUMS.txt', 'PROVENANCE.txt', 'icon.png') -or $rel.StartsWith('provenance/visual-novel-template-')) { continue }
  if (-not $mcpOn -and ($first -eq 'mcp' -or $rel.StartsWith('provenance/mcp-'))) { continue }
  $target = Join-Path $OutDir $rel
  New-Item -ItemType Directory -Force (Split-Path -Parent $target) | Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $target
}
$ContentDir = (Resolve-Path -LiteralPath $ContentDir).Path
foreach ($file in Get-ChildItem -LiteralPath $ContentDir -Recurse -File) {
  $target = Join-Path (Join-Path $OutDir 'game') (Get-Rel $ContentDir $file.FullName)
  New-Item -ItemType Directory -Force (Split-Path -Parent $target) | Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $target
}

# 5. Project icon.
$exeIcon = 'unchanged'
if ($IconDir) {
  $windowPng = Join-Path $IconDir 'icon.png'
  if (Test-Path -LiteralPath $windowPng -PathType Leaf) { Copy-Item -LiteralPath $windowPng -Destination (Join-Path $OutDir 'icon.png') }
  $playIco = Join-Path $IconDir 'play.ico'
  if (Test-Path -LiteralPath $playIco -PathType Leaf) {
    if (-not $Rcedit) { throw 'a play.exe icon was resolved but no rcedit path was given' }
    & $Rcedit (Join-Path $OutDir 'play.exe') --set-icon $playIco
    if ($LASTEXITCODE -ne 0) { throw "rcedit exit $LASTEXITCODE" }
    $exeIcon = 'replaced'
  }
}

# 6. Provenance and checksums.
$lines = [System.Collections.Generic.List[string]]::new()
foreach ($line in $provenance) {
  if (-not $mcpOn -and $line.StartsWith($mcpHeader)) { break }
  $lines.Add($line.TrimStart([char]0xFEFF))
}
while ($lines.Count -and -not $lines[$lines.Count - 1].Trim()) { $lines.RemoveAt($lines.Count - 1) }
$lines.Add('')
$lines.Add('Game replaced by DRincs-Productions/roves-action')
$lines.Add('  game\ contains the developer''s own build output; any sample game of the base package')
$lines.Add('  and its provenance files were removed. The')
if ($exeIcon -eq 'replaced') {
  $lines.Add('  engine files (play.exe, play.dll, CEF runtime) are the base package''s; only play.exe''s')
  $lines.Add('  icon resource was replaced (electron/rcedit v2.0.0).')
} else {
  $lines.Add('  engine files (play.exe, play.dll, CEF runtime) are the base package''s, unmodified.')
}
if ($IconNote) { $lines.Add("  icons: $IconNote") }
if ($BaseNote) { $lines.Add("  base: $BaseNote") }
if ($mcpOn) {
  $lines.Add('  Local MCP bridge: ON (mcp\enabled kept). Development and playtests only: any program')
  $lines.Add('  running as your Windows user can read and control the running game. Never ship to players.')
} else {
  $lines.Add('  Local MCP bridge: OFF (no mcp\ folder, no activation marker).')
}
$lines | Set-Content -Encoding utf8 (Join-Path $OutDir 'PROVENANCE.txt')
Get-ChildItem -LiteralPath $OutDir -Recurse -File | Where-Object { (Get-Rel $OutDir $_.FullName) -ne 'SHA256SUMS.txt' } | ForEach-Object {
  $rel = Get-Rel $OutDir $_.FullName
  [pscustomobject]@{ Rel = $rel; Line = "$(Get-Sha $_.FullName)  $rel" }
} | Sort-Object { $_.Rel } | ForEach-Object { $_.Line } | Set-Content -Encoding utf8 (Join-Path $OutDir 'SHA256SUMS.txt')

$marker = Test-Path -LiteralPath (Join-Path $OutDir 'mcp/enabled') -PathType Leaf
if ($mcpOn -ne $marker -or (-not $mcpOn -and (Test-Path -LiteralPath (Join-Path $OutDir 'mcp')))) {
  throw 'internal error: the MCP state of the assembled package does not match enable-mcp'
}
Write-Output "::notice::CEF Windows package assembled (local MCP bridge $(if ($mcpOn) { 'ON' } else { 'OFF' }))"
