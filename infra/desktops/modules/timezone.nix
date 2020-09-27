# Copyright (c) 2020 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  time.timeZone = "Australia/Brisbane";

  environment.shellInit = ''
    export TZ='Australia/Brisbane'
  '';

}
