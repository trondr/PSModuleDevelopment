﻿function Invoke-PSMDTemplate {
<#
	.SYNOPSIS
		Creates a project/file from a template.
	
	.DESCRIPTION
		This function takes a template and turns it into a finished file&folder structure.
		It does so by creating the files and folders stored within, replacing all parameters specified with values provided by the user.
		
		Missing parameters will be prompted for.
	
	.PARAMETER Template
		The template object to build from.
		Accepts objects returned by Get-PSMDTemplate.
	
	.PARAMETER TemplateName
		The name of the template to build from.
		Warning: This does wildcard interpretation, don't specify '*' unless you like answering parameter prompts.
	
	.PARAMETER Store
		The template store to retrieve tempaltes from.
		By default, all stores are queried.
	
	.PARAMETER Path
		Instead of a registered store, look in this path for templates.
	
	.PARAMETER OutPath
		The path in which to create the output.
		By default, it will create in the current directory.
	
	.PARAMETER Name
		The name of the produced output.
		Automatically inserted for any name parameter specified on creation.
		Also used for creating a root folder, when creating a project.
	
	.PARAMETER NoFolder
		Skip automatic folder creation for project templates.
		By default, this command will create a folder to place files&folders in when creating a project.
	
	.PARAMETER Encoding
		The encoding to apply to text files.
		The default setting for this can be configured by updating the 'PSFramework.Text.Encoding.DefaultWrite' configuration setting.
		The initial default value is utf8 with BOM.
	
	.PARAMETER Parameters
		A Hashtable containing parameters for use in creating the template.
	
	.PARAMETER Raw
		By default, all parameters will be replaced during invocation.
		In Raw mode, this is skipped, reproducing mostly the original template input (dynamic scriptblocks will now be named scriptblocks)).
	
	.PARAMETER Force
		If the target path the template should be written to (filename or folder name within $OutPath), then overwrite it.
		By default, this function will fail if an overwrite is required.
	
	.PARAMETER Silent
		This places the function in unattended mode, causing it to error on anything requiring direct user input.
	
	.PARAMETER EnableException
		Replaces user friendly yellow warnings with bloody red exceptions of doom!
		Use this if you want the function to throw terminating errors you want to catch.
	
	.PARAMETER Confirm
		If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.
	
	.PARAMETER WhatIf
		If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.
	
	.EXAMPLE
		PS C:\> Invoke-PSMDTemplate -TemplateName "module"
		
		Creates a project based on the module template in the current folder, asking for all details.
	
	.EXAMPLE
		PS C:\> Invoke-PSMDTemplate -TemplateName "module" -Name "MyModule"
		
		Creates a project based on the module template with the name "MyModule"
