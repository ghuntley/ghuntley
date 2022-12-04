# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# Helper functions for instantiating depot-compatible NixOS machines.
{ depot, lib, pkgs, ... }@args:

let inherit (lib) findFirst isAttrs;
in
rec {
  # This provides our standard set of arguments to all NixOS modules.
  baseModule = { ... }: {
    # Ensure that pkgs == third_party.nix
    nixpkgs.pkgs = depot.third_party.nixpkgs;
    nix.nixPath =
      let
        # Due to nixpkgsBisectPath, pkgs.path is not always in the nix store
        nixpkgsStorePath =
          if lib.hasPrefix builtins.storeDir (toString pkgs.path)
          then builtins.storePath pkgs.path # nixpkgs is already in the store
          else pkgs.path; # we need to dump nixpkgs to the store either way
      in
      [
        ("nixos=" + nixpkgsStorePath)
        ("nixpkgs=" + nixpkgsStorePath)
      ];
  };

  nixosFor = configuration: (depot.third_party.nixos {
    configuration = { ... }: {
      imports = [
        baseModule
        configuration
      ];
    };

    specialArgs = {
      inherit (args) depot;
    };
  });

  findSystem = hostname:
    (findFirst
      (system: system.config.networking.hostName == hostname)
      (throw "${hostname} is not a known NixOS host")
      (map nixosFor depot.ops.machines.all-systems));

  rebuild-system = rebuildSystemWith depot.path;

  rebuildSystemWith = depotPath: pkgs.writeShellScriptBin "rebuild-system" ''
    set -ue
    if [[ $EUID -ne 0 ]]; then
      echo "Oh no! Only root is allowed to rebuild the system!" >&2
      exit 1
    fi

    echo "Rebuilding NixOS for $HOSTNAME"
    system=$(${pkgs.nix}/bin/nix-build -E "((import ${depotPath} {}).ops.nixos.findSystem \"$HOSTNAME\").system" --no-out-link --show-trace)

    ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/system --set $system
    $system/bin/switch-to-configuration switch
  '';

  # Systems that should be built in CI
  prd-bne-ca-System = (nixosFor depot.ops.machines.prd-bne-ca).system;
  prd-bne-cache-System = (nixosFor depot.ops.machines.prd-bne-cache).system;
  prd-bne-code-System = (nixosFor depot.ops.machines.prd-bne-code).system;
  prd-bne-proxy-System = (nixosFor depot.ops.machines.prd-bne-proxy).system;
  prd-bne-smtp-System = (nixosFor depot.ops.machines.prd-bne-smtp).system;
  prd-bne-time-System = (nixosFor depot.ops.machines.prd-bne-time).system;
  prd-bne-ts-System = (nixosFor depot.ops.machines.prd-bne-ts).system;
  prd-fsn1-dc11-1880953-System = (nixosFor depot.ops.machines.prd-fsn1-dc11-1880953).system;
  meta.ci.targets = [
    "prd-bne-ca-System"
    "prd-bne-cache-System"
    "prd-bne-code-System"
    "prd-bne-proxy-System"
    "prd-bne-smtp-System"
    "prd-bne-time-System"
    "prd-bne-ts-System"
    "prd-fsn1-dc11-1880953-System"
  ];
}
