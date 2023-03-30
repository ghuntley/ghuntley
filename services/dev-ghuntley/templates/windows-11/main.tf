# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.6.17"
    }
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.6.2"
    }
  }
}

resource "libvirt_cloudinit_disk" "init" {
  name           = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}.init.iso"
  meta_data      = coder_agent.main.token
  network_config  = coder_agent.main.init_script

  pool           = libvirt_pool.coder_pool.name
}

# instance the provider
provider "libvirt" {
  uri = "qemu:///system"
}

data "coder_workspace" "me" {
}

resource "libvirt_pool" "coder_pool" {
  name = "coder"
  type = "dir"
  path = "/var/lib/libvirt/images/coder"
}

# We fetch the latest ubuntu release image from their mirrors
resource "libvirt_volume" "qcow2" {
  name   = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}.qcow2"
  pool   = libvirt_pool.coder_pool.name
  source = "/var/lib/libvirt/images/win11-2023-03-25.qcow2"
  format = "qcow2"
}

data "coder_parameter" "admin_password" {
  name = "Administrator password for logging in via RDP"
  description = "Must meet Windows password complexity requirements: https://docs.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/password-must-meet-complexity-requirements#reference"
  default = "Hunter2!Hunter2"
  mutable = true
}


# Create the machine
resource "libvirt_domain" "domain-coder" {
  name   = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
  memory = "8096"

  cpu {
    mode = "host-passthrough"
  }

  firmware = "/run/libvirt/nix-ovmf/OVMF_CODE.fd"
  nvram {
    file = "/var/lib/libvirt/qemu/nvram/win11_VARS.fd"
  }

  network_interface {
    network_name = "default"
  }

  cloudinit = libvirt_cloudinit_disk.init.id

  disk {
    volume_id = libvirt_volume.qcow2.id
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "windows"

  login_before_ready = false

  startup_script = <<EOF
    # Set admin password and enable admin user (must be in this order)
    Get-LocalUser -Name "Administrator" | Set-LocalUser -Password (ConvertTo-SecureString -AsPlainText "${data.coder_parameter.admin_password.value}" -Force)
    Get-LocalUser -Name "Administrator" | Enable-LocalUser

    # Enable RDP
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0

    # Enable RDP through Windows Firewall
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    choco feature enable -n=allowGlobalConfirmation

    #--- Apps ---
    choco install -y 7zip
    choco install -y 7zip.commandline
    #choco install -y ack
    #choco install -y curl
    #choco install -y fiddler
    #choco install -y filezilla
    #choco install -y paint.net
    choco install -y sudo

    #--- Browsers ---
    choco install -y firefox
    #choco install -y firefox-dev
    choco install -y googlechrome
    #choco install -y googlechrome.canary

    #--- Sysadmin ---
    #choco install -y putty
    #choco install -y sysinternals
    #choco install -y windirstat
    #choco install -y winscp

    #--- Development ---
    #choco install -y dotpeek
    #choco install -y linqpad5

    #choco install -y java.jdk
    #choco install -y javaruntime

    #choco install -y visualstudiocode-insiders
    choco install -y vscode

    choco install -y microsoft-windows-terminal

    #Install-Module posh-git -Scope CurrentUser -Force -SkipPublisherCheck
    #Install-Module oh-my-posh -Scope CurrentUser -Force -SkipPublisherCheck
    #Install-Module -Name PSReadLine -Scope CurrentUser -Force -SkipPublisherCheck

    #echo "Import-Module posh-git" > $PROFILE
    #echo "Import-Module oh-my-posh" >> $PROFILE
    #echo "Set-Theme Paradox" >> $PROFILE

EOF

}
