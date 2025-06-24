
# Parameters
param(
    [switch]$CreateNewDiscussions = $false
)

# Helpers
. ./.powershell/_includes/IncludesForAll.ps1
$levelSwitch.MinimumLevel = 'Information'

# Ensure PowerShell-YAML module is available (inherited from HugoHelpers.ps1)
# The module is already imported in HugoHelpers.ps1

# GitHub Configuration
$GitHubOwner = "nkdAgility"
$GitHubRepo = "azure-devops-migration-tools"
$GitHubDiscussionCategory = "documentation"
$GitHubToken = $env:GITHUB_TOKEN

# Handle parameter logic
if ($CreateNewDiscussions) {
    Write-InformationLog "Running in CREATE mode - will find existing discussions and create new ones if needed."
}
else {
    Write-InformationLog "Running in FIND-ONLY mode - will only find existing discussions, not create new ones."
}

if (-not $GitHubToken) {
    Write-ErrorLog "GitHub token not found. Please set the GITHUB_TOKEN environment variable."
    exit 1
}

# Function to search GitHub discussions using GraphQL
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
        
        # Add rate limiting delay
        Start-Sleep -Milliseconds 100
        
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
        if ($_.Exception.Response.StatusCode -eq 403) {
            Write-WarningLog "Rate limit exceeded. Waiting 60 seconds..."
            Start-Sleep -Seconds 60
            # Retry once after rate limit wait
            try {
                $response = Invoke-RestMethod -Uri $graphqlUrl -Headers $headers -Method Post -Body $query
                if ($response.errors) {
                    Write-ErrorLog "GraphQL errors: $($response.errors | ConvertTo-Json)"
                    return @()
                }
                $discussions = $response.data.repository.discussions.nodes
                if ($cleanSearchTerm) {
                    $filteredDiscussions = $discussions | Where-Object { 
                        $_.title -like "*$cleanSearchTerm*"
                    }
                    return $filteredDiscussions
                }
                return $discussions
            }
            catch {
                Write-WarningLog "Failed to search GitHub discussions after retry: $($_.Exception.Message)"
                return @()
            }
        }
        else {
            Write-WarningLog "Failed to search GitHub discussions: $($_.Exception.Message)"
            return @()
        }
    }
}

# Function to create a GitHub discussion using GraphQL
function New-GitHubDiscussion {
    param(
        [string]$Title,
        [string]$Body,
        [string]$CategoryId,
        [string]$Owner = $GitHubOwner,
        [string]$Repo = $GitHubRepo,
        [string]$Token = $GitHubToken
    )
    
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "User-Agent"    = "PowerShell-GitHubAPI"
    }
    
    # First, get the repository ID
    $repoQuery = @{
        query = @"
            query {
              repository(owner: "$Owner", name: "$Repo") {
                id
              }
            }
"@
    } | ConvertTo-Json
    
    try {
        $graphqlUrl = "https://api.github.com/graphql"
        
        # Get repository ID
        $repoResponse = Invoke-RestMethod -Uri $graphqlUrl -Headers $headers -Method Post -Body $repoQuery
        
        if ($repoResponse.errors) {
            Write-ErrorLog "GraphQL errors getting repository ID: $($repoResponse.errors | ConvertTo-Json)"
            return $null
        }
        
        $repositoryId = $repoResponse.data.repository.id
        
        # Escape quotes in title and body for GraphQL
        $escapedTitle = $Title -replace '"', '\"'
        $escapedBody = $Body -replace '"', '\"' -replace '\n', '\\n' -replace '\r', ''
        
        # Create discussion mutation
        $mutation = @{
            query = @"
                mutation {
                  createDiscussion(input: {
                    repositoryId: "$repositoryId"
                    categoryId: "$CategoryId"
                    title: "$escapedTitle"
                    body: "$escapedBody"
                  }) {
                    discussion {
                      id
                      number
                      title
                      url
                      createdAt
                    }
                  }
                }
"@
        } | ConvertTo-Json
        
        # Add rate limiting delay
        Start-Sleep -Milliseconds 500
        
        $response = Invoke-RestMethod -Uri $graphqlUrl -Headers $headers -Method Post -Body $mutation
        
        if ($response.errors) {
            Write-ErrorLog "GraphQL errors creating discussion: $($response.errors | ConvertTo-Json)"
            return $null
        }
        
        return $response.data.createDiscussion.discussion
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 403) {
            Write-WarningLog "Rate limit exceeded while creating discussion. Waiting 60 seconds..."
            Start-Sleep -Seconds 60
            # Retry once after rate limit wait
            try {
                $response = Invoke-RestMethod -Uri $graphqlUrl -Headers $headers -Method Post -Body $mutation
                if ($response.errors) {
                    Write-ErrorLog "GraphQL errors creating discussion: $($response.errors | ConvertTo-Json)"
                    return $null
                }
                return $response.data.createDiscussion.discussion
            }
            catch {
                Write-ErrorLog "Failed to create GitHub discussion after retry: $($_.Exception.Message)"
                return $null
            }
        }
        else {
            Write-ErrorLog "Failed to create GitHub discussion: $($_.Exception.Message)"
            if ($_.Exception.Response) {
                try {
                    $errorResponse = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($errorResponse)
                    $errorBody = $reader.ReadToEnd()
                    Write-ErrorLog "Error details: $errorBody"
                }
                catch {
                    Write-ErrorLog "Could not read error response"
                }
            }
            return $null
        }
    }
}

