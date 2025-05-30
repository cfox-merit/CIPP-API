<#
.SYNOPSIS
    This script updates the comment block in the CIPP standard files.

.DESCRIPTION
    The script reads the standards.json file and updates the comment block in the corresponding CIPP standard files.
    It adds or modifies the comment block based on the properties defined in the standards.json file.
    This is made to be able to generate the help documentation for the CIPP standards automatically.

.INPUTS
    None. You cannot pipe objects to this script.

.OUTPUTS
    None. The script modifies the CIPP standard files directly.

.NOTES
    .FUNCTIONALITY Internal needs to be present in the comment block for the script, otherwise it will not be updated.
    This is done as a safety measure to avoid updating the wrong files.

.EXAMPLE
    Update-StandardsComments.ps1

    This example runs the script to update the comment block in the CIPP standard files.

#>
param (
    [switch]$WhatIf
)


function EscapeMarkdown([object]$InputObject) {
    # https://github.com/microsoft/FormatPowerShellToMarkdownTable/blob/master/src/FormatMarkdownTable/FormatMarkdownTable.psm1
    $Temp = ''

    if ($null -eq $InputObject) {
        return ''
    } elseif ($InputObject.GetType().BaseType -eq [System.Array]) {
        $Temp = '{' + [System.String]::Join(', ', $InputObject) + '}'
    } elseif ($InputObject.GetType() -eq [System.Collections.ArrayList] -or $InputObject.GetType().ToString().StartsWith('System.Collections.Generic.List')) {
        $Temp = '{' + [System.String]::Join(', ', $InputObject.ToArray()) + '}'
    } elseif (Get-Member -InputObject $InputObject -Name ToString -MemberType Method) {
        $Temp = $InputObject.ToString()
    } else {
        $Temp = ''
    }

    return $Temp.Replace('\', '\\').Replace('*', '\*').Replace('_', '\_').Replace("``", "\``").Replace('$', '\$').Replace('|', '\|').Replace('<', '\<').Replace('>', '\>').Replace([System.Environment]::NewLine, '<br />')
}


# Find the paths to the standards.json file based on the current script path
$StandardsJSONPath = Split-Path (Split-Path $PSScriptRoot)
$StandardsJSONPath = Resolve-Path "$StandardsJSONPath\*\src\data\standards.json"
$StandardsInfo = Get-Content -Path $StandardsJSONPath | ConvertFrom-Json -Depth 10

foreach ($Standard in $StandardsInfo) {

    # Calculate the standards file name and path
    $StandardFileName = $Standard.name -replace 'standards.', 'Invoke-CIPPStandard'
    $StandardsFilePath = Resolve-Path "$(Split-Path $PSScriptRoot)\Modules\CIPPCore\Public\Standards\$StandardFileName.ps1"
    if (-not (Test-Path $StandardsFilePath)) {
        Write-Host "No file found for standard $($Standard.name)" -ForegroundColor Yellow
        continue
    }
    $Content = (Get-Content -Path $StandardsFilePath -Raw).TrimEnd() + "`n"

    # Remove random newlines before the param block
    $regexPattern = '#>\s*\r?\n\s*\r?\n\s*param'
    $Content = $Content -replace $regexPattern, "#>`n`n    param"

    # Regex to match the existing comment block
    $Regex = '<#(.|\n)*?\.FUNCTIONALITY\s*Internal(.|\n)*?#>'

    if ($Content -match $Regex) {
        $NewComment = [System.Collections.Generic.List[string]]::new()
        # Add the initial static comments
        $NewComment.Add("<#`n")
        $NewComment.Add("   .FUNCTIONALITY`n")
        $NewComment.Add("       Internal`n")
        $NewComment.Add("   .COMPONENT`n")
        $NewComment.Add("       (APIName) $($Standard.name -replace 'standards.', '')`n")
        $NewComment.Add("   .SYNOPSIS`n")
        $NewComment.Add("       (Label) $($Standard.label.ToString())`n")
        $NewComment.Add("   .DESCRIPTION`n")
        if ([string]::IsNullOrWhiteSpace($Standard.docsDescription)) {
            $NewComment.Add("       (Helptext) $($Standard.helpText.ToString())`n")
            $NewComment.Add("       (DocsDescription) $(EscapeMarkdown($Standard.helpText.ToString()))`n")
        } else {
            $NewComment.Add("       (Helptext) $($Standard.helpText.ToString())`n")
            $NewComment.Add("       (DocsDescription) $(EscapeMarkdown($Standard.docsDescription.ToString()))`n")
        }
        $NewComment.Add("   .NOTES`n")

        # Loop through the rest of the properties of the standard and add them to the NOTES field
        foreach ($Property in $Standard.PSObject.Properties) {
            switch ($Property.Name) {
                'name' { continue }
                'impactColour' { continue }
                'docsDescription' { continue }
                'helpText' { continue }
                'label' { continue }
                Default {
                    $NewComment.Add("       $($Property.Name.ToUpper())`n")
                    if ($Property.Value -is [System.Object[]]) {
                        foreach ($Value in $Property.Value) {
                            $NewComment.Add("           $(ConvertTo-Json -InputObject $Value -Depth 5 -Compress)`n")
                        }
                        continue
                    } elseif ($Property.Value -is [System.Management.Automation.PSCustomObject]) {
                        $NewComment.Add("           $(ConvertTo-Json -InputObject $Property.Value -Depth 5 -Compress)`n")
                        continue
                    } else {
                        if ($null -ne $Property.Value) {
                            $NewComment.Add("           $(EscapeMarkdown($Property.Value.ToString()))`n")
                        }
                    }
                }
            }

        }

        # Add header about how to update the comment block with this script
        $NewComment.Add("       UPDATECOMMENTBLOCK`n")
        $NewComment.Add("           Run the Tools\Update-StandardsComments.ps1 script to update this comment block`n")
        # -Online help link
        $NewComment.Add("   .LINK`n")
        $DocsLink = 'https://docs.cipp.app/user-documentation/tenant/standards/list-standards'

        $NewComment.Add("       $DocsLink`n")
        $NewComment.Add('   #>')

        # Write the new comment block to the file
        if ($WhatIf.IsPresent) {
            Write-Host "Would update $StandardsFilePath with the following comment block:"
            $NewComment
        } else {
            $Content -replace $Regex, $NewComment | Set-Content -Path $StandardsFilePath -Encoding utf8 -NoNewline
        }
    } else {
        Write-Host "No comment block found in $StandardsFilePath" -ForegroundColor Yellow
    }
}
