
# Helpers
. ./.powershell/_includes/IncludesForAll.ps1
$levelSwitch.MinimumLevel = 'Information'

$hugoMarkdownObjects = Get-RecentHugoMarkdownResources -Path ".\site\content\" 


Write-InformationLog "Processing ({count}) HugoMarkdown Objects." -PropertyValues ($hugoMarkdownObjects.Count)


foreach ($hugoMarkdown in $hugoMarkdownObjects) {
    Save-HugoMarkdown -hugoMarkdown $hugoMarkdown -Path $hugoMarkdown.FilePath
}