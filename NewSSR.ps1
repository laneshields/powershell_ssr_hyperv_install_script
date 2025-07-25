<#
.SYNOPSIS
    Provision SSR VM no Hyper-V
.Example
    PS C:\> .\<name>.ps1 -VMName SSR01 -NumCores 4 -Memory 8GB -Nics firstIfSwitch,secondIfSwitch,thirdIfSwitch -RouterName SSR01 -OnboardingMode conductor-managed
#>

#requires -Modules Hyper-V
#requires -RunAsAdministrator

[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$VMName,
    [Parameter(Mandatory)] [string]$BaseQcowPath,
    [Parameter(Mandatory)] [int]$NumCores,
    [Parameter(Mandatory)] [string]$Memory,
    [Parameter(Mandatory)] [string[]]$Nics,
    [Parameter(Mandatory)] [ValidateSet("mist-managed", "conductor-managed", "conductor")] [string]$OnboardingMode,
    [Parameter(Mandatory)] [string]$RouterName,
    [Parameter()] [string]$RegistrationCode,
    [Parameter()] [ValidateCount(1,2)] [ValidatePattern("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$")] [string[]]$ConductorAddress,
    [Parameter()] [ValidateSet("node0", "node1")] [string]$NodeName,
    [Parameter()] [string]$ArtifactoryUser,
    [Parameter()] [string]$ArtifactoryPassword,
    [Parameter()] [ValidatePattern("^ge-0-[0-9]$")] [string]$ManagementInterfaceName,
    [Parameter()] [ValidatePattern("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(\/([0-9]|[12][0-9]|3[0-2]))?$")] [string]$NodeIp,
    [Parameter()] [ValidatePattern("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$")] [string]$NodeGateway,
    [Parameter()] [ValidateCount(1,2)] [ValidatePattern("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$")] [string[]]$DnsServers,
    [Parameter()] [bool]$clustered,
    [Parameter()] [ValidatePattern("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(\/([0-9]|[12][0-9]|3[0-2]))?$")] [string]$HaIp,
    [Parameter()] [ValidatePattern("^ge-0-[0-9]$")] [string]$HaInterfaceName,
    [Parameter()] [string]$HaPeerName,
    [Parameter()] [ValidatePattern("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$")] [string]$HaPeerIp,
    [Parameter()] [bool]$LearnFromHaPeer,
    [Parameter()] [string]$HaPeerUsername,
    [Parameter()] [string]$HaPeerPassword,
    [Parameter()] [ValidatePattern("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(\/([0-9]|[12][0-9]|3[0-2]))?$")] [string]$StaticAddress,
    [Parameter()] [ValidatePattern("^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$")] [string]$StaticGateway,
    [Parameter()] [ValidateRange(1,4094)] [int]$Vlan
)


if ($OnboardingMode -eq "mist-managed" -and -not $RegistrationCode) {
    throw "Registration Code required when onboarding-mode is mist-managed"
}
if ($OnboardingMode -eq "conductor-managed" -and -not $ConductorAddress) {
    throw "Conductor Address required when onboarding-mode is conductor-managed"
}
if ($OnboardingMode -eq "conductor" -and -not $NodeName) {
    throw "Node name required when onboarding-mode is conductor"
}
if ($OnboardingMode -eq "conductor" -and $clustered) {
    if (-not $HaIp -or -not $HaInterfaceName -or -not $HaPeerName) {
        throw "For Conductor Clustered onboarding, all options must be set: HaInterfaceName, HaPeerName, and HaPeerIp"
    }
}
if ($LearnFromHaPeer -and (-not $HaPeerUsername -or -not $HaPeerPassword)) {
    throw "When learning from Conductor HA peer both username and password must be specified"
}


function Convert-ToBytes ($value) {
    if ($value -match '^\s*(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB|PB)?\s*$') {
        $size = [double]$matches[1]
        $unit = $matches[2]

        if (-not $unit) {
            $unit = 'B'
        }

        switch ($unit.ToUpper()) {
            'B'  { return [int64]$size }
            'KB' { return [int64]($size * 1KB) }
            'MB' { return [int64]($size * 1MB) }
            'GB' { return [int64]($size * 1GB) }
            'TB' { return [int64]($size * 1TB) }
            'PB' { return [int64]($size * 1PB) }
            default { throw "Unsupported unit: $unit" }
        }
    } else {
        throw "Invalid memory format: '$value'. Use formats like '1048576', '512MB', '8 GB'."
    }
}


function Find-QemuImg {
    $pathList = @()

    # Split PATH entries
    $pathList += ($env:PATH -split ';')

    # Common install paths
    $pathList += 'C:\Program Files\qemu'
    $pathList += 'C:\Program Files (x86)\qemu'
    $pathList += 'D:\Tools'

    # MSYS2 paths
    $pathList += 'C:\msys64\ucrt64\bin'
    $pathList += 'C:\msys64\mingw64\bin'
    $pathList += 'C:\msys64\clang64\bin'

    foreach ($path in $pathList) {
        if (![string]::IsNullOrWhiteSpace($path)) {
            $exePath = Join-Path -Path $path.Trim() -ChildPath 'qemu-img.exe'
            if (Test-Path $exePath) {
                return $exePath
            }
        }
    }

    throw "qemu-img.exe not found. Please install QEMU or place qemu-img.exe in a known location (like D:\Tools or MSYS2's bin directories) and ensure it's accessible."
}


# Newer versions of qemu-img automatically create the vhdx as sparse, which Hyper-V does not like, handle that
function Remove-SparseAttribute {
    param (
        [string]$Path
    )

    $isSparse = (fsutil sparse queryflag $Path) -match 'This file is set as sparse'
    if ($isSparse) {
        Write-Host "qemu-img generated VHDX file is sparse, de-sparsifying: $Path"
        #$temp = "$Path.tmp"
        #Copy-Item -Path $Path -Destination $temp
        #Remove-Item $Path
        #Move-Item $temp $Path
		fsutil sparse setflag $Path 0
    } else {
        Write-Host "qemu-img generated VHDX file is not sparse, continuing..."
    }
}


$MemoryBytes = Convert-ToBytes $Memory

$regPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
try {
    $kitsRoot = Get-ItemProperty -Path $regPath -Name "KitsRoot10" -ErrorAction Stop
    $oscdimgPath = Join-Path $kitsRoot.KitsRoot10 "Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"

    if (-not (Test-Path $oscdimgPath)) {
        throw "Oscdimg.exe not found at expected path: $oscdimgPath"
    }
} catch {
    throw "Could not locate Oscdimg.exe. Is the Windows ADK installed?"
}

$qemuImgPath = Find-QemuImg

$vmPath = (Get-VMHost).VirtualMachinePath
$vmStoragePath = (Get-VMHost).VirtualHardDiskPath
$vmDiskPath = "$($VMStoragePath)\$($VMName).vhdx"
$metaDataIso = "D:\ISO\$($VMName)_metadata.iso"
$tempPath = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()

$existingVm = Get-VM -Name $VMName -ErrorAction SilentlyContinue

if ($existingVm) {
    $response = Read-Host "VM '$VMName' exists. Do you want to delete it? (Y/N)"
    if ($response -match '^[Yy]$') {
        try {
            Stop-VM -Name $VMName -Force -TurnOff
            Remove-VM -Name $VMName -Force
            Write-Host "VM '$VMName' deleted successfully."
        } catch {
            throw "Failed to delete VM: $_"
        }
    } else {
        throw "Script exited due to the presence of an existing VM named $VMName"
    }
} else {
    Write-Host "VM '$vmName' does not exist."
}

if (Test-Path -Path $vmDiskPath) {
    $response = Read-Host "A virtual disk already exists at '$vmDiskPath'. Do you want to delete it? (Y/N)"
    if ($response -match '^[Yy]$') {
        try {
            Remove-Item -Path $vmDiskPath -Force
            Write-Host "existing virtual disk deleted successfully."
        } catch {
            throw "Failed to delete existing virtual disk: $_"
        }
    } else {
        throw "Script exited due to presence of an existing disk image with matching filename $vmDiskPath"
    }
}

if (Test-Path -Path $metaDataIso) {
    $response = Read-Host "A cloud-init ISO already exists at '$metaDataIso'. Do you want to delete it? (Y/N)"
    if ($response -match '^[Yy]$') {
        try {
            Remove-Item -Path $metaDataIso -Force
            Write-Host "existing cloud-init ISO deleted successfully."
        } catch {
            throw "Failed to delete existing cloud-init ISO: $_"
        }
    } else {
        throw "Script exited due to presence of an existing cloud-init ISO with matching filename $metaDataIso"
    }
}

Write-Host "Converting Qcow image to VHDX"
& $qemuImgPath convert -f qcow2 -O vhdx "$BaseQcowPath" $vmDiskPath
Remove-SparseAttribute $vmDiskPath
Resize-VHD -Path $vmDiskPath -SizeBytes 60GB

Write-Host "Creating cloud-init ISO"
$metadata = @"
instance-id: $($VMName)
local-hostname: $($VMName)
"@

$userdata = @"
#cloud-config
write_files:
- path: /etc/128T-hardware-bootstrapper/post-bootstrap
  permissions: 0755
  content: |
    #!/bin/bash
    \rm /etc/sysconfig/network-scripts/ifcfg-br-128*
    sed -i '/BRIDGE=br-128/d' /etc/sysconfig/network-scripts/ifcfg-*
- path: /root/prepare_hyperv_ssr_onboarding.py
  permissions: 0755
  content: |
    #!/bin/env python3
    import json
    import logging
    import os
    import pathlib
    import sys


    ONBOARDING_CONFIG_FILE="/etc/128T-hardware-bootstrapper/onboarding-config.json"
    SYSFS_NET_PATH = pathlib.Path('/sys/class/net')
    LOGFILE="/root/hypervSsrOnboarding.log"


    logger = logging.getLogger(__name__)


    def string2bool(string):
        return string.lower() == "true"


    def _get_port_type(index, num_ports):
        # Stealing the logic directly from bootstrapper
        if num_ports < 4:
            return "LAN" if index != 0 else "WAN"

        if index == 0:
            return "WAN"
        if index == num_ports - 2:
            return "HASync"
        if index == num_ports - 1:
            return "HAFabric"
        return "LAN"    


    def get_orderedIfList():
        ifMap = {}
        for ifPath in SYSFS_NET_PATH.glob('*'):
            devicePath = ifPath / 'device'
            if devicePath.is_symlink():
                vmbus_uuid = devicePath.resolve().stem
                mac = (ifPath / 'address').read_text().strip()
                ifMap[mac] = vmbus_uuid
        sortedIfMap = {key: ifMap[key] for key in sorted(ifMap)}
        return sortedIfMap.values()


    def get_static_config(env):
        logger.info("Checking for ge-0-0 static config in environment")
        static_config = {}

        if env.get('STATIC_ADDRESS'):
            static_config['address'] = env['STATIC_ADDRESS']

        if env.get('STATIC_GATEWAY'):
            static_config['gateway'] = env['STATIC_GATEWAY']

        if env.get('VLAN'):
            try:
                vlanNo = int(env['VLAN'])
                if vlanNo > 0:
                    static_config['vlan'] = vlanNo
            except ValueError as err:
                logger.error(f"Invalid vlan value configured: {err}")

        return static_config


    def create_device_map(
        sortedIfList,
        static_config,
    ):
        num_ports = len(sortedIfList)
        ifIndex = 0
        ethernet = []
        for vmbusId in sortedIfList:
            interface = {
                "type": _get_port_type(ifIndex, num_ports),
                "name": f"ge-0-{ifIndex}",
                "pciAddress": None,
                "vmbusId": vmbusId,
            }

            if ifIndex == 0 and static_config:
                interface.update(static_config)

            ethernet.append(interface)
            ifIndex += 1

        return {
            "ethernet": ethernet
        }  


    def onboard_mist_managed(env):
        logger.info("Creating onboarding-config for Mist-managed router")
        onboarding_config = {
            "mode": "mist-managed",
        }

        onboarding_config['registration-code'] = env.get('REGISTRATION_CODE')
        onboarding_config['name'] = env.get('ROUTER_NAME')

        return onboarding_config


    def onboard_conductor_managed(env):
        logger.info("Creating onboarding-config for Conductor-managed router")
        onboarding_config = {
            "mode": "conductor-managed",
        }

        try:
            conductors = env.get('CONDUCTOR_ADDRESS').split(',')
        except AttributeError:
            logger.error("No conductor addresses defined, cannot continue")
            sys.exit(1)

        onboarding_config['conductor-hosts'] = conductors
        onboarding_config['name'] = env.get('ROUTER_NAME')

        return onboarding_config


    def onboard_conductor(env):
        logger.info("Creating onboarding-config for Conductor")
        onboarding_config = {
            "mode": "conductor",
        }

        onboarding_config['name'] = env.get('ROUTER_NAME')
        onboarding_config['node-name'] = env.get('NODE_NAME')

        artifactoryUser = env.get('ARTIFACTORY_USER')
        artifactoryPassword = env.get('ARTIFACTORY_PASSWORD')
        if artifactoryUser and artifactoryPassword:
            onboarding_config['artifactory-user'] = artifactoryUser
            onboarding_config['artifactory-password'] = artifactoryPassword

        # Maybe do more validation here but for now let the bootstrapper do that

        nodeIp = env.get('NODE_IP')
        if nodeIp:
            onboarding_config['node-ip'] = nodeIp

        nodeGateway = env.get('NODE_GATEWAY')
        if nodeGateway:
            onboarding_config['node-gateway'] = nodeGateway

        interfaceName = env.get('MGMT_IF_NAME')
        if interfaceName:
            onboarding_config['interface-name'] = interfaceName

        dnsServers = env.get('DNS_SERVERS')
        if dnsServers:
            onboarding_config['dns-servers'] = dnsServers.split(',')

        clustered = env.get('CLUSTERED')
        if clustered and string2bool(clustered):
            onboarding_config['clustered'] = True

        haIp = env.get('HA_IP')
        if haIp:
            onboarding_config['ha-ip'] = haIp

        haInterface = env.get('HA_IFNAME')
        if haInterface:
            onboarding_config['ha-interface-name'] = haInterface

        haPeerName = env.get('HA_PEER_NAME')
        if haPeerName:
            onboarding_config['ha-peer-name'] = haPeerName

        learnFromHaPeer = env.get('LEARN_FROM_HA_PEER')
        if learnFromHaPeer and string2bool(learnFromHaPeer):
            onboarding_config['learn-from-ha-peer'] = True

        haPeerUsername = env.get('HA_PEER_USERNAME')
        if haPeerUsername:
            onboarding_config['ha-peer-username'] = haPeerUsername

        haPeerPassword = env.get('HA_PEER_PASSWORD')
        if haPeerPassword:
            onboarding_config['unsafe-ha-peer-password'] = haPeerPassword

        return onboarding_config


    def main():
        logger.info("Loading Environment Variables")
        env = os.environ

        logger.info("Loaded environment data, looking for onboarding mode...")
        onboardingMode = env['ONBOARDING_MODE']

        if onboardingMode == "mist-managed":
            onboarding_config = onboard_mist_managed(env)
        elif onboardingMode == "conductor-managed":
            onboarding_config = onboard_conductor_managed(env)
        elif onboardingMode == "conductor":
            onboarding_config = onboard_conductor(env)
        else:
            logger.error(f"Unrecognized onboarding-mode: {onboardingMode}")
            sys.exit(1)

        static_config = get_static_config(env)
        device_map = create_device_map(get_orderedIfList(), static_config)
        onboarding_config["devicemap"] = device_map

        logger.info(f"Writing onboarding config: {onboarding_config}")
        with open(ONBOARDING_CONFIG_FILE, 'w') as fh:
            json.dump(onboarding_config, fh)

        logger.info("Finished successfully")


    if __name__ == '__main__':
        logging.basicConfig(
            filename=LOGFILE,
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        try:
            main()
        except Exception as e:
            logger.exception("Exception encountered:")
            logger.info(f"full environment: {os.environ}")
runcmd:
- env
- export ONBOARDING_MODE=$($OnboardingMode)
- export ROUTER_NAME=$($RouterName)
- export REGISTRATION_CODE=$($RegistrationCode)
- export CONDUCTOR_ADDRESS=$($ConductorAddress -join ',')
- export NODE_NAME=$($NodeName)
- export ARTIFACTORY_USER=$($ArtifactoryUser)
- export ARTIFACTORY_PASSWORD=$($ArtifactoryPassword)
- export MGMT_IF_NAME=$($ManagementInterfaceName)
- export NODE_IP=$($NodeIp)
- export NODE_GATEWAY=$($NodeGateway)
- export DNS_SERVERS=$($DnsServers -join ',')
- export CLUSTERED=$($clustered.ToString().ToLower())
- export HA_IP=$($HaIp)
- export HA_IFNAME=$($HaInterfaceName)
- export HA_PEER_NAME=$($HaPeerName)
- export HA_PEER_IP=$($HaPeerIp)
- export LEARN_FROM_HA_PEER=$($LearnFromHaPeer.ToString().ToLower())
- export HA_PEER_USERNAME=$($HaPeerUsername)
- export HA_PEER_PASSWORD=$($HaPeerPassword)
- export STATIC_ADDRESS=$($StaticAddress)
- export STATIC_GATEWAY=$($StaticGateway)
- export VLAN=$($Vlan)
- /root/prepare_hyperv_ssr_onboarding.py
"@

md -Path $tempPath\cloud-init
# Output meta and user data to files
sc "$($tempPath)\cloud-init\meta-data" ([byte[]][char[]] "$metadata") -Encoding Byte
sc "$($tempPath)\cloud-init\user-data" ([byte[]][char[]] "$userdata") -Encoding Byte


# Create meta data ISO image
& $oscdimgPath "$($tempPath)\cloud-init" $metaDataIso -j2 -lcidata

# Clean up temp directory
rd -Path $tempPath -Recurse -Force

Write-Host "Creating SSR VM"
$first_nic, $remaining_nics = $nics
New-VM -Name $VMName `
    -MemoryStartupBytes $MemoryBytes `
    -VHDPath $vmDiskPath `
    -Generation 2 `
    -BootDevice VHD `
    -Switch $first_nic `
    -Path $vmPath 

Set-VMProcessor -VMName $VMName -Count $NumCores

# Not currently supported for SSR
Set-VMFirmware -VMName $VMName -EnableSecureBoot Off

foreach ($nic in $remaining_nics) {
    Add-VMNetworkAdapter -VMName $VMName -SwitchName $nic
}

Add-VMDvdDrive -VMName $VMName
Set-VMDvdDrive -VMName $VMName -Path $metaDataIso
Start-VM $VMName
