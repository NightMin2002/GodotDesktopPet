# release.ps1 — 一键发版脚本
# 用法: .\release.ps1 -Version "1.8" [-Notes "更新说明"]
# 流程: 改版本号 → git commit → git tag → git push → 提示上传安装包
param(
    [Parameter(Mandatory=$true)]
    [string]$Version,
    
    [string]$Notes = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── 1. 版本号同步 ──

$files = @(
    @{ Path = "$Root\core\update_checker.gd"; Pattern = 'const CURRENT_VERSION := ".*?"'; Replace = "const CURRENT_VERSION := `"$Version`"" },
    @{ Path = "$Root\installer.iss"; Pattern = '#define MyAppVersion ".*?"'; Replace = "#define MyAppVersion `"$Version`"" }
)

Write-Host "`n=== 发版 v$Version ===" -ForegroundColor Cyan

foreach ($f in $files) {
    $content = Get-Content $f.Path -Raw -Encoding UTF8
    $newContent = $content -replace $f.Pattern, $f.Replace
    if ($content -eq $newContent) {
        Write-Host "[跳过] $($f.Path | Split-Path -Leaf) 已是目标版本" -ForegroundColor Yellow
    } else {
        [System.IO.File]::WriteAllText($f.Path, $newContent, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[更新] $($f.Path | Split-Path -Leaf) -> v$Version" -ForegroundColor Green
    }
}

# ── 2. Git 提交 + Tag ──

Write-Host "`n--- Git 操作 ---" -ForegroundColor Cyan
Set-Location $Root
git add core/update_checker.gd installer.iss
git commit -m "release: v$Version"
git tag -a "v$Version" -m "Release v$Version"

Write-Host "`n--- 推送到远程 ---" -ForegroundColor Cyan
git push origin dev
git push origin "v$Version"

# ── 3. 安装包检查 ──

$installer = Get-ChildItem "$Root\dist" -Filter "*$Version*Setup.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($installer) {
    Write-Host "`n[就绪] 安装包: $($installer.Name) ($([math]::Round($installer.Length / 1MB, 1)) MB)" -ForegroundColor Green
} else {
    $latest = Get-ChildItem "$Root\dist" -Filter "*Setup.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        Write-Host "`n[注意] 未找到 v$Version 安装包，最新文件: $($latest.Name)" -ForegroundColor Yellow
    } else {
        Write-Host "`n[注意] dist/ 目录下无安装包，请先用 Inno Setup 编译" -ForegroundColor Yellow
    }
}

# ── 4. 提示下一步 ──

Write-Host "`n=== 下一步 ===" -ForegroundColor Cyan
Write-Host "1. 确认安装包已编译到 dist/ 目录"
Write-Host "2. 在 GitHub 仓库创建 Release:"
Write-Host "   https://github.com/NightMin2002/GodotDesktopPet/releases/new?tag=v$Version"
Write-Host "3. 上传安装包到 Release 附件"

if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "`n或者直接用 gh CLI:" -ForegroundColor Cyan
    if ($installer) {
        Write-Host "   gh release create v$Version `"$($installer.FullName)`" --title `"v$Version`" --notes `"$Notes`""
    } else {
        Write-Host "   gh release create v$Version --title `"v$Version`" --notes `"$Notes`""
    }
}

Write-Host "`n发版 v$Version 准备完毕!" -ForegroundColor Green
