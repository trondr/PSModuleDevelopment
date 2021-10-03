function Add-PsmdFsFileToFsProject {
    <#
        .SYNOPSIS
        Adds a f# source file to a F# project.
        
        .DESCRIPTION
        Adds a f# source file to a F# project. Source file is inserted before Program.fs 
        if project is a console project. Otherwise source file is added to the end.

        .PARAMETER FsProjectPath
        Full path to the F# project file.

        .PARAMETER FsFilePath
        Full path to the F# source file.

        .EXAMPLE
        Write-Host Add F# source file to F# project
        $fsprojectFilePath = "C:\temp\Fsharp.Console.TestApp\Fsharp.Console.TestApp.fsproj"
        $fsFilePath = "C:\temp\Fsharp.Console.TestApp\Tests\ExampleTests2.fs"
        Add-PSMDFsFileToFsProject -FsProjectPath $fsprojectFilePath -FsFilePath $fsFilePath

        .NOTES               
		Version:        1.0
		Author:         github/trondr
		Company:        github/trondr
		Repository:     https://github.com/trondr/PSModuleDevelopment.git
    
    #>
    
    [CmdletBinding()]
    param (
        [ValidateScript({
            [string]$path = $_
            (Test-Path $path -PathType 'Leaf') -and ($path.EndsWith(".fsproj"))
        })]
        [string]
        $FsProjectPath,
        [ValidateScript({
            [string]$path = $_
            (Test-Path $path -PathType 'Leaf') -and ($path.EndsWith(".fs"))
        })]
        [string]
        $FsFilePath
    )
    
    begin {
        $fsProjectFileDirectoryPath = [System.IO.FileInfo]::new($FsProjectPath).Directory.FullName
        $fsFilePathRelativePath = $FsFilePath.Replace($fsProjectFileDirectoryPath,"").TrimStart([System.IO.Path]::DirectorySeparatorChar).Replace([System.IO.Path]::DirectorySeparatorChar,[System.IO.Path]::AltDirectorySeparatorChar)
        function Format-XML
        {
            param(
                [xml]$Xml, 
                $Indent=2
            )
            $StringWriter = New-Object System.IO.StringWriter
            $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter
            $xmlWriter.Formatting = "indented"
            $xmlWriter.Indentation = $Indent
            $xml.WriteContentTo($XmlWriter)| Out-Null
            $XmlWriter.Flush()
            $StringWriter.Flush()
            Write-Output $StringWriter.ToString()
        }
    }
    
    process {
        [xml]$fsprojXmlDoc = Get-Content $FsProjectPath
        $itemGroups = $fsprojXmlDoc.SelectNodes("/Project/ItemGroup/Compile")
        if($itemGroups.Count -gt 0)
        {
            $allreadyExists = (($itemGroups.Include | Where-Object { ($_ -eq $fsFilePathRelativePath) }) | Measure-Object).Count -gt 0
            if($allreadyExists -eq $false)
            {
                #Fs file is not allready added, so add it.
                Write-Host "Adding file '$FsFilePath' to project '$FsProjectPath'." -ForegroundColor Yellow
                [System.Xml.XmlNode]$compileElement = $fsprojXmlDoc.CreateElement("Compile")
                ($compileElement.SetAttribute("Include",$fsFilePathRelativePath)) | Out-Null
                [System.Xml.XmlNode]$parentNode = $itemGroups[0].ParentNode
                [System.Xml.XmlNode]$lastChild = $parentNode.LastChild
                if ($parentNode.LastChild.Include -ieq "Program.fs")
                {
                    #Add the new Compile item before Program.fs).
                    ($parentNode.InsertBefore($compileElement, $lastChild)) | Out-Null
                }
                else {
                    #Add the new Compile item to the end of the list.
                    ($parentNode.AppendChild($compileElement)) | Out-Null
                }
                #Write changes back to fsproj file.
                (Format-XML -Xml $($fsprojXmlDoc.InnerXml) -Indent 4) | Set-Content -Path $fsprojectFilePath -Encoding utf8BOM | Out-Null
            }
            else {
                Write-Host "File '$FsFilePath' has allready been added to project '$FsProjectPath'." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "No ItemGroup with Compile items found in project file '$FsProjectPath'. There must be at least one Compile item in one ItemGroup." -ForegroundColor Yellow
        }
    }
    
    end {
        
    }
}
#TEST:
#$fsprojectFilePath = "C:\temp\Fsharp.Console.TestApp\Fsharp.Console.TestApp.fsproj"
#$fsFilePath = "C:\temp\Fsharp.Console.TestApp\Tests\ExampleTests2.fs"
#Add-PSMDFsFileToFsProject -FsProjectPath $fsprojectFilePath -FsFilePath $fsFilePath