# Run on Windows with a cached Microsoft.Web.WebView2 NuGet SDK and installed runtime:
# powershell -NoProfile -File test/scroll_document_rewrite_test.ps1
param([string]$WebView2Sdk)
$ErrorActionPreference = 'Stop'
if (-not $WebView2Sdk) {
  $WebView2Sdk = (Get-ChildItem "$env:USERPROFILE\.nuget\packages\microsoft.web.webview2" -Directory |
    Sort-Object Name -Descending | Select-Object -First 1).FullName
}
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('webview-scroll-rewrite-' + [guid]::NewGuid())
New-Item $scratch -ItemType Directory | Out-Null
try {
  $controller = Get-Content (Join-Path $PSScriptRoot '../lib/src/windows_webview_controller.dart') -Raw
  $start = $controller.IndexOf('_scrollBridgeInstalled = true;')
  $script = [regex]::Match($controller.Substring($start), "(?s)final script =\s*'''(.*?)''';").Groups[1].Value
  if (-not $script) { throw 'Could not extract the production scroll bridge script' }
  $script = $script.Replace('$_channelMessageType', '__windows_webview_all_type').Replace('$_scrollMessageType', 'scrollPositionChange')
  [System.IO.File]::WriteAllText((Join-Path $scratch 'scroll.js'), $script)
  foreach ($assembly in @('Core', 'WinForms')) {
    Copy-Item (Join-Path $WebView2Sdk "lib/net45/Microsoft.Web.WebView2.$assembly.dll") $scratch
  }
  Copy-Item (Join-Path $WebView2Sdk 'runtimes/win-x64/native/WebView2Loader.dll') $scratch
  $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
  & $compiler /nologo /target:exe /platform:x64 "/out:$scratch/scroll-test.exe" `
    /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll `
    "/r:$scratch/Microsoft.Web.WebView2.Core.dll" "/r:$scratch/Microsoft.Web.WebView2.WinForms.dll" `
    (Join-Path $PSScriptRoot 'scroll_document_rewrite_test.cs')
  if ($LASTEXITCODE -ne 0) { throw 'C# test harness compilation failed' }
  & "$scratch/scroll-test.exe" "$scratch/scroll.js"
  if ($LASTEXITCODE -ne 0) { throw 'WebView2 regression test failed' }
} finally {
  Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
