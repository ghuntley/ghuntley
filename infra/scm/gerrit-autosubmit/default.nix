# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

{ depot, pkgs, ... }:

depot.third_party.naersk.buildPackage {
  src = ./.;
  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.openssl ];
}
