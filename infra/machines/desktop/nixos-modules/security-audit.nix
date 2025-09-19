# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ config, lib, pkgs, ... }: {
  # Enable auditd daemon for proper log file generation
  security.auditd.enable = true;
  
  # Configure audit log rotation
  services.logrotate = {
    enable = true;
    settings.audit = {
      files = "/var/log/audit/*.log";
      frequency = "daily";
      rotate = 7;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "640 root root";
      postrotate = ''
        /bin/kill -HUP `cat /var/run/auditd.pid 2> /dev/null` 2> /dev/null || true
      '';
    };
  };
  
  security.audit = {
    enable = true;
    failureMode = "printk";
    backlogLimit = 65536;
    rateLimit = 0;
    rules = [
      # Monitor execve syscalls for process execution tracking
      "-a exit,always -F arch=b64 -S execve"
      "-a exit,always -F arch=b32 -S execve"
      
      # Monitor file access on sensitive directories (only existing paths)
      "-w /etc/passwd -p wa -k identity"
      "-w /etc/shadow -p wa -k identity"
      "-w /etc/group -p wa -k identity"
      "-w /etc/sudoers -p wa -k sudo_changes"
      "-w /etc/ssh/sshd_config -p wa -k sshd_config"
      
      # Monitor secrets (only if directories exist)
      "-w /run/secrets -p rwxa -k sops_secrets"
      "-w /run/secrets.d -p rwxa -k sops_secrets"
      
      # Monitor network configuration changes
      "-a always,exit -F arch=b64 -S sethostname -S setdomainname -k network"
      "-a always,exit -F arch=b32 -S sethostname -S setdomainname -k network"
      
      # Monitor time changes
      "-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change"
      "-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change"
      "-a always,exit -F arch=b64 -S clock_settime -k time-change"
      "-a always,exit -F arch=b32 -S clock_settime -k time-change"
      
      # Monitor SSH keys
      "-w /root/.ssh -p rwxa -k ssh_keys"
      "-w /home/ghuntley/.ssh -p rwxa -k ssh_keys"
                  
      # Monitor network and DNS configuration
      "-w /etc/hosts -p wa -k network_config"
      "-w /etc/resolv.conf -p wa -k network_config"
      "-w /etc/nsswitch.conf -p wa -k network_config"
      
      # Monitor certificate and trust stores (existing paths)
      "-w /etc/ssl/certs -p wa -k certificates"
      
      # Advanced syscall monitoring
      "-a always,exit -F arch=b64 -S ptrace -k injection"
      "-a always,exit -F arch=b32 -S ptrace -k injection"
      "-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -k file_permissions"
      "-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -k file_permissions"
      "-a always,exit -F arch=b64 -S chown -S fchown -S lchown -S fchownat -k file_ownership"
      "-a always,exit -F arch=b32 -S chown -S fchown -S lchown -S fchownat -k file_ownership"
      
      # Monitor kernel module loading/unloading
      "-a always,exit -F arch=b64 -S init_module -S delete_module -k modules"
      "-a always,exit -F arch=b32 -S init_module -S delete_module -k modules"
      
      # Monitor mount operations
      "-a always,exit -F arch=b64 -S mount -S umount2 -k mount"
      "-a always,exit -F arch=b32 -S mount -S umount -S umount2 -k mount"
    ];
  };
}