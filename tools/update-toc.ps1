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

function Get-TocItemsFromFile {
    param([string]$TocPath)

    if (-not (Test-Path $TocPath)) {
        return @()
    }

    $lines = Get-Content -Path $TocPath -Encoding UTF8
    $items = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.List[object]

    foreach ($raw in $lines) {
        $line = $raw
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.TrimStart().StartsWith("#")) { continue }

        $indent = ($line.Length - $line.TrimStart().Length)
        $trim = $line.Trim()

        if ($trim -match '^- name:\s*(.+)$') {
            $item = [PSCustomObject]@{
                Name = $matches[1].Trim()
                Href = $null
                Items = New-Object System.Collections.Generic.List[object]
                Indent = $indent
            }

            while ($stack.Count -gt 0 -and $stack[$stack.Count - 1].Indent -ge $indent) {
                $stack.RemoveAt($stack.Count - 1)
            }

            if ($stack.Count -gt 0) {
                $stack[$stack.Count - 1].Items.Add($item) | Out-Null
            }
            else {
                $items.Add($item) | Out-Null
            }

            $stack.Add($item) | Out-Null
            continue
        }

        if ($trim -match '^href:\s*(.+)$') {
            if ($stack.Count -gt 0) {
                $stack[$stack.Count - 1].Href = $matches[1].Trim()
            }
            continue
        }
    }

    return $items
}

function Get-TocNameMapping {
    param(
        [string]$Root,
        [string]$TocPath
    )

    $mapping = @{}
    $tocDir = Split-Path -Parent $TocPath

    function Invoke-TocItemTraversal {
        param([object]$Item)

        if ($Item.Href) {
            $href = $Item.Href
            $resolved = Join-Path $tocDir $href
            if ($href.ToLowerInvariant().EndsWith(".yml") -and (Test-Path $resolved)) {
                $nested = Get-TocNameMapping -Root $Root -TocPath $resolved
                foreach ($key in $nested.Keys) {
                    $mapping[$key] = $nested[$key]
                }
            }
            elseif ($href.ToLowerInvariant().EndsWith(".md")) {
                $full = (Resolve-Path -LiteralPath $resolved -ErrorAction SilentlyContinue)
                if ($full) {
                    $relative = Get-RelativePath -BasePath $Root -TargetPath $full.Path
                    $key = $relative.ToLowerInvariant()
                    if (-not $mapping.ContainsKey($key)) {
                        $mapping[$key] = $Item.Name
                    }
                }
            }
        }

        if ($Item.Items -and $Item.Items.Count -gt 0) {
            foreach ($child in $Item.Items) {
                Invoke-TocItemTraversal -Item $child
            }
        }
    }

    $items = Get-TocItemsFromFile -TocPath $TocPath
    foreach ($item in $items) {
        Invoke-TocItemTraversal -Item $item
    }

    return $mapping
}

function Set-MarkdownTitle {
    param(
        [string]$FilePath,
        [string]$Title,
        [string]$Root
    )

    if (-not (Test-Path $FilePath)) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return
    }

    $content = Get-Content -Path $FilePath -Raw -Encoding UTF8
    if ($null -eq $content) {
        return
    }

    $newline = if ($content -match "`r`n") { "`r`n" } else { "`n" }
    $escapedTitle = ($Title.Trim() -replace "'", "''")
    $titleLine = "title: '$escapedTitle'"

    $contentForMatch = $content
    if ($contentForMatch.Length -gt 0 -and $contentForMatch[0] -eq [char]0xFEFF) {
        $contentForMatch = $contentForMatch.Substring(1)
    }

    $frontMatterMatch = [System.Text.RegularExpressions.Regex]::Match(
        $contentForMatch,
        '\A---\s*\r?\n([\s\S]*?)\r?\n---\s*(\r?\n)?'
    )

    if ($frontMatterMatch.Success) {
        $frontMatter = $frontMatterMatch.Groups[1].Value
        $body = $contentForMatch.Substring($frontMatterMatch.Length)

        $frontLines = New-Object System.Collections.Generic.List[string]
        foreach ($line in ($frontMatter -split "\r?\n")) {
            $frontLines.Add($line) | Out-Null
        }

        $titleUpdated = $false
        for ($i = 0; $i -lt $frontLines.Count; $i++) {
            if ($frontLines[$i] -match '^\s*title\s*:') {
                $frontLines[$i] = $titleLine
                $titleUpdated = $true
                break
            }
        }

        if (-not $titleUpdated) {
            $frontLines.Insert(0, $titleLine)
        }

        $newFrontMatter = ($frontLines -join $newline).TrimEnd()
        $newContent = "---$newline$newFrontMatter$newline---$newline$body"
    }
    else {
        $newContent = "---$newline$titleLine$newline---$newline$newline$contentForMatch"
    }

    if ($newContent -ne $contentForMatch) {
        $resolvedPath = (Resolve-Path -LiteralPath $FilePath).Path
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($resolvedPath, $newContent, $utf8NoBom)
        $relative = ConvertTo-RelativePath (Get-RelativePath -BasePath $Root -TargetPath $FilePath)
        Write-Host "Synced markdown title: $relative"
    }
}

function Sync-MarkdownTitlesFromToc {
    param(
        [string]$Root,
        [string]$TocPath
    )

    if (-not (Test-Path $TocPath)) {
        return
    }

    $mapping = Get-TocNameMapping -Root $Root -TocPath $TocPath
    foreach ($key in $mapping.Keys) {
        $mdPath = Join-Path $Root $key
        if (Test-Path $mdPath) {
            Set-MarkdownTitle -FilePath $mdPath -Title $mapping[$key] -Root $Root
        }
    }
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
    Sync-MarkdownTitlesFromToc -Root $Root -TocPath $productsTocPath

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
    
    if ($firstName) {
        $lines.Add("- name: $SectionName")
        $lines.Add("  href: index.md")
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
    Set-MarkdownTitle -FilePath $file.FullName -Title $title -Root $Root
    $lines.Add("    - name: $title")
    $lines.Add("      href: $relative")
}

$content = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
Set-Content -Path $TocPath -Value $content -Encoding UTF8

Write-Host "toc.yml updated with $($mdFiles.Count) markdown files."
