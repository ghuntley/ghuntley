# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  boot.kernel.sysctl = {
    "fs.file-max" = 100000;
    "fs.inotify.max_user_instances" = 8192;
    "fs.inotify.max_user_watches" = 524288;
    "kern.maxproc" = 65536;
    "kernel.pid_max" = 4194303; # 64-bit max
    "net.ipv4.tcp_congestion_control" = "bbr";
  };

}
