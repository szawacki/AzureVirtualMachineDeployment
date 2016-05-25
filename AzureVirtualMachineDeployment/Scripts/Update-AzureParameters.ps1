$JsonFile = "$($PSScriptRoot)\..\Templates\azuredeploy.json"

$Context = Get-AzureRmContext

if (!$Context)
{
    Login-AzureRmAccount -Credential (Get-Credential -Message "Provide username  password for login into azure.") -ErrorAction Stop
}

Function GetHardwareConfiguration() 
{
    $arrRoles = Get-AzureRoleSize
    $arrString = New-Object Collections.Generic.List[String]

    foreach ($role in $arrRoles) 
    {
        $arrString.Add("`t`t`t`t""$($role.InstanceSize)"",") | Out-Null
    }

    return $arrString
}

Function GetSkus()
{
    #Filtered to images including visual studio installations
    $Skus = (Get-AzureRmVMImageSku -Location "West europe" -PublisherName "MicrosoftVisualStudio" -Offer "VisualStudio" | Where-Object { $_.Skus -like 'VS*' -and $_.Skus -like "*-Comm*" }).Skus
    $SKus += (Get-AzureRmVMImageSku -Location "West europe" -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer").Skus
    $SkuList = New-Object Collections.Generic.List[String]

    foreach ($Sku in $Skus) 
    {
        $SkuList.Add("`t`t`t`t""$($Sku)"",") | Out-Null
    }

    return $SkuList
}

Function GetContentList($content, $sectionName, [Collections.Generic.List[String]]$arrayContent) 
{
    [Collections.Generic.List[String]]$contentList = $content
    $arrayContent.Sort()
    $arrayContent[$($arrayContent.Count -1)] = $arrayContent[$($arrayContent.Count -1)].Substring(0, $arrayContent[$($arrayContent.Count -1)].LastIndexOf(","))

    for ($i = 0; $i -lt $contentList.Count; $i++) 
    {
        if ($contentList[$i].contains($sectionName)) 
        {
            $startIndex = $contentList.FindIndex($i, { param($m) $m.contains("allowedValues") })
            if ($startIndex -gt -1) 
            {
                $endIndex = $contentList.FindIndex($i, { param($m) $m.contains("]") })
                $contentList.RemoveRange($startIndex +1, $endIndex - $startIndex -1)
                $contentList.InsertRange($startIndex +1, $arrayContent)
            }
            break
        }

    }

    return $contentList
}


(GetContentList (Get-Content $JsonFile) ("VirtualComputerSize") (GetHardwareConfiguration)) | Out-File $JsonFile -Force

if ($?)
{
    Write-Host "Successfully updated allowed values of parameter 'VirtualComputerSize'."
} 
else 
{
    throw "Failed updating allowed values of parameter 'VirtualComputerSize'."
}

(GetContentList (Get-Content $JsonFile) ("Image") (GetSkus)) | Out-File $JsonFile -Force

if ($?)
{
    Write-Host "Successfully updated allowed values of parameter 'Image'."
} 
else 
{
    throw "Failed updating allowed values of parameter 'Image'."
}

