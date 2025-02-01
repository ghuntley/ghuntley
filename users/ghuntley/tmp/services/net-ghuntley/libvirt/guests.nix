# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{
  system.activationScripts."libvirt-guests".text = ''
    rm -f "/var/lib/libvirt/qemu/win11.xml" 1>/dev/null 2>&1 || true
    ln -s "/depot/services/net-ghuntley/libvirt/win11.xml" "/var/lib/libvirt/qemu/win11.xml"
  '';
}
