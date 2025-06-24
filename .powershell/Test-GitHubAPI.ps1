# Test script for GitHub Discussion API integration
# This script tests the GitHub API functions without making actual changes

# Helpers
. ./.powershell/_includes/IncludesForAll.ps1
$levelSwitch.MinimumLevel = 'Information'

# GitHub Configuration
$GitHubOwner = "nkdAgility"
$GitHubRepo = "azure-devops-migration-tools"
$GitHubDiscussionCategory = "documentation"
$GitHubToken = $env:GITHUB_TOKEN

if (-not $GitHubToken) {
    Write-ErrorLog "GitHub token not found. Please set the GITHUB_TOKEN environment variable."
    Write-InformationLog "To get a GitHub token:"
    Write-InformationLog "1. Go to https://github.com/settings/tokens"
    Write-InformationLog "2. Generate a new token with 'repo' and 'discussions' scopes"
    Write-InformationLog "3. Set it as environment variable: `$env:GITHUB_TOKEN = 'your_token_here'"
    exit 1
}

# Function to search GitHub discussions (read-only test) using GraphQL
function Get-GitHubDiscussions {
    param(
        [string]$SearchTerm,
        [string]$Owner = $GitHubOwner,
        [string]$Repo = $GitHubRepo,
        [string]$Token = $GitHubToken
    )
    
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "User-Agent"    = "PowerShell-GitHubAPI"
    }
    
    # Clean up search term (remove quotes for GraphQL search)
    $cleanSearchTerm = $SearchTerm -replace '"', ''
    
    $query = @{
        query = @"
            query {
              repository(owner: "$Owner", name: "$Repo") {
                discussions(first: 100) {
                  nodes {
                    id
                    number
                    title
                    url
                    createdAt
                    category {
                      id
                      name
                    }
                  }
                }
              }
            }
"@
    } | ConvertTo-Json
    
    try {
        $graphqlUrl = "https://api.github.com/graphql"
        Write-InformationLog "Testing GraphQL API call to: $graphqlUrl"
        $response = Invoke-RestMethod -Uri $graphqlUrl -Headers $headers -Method Post -Body $query
        
        if ($response.errors) {
            Write-ErrorLog "GraphQL errors: $($response.errors | ConvertTo-Json)"
            return @()
        }
        
        $discussions = $response.data.repository.discussions.nodes
        
        # Filter discussions by search term
        if ($cleanSearchTerm) {
            $filteredDiscussions = $discussions | Where-Object { 
                $_.title -like "*$cleanSearchTerm*"
            }
            return $filteredDiscussions
        }
        
        return $discussions
    }
    catch {
        Write-ErrorLog "Failed to search GitHub discussions: $($_.Exception.Message)"
        return @()
    }
}

# Function to get discussion categories (read-only test) using GraphQL
function Get-GitHubDiscussionCategories {
    param(
        [string]$Owner = $GitHubOwner,
        [string]$Repo = $GitHubRepo,
        [string]$Token = $GitHubToken
    )
    
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "User-Agent"    = "PowerShell-GitHubAPI"
    }
    
    $query = @{
        query = @"
            query {
              repository(owner: "$Owner", name: "$Repo") {
                discussionCategories(first: 20) {
                  nodes {
                    id
                    name
                    slug
                    description
                  }
                }
              }
            }
"@
    } | ConvertTo-Json
    
    try {
        $graphqlUrl = "https://api.github.com/graphql"
        Write-InformationLog "Testing GraphQL API call to: $graphqlUrl"
        $response = Invoke-RestMethod -Uri $graphqlUrl -Headers $headers -Method Post -Body $query
        
        if ($response.errors) {
            Write-ErrorLog "GraphQL errors: $($response.errors | ConvertTo-Json)"
            return @()
        }
        
        return $response.data.repository.discussionCategories.nodes
    }
    catch {
        Write-ErrorLog "Failed to get GitHub discussion categories: $($_.Exception.Message)"
        return @()
    }
}

