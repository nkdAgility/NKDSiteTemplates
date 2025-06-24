# Script to generate reference documentation files from data files
$dataPath = "site\data"
$contentPath = "site\content\docs\reference"

$ErrorActionPreference = 'Stop'

# Function to convert PascalCase to kebab-case
function ConvertTo-KebabCase {
    param(
        [string]$InputString
    )
    
    if ([string]::IsNullOrEmpty($InputString)) {
        return $InputString
    }
    
    # Define special words that should be treated as single units
    $specialWords = @('DevOps', 'API', 'URL', 'JSON', 'XML', 'HTTP', 'HTTPS', 'SQL', 'TFS', 'CSV')
    
    # Create a temporary string with placeholders for special words
    $tempString = $InputString
    $placeholders = @{}
    $counter = 0
    
    foreach ($word in $specialWords) {
        if ($tempString -match $word) {
            $placeholder = "Placeholder$counter"
            $placeholders[$placeholder] = $word.ToLower()
            $tempString = $tempString -replace $word, $placeholder
            $counter++
        }
    }
    
    # Insert hyphens before uppercase letters (except the first character)
    $kebabCase = $tempString -creplace '(?<!^)([A-Z])', '-$1'
    
    # Convert to lowercase
    $kebabCase = $kebabCase.ToLower()
    
    # Replace placeholders back with special words
    foreach ($placeholder in $placeholders.Keys) {
        $kebabCase = $kebabCase -replace $placeholder.ToLower(), $placeholders[$placeholder]
    }
    
    return $kebabCase
}

# Function to convert PascalCase to Title Case (with spaces)
function ConvertTo-TitleCase {
    param(
        [string]$InputString
    )
    
    if ([string]::IsNullOrEmpty($InputString)) {
        return $InputString
    }
    
    # Insert spaces before uppercase letters (except the first character)
    $titleCase = $InputString -creplace '(?<!^)([A-Z])', ' $1'
    
    return $titleCase
}

# Install powershell-yaml module if not already installed
if (!(Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Host "Installing powershell-yaml module..." -ForegroundColor Yellow
    Install-Module -Name powershell-yaml -Force -Scope CurrentUser
}

Import-Module powershell-yaml

# Get all YAML files from the data directory recursively
$dataFiles = Get-ChildItem -Path $dataPath -Filter "*.yaml" -Recurse

foreach ($file in $dataFiles) {
    Write-Host "Processing: $($file.Name)" -ForegroundColor Cyan    # Get the relative path from the data directory
    $relativePath = $file.FullName.Substring((Resolve-Path $dataPath).Path.Length + 1)
    
    # Load and parse the YAML content to get data for folder structure
    try {
        $yamlContent = Get-Content -Path $file.FullName -Raw
        $data = ConvertFrom-Yaml -Yaml $yamlContent
    }
    catch {
        Write-Host "Error parsing YAML file $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
    # Build directory structure using data from YAML: {typeName}\{className}
    if ($data.typeName -and $data.className) {
        $contentDir = Join-Path $contentPath (ConvertTo-KebabCase $data.typeName)
        $contentDir = Join-Path $contentDir (ConvertTo-KebabCase $data.className)
    }
    else {
        Write-Host "Missing typeName or className in $($file.Name), skipping..." -ForegroundColor Yellow
        continue
    }
    
    # Ensure the directory exists
    if (!(Test-Path $contentDir)) {
        New-Item -ItemType Directory -Path $contentDir -Force
    }
    
    # Create the index.md file path
    $indexFile = Join-Path $contentDir "index.md"
    
    # Create the data file reference path
    $dataFileRef = "data/" + $relativePath.Replace("\", "/")
    
    # Create the markdown content
    $content = @"
---
title: $(ConvertTo-TitleCase $data.className)
dataFile: $dataFileRef
slug: $(ConvertTo-KebabCase $data.className)
aliases:
  - /docs/Reference/$($data.typeName)/$($data.className)
  - /Reference/$($data.typeName)/$($data.className)
  - /learn/azure-devops-migration-tools/Reference/$($data.typeName)/$($data.className)
  - /learn/azure-devops-migration-tools/Reference/$($data.typeName)/$($data.className)/index.md
---
"@
    
    # Write the file only if it doesn't exist (to avoid overwriting existing content)
    if (!(Test-Path $indexFile)) {
        Set-Content -Path $indexFile -Value $content -Encoding UTF8
        Write-Host "Created: $indexFile" -ForegroundColor Green
    }
    else {
        Write-Host "Skipped (already exists): $indexFile" -ForegroundColor Yellow
    }
}

Write-Host "Script completed!" -ForegroundColor Cyan