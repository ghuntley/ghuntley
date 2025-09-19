# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{
  description = "NixOS machine configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-vscode-server, sops-nix, home-manager }:
    let
      toolsOverlay = import ./tools/pkgs;
      mkSystem = modules: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = modules ++ [
          ({ config, pkgs, ... }: {
            nixpkgs.overlays = [ toolsOverlay ];
          })
        ];
      };
    in
    {
      nixosConfigurations = {
        hammer = mkSystem [
          ./infra/machines/desktop/hammer.nix
          nixos-vscode-server.nixosModules.default
          sops-nix.nixosModules.sops
        ];
      };

      homeConfigurations = {
        ghuntley = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux.extend toolsOverlay;
          modules = [ ./users/ghuntley/home/machines/hammer.nix ];
        };
      };

      packages.x86_64-linux = 
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux.extend toolsOverlay;
        in
        {
          inherit (pkgs) license;
        };
    };
}