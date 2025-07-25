# Powershell SSR Hyper-V Install Script
Powershell script to automate SSR installation for Hyper-V environments

This tool is provided as community supported and is not maintained by Juniper Networks officially. Any issues can be reported through this github repository with no guarantee that a fix will be provided and no SLA for any fix timeframes.

## Requirements
1. A Microsoft Hyper-V server running Windows Server 2022

   This server must be running Intel x86_64 CPUs and have sufficient CPU cores / memory / disk space to support the SSR VM or VMs without oversubscribing resources.
   
2. ocsd.exe present on the system

   This is required for creating the cloud-init nocloud ISO that seeds the automation information to the VM on firt boot. This executable is included in the [Windows Assessment and Deployment Kit (ADK)](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install). When installing, you only need to select the option for deployment tools to provide the necessary components for this script. This script has been validated against ADK version `10.1.26100.2454`.

3. qemu-img.exe present on the system

   This is required for converting the officially provided Juiper SSR qcow image into Windows VHDX format. There are multiple ways to install the needed executables:
   * The official [QEMU website site](https://www.qemu.org/download/#windows) provides instructions for installing the full QEMU package for Windows. This requires installing and using the [MSYS2](https://www.msys2.org/) system for package management. This installs the full QEMU emulator which includes qemu-img.exe. This script has been validated against `mingw-w64-ucrt-x86_64-qemu 10.0.2-3`.
   * [This site](https://qemu.weilnetz.de/w64/) provides a standalone installer for QEMU for Windows if you wish to bypass MSYS2. This script has been validated against installer `qemu-w64-setup-20250723.exe`.
   * [Cloudbase.it](https://cloudbase.it/qemu-img-windows/) provides a compiled executable for just qemu-img.exe without the full QEMU package. If you choose this option, please extract the contents of the downloaded ZIP file into `D:\tools\` so that the script can find it. This script has been validated against `qemu-img-win-x64-2_3_0.zip`

4. SSR qcow

   This script makes use of automation features present only in IBU versions of SSR software starting with SSR6.3.0. These qcows can be found in the [official Juniper SSR image-based ISO repositiory](https://software.128technology.com/artifactory/list/generic-128t-install-images-release-local). You will need a valid software token to download the software. If you do not have a token, please contact members of your Juniper sales team. The qcow may be placed anywhere on the Windows host's filesystem, but the full path must be referenced when running the script.

5. This script

   The Powershell script located in this repository

## Script Parameters

# Required parameters
* *-VMName* - The name of the Virtual Machine as it will appear in the Hyper-V Manager console.
* *-BaseQcowPath* - The full path to the SSR qcow as mentioned in requirement #4.
* *-NumCores* - The number of virtual cores to allocate to the SSR VM. A minimum of 4 cores are required. Please consult your Juniper SE for sizing guidance.
* *-Memory* - The amount of memory to allocate to the SSR VM. This can be represented as an integer of bytes or a string representation such as 8GB. A minimum of 8GB is required. Please consult your Juniper SE for sizing guidance.
* *-Nics* - A comma seperated list representing the individual interfaces assigned to the VM. The name provided for each interface needs to correspond to a valid virtual switch already created on the host.
* *-OnboardingMode* - A string representing the initialization flow used with this device. The valid options are: `conductor`, `conductor-managed`, and `mist-managed`. These correspond to the [initialization flows documented here](https://docs.128technology.com/docs/initialize_u-iso_adv_workflow). Details on the additional options availalable for each method will also be provided below.
* *-RouterName* - When initializing a conductor, this will represent the name of the conductor (represented as a router object in the datamodel). When initializing a conductor-managed router, this will correspond to the asset ID seen when registering to the conductor. When initializing as mist-manged, this will correspond to the router-name object seen in the Mist inventory when the device registers to the cloud.

# Onboarding Mode mist-managed parameter
* *-RegistrationCode* - This is the registration code for the Mist org to which the device should register. This can be obtained from the inventory page of your Mist org.

# Onboarding Mode conductor-managed parameter
* *-ConductorAddress* - A comma seperated list representing one or two IP addresses corresponding to the reachable IP addresses for your conductor node(s)

# Interface configuration options for Onboarding Mode mist-managed or conductor-managed
The `128T-hardware-bootstrapper` will generate a basic configuration to allow the device to reach out to the Mist cloud or Conductor from where the device will receive a full configuration. By default, this configuration sets the first interface (`ge-0-0`) to receive an address via DHCP with no VLAN tag applied. These options can be used to provide a static IP address for `ge-0-0` and/or a VLAN tag. You should always plan to use this first interface (`ge-0-0`) as the interface that can provide connectivity to either the Mist cloud or Conductor for onboarding.
* *-StaticAddress* - The static IP address to apply to interface `ge-0-0` including prefix-length. This should be in the format `x.x.x.x/x`.
* *-StaticGateway* - The static address to use for the gateway on interface `ge-0-0` when providing a static address.
* *-Vlan* - A VLAN to apply to interface `ge-0-0` if a value other than the default VLAN 0 should be applied.

# Onboarding Mode conductor required parameter
* *-NodeName* - The name of the specific node for this conductor. This should be either `node0` or `node1`. The value `node1` should only be used for the second node within an HA conductor.

# Onboarding Mode conductor optional parameters
* *-ArtifactoryUser* and *-ArtifactoryPassword* - These values correspond to the token provided in your sales order from Juniper. These are required for obtaining software updates automatically over the Internet. This can be provided through configuration at a later time after the system is initialized. If you need your token information, please reach out to your Juniper sales team.
* *-ManagementInterfaceName* - The interface on the system to use for all management traffic including SSH/HTTPS/Router management traffic. This interface will receive a default route outbound. The interface should be in the format of `ge-0-x` where `x` is the index of the interface as they are added to the VM, starting with `0`.
* *-NodeIp* - The static IP address and prefix length to set on the management interface when using static address assignments. This should be in the format `x.x.x.x/x`. Do not use option *-StaticAddress* for conductor initialization.
* *-NodeGateway* - The static address to use for the gateway of the management interface. Do not use option *-StaticGateway* for conductor initialization.
* *-DnsServers* - A comma seperated list representing one or two IP addresses to use for DNS servers by the conductor.

# Additional options for Onboarding Mode Conductor when creating an HA Conductor
*Note:* This workflow has not been validated with these scripts and this should be considered experimental at this time. These options have been plumbed in at this time for future work. If you need to instantiate an HA Conductor, please work with your Juniper SE for assistance.
* *-clustered* - A boolean parameter representing whether the node is planned to be part of an HA Conductor installation.
* *-HaIp* - The IP address and prefix-length to use for the local HA interface. This should dbe in the format `x.x.x.x/x`.
* *-HaInterfaceName* - The interface on the system to use for HA traffic towards the other Conductor node. The interface should be in the format of `ge-0-x` where `x` is the index of the interface as they are added to the VM, starting with `0`. At this time, this must be a different interface than the *-ManagementInterfaceName*.
* *-HaPeerName* - The name of the OTHER node within the HA cluster. If this VM is instantiated with *-NodeName* of `node0` then this option should be set to `node1`. If this VM is instantiated with *-NodeName* of `node1` then this option should be set to `node0`.
* *-HaPeerIp* - The IP address of the OTHER node. This corresponds to the IP address used (or to be used) for option *-HaIp* on the other device. At the moment only an address within the subnet provided for *-HaIp* is supported.
* *-LearnFromHaPeer* - This option should be used on the second node that is instantiated of the HA conductor. It will attempt to connect across the HA connection and pull information from the first node. Consequently some time needs to pass to allow the first node to complete initialization and startup before the second node can be successfully initialized.
* *-HaPeerUsername* and *-HaPeerPassword* - These options are required to authenticate to the other node using the option above. The user here should be a Linux user with sudo priveleges (such as `t128`), NOT the `admin` user.

## Examples
1. Create an SSR VM with minimum requirements. Connect the interfaces to existing virtual switches in this order: ge-0-0 -> WAN1, ge-0-1 -> WAN, ge-0-2 -> LAN1, ge-0-3 -> LAN2. Initialize the device as a mist-managed router and have it register to the Mist org that supplied the registration code as router name `ssr01`. Use the default onboarding logic to attempt to DHCP on ge-0-0 which should provide access to the Internet and Mist cloud.

`.\NewSSR.ps1 -VMName ssr01 -BaseQcowPath D:\ISO\SSR-6.3.4-7.r2.el7.x86_64.ibu-v1.qcow2 -NumCores 4 -Memory 8GB -Nics WAN1,WAN2,LAN1,LAN2 -RouterName ssr01 -OnboardingMode mist-managed -RegistrationCode <redacted>`

2. Create an SSR VM with minimum requirements. Connect the interfaces to existing virtual switches in this order: ge-0-0 -> WAN1, ge-0-1 -> WAN, ge-0-2 -> LAN1, ge-0-3 -> LAN2. Initialize the device as a conductor-managed router and have it reach out to the conductor at address 10.10.10.10 as asset-id `ssr01`. Use the default onboarding logic to attempt to DHCP on ge-0-0 which should provide access to the Conductor.

`.\NewSSR.ps1 -VMName ssr01 -BaseQcowPath D:\ISO\SSR-6.3.4-7.r2.el7.x86_64.ibu-v1.qcow2 -NumCores 4 -Memory 8GB -Nics WAN1,WAN2,LAN1,LAN2 -RouterName ssr01 -OnboardingMode conductor-managed -ConductorAddress 10.10.10.10`

3. Create an SSR VM with minimum requirements. Connect the interfaces to existing virtual switches in this order: ge-0-0 -> WAN1, ge-0-1 -> WAN, ge-0-2 -> LAN1, ge-0-3 -> LAN2. Initialize the device as a conductor-managed router and have it reach out to the conductor at addresses 10.10.10.10 and 20.20.20.20 as asset-id `ssr01`. Set a static address of 192.168.128.100/24 and gateway 192.168.128.1 on ge-0-0 which should provide access to the Conductor.

`.\NewSSR.ps1 -VMName ssr01 -BaseQcowPath D:\ISO\SSR-6.3.4-7.r2.el7.x86_64.ibu-v1.qcow2 -NumCores 4 -Memory 8GB -Nics WAN1,WAN2,LAN1,LAN2 -RouterName ssr01 -OnboardingMode conductor-managed -ConductorAddress 10.10.10.10,20.20.20.20 -StaticAddress 192.168.128.100/24 -StaticGateway 192.168.128.1`

4. Create an SSR VM with minimum requirements. Connect a single interface to virtal switch MGMT. Initialize the device as a conductor named conductor. Set a static address of 192.168.128.100/24 and gateway 192.168.128.1 on the management-interface ge-0-0. Set the DNS servers to 10.10.10.10 and 20.20.20.20

`.\NewSSR.ps1 -VMName conductor -BaseQcowPath D:\ISO\SSR-6.3.4-7.r2.el7.x86_64.ibu-v1.qcow2 -NumCores 4 -Memory 8GB -Nics MGMT -RouterName conductor -OnboardingMode conductor -NodeName node0 -ManagementInterfaceName ge-0-0 -NodeIp 192.168.128.100/24 -NodeGateway 192.168.128.1 -DnsServers 10.10.10.10,20.20.20.20`


## Troubleshooting

Errors from running the Powershell script itself my indicate issues with different versions of the required utilities. This script has not been extensively tested with different versions of ADK and QEMU. When in doubt please try to use a version matching those provided in the requirements. Additional errors may indicate unexpected values provided in the script and the errors themselves should be read and investigated.

Issues with SSR initialization and onboarding should be investigated by checking these steps:
* Check the presence of the file `/etc/128T-hardware-bootstrapping/onboarding-config.json`. If this file is present then please examine the logs provided in `journalctl -u 128T-hardware-bootstrapper` and `/var/log/128T-hardware-bootstrapper`.
* If that file is not present, please check the logfile at `/root/hypervSsrOnboarding.log` for issues
* If the above logfile is not present, please check for the presence of the script `/root/prepare_hyperv_ssr_onboarding.py`
* If that script is not present, please check the following:
  * The contents of `/var/lib/cloud/instance/user-data.txt`
  * The contents of logfile `/var/log/cloud-init.log`
  * The output of `cloud-init -d init` and `cloud-init -d modules` looking for any errors

