# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

# Helper functions for instantiating depot-compatible NixOS machines.
{ depot, lib, pkgs, ... }@args:

let inherit (lib) findFirst isAttrs hasAttr;
in rec {
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

  # List of pre-processed configurations to check in addition to regular NixOS modules
  preProcessedSystems = [
    {
      # Add an attribute to identify this as a pre-processed system
      isPreProcessed = true;

      # The host name to match against
      hostName = "com-ghuntley-media";

      # Path to the pre-processed configuration
      path = depot.services.ghuntley.machines.com-ghuntley-media;

      # The attribute to use for the system
      systemAttr = "vm";
    }
    # Add more pre-processed systems here as needed
  ];

  findSystem = hostname:
    let
      # First check if there's a direct match in pre-processed systems
      preProcessedMatch = findFirst
        (system: system.hostName == hostname)
        null
        preProcessedSystems;

      # If we found a pre-processed match, return the appropriate system
      preProcessedResult =
        if preProcessedMatch != null
        then
          if hasAttr preProcessedMatch.systemAttr preProcessedMatch.path
          then preProcessedMatch.path.${preProcessedMatch.systemAttr}
          else throw "Pre-processed system ${hostname} does not have attribute ${preProcessedMatch.systemAttr}"
        else null;

      # Traditional search through all-systems
      traditionalResult =
        findFirst
          (system: system.config.networking.hostName == hostname)
          null
          (map nixosFor depot.infra.machines.all-systems);
    in
    # Return the first match, or throw an error if neither approach found a match
    if preProcessedResult != null
    then {
      # Create a compatible system structure
      system = preProcessedResult;
      # Add an indicator this is a pre-processed system
      isPreProcessed = true;
    }
    else if traditionalResult != null
    then traditionalResult
    else throw "${hostname} is not a known NixOS host";

  rebuild-system = rebuildSystemWith (
    # HACK: use the string of the original source to avoid copying the whole
    # depot into the store just for this
    builtins.toString depot.path.origSrc);

  rebuildSystemWith = depotPath: pkgs.writeShellScriptBin "rebuild-system" ''
    set -ue
    if [[ $EUID -ne 0 ]]; then
      echo "Oh no! Only root is allowed to rebuild the system!" >&2
      exit 1
    fi

    echo "Rebuilding NixOS for $HOSTNAME"
    system=$(${pkgs.nix}/bin/nix-build -E "
      let
        depot = import ${depotPath} {};
        result = depot.infra.nixos.findSystem \"$HOSTNAME\";
      in
        if result ? isPreProcessed && result.isPreProcessed
        then result.system
        else result.system
    " --no-out-link --show-trace)

    ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/system --set $system
    $system/bin/switch-to-configuration switch
  '';

  # Systems that should be built in CI
  prybarSystem = (nixosFor depot.infra.machines.prybar).system;
  crowbarSystem = (nixosFor depot.infra.machines.crowbar).system;
  mediaSystem = depot.services.ghuntley.machines.com-ghuntley-media.vm;

  meta.ci.targets = [
    "prybarSystem"
    "crowbarSystem"
    "mediaSystem"
  ];
}
