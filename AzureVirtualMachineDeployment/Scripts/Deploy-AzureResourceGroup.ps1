#Requires -Version 3.0
#Requires -Module AzureRM.Resources
#Requires -Module Azure.Storage

Param(
    [string] [Parameter(Mandatory=$true)] $ResourceGroupLocation,
    [string] [Parameter(Mandatory=$true)] $ResourceGroupName = 'AzureCustomVmDeployment',
    [switch] $UploadArtifacts,
    [string] $StorageAccountName,
    [string] [Parameter(Mandatory=$true)] $TemplateFile = '..\Templates\azuredeploy.json',
    [string] [Parameter(Mandatory=$true)] $TemplateParametersFile = '..\Templates\azuredeploy.parameters.json',
    [string] $ArtifactStagingDirectory = '..\bin\Debug\staging',
    [string] $AzCopyPath = '..\Tools\AzCopy.exe',
    [string] $DSCSourceFolder = '..\DSC'
)

Import-Module Azure -ErrorAction SilentlyContinue

try {
    [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent("VSAzureTools-$UI$($host.name)".replace(" ","_"), "2.8")
} catch { }

Set-StrictMode -Version 3

Function GetParameters () 
{
    Param(  [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]  
            [string]$JsonFile,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()] 
            [ValidateSet("DefaultValue", "Value")] 
            [string]$Value
    )

    $Parameters = New-Object -TypeName Hashtable
    $JsonContent = Get-Content $JsonFile -Raw | ConvertFrom-Json
    $JsonParameters = $JsonContent | Get-Member -Type NoteProperty | Where-Object {$_.Name -eq "parameters"}

    if ($JsonParameters -eq $null) {
        $JsonParameters = $JsonContent
    }
    else 
    {
        $JsonParameters = $JsonContent.parameters
    }

    $JsonParameters | Get-Member -Type NoteProperty | ForEach-Object {
        $ParameterValue = $JsonParameters | Select-Object -ExpandProperty $_.Name
            
        if ($Value -eq "DefaultValue")
        {
            try
            {
                $Parameters[$_.Name] = $ParameterValue.defaultvalue
            }
            catch {}
        } 
        elseif ($Value -eq "Value")
        {
            try 
            {
                $Parameters[$_.Name] = $ParameterValue.value
            }
            catch {}
        }
    }

    return $Parameters
}

Function CreateVirtualNetwork 
{
    Param(  [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]  
            [string]$ResourceGroupName,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]  
            [string]$ResourceGroupLocation,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]  
            [string]$VNetName,

            [Parameter(Mandatory=$true)] 
            [ValidateNotNullOrEmpty()] 
            [string]$VnetAddressPrefix,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]  
            [string]$SubnetName,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]  
            [string]$SubnetAddressPrefix
    )

    Write-Host "Get virtual network: $($VNetName)"
    $Vnet = Get-AzureRmVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

    if(!$Vnet) 
    {
        $SubnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetAddressPrefix -ErrorAction Stop

        Write-Host "Virtual network $($VNetName) not found, creating new..."
        $Vnet = New-AzureRmVirtualNetwork -Name $VNetName `
                                            -ResourceGroupName $ResourceGroupName `
                                            -Location $ResourceGroupLocation `
                                            -AddressPrefix $VnetAddressPrefix `
                                            -Subnet $SubnetConfig `
                                            -ErrorAction Stop
    } 
    else 
    {
        $SubnetConfig = Get-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $Vnet -ErrorAction SilentlyContinue

        if (!$SubnetConfig)
        {
            Write-Host "Subnet $($SubnetName) not found, creating new..."
            $Vnet | Add-AzureRmVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix $SubnetAddressPrefix -ErrorAction Stop
        }
    }

    return $Vnet
}

Function CreateAzureStorageConatiner() 
{
    Param(  [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]  
            [string]$ContainerName,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]  
            [string]$ResourceGroupName,

            [Parameter(Mandatory=$true)] 
            [ValidateNotNullOrEmpty()] 
            [string]$StorageAccountName,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]  
            [string]$StorageType 
    )
    
    $StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue

    if (!$StorageAccount)
    {
        Write-Host "Storage '$($StorageAccountName)' not found, creating new ..."
        $StorageAccount = New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName `                                                    -Name $StorageAccountName `                                                    -Type $StorageType `                                                    -Location (Get-AzureRmResourceGroup -Name $ResourceGroupName).Location `
                                                    -ErrorAction Stop `
     }

    # Destination Storage Account Information #
    $StorageAccountKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).Key1
    $StorageAccountContext = New-AzureStorageContext –StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey  

    # Create the destination container #
    $Container = Get-AzureStorageContainer -Name $ContainerName -Context $StorageAccountContext -ErrorAction SilentlyContinue
        
    if (!$Container) 
    {
        Write-Host "StorageContainer '$($ContainerName)' not found. Creating new ..."
        New-AzureStorageContainer -Name $ContainerName -Context $StorageAccountContext -ErrorAction Stop
    } 
}

$Parameters = GetParameters -JsonFile $TemplateFile -Value DefaultValue
$OptionalParameters = GetParameters -JsonFile $TemplateParametersFile -Value Value
$ContextFile = "$($env:temp)\~016737cvm.tmp"
$VmListFile = "$($PSScriptRoot)\..\Templates\VmList.txt"

foreach ($Key in $OptionalParameters.Keys)
{
    if ($OptionalParameters[$Key])
    {
        $Parameters[$Key] = $OptionalParameters[$Key]
    }
}

$Context = Get-AzureRmContext

#if (!$Context)
#{ 
#    Write-Host "New Azure Login"
#    $Context = Login-AzureRmAccount -Credential (Get-Credential -Message "Provide username and password.") -SubscriptionName $AzureSubscription    
#} 

Write-Host "Deploying with following parameters:" 
Write-Host "------------------------------------"
$Parameters 
Write-Host ""

$ResourceGroup = New-AzureRmResourceGroup -Name $ResourceGroupName `
                                          -Location $ResourceGroupLocation `
                                          -Force `
                                          -ErrorAction Stop `

CreateAzureStorageConatiner -ContainerName "vhds" `                            -ResourceGroupName $ResourceGroup.ResourceGroupName `
                            -StorageAccountName $Parameters["StorageAccountName"].ToLower() `
                            -StorageType $Parameters["StorageAccountType"]


CreateVirtualNetwork -ResourceGroupName $ResourceGroup.ResourceGroupName `
                     -ResourceGroupLocation $ResourceGroup.Location `
                     -VNetName $Parameters["VirtualNetworkName"] `
                     -VnetAddressPrefix $Parameters["VirtualNetworkPrefix"] `
                     -SubnetName "SUB1" `
                     -SubnetAddressPrefix $Parameters["VirtualNetworkSubnetPrefix"]


if (Test-Path -Path $VmListFile -PathType Leaf)
{
    $VmNames = Get-Content $VmListFile
}

if (!$VmNames)
{
    $VmNames = @($Parameters["VirtualComputerName"])
}

try {
    Save-AzureRmProfile -Path $ContextFile

    foreach ($VmName in $VmNames)
    {
        Start-Job -FilePath "$($PSScriptRoot)\Create-VirtualMachine.ps1" `
                  -ArgumentList @($ContextFile, 
                                  $ResourceGroup.ResourceGroupName, 
                                  $ResourceGroup.Location, 
                                  $Parameters["StorageAccountName"].ToLower(), 
                                  $VmName.Trim(), 
                                  $Parameters["VirtualComputerSize"], 
                                  $Parameters["Image"], 
                                  $Parameters["VirtualNetworkName"], 
                                  $Parameters["VirtualComputerAdminUserName"], 
                                  $Parameters["VirtualComputerAdminPassword"],
                                  $Parameters["NumberOfAdditionalHarddisks"],
                                  $Parameters["AdditionalHarddiskSize"],
                                  $Parameters["InstallExtendedLoad"]
                                  )
    }

    Get-Job | Wait-Job
    Get-Job | Receive-Job
}
finally
{
    Remove-Item -Path $ContextFile
}
