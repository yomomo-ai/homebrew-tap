# influo-cli installer for Windows.
#
# Usage:
#   irm https://raw.githubusercontent.com/yomomo-ai/homebrew-tap/main/install.ps1 | iex
#
# Detects arch, downloads the latest release zip from the public tap repo
# (yomomo-ai/homebrew-tap, which also hosts the brew formula), and installs
# into $env:LOCALAPPDATA\Programs\influo, prepending it to user PATH.
#
# Override the install dir with $env:INFLUO_PREFIX before piping into iex.

$ErrorActionPreference = "Stop"

$ReleasesRepo = "yomomo-ai/homebrew-tap"
$BinName      = "influo"

function Write-Step([string]$msg)  { Write-Host "  $msg" }
function Write-Muted([string]$msg) { Write-Host "  $msg" -ForegroundColor DarkGray }
function Write-OK([string]$msg)    { Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Bad([string]$msg)   { Write-Host "✗ $msg" -ForegroundColor Red }

Write-Host "influo · installer" -ForegroundColor Cyan
Write-Muted "─────────────────────────"

# ---- detect arch -----------------------------------------------------------

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    "AMD64" { "amd64" }
    "ARM64" { "arm64" }
    default {
        Write-Bad "不支持的 CPU 架构: $($env:PROCESSOR_ARCHITECTURE)"
        exit 1
    }
}
Write-Step "目标平台      windows/$arch"

# ---- look up latest release ------------------------------------------------

try {
    # GitHub API returns 403 without a UA header for some accounts; supply one.
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$ReleasesRepo/releases/latest" `
        -Headers @{ "User-Agent" = "influo-installer" }
} catch {
    Write-Bad "无法获取最新版本 (网络问题或仓库为空?): $_"
    exit 1
}
$tag = $release.tag_name
if (-not $tag) {
    Write-Bad "GitHub API 未返回 tag_name"
    exit 1
}
Write-Step "最新版本      $tag"

# ---- download + extract ----------------------------------------------------

$archive = "${BinName}_windows_${arch}.zip"
$url     = "https://github.com/$ReleasesRepo/releases/download/$tag/$archive"
Write-Step "下载          $url"

$tempRoot = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "influo-install-$([Guid]::NewGuid())") -Force
try {
    $zipPath = Join-Path $tempRoot.FullName $archive
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $tempRoot.FullName -Force

    $exe = Get-ChildItem -Path $tempRoot.FullName -Filter "${BinName}.exe" -Recurse | Select-Object -First 1
    if (-not $exe) {
        Write-Bad "归档里没有找到 ${BinName}.exe"
        exit 1
    }

    # ---- install ---------------------------------------------------------------

    $installDir = if ($env:INFLUO_PREFIX) {
        $env:INFLUO_PREFIX
    } else {
        Join-Path $env:LOCALAPPDATA "Programs\influo"
    }
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }

    $targetExe = Join-Path $installDir "${BinName}.exe"
    Copy-Item -Path $exe.FullName -Destination $targetExe -Force
    Write-Step "安装位置      $targetExe"

    # ---- PATH ------------------------------------------------------------------

    # Append installDir to USER PATH if not already present. We touch user
    # scope only — no machine PATH writes — so no admin elevation needed.
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($null -eq $userPath) { $userPath = "" }
    $pathEntries = $userPath -split [IO.Path]::PathSeparator | Where-Object { $_ -ne "" }
    if (-not ($pathEntries -contains $installDir)) {
        $newPath = if ($userPath -eq "") { $installDir } else { "$userPath;$installDir" }
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Muted "─────────────────────────"
        Write-Muted "$installDir 已加入用户 PATH (新打开的终端生效)"
    }
} finally {
    Remove-Item -Recurse -Force $tempRoot.FullName -ErrorAction SilentlyContinue
}

Write-OK "安装完成"
Write-Muted "─────────────────────────"
Write-Step "运行          $BinName"