# Function to get discussion categories using GraphQL
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
        
        # Add rate limiting delay
        Start-Sleep -Milliseconds 100
        
        $response = Invoke-RestMethod -Uri $graphqlUrl -Headers $headers -Method Post -Body $query
        
        if ($response.errors) {
            Write-ErrorLog "GraphQL errors: $($response.errors | ConvertTo-Json)"
            return @()
        }
        
        return $response.data.repository.discussionCategories.nodes
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 403) {
            Write-WarningLog "Rate limit exceeded. Waiting 60 seconds..."
            Start-Sleep -Seconds 60
            # Retry once after rate limit wait
            try {
                $response = Invoke-RestMethod -Uri $graphqlUrl -Headers $headers -Method Post -Body $query
                if ($response.errors) {
                    Write-ErrorLog "GraphQL errors: $($response.errors | ConvertTo-Json)"
                    return @()
                }
                return $response.data.repository.discussionCategories.nodes
            }
            catch {
                Write-WarningLog "Failed to get GitHub discussion categories after retry: $($_.Exception.Message)"
                return @()
            }
        }
        else {
            Write-WarningLog "Failed to get GitHub discussion categories: $($_.Exception.Message)"
            return @()
        }
    }
}

# Function to get class name from data file
function Get-ClassNameFromDataFile {
    param(
        [string]$DataFilePath
    )
    
    if (-not (Test-Path $DataFilePath)) {
        Write-WarningLog "Data file not found: $DataFilePath"
        return $null
    }
    
    try {
        $yamlContent = Get-Content -Path $DataFilePath -Raw
        $data = ConvertFrom-Yaml -Yaml $yamlContent
        return $data.className
    }
    catch {
        Write-WarningLog "Failed to parse data file $DataFilePath : $($_.Exception.Message)"
        return $null
    }
}

