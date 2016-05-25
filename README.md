# Azure Virtual Machine Deployment Project

This project for visual studio 2015 provieds an easy way to create virtual machines in Microsoft Azure. As the original ARM-Templates have some limitations, this project uses a powershell script to created the virtual machines, configured in the json template file.
Creation of multiple virtual machines with equal configuration is supported.

Azuredeploy.json contains the json template it is not neccessarry to do any chnages here. The parameter file azuredeploy.parameters.json saves the settings for late reuse.

The scripts folder continas the powerhsell scripts, Create-VirtualMachine.ps1, Deploy-AzureResourceGroup.ps1 and Update-AzureParameters.ps1.

## Update-AzureParameters.ps1

In azuredeploy.json file the default values for "Image" and "VirtualComputerSize" may change in the future. So the update script requests these parameters from azure and updates the json template file. It is neccessarry to provide credentials when updating the template file.

## Deploy-AzureResourceGroup.ps1

The main installation script reads the json template files and starts passes the needed informartion to the Create-VirtualMachine.ps1 script that performs the creation of the new virtual machines.

## VmList.txt

This text file is located in the templates folder and is used for creation of multiple virtual machines simultaniously.
Set one vm name per line and to create multiple vms. This overrides the name of the virtual machine set in azuredeploy.parameters.json file.
Leave this file empty to create a singel vm with the name provided in azuredeploy.parameters.json.


## Usage

Open the project and right click the project "AzureVirtualMachineDeployment" in solution explorer.
Select "Deploy" -> "New Deployment".

In the upcomming dialog make your configuration settings deploy it.

Create a project template and reuse it in visual studio if you want.