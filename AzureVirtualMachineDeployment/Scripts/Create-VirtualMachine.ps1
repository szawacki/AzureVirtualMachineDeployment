Param(  [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()] 
        [string]$File,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]  
        [string]$ResourceGroupName,

        [Parameter(Mandatory=$true)] 
        [ValidateNotNullOrEmpty()] 
        [string]$ResourceGroupLocation,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]  
        [string]$StorageAccountName,

        [Parameter(Mandatory=$true)] 
        [ValidateNotNullOrEmpty()] 
        [string]$VmName,

        [Parameter(Mandatory=$true)] 
        [ValidateNotNullOrEmpty()] 
        [string]$VmSize,

        [Parameter(Mandatory=$true)] 
        [ValidateNotNullOrEmpty()]  
        [string]$Skus,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]  
        [string]$VnetName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]  
        [string]$AdminName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]  
        [string]$AdminPwd,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]  
        [int]$NumberOfDisks,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]  
        [int]$DiskSize,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]  
        [string]$InstallExtendedLoad
)


function ConvertTo-Boolean
{
    Param
    (
        [Parameter(Mandatory=$false)]
        [string] $Value
    )

    Switch ($Value)
    {
        "y" { return $true; }
        "yes" { return $true; }
        "true" { return $true; }
        "t" { return $true; }
        1 { return $true; }
        "" { return $false }
        "n" { return $false; }
        "no" { return $false; }
        "false" { return $false; }
        "f" { return $false; } 
        0 { return $false; }
    }
}

Function GetPublicIpFQDN () 
{
    Param(  [Parameter(Mandatory=$true)] 
            [ValidateNotNullOrEmpty()] 
            [string]$ResourceGroupName,

            [Parameter(Mandatory=$true)] 
            [ValidateNotNullOrEmpty()] 
            [string]$PublicIpAdressName
    )

    return (Get-AzureRmPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $PublicIpAdressName).DnsSettings.Fqdn
}

Function GetRdpFile()
{
    Param(  [Parameter(Mandatory=$true)] 
            [ValidateNotNullOrEmpty()] 
            [string]$ResourceGroupName,

            [Parameter(Mandatory=$true)] 
            [ValidateNotNullOrEmpty()] 
            [string]$VirtualComputerName,

            [Parameter(Mandatory=$true)] 
            [ValidateNotNullOrEmpty()] 
            [string]$VirtualComputerAdminUserName
    )

    $RdpFilePath = "$($env:USERPROFILE)\Downloads\$($VirtualComputerName).rdp"

    Get-AzureRmRemoteDesktopFile -ResourceGroupName $ResourceGroupName -Name $VirtualComputerName -LocalPath $RdpFilePath
    $Fqdn = GetPublicIpFQDN -ResourceGroupName $ResourceGroupName -PublicIpAdressName "$($VirtualComputerName)PublicIP01"
    $Content = [System.IO.File]::ReadAllText($RdpFilePath) -ireplace 'full address:s:.+', "full address:s:$($Fqdn)"
    [System.IO.File]::WriteAllText($RdpFilePath, $Content)
    Add-Content -Path $RdpFilePath -Value "`r`nusername:s:$($Fqdn)\$($VirtualComputerAdminUserName)"
}

Function CreateCustomScriptExtension()
{
    Param(  [Parameter(Mandatory=$true)] 
            [ValidateNotNullOrEmpty()] 
            [string]$VmName,

            [Parameter(Mandatory=$true)] 
            [ValidateNotNullOrEmpty()] 
            [string]$ResourceGroupName,

            [Parameter(Mandatory=$true)] 
            [ValidateNotNullOrEmpty()] 
            [string]$AdminName,

            [Parameter(Mandatory=$true)] 
            [ValidateNotNullOrEmpty()] 
            [string]$AdminPwd
    )
   
    $key = (Get-AzureRmStorageAccountKey -ResourceGroupName "<your resource group name>" -Name "<your storage name>" -ErrorAction Stop).Key1

    Set-AzureRmVMCustomScriptExtension -ResourceGroupName $ResourceGroupName `
                                       -VMName $VmName `
                                       -Name "CustomInstallation" `
                                       -StorageAccountName "<your storage name>" `
                                       -ContainerName "sqlserver2014" `
                                       -StorageAccountKey $key `
                                       -FileName @('<your files array>') `
                                       -Run '<your installation script name>' `
                                       -Argument "$($AdminName) $($AdminPwd)" `
                                       -Location "<your location>" `
                                       -ErrorAction Stop  
}

Select-AzureRmProfile -Path $File

$StorageAccount = Get-AzureRmStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction Stop

$OsDiskUri = $StorageAccount.PrimaryEndpoints.Blob.ToString() + "vhds/$($VmName)-OsDisk.vhd"  

$Credential = New-Object System.Management.Automation.PSCredential($AdminName, (ConvertTo-SecureString $AdminPwd -AsPlainText -Force))

$PublicIP = New-AzureRmPublicIpAddress -Name "$($VmName)PublicIP01" `
                                       -ResourceGroupName $ResourceGroupName `
                                       -Location $ResourceGroupLocation `
                                       -DomainNameLabel $VmName.ToLower() `
                                       -AllocationMethod Dynamic `
                                       -ErrorAction Stop `
                                       -Force
                                        
$Vnet = Get-AzureRmVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroupName                                                                                 
                                                       
$Nic = New-AzureRmNetworkInterface -Name "$($VmName)Nic001" `
                                   -ResourceGroupName $ResourceGroupName `
                                   -Location $ResourceGroupLocation `
                                   -SubnetId $Vnet.Subnets[0].Id `
                                   -PublicIpAddressId $PublicIP.Id `
                                   -ErrorAction Stop `
                                   -Force

$Vm = New-AzureRmVMConfig -VMName $VmName -VMSize $VmSize
$Vm = Set-AzureRmVMOperatingSystem -VM $Vm -Windows -ComputerName $VmName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate
$Vm = Set-AzureRmVMSourceImage -VM $Vm -PublisherName "MicrosoftVisualStudio" -Offer VisualStudio -Skus $Skus -Version "latest"
$Vm = Add-AzureRmVMNetworkInterface -VM $Vm -Id $Nic.Id
$Vm = Set-AzureRmVMOSDisk -VM $Vm -Name "$($VmName)-OsDisk" -VhdUri $OsDiskUri -CreateOption FromImage

if ($NumberOfDisks -gt 0)
{
    for ($i = 0; $i -lt $NumberOfDisks; $i++)
    {
        $Vm = Add-AzureRmVMDataDisk -VM $Vm `
                                    -Name "$($VmName)-DataDisk$($i)" `
                                    -VhdUri ($StorageAccount.PrimaryEndpoints.Blob.ToString() + "vhds/$($VmName)-DataDisk$($i).vhd") `
                                    -DiskSizeInGB $DiskSize `
                                    -CreateOption Empty `
                                    -Lun $i -ErrorAction Stop
    }
}
 
Write-Host "Creating new virtual machine '$($VmName)' ..."

New-AzureRmVM -ResourceGroupName $ResourceGroupName `
              -Location $ResourceGroupLocation `
              -VM $Vm `
              -ErrorAction Stop

if (ConvertTo-Boolean -Value $InstallExtendedLoad)
{
    #Install custom script extensions, for configuration see above function
    #CreateCustomScriptExtension -VmName $VmName -ResourceGroupName $ResourceGroupName -AdminName $AdminName -AdminPwd $AdminPwd
}

GetRdpFile -ResourceGroupName $ResourceGroupName `
           -VirtualComputerName $VmName `
           -VirtualComputerAdminUserName $AdminName