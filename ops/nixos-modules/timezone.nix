# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ pkgs, config, lib, ... }: {

  time.timeZone = "UTC";

  environment.shellInit = ''
    export TZ='UTC'
  '';

}