# Function to convert class name to friendly name
function Convert-ClassNameToFriendlyName {
    param(
        [string]$ClassName
    )
    
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

# Function to find or create discussion
function Find-OrCreateDiscussion {
    param(
        [HugoMarkdown]$HugoMarkdown,
        [bool]$AllowCreate = $true
    )
    
    $title = $hugoMarkdown.FrontMatter.title
    $dataFile = $hugoMarkdown.FrontMatter.dataFile
    
    if (-not $title) {
        Write-WarningLog "No title found for $($hugoMarkdown.FilePath)"
        return $null
    }
    
    # Get class name from data file if available
    $className = $null
    if ($dataFile) {
        $dataFilePath = Join-Path ".\site\" $dataFile
        $className = Get-ClassNameFromDataFile -DataFilePath $dataFilePath
    }
    
    # Convert class name to friendly name
    $friendlyName = Convert-ClassNameToFriendlyName -ClassName $className
    
    # Search for existing discussions
    $searchTerms = @()
    if ($className) { $searchTerms += "`"$className`"" }
    if ($friendlyName) { $searchTerms += "`"$friendlyName`"" }
    $searchTerms += "`"$title`""
    
    $existingDiscussion = $null
    foreach ($searchTerm in $searchTerms) {
        Write-DebugLog "Searching for discussion with term: $searchTerm"
        $discussions = Get-GitHubDiscussions -SearchTerm $searchTerm
        
        if ($discussions -and $discussions.Count -gt 0) {
            # Find the most relevant discussion
            $existingDiscussion = $discussions | Where-Object { 
                $_.title -eq "$className" -or 
                $_.title -eq "$friendlyName" -or 
                $_.title -eq $title 
            } | Select-Object -First 1
            
            if ($existingDiscussion) {
                Write-InformationLog "Found existing discussion: $($existingDiscussion.title) (ID: $($existingDiscussion.number))"
                break
            }
        }
    }
    
    # Create new discussion if none found and creation is allowed
    if (-not $existingDiscussion) {
        if (-not $AllowCreate) {
            Write-InformationLog "No existing discussion found for: $title (creation disabled)"
            return $null
        }
    
        Write-InformationLog "Creating new discussion for: $title"
        
        # Get documentation category ID
        $categories = Get-GitHubDiscussionCategories
        $docCategory = $categories | Where-Object { $_.name -eq $GitHubDiscussionCategory }
        
        if (-not $docCategory) {
            Write-ErrorLog "Documentation category '$GitHubDiscussionCategory' not found"
            Write-InformationLog "Available categories: $($categories.name -join ', ')"
            return $null
        }
        
        # Generate documentation URL
        $docUrl = ""
        if ($hugoMarkdown.FrontMatter.slug) {
            $docUrl = "https://devopsmigration.io/docs/reference/$($hugoMarkdown.FrontMatter.slug)/"
        }
        elseif ($hugoMarkdown.ReferencePath) {
            $relativePath = $hugoMarkdown.ReferencePath.Replace('docs/', '').Replace('\', '/')
            $docUrl = "https://devopsmigration.io/$relativePath/"
        }
        
        # Create discussion body
        $discussionBody = @"
This discussion is for questions, feedback, and community support related to the **$title**.

## Quick Reference

"@
        
        if ($className) {
            $discussionBody += "`n- **Class Name**: ``$className``"
        }
        
        if ($friendlyName) {
            $discussionBody += "`n- **Friendly Name**: $friendlyName"
        }
        
        # Add link to documentation if URL is available
        if ($docUrl) {
            $discussionBody += "`n- **Documentation**: [$title]($docUrl)"
        }
        
        $discussionBody += @"

## How to Use This Discussion

- **Ask Questions**: If you need help configuring or using this component
- **Share Examples**: Post your configuration examples or use cases
- **Report Issues**: Describe any problems you encounter (though bugs should be reported as GitHub Issues)
- **Request Features**: Suggest improvements or new features

## Related Documentation

"@
        
        if ($docUrl) {
            $discussionBody += "Please refer to the [official documentation]($docUrl) for detailed configuration options and examples."
        }
        else {
            $discussionBody += "Please refer to the official documentation for detailed configuration options and examples."
        }
        
        $newDiscussion = New-GitHubDiscussion -Title $title -Body $discussionBody -CategoryId $docCategory.id
        
        if ($newDiscussion) {
            Write-InformationLog "Created new discussion: $($newDiscussion.title) (ID: $($newDiscussion.number))"
            return $newDiscussion
        }
        else {
            Write-ErrorLog "Failed to create discussion for: $title"
            return $null
        }
    }
    
    return $existingDiscussion
}

# Main processing
$hugoMarkdownObjects = Get-RecentHugoMarkdownResources -Path ".\site\content\docs\reference\" 

Write-InformationLog "Processing ({count}) HugoMarkdown Objects." -PropertyValues ($hugoMarkdownObjects.Count)

# Statistics tracking
$stats = @{
    Total     = $hugoMarkdownObjects.Count
    Processed = 0
    Skipped   = 0
    Created   = 0
    Found     = 0
    Errors    = 0
    NotFound  = 0
}

foreach ($hugoMarkdown in $hugoMarkdownObjects) {
    $stats.Processed++
    
    Write-InformationLog "[$($stats.Processed)/$($stats.Total)] Processing: $($hugoMarkdown.FrontMatter.title)"
    
    # Skip if discussionId already exists and is not empty
    if ($hugoMarkdown.FrontMatter.discussionId -and $hugoMarkdown.FrontMatter.discussionId -ne "") {
        Write-InformationLog "Discussion ID already exists: $($hugoMarkdown.FrontMatter.discussionId)"
        $stats.Skipped++
        continue    
    }
    
    # Find or create discussion
    $discussion = Find-OrCreateDiscussion -HugoMarkdown $hugoMarkdown -AllowCreate $CreateNewDiscussions
    
    if ($discussion) {
        # Determine if this was a new discussion or existing one
        $isNewDiscussion = $discussion.createdAt -and ($discussion.createdAt -gt (Get-Date).AddMinutes(-5))
        
        if ($isNewDiscussion) {
            $stats.Created++
            $action = "Created"
        }
        else {
            $stats.Found++
            $action = "Found"
        }
        
        # Update frontmatter with discussion ID
        Update-Field -frontMatter $hugoMarkdown.FrontMatter -fieldName "discussionId" -fieldValue $discussion.number -addAfter "date"
        
        # Save the updated markdown
        Save-HugoMarkdown -hugoMarkdown $hugoMarkdown -Path $hugoMarkdown.FilePath
        
        Write-InformationLog "$action discussion for '$($hugoMarkdown.FrontMatter.title)' with ID: $($discussion.number)"
    }
    else {
        if (-not $CreateNewDiscussions) {
            Write-InformationLog "No existing discussion found for: $($hugoMarkdown.FrontMatter.title) (creation disabled)"
            $stats.NotFound++
        }
        else {
            Write-WarningLog "Could not find or create discussion for: $($hugoMarkdown.FrontMatter.title)"
            $stats.Errors++
        }
    }
    
    # Add a small delay between processing items to be respectful to the API
    Start-Sleep -Milliseconds 200
}

# Summary report
Write-InformationLog ("`n" + "=" * 50)
Write-InformationLog "PROCESSING SUMMARY"
Write-InformationLog ("=" * 50)
Write-InformationLog "Total files processed: $($stats.Total)"
Write-InformationLog "Files with existing discussion IDs (skipped): $($stats.Skipped)"
Write-InformationLog "New discussions created: $($stats.Created)"
Write-InformationLog "Existing discussions found: $($stats.Found)"
if (-not $CreateNewDiscussions) {
    Write-InformationLog "Files without existing discussions (creation disabled): $($stats.NotFound)"
}
Write-InformationLog "Errors encountered: $($stats.Errors)"
Write-InformationLog "Successfully updated: $($stats.Created + $stats.Found)"

if ($stats.Errors -eq 0) {
    if ($stats.NotFound -gt 0 -and -not $CreateNewDiscussions) {
        Write-InformationLog "`n✅ All files processed successfully! $($stats.NotFound) files had no existing discussions (creation was disabled)."
    }
    else {
        Write-InformationLog "`n✅ All files processed successfully!"
    }
}
else {
    Write-WarningLog "`n⚠️  Some files had errors. Check the log above for details."
}