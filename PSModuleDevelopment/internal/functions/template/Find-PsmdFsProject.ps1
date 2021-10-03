function Find-PsmdFsProject
{
    <#
        .SYNOPSIS
        Find F# nearest project file(s) in current directory or in parent directories.
        
        .DESCRIPTION
        Find F# nearest project file(s) in current directory or in parent directories.

        .PARAMETER FolderPath
        Full path to the folder to search
        
        .EXAMPLE
        Write-Host Find neares F# project file.
        Find-PsmdFsProject -FolderPath "C:\temp\Fsharp.Console.TestApp\Tests"

        .NOTES               
		Version:        1.0
		Author:         github/trondr
		Company:        github/trondr
		Repository:     https://github.com/trondr/PSModuleDevelopment.git
    
    #>
    param(
        [ValidateScript({ (Test-Path $_ -PathType 'Container') })]
        [string]
        $FolderPath
    )
    $projectFiles = Get-ChildItem -LiteralPath $FolderPath -Filter "*.fsproj" -File
    if($projectFiles.Length -eq 0)
    {
        #Did not find *.fsproj file(s) in current directory, continue recursively up the tree.
        $Directory = [System.IO.DirectoryInfo]::new($FolderPath)
        if($null -ne $Directory.Parent)
        {
            Find-PsmdFsProject -FolderPath $($Directory.Parent.FullName)
        }
    }
    else {
        #Found *.fsproj file(s) in current directory, stop the search and return the findings.
        $projectFiles | ForEach-Object{ Write-Output -InputObject $_.FullName}
    }
}
#TEST
#Find-PsmdFsProject -FolderPath "C:\temp\Fsharp.Console.TestApp\Tests"