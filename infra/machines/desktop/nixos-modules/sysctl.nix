# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }:

{
  # Kernel system control parameters for performance and resource management
  boot.kernel.sysctl = {
    "fs.file-max" = 100000;
    "fs.inotify.max_user_instances" = 8192;
    "fs.inotify.max_user_watches" = 524288;
    "kern.maxproc" = 65536;
    "kernel.pid_max" = 4194303; # 64-bit max
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.rmem_max" = 4194304;
    "net.core.wmem_max" = 1048576;
  };
}