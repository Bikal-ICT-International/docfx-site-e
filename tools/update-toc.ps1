param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$DocsRoot = "Products",
    [string]$TocPath = $null,
    [string]$SectionName = "Product Support Documentation",
    [string]$SectionHref = "Products/Sap-Flow-Sensor-SFS-Manual.md",
    [switch]$Flat
)

$ErrorActionPreference = "Stop"

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $base = [System.IO.Path]::GetFullPath($BasePath)
    $target = [System.IO.Path]::GetFullPath($TargetPath)

    if (-not $base.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString())) {
        $base += [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = New-Object System.Uri($base)
    $targetUri = New-Object System.Uri($target)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    return [System.Uri]::UnescapeDataString($relativeUri.ToString()) -replace "/", "\\"
}

function ConvertTo-RelativePath {
    param([string]$Path)
    return ($Path -replace "\\\\", "/")
}

if (-not $TocPath) {
    $TocPath = Join-Path $Root "toc.yml"
}

$docsPath = Join-Path $Root $DocsRoot
if (-not (Test-Path $docsPath)) {
    throw "Docs root not found: $docsPath"
}

$lines = New-Object System.Collections.Generic.List[string]

# Check if Products/toc.yml exists and use it to generate root TOC
$productsTocPath = Join-Path $docsPath "toc.yml"
if (Test-Path $productsTocPath) {
    # Read the Products/toc.yml and get the first item's href
    $productsContent = Get-Content -Path $productsTocPath -Raw
    $productsLines = $productsContent -split "`n"
    
    $firstName = $null
    $firstHref = $null
    
    foreach ($line in $productsLines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        
        if ($line -match '^\s*- name:\s*(.+)$') {
            if ($null -eq $firstName) {
                $firstName = $matches[1].Trim()
            }
        }
        elseif ($line -match '^\s*href:\s*(.+)$') {
            if ($null -eq $firstHref) {
                $firstHref = $matches[1].Trim()
                # Prefix with Products/ if not already prefixed
                if (-not $firstHref.StartsWith("Products/")) {
                    $firstHref = "Products/" + $firstHref
                }
            }
        }
    }
    
    if ($firstName -and $firstHref) {
        $lines.Add("- name: $SectionName")
        $lines.Add("  href: $firstHref")
    }
    
    $content = ($lines -join "`n").TrimEnd() + "`n"
    Set-Content -Path $TocPath -Value $content -Encoding UTF8
    Write-Host "toc.yml updated from $DocsRoot/toc.yml"
    return
}

# Fallback: Generate TOC from markdown files
$lines.Add("- name: $SectionName")
$lines.Add("  items:")

$mdFiles = Get-ChildItem -Path $docsPath -File -Filter "*.md" |
    Where-Object { $_.Name -ne "index.md" } |
    Sort-Object FullName

foreach ($file in $mdFiles) {
    $relative = ConvertTo-RelativePath (Get-RelativePath -BasePath $Root -TargetPath $file.FullName)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $title = ($base -replace "[-_]+", " ").Trim()
    if ([string]::IsNullOrWhiteSpace($title)) {
        continue
    }
    $lines.Add("    - name: $title")
    $lines.Add("      href: $relative")
}

$content = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
Set-Content -Path $TocPath -Value $content -Encoding UTF8

Write-Host "toc.yml updated with $($mdFiles.Count) markdown files."
