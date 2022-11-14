# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# Utility for invoking slappasswd with the correct options for
# creating an ARGON2 password hash.
{ pkgs, ... }:

let
  script = pkgs.writeShellScriptBin "hash-password" ''
    ${pkgs.openldap}/bin/slappasswd -o module-load=argon2 -h '{ARGON2}' "$@"
  '';
in
script.overrideAttrs (old: {
  doCheck = true;
  checkPhase = ''
    ${pkgs.stdenv.shell} $out/bin/hash-password -s example-password > /dev/null
  '';
})