# Test GitHub API connectivity
Write-InformationLog "Testing GitHub API connectivity..."

# Test 1: Get discussion categories
Write-InformationLog "Test 1: Getting discussion categories..."
$categories = Get-GitHubDiscussionCategories
if ($categories) {
    Write-InformationLog "Found $($categories.Count) discussion categories:"
    foreach ($category in $categories) {
        Write-InformationLog "  - $($category.name) (ID: $($category.id))"
    }
    
    # Check if documentation category exists
    $docCategory = $categories | Where-Object { $_.name -eq $GitHubDiscussionCategory }
    if ($docCategory) {
        Write-InformationLog "✅ Documentation category found (ID: $($docCategory.id))"
    }
    else {
        Write-WarningLog "❌ Documentation category '$GitHubDiscussionCategory' not found"
        Write-InformationLog "Available categories: $($categories.name -join ', ')"
    }
}
else {
    Write-ErrorLog "❌ Failed to get discussion categories"
}

# Test 2: Search for existing discussions
Write-InformationLog "`nTest 2: Searching for existing discussions..."
$testSearchTerms = @("TfsTeamSettingsProcessor", "OutboundLinkCheckingProcessor", "processor")

foreach ($searchTerm in $testSearchTerms) {
    Write-InformationLog "Searching for: $searchTerm"
    $discussions = Get-GitHubDiscussions -SearchTerm "`"$searchTerm`""
    
    if ($discussions -and $discussions.Count -gt 0) {
        Write-InformationLog "  Found $($discussions.Count) discussions matching '$searchTerm'"
        foreach ($discussion in $discussions | Select-Object -First 3) {
            Write-InformationLog "    - $($discussion.title) (ID: $($discussion.number))"
        }
    }
    else {
        Write-InformationLog "  No discussions found matching '$searchTerm'"
    }
}

# Test 3: Test data file parsing
Write-InformationLog "`nTest 3: Testing data file parsing..."
$testDataFile = ".\site\data\reference.processors.outboundlinkcheckingprocessor.yaml"
if (Test-Path $testDataFile) {
    try {
        $yamlContent = Get-Content -Path $testDataFile -Raw
        $data = ConvertFrom-Yaml -Yaml $yamlContent
        Write-InformationLog "✅ Successfully parsed data file"
        Write-InformationLog "  Class Name: $($data.className)"
        Write-InformationLog "  Type Name: $($data.typeName)"
        Write-InformationLog "  Description: $($data.description)"
    }
    catch {
        Write-ErrorLog "❌ Failed to parse data file: $($_.Exception.Message)"
    }
}
else {
    Write-WarningLog "❌ Test data file not found: $testDataFile"
}

# Test 4: Test friendly name conversion
Write-InformationLog "`nTest 4: Testing friendly name conversion..."
$testClassNames = @("TfsTeamSettingsProcessor", "OutboundLinkCheckingProcessor", "AzureDevOpsPipelineProcessor", "FieldToTagFieldMap")

function Convert-ClassNameToFriendlyName {
    param([string]$ClassName)
    
    if (-not $ClassName) {
        return $null
    }
    
    # Remove common suffixes
    $friendlyName = $ClassName -replace '(Processor|Endpoint|FieldMap|Tool)$', ''
    
    # Split camelCase/PascalCase into words
    $friendlyName = $friendlyName -creplace '([a-z])([A-Z])', '$1 $2'
    
    # Handle acronyms (e.g., TFS, AzureDevOps)
    $friendlyName = $friendlyName -creplace '([A-Z]+)([A-Z][a-z])', '$1 $2'
    
    return $friendlyName.Trim()
}

foreach ($className in $testClassNames) {
    $friendlyName = Convert-ClassNameToFriendlyName -ClassName $className
    Write-InformationLog "  $className -> '$friendlyName'"
}

Write-InformationLog "`n✅ GitHub API test completed successfully!"
Write-InformationLog "You can now run the main Get-DiscussionId.ps1 script."