#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSPossibleIncorrectUsageOfAssignmentOperator", "")]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    [Alias('imt')]
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'NameStore')]
		[Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'NamePath')]
		[string]
		$TemplateName,
		
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'Template')]
		[PSModuleDevelopment.Template.TemplateInfo[]]
		$Template,
		
		[Parameter(ParameterSetName = 'NameStore')]
		[string]
		$Store = "*",
		
		[Parameter(Mandatory = $true, ParameterSetName = 'NamePath')]
		[string]
		$Path,
		
		[Parameter(Position = 2)]
		[PSFramework.Validation.PsfValidateScript('PSFramework.Validate.FSPath.Folder', ErrorString = 'PSFramework.Validate.FSPath.Folder')]
		[string]
		$OutPath = (Get-PSFConfigValue -FullName 'PSModuleDevelopment.Template.OutPath' -Fallback "."),
		
		[Parameter(Position = 1)]
		[string]
		$Name,
		
		[PSFEncoding]
		$Encoding = (Get-PSFConfigValue -FullName 'PSFramework.Text.Encoding.DefaultWrite'),
		
		[switch]
		$NoFolder,
		
		[hashtable]
		$Parameters = @{ },
		
		[switch]
		$Raw,
		
		[switch]
		$Force,
		
		[switch]
		$Silent,
		
		[switch]
		$EnableException
	)
	
	begin {
		$templates = @()
		switch ($PSCmdlet.ParameterSetName) {
			'NameStore' { $templates = Get-PSMDTemplate -TemplateName $TemplateName -Store $Store }
			'NamePath' { $templates = Get-PSMDTemplate -TemplateName $TemplateName -Path $Path }
		}
		if ($TemplateName -and -not $templates) {
			Stop-PSFFunction -String 'Invoke-PSMDTemplate.Template.NotFound' -StringValues $TemplateName -EnableException $EnableException -Cmdlet $PSCmdlet
			return
		}
		
        # Import context aware configuration parameters by processing PSMDConfig.ps1 in all parent directories 
        # all the way to the top from current directory. The config file in the current directory have precedens over config files 
        # further up the tree. Each config file have a dictionary defined that stores key value pairs.
        #Example: 
        #   Top Directory: PSMDConfig.ps1:
        #   $PSMDConfig = @{
        #       "Author" = "Ola Hansen"
        #       "Company" = "work.com"
        #   }
        #   Parent Directory: PSMDConfig.ps1:
        #   $PSMDConfig = @{
        #       "Company" = "customer.com"
        #       "NameSpace" = "App1"
        #   }
        #   Current Directory: PSMDConfig.ps1:
        #   $PSMDConfig = @{            
        #       "NameSpace" = "App1.Library"
        #   }
        #   Resultant config for current directory after processing the PSMDConfig.ps1 files further up:
        #   $PSMDConfig = @{
        #       "Author" = "Ola Hansen"
        #       "Company" = "customer.com"
        #       "NameSpace" = "App1.Library"
        #   }
        #  The resultant config will be will be added to 'Template.ParameterDefault.*' with the Set-PSFConfig command.
        function Get-ParentDirectory
        {
            param(
                [System.IO.DirectoryInfo]
                $Directory
            )
            if($null -ne $Directory.Parent)
            {
                Write-Output -InputObject $Directory.FullName
                Get-ParentDirectory -Directory $($Directory.Parent)
            }
        }        
        $currentDirectory = [System.IO.DirectoryInfo]::new((Get-Location).Path)
        Get-ParentDirectory -Directory $currentDirectory | Sort-Object | ForEach-Object{
            $folderPath = $_
            $psmdConfigPath = [System.IO.Path]::Combine($folderPath,"PSMDConfig.ps1")
            $psmdConfigPath
        } | Where-Object { Test-Path -Path $_} | Foreach-Object {
            $psmdConfigPath = $_
            . $psmdConfigPath 
            #$PSMDConfig variable is now set, run through it and overwrite coresponding values in Template.ParameterDefault.*
            foreach ($key in $PSMDConfig.Keys) {                
                Set-PSFConfig -Module 'PSModuleDevelopment' -Name "Template.ParameterDefault.$($key)" -Value $($PSMDConfig[$key])
            }
        }

		#region Parameter Processing
		if (-not $Parameters) { $Parameters = @{ } }
		if ($Name) { $Parameters["Name"] = $Name }
		
		foreach ($config in (Get-PSFConfig -Module 'PSModuleDevelopment' -Name 'Template.ParameterDefault.*')) {
			$cfgName = $config.Name -replace '^.+\.([^\.]+)$', '$1'
			if (-not $Parameters.ContainsKey($cfgName)) {
				$Parameters[$cfgName] = $config.Value
			}
		}
		#endregion Parameter Processing
		
		#region Helper function
		function Invoke-Template {
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
			[CmdletBinding()]
			param (
				[PSModuleDevelopment.Template.TemplateInfo]
				$Template,
				
				[string]
				$OutPath,
				
				[PSFEncoding]
				$Encoding,
				
				[bool]
				$NoFolder,
				
				[hashtable]
				$Parameters,
				
				[bool]
				$Raw,
				
				[bool]
				$Silent
			)
			Write-PSFMessage -Level Verbose -Message "Processing template $($item)" -Tag 'template', 'invoke' -FunctionName Invoke-PSMDTemplate
			
			$templateData = Import-PSFClixml -Path $Template.Path -ErrorAction Stop
			#region Process Parameters
			foreach ($parameter in $templateData.Parameters) {
				if (-not $parameter) { continue }
				if (-not $Parameters.ContainsKey($parameter)) {
					if ($Silent) { throw "Parameter not specified: $parameter" }
					try {
						$value = Read-Host -Prompt "Enter value for parameter '$parameter'" -ErrorAction Stop
						$Parameters[$parameter] = $value
					}
					catch { throw }
				}
			}
			#endregion Process Parameters
			
			#region Scripts
			$scriptParameters = @{ }
			
			if (-not $Raw) {
				foreach ($scriptParam in $templateData.Scripts.Values) {
					if (-not $scriptParam) { continue }
					try { $scriptParameters[$scriptParam.Name] = "$([scriptblock]::Create($scriptParam.StringScript).Invoke())" }
					catch {
						if ($Silent) { throw (New-Object System.Exception("Scriptblock $($scriptParam.Name) failed during execution: $_", $_.Exception)) }
						else {
							Write-PSFMessage -Level Warning -Message "Scriptblock $($scriptParam.Name) failed during execution. Please specify a custom value or use CTRL+C to terminate creation" -ErrorRecord $_ -FunctionName "Invoke-PSMDTemplate" -ModuleName 'PSModuleDevelopment'
							$scriptParameters[$scriptParam.Name] = Read-Host -Prompt "Value for script $($scriptParam.Name)"
						}
					}
				}
			}
			#endregion Scripts
			
			switch ($templateData.Type.ToString()) {
				#region File
				"File"
				{
					foreach ($child in $templateData.Children) {
						Write-TemplateItem -Item $child -Path $OutPath -Encoding $Encoding -ParameterFlat $Parameters -ParameterScript $scriptParameters -Raw $Raw
					}
					if ($Raw -and $templateData.Scripts.Values) {
						$templateData.Scripts.Values | Export-Clixml -Path (Join-Path $OutPath "_PSMD_ParameterScripts.xml")
					}
				}
				#endregion File
				
				#region Project
				"Project"
				{
					#region Resolve output folder
					if (-not $NoFolder) {
						if ($Parameters["Name"]) {
							$projectName = $Parameters["Name"]
							$projectFullName = Join-Path $OutPath $projectName
							if ((Test-Path $projectFullName) -and (-not $Force)) {
								throw "Project root folder already exists: $projectFullName"
							}
							$newFolder = New-Item -Path $OutPath -Name $Parameters["Name"] -ItemType Directory -ErrorAction Stop -Force
						}
						else {
							throw "Parameter Name is needed to create a project without setting the -NoFolder parameter!"
						}
					}
					else { $newFolder = Get-Item $OutPath }
					#endregion Resolve output folder
					
					foreach ($child in $templateData.Children) {
						Write-TemplateItem -Item $child -Path $newFolder.FullName -Encoding $Encoding -ParameterFlat $Parameters -ParameterScript $scriptParameters -Raw $Raw
					}
					
					#region Write Config File (Raw)
					if ($Raw) {
						$guid = [System.Guid]::NewGuid().ToString()
						$optionsTemplate = @"
@{
	TemplateName = "$($Template.Name)"
	Version = ([Version]"$($Template.Version)")
	Tags = $(($Template.Tags | ForEach-Object { "'$_'" }) -join ",")
	Author = "$($Template.Author)"
	Description = "$($Template.Description)"
þþþPLACEHOLDER-$($guid)þþþ
}
"@
						if ($params = $templateData.Scripts.Values) {
							$list = @()
							foreach ($param in $params) {
								$list += @"
	$($param.Name) = {
		$($param.StringScript)
	}
"@
							}
							$optionsTemplate = $optionsTemplate -replace "þþþPLACEHOLDER-$($guid)þþþ", ($list -join "`n`n")
						}
						else {
							$optionsTemplate = $optionsTemplate -replace "þþþPLACEHOLDER-$($guid)þþþ", ""
						}
						
						$configFile = Join-Path $newFolder.FullName "PSMDTemplate.ps1"
						Set-Content -Path $configFile -Value $optionsTemplate -Encoding ([PSFEncoding]'utf-8').Encoding
					}
					#endregion Write Config File (Raw)
				}
				#endregion Project
			}
		}
		
		function Write-TemplateItem {
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
			[CmdletBinding()]
			param (
				[PSModuleDevelopment.Template.TemplateItemBase]
				$Item,
				
				[string]
				$Path,
				
				[PSFEncoding]
				$Encoding,
				
				[hashtable]
				$ParameterFlat,
				
				[hashtable]
				$ParameterScript,
				
				[bool]
				$Raw
			)
			
			Write-PSFMessage -Level Verbose -Message "Creating file: $($Item.Name) ($($Item.RelativePath))" -FunctionName Invoke-PSMDTemplate -ModuleName PSModuleDevelopment -Tag 'create', 'template'
			
			$identifier = $Item.Identifier
			$isFile = $Item.GetType().Name -eq 'TemplateItemFile'
			
			#region File
			if ($isFile) {
				$fileName = $Item.Name
				if (-not $Raw) {
					foreach ($param in $Item.FileSystemParameterFlat) {
						$fileName = $fileName.Replace("$($identifier)$($param)$($identifier)", $ParameterFlat[$param], $true, $null)
					}
					foreach ($param in $Item.FileSystemParameterScript) {
						$fileName = $fileName.Replace("$($identifier)$($param)$($identifier)", $ParameterScript[$param], $true, $null)
					}
				}
				$destPath = Join-Path $Path $fileName
				
				if ($Item.PlainText) {
					$text = $Item.Value
					if (-not $Raw) {
						foreach ($param in $Item.ContentParameterFlat) {
							$text = $text.Replace("$($identifier)$($param)$($identifier)", $ParameterFlat[$param], $true, $null)
						}
						foreach ($param in $Item.ContentParameterScript) {
							$text = $text.Replace("$($identifier)!$($param)!$($identifier)", $ParameterScript[$param], $true, $null)
						}
					}
					[System.IO.File]::WriteAllText($destPath, $text, $Encoding)

                    #If destination path is a *.fs file it should to be included in a F# project in the current directory
                    #or some parent directory futher up. Look for the neares .*fsproj file and add the file to the project.
                    if($destPath.EndsWith(".fs"))
                    {
                        #Destination is a F# source file. Find the parent project(s) and add.
                        $destinationFile = [System.IO.FileInfo]::new($destPath)
                        Find-PsmdFsProject -FolderPath $($destinationFile.Directory.FullName) | ForEach-Object {
                            $fsProjectFilePath = $_
                            Add-PSMDFsFileToFsProject -FsFilePath $destPath -FsProjectPath $fsProjectFilePath
                        }
                    }
				}
				else {
					$bytes = [System.Convert]::FromBase64String($Item.Value)
					[System.IO.File]::WriteAllBytes($destPath, $bytes)
				}
			}
			#endregion File
			
			#region Folder
			else {
				$folderName = $Item.Name
				if (-not $Raw) {
					foreach ($param in $Item.FileSystemParameterFlat) {
						$folderName = $folderName -replace "$($identifier)$([regex]::Escape($param))$($identifier)", $ParameterFlat[$param]
					}
					foreach ($param in $Item.FileSystemParameterScript) {
						$folderName = $folderName -replace "$($identifier)!$([regex]::Escape($param))!$($identifier)", $ParameterScript[$param]
					}
				}
				$folder = New-Item -Path $Path -Name $folderName -ItemType Directory
				
				foreach ($child in $Item.Children) {
					Write-TemplateItem -Item $child -Path $folder.FullName -Encoding $Encoding -ParameterFlat $ParameterFlat -ParameterScript $ParameterScript -Raw $Raw
				}
			}
			#endregion Folder
		}
		#endregion Helper function
	}
	process {
		if (Test-PSFFunctionInterrupt) { return }
		
		$invokeParam = @{
			Parameters = $Parameters.Clone()
			OutPath    = Resolve-PSFPath -Path $OutPath
			NoFolder   = $NoFolder
			Encoding   = $Encoding
			Raw	       = $Raw
			Silent	   = $Silent
		}
		
		foreach ($item in $Template) {
			Invoke-PSFProtectedCommand -ActionString 'Invoke-PSMDTemplate.Invoking' -ActionStringValues $item -Target $item -ScriptBlock {
				Invoke-Template @invokeParam -Template $item
			} -EnableException $EnableException -PSCmdlet $PSCmdlet -Continue
		}
		foreach ($item in $templates) {
			Invoke-PSFProtectedCommand -ActionString 'Invoke-PSMDTemplate.Invoking' -ActionStringValues $item -Target $item -ScriptBlock {
				Invoke-Template @invokeParam -Template $item
			} -EnableException $EnableException -PSCmdlet $PSCmdlet -Continue
		}
	}
}