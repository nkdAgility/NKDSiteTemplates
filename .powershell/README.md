# GitHub Discussion Integration Scripts

This directory contains PowerShell scripts for integrating GitHub Discussions with Hugo documentation pages.

## Scripts

### `Get-DiscussionId.ps1`

The main script that processes Hugo markdown files and adds GitHub discussion IDs to their frontmatter.

**Features:**

- Searches for existing GitHub discussions using class names and friendly names
- Creates new discussions if none exist
- Updates Hugo frontmatter with discussion IDs
- Handles both technical class names (e.g., `TfsTeamSettingsProcessor`) and friendly names (e.g., `Tfs Team Settings Processor`)

### `Test-GitHubAPI.ps1`

A test script to verify GitHub API connectivity and configuration before running the main script.

**Tests:**

- GitHub API authentication
- Discussion categories retrieval
- Discussion search functionality
- Data file parsing
- Friendly name conversion

## Setup

### 1. GitHub Token

You need a GitHub Personal Access Token with the following permissions:

- `repo` (for accessing repository data)
- `discussions` (for creating and managing discussions)

To create a token:

1. Go to [GitHub Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens)
2. Click "Generate new token (classic)"
3. Select the required scopes: `repo` and `discussions`
4. Generate the token and copy it

### 2. Environment Variable

Set the GitHub token as an environment variable:

```powershell
$env:GITHUB_TOKEN = "your_token_here"
```

For persistent storage, add it to your PowerShell profile or system environment variables.

### 3. Configuration

The scripts are configured for:

- **Repository**: `nkdAgility/azure-devops-migration-tools`
- **Discussion Category**: `documentation`
- **Content Path**: `.\site\content\docs\reference\`

You can modify these values in the script if needed.

## Usage

### Step 1: Test the Setup

Run the test script first to verify everything is configured correctly:

```powershell
.\.powershell\Test-GitHubAPI.ps1
```

This will:

- Verify your GitHub token works
- Check if the documentation category exists
- Test discussion search functionality
- Validate data file parsing

### Step 2: Run the Main Script

The script supports different modes of operation:

**Default mode (Create discussions):**

```powershell
.\.powershell\Get-DiscussionId.ps1
```

**Find-only mode (Find existing discussions only):**

```powershell
.\.powershell\Get-DiscussionId.ps1 -CreateNewDiscussions:$false
```

#### Mode Descriptions

- **Default/Create Mode**: Finds existing discussions and creates new ones if none are found
- **Find-Only Mode**: Only searches for existing discussions, never creates new ones - useful for testing or when you only want to link existing discussions

This will:

- Process all Hugo markdown files in the reference documentation
- Skip files that already have a `discussionId`
- Search for existing discussions using multiple search strategies
- Create new discussions if none are found
- Update frontmatter with the discussion ID

## How It Works

### Discussion Search Strategy

The script searches for existing discussions using multiple approaches:

1. **Class name search**: Searches for the exact class name (e.g., `TfsTeamSettingsProcessor`)
2. **Friendly name search**: Searches for the human-readable name (e.g., `Tfs Team Settings Processor`)
3. **Title search**: Searches for the Hugo page title

### Discussion Creation

When creating new discussions, the script:

- Uses the Hugo page title as the discussion title
- Creates a structured body with quick reference information
- Links back to the documentation
- Categorizes it under "documentation"
- Includes usage guidelines for the community

### Data File Integration

The script reads YAML data files to extract:

- `className`: The technical class name
- `typeName`: The component type (Processor, Endpoint, FieldMap, etc.)
- `description`: Component description

### Frontmatter Updates

The script adds the `discussionId` field after the `date` field in the Hugo frontmatter:

```yaml
---
title: "My Processor"
date: 2025-06-24T12:07:31Z
discussionId: 123
---
```

## Error Handling

The script includes comprehensive error handling:

- **Missing GitHub token**: Exits with instructions
- **API failures**: Logs warnings and continues with other files
- **Missing data files**: Logs warnings but continues processing
- **Parsing errors**: Logs errors and skips problematic files

## Logging

The script uses the existing logging infrastructure:

- **Information logs**: Progress and success messages
- **Warning logs**: Non-critical issues
- **Error logs**: Critical failures
- **Debug logs**: Detailed troubleshooting information

## Customization

### Modifying Search Terms

To change how discussions are searched, modify the `Find-OrCreateDiscussion` function.

### Changing Discussion Template

To modify the discussion body template, edit the `New-GitHubDiscussion` function.

### Adding New Component Types

To support new component types, update the `Convert-ClassNameToFriendlyName` function's regex patterns.

## Troubleshooting

### Common Issues

1. **Authentication Error**

   - Verify your GitHub token is set correctly
   - Ensure the token has `repo` and `discussions` permissions
   - Check that the token hasn't expired

2. **Category Not Found**

   - Verify the "documentation" category exists in the repository
   - Check the category name spelling and capitalization

3. **API Rate Limiting**

   - The script includes delays between API calls
   - For large repositories, consider running in smaller batches

4. **YAML Parsing Errors**
   - Ensure data files are valid YAML
   - Check for special characters that might break parsing

### Debug Mode

Enable debug logging for detailed troubleshooting:

```powershell
$levelSwitch.MinimumLevel = 'Debug'
```

## Contributing

When modifying these scripts:

1. Test with the `Test-GitHubAPI.ps1` script first
2. Use the existing logging functions for consistency
3. Follow the established error handling patterns
4. Update this README with any new features or changes
