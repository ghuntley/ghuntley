# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  boot.kernel.sysctl = {
    "net.ipv4.tcp_congestion_control" = "bbr";
    "fs.file-max" = 100000;
    "fs.inotify.max_user_watches" = 524288;
  };

}
