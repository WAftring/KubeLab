param(
        $WinISO,
        $UbuntuISO,
        [int]$NumUbuntu,
        [int]$NumWindows,
        [int]$GBMemoryPerVM
)

$Script:VMSwitchName = "k8s-switch"
$Script:MasterNodeName = "k8s-master"
$Script:WorkerName = "~OS~-worker-~NUM~"
$Script:Storage = 75GB
$Script:HyperVPath = "C:\k8s-lab\"
$Script:VMMemory = 4GB
$Script:K8sMasterVHD = "C:\k8s-lab\VHD\k8s-master.vhdx"
$Script:WorkerVHD = "C:\k8s-lab\VHD\~WORKER~.vhdx"
$Script:GB2B = 1073741824

enum LogType {
        ERROR
        WARN
        INFO
}

function Write-Log {
        param(
                $Content,
                $Type
        )

        $FullContent = Get-Date -UFormat "%T "
        switch ($Type) {
                [LogType]::INFO {
                        $FullContent += "[INFO] " + $Content
                        Write-Output $FullContent
                }
                [LogType]::WARN {
                        $FullContent += "[WARN] " + $Content
                        Write-Host $FullContent -ForegroundColor Yellow
                }
                [LogType]::ERROR {
                        $FullContent += "[ERROR] " + $Content
                        Write-Host $FullContent -ForegroundColor Red
                }
        }
}

function CreateVM {
        param(
                [string]$Name,
                $Memory,
                [string]$VHDPath,
                $VHDSize
        )

        $Temp = New-VM -Name $Name  -MemoryStartUpBytes $Memory `
                -NewVHDPath $VHDPath -NewVHDSizeBytes $VHDSize -Generation 2

        return $Temp
}

function Setup-HyperV {

        # Setting up the environment requirements
        Write-Log -Content "Starting Hyper-V setup" -Type [LogType]::INFO
        $PhysicalAdapter = (Get-NetAdapter -Physical | Select-Object -First 1).Name
        Write-Log -Content "Creating VMSwitch. You may have a momentary network interruption`nPress Enter to continue." -Type [LogType]::WARN
        Read-Host
        New-VMSwitch -Name $Script:VMSwitchName -NetAdapterName $PhysicalAdapter
        New-Item -Path $Script:HyperVPath -Name VHD -ItemType Directory -Force
        Write-Log -Content "Done Hyper-V setup" -Type [LogType]::INFO
}

function Setup-VMs {
        param(
                [int]$NumNixVM,
                [int]$NumWinVM,
                [int]$GBPerVM,
                [string]$UbuntuISO,
                [string]$WindowsISO
        )

        $VMArrayList = [System.Collections.ArrayList]::New()
        # Starting to create k8s-master
        Write-Log -Content "Starting Ubuntu VM(s) setup" -Type [LogType]::INFO
        $k8smaster = CreateVM -Name $Script:MasterNodeName -Memory $Script:VMMemory -VHDPath $Script:K8sMasterVHD `
                -VHDSize $Script:Storage
        $VMArrayList.Add($k8smaster) | Out-Null

        if ($NumNixVM -ne 0) {
                Write-Log -Content "Creating additional $NumVM Ubuntu VM(s)" -Type [LogType]::INFO
                for ($i = 1; $i -lt $NumNixVM + 1; $i++) {
                        $UName = $Script:WorkerName.Replace("~OS~", "UBUNTU").Replace("~NUM~", $i)
                        $UVM = CreateVM -Name $UName -Memory ($GBPerVM * $Script:GB2B) `
                                -VHDPath $Script:WorkerVHD.Replace("~WORKER~", $UName) `
                                -VHDSize $Script:Storage
                        $VMArrayList.Add($UVM) | Out-Null
                }
        }

        Write-Log -Content "Configuring Ubuntu VM(s)" -Type [LogType]::INFO
        $VMArrayList | ForEach-Object {
                $_ | Set-VM -ProcessorCount 2 -DynamicMemory
                $_ | Set-VMProcessor -ExposeVirtualizationExtension $true
                $_ | Set-VMFirmware -EnableSecureBoot Off
                $HardDisk = Get-VMHardDiskDrive -VM $_
                $_ | Set-VMFirmware -BootOrder $HardDisk
                $_ | Set-VMNetworkAdapter -MacAddressSpoofing On
                $VMAdapter = Get-VMNetworkAdapter -VM $_
                Connect-VMNetworkAdapter -SwitchName $Script:VMSwitchName -VMNetworkAdapter $VMAdapter
                #$_ | Add-VMDvdDrive -Path $UbuntuISO
        }
        Write-Log -Content "Done configuring Ubuntu VM(s)" -Type [LogType]::INFO
        Write-Log -Content "Starting Windows VM(s) setup" -Type [LogType]::INFO

        $VMArrayList.Clear()
        $WinWorker1 = $Script:WorkerName.Replace("~OS~", "WIN").Replace("~NUM~", 1)
        $WinNode1 = CreateVM -Name $WinWorker1 -Memory $Script:VMMemory `
                -VHDPath $Script:WorkerVHD.Replace("~WORKER~", $WinWorker1) `
                -VHDSize $Script:Storage
        $VMArrayList.Add($WinNode1) | Out-Null

        if ($NumWinVM -ne 0) {

                Write-Log -Content "Creating additional $NumWinVM Windows VM(s)" -Type [LogType]::INFO
                for ($i = 1; $i -lt $NumWinVM + 1; $i++) {
                        $UName = $Script:WorkerName.Replace("~OS~", "WIN").Replace("~NUM~", $i + 1)
                        $UVM = CreateVM -Name $UName -Memory ($GBPerVM * $Script:GB2B) `
                                -VHDPath $Script:WorkerVHD.Replace("~WORKER~", $UName) `
                                -VHDSize $Script:Storage
                        $VMArrayList.Add($UVM) | Out-Null
                }
        }

        Write-Log "Configuring Windows VM(s)" -Type [LogType]::INFO
        $VMArrayList | ForEach-Object {
                $_ | Set-VM -ProcessorCount 2 -DynamicMemory
                $_ | Set-VMProcessor -ExposeVirtualizationExtension $true
                $HardDisk = Get-VMHardDiskDrive -VM $_
                $_ | Set-VMFirmware -BootOrder $HardDisk
                $_ | Set-VMNetworkAdapter -MacAddressSpoofing On
                $VMAdapter = Get-VMNetworkAdapter -VM $_
                Connect-VMNetworkAdapter -SwitchName $Script:VMSwitchName -VMNetworkAdapter $VMAdapter
                #$_ | Add-VMDvdDrive -Path $WinISO
        }

        $VMArrayList.Clear()

}





#Confirm our ISO's exist

if(!(Test-Path $WinISO) -or !(Test-Path $UbuntuISO)){
        Write-Log -Content "Invalid ISO path" -Type [LogType]
}


if ($WinISO -notlike "*server_2019*") {
        Write-Log -Content "ISO doesn't match '*server_2019*'. Did you provide the right ISO?" -Type [LogType]::ERROR
        return
}
if ($UbuntuISO -notlike "ubuntu-*") {
        Write-Log -Content "ISO doesn't match 'ubuntu-*'. Did you provide the right ISO?" -Type [LogType]::ERROR
        return
}




Write-Log -Content "Starting k8s lab setup" -Type [LogType]::INFO

# Setting up Hyper-V
#Setup-HyperV

# Creating linux VMs
Setup-VMs -NumNixVM $NumUbuntu -NumWinVM $NumWindows `
        -GBPerVM $GBMemoryPerVM -UbuntuISO $UbuntuISO `
        -WindowsISO $WinISO
