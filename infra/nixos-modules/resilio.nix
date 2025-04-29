# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# NixOS module for Resilio Sync file synchronization service
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.depot.resilio;

  # Define a shared folder type for the module
  sharedFolderOpts = types.submodule {
    options = {
      secret = mkOption {
        type = types.str;
        description = "Sync secret key for the shared folder";
      };

      directory = mkOption {
        type = types.str;
        description = "Directory path for the shared folder";
      };

      knownHosts = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of known hosts for the shared folder";
      };

      useRelayServer = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to use relay servers";
      };

      useTracker = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to use tracker servers";
      };

      useDHT = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to use DHT";
      };

      searchLAN = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to search for peers in LAN";
      };

      useSyncTrash = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to use sync trash";
      };
    };
  };

  # Generate tmpfiles.rules for shared folders
  folderRules = map
    (folder: "d ${folder.directory} 0775 rslsync rslsync -")
    cfg.sharedFolders;

in
{
  options.services.depot.resilio = {
    enable = mkEnableOption "Resilio Sync service";

    enableWebUI = mkOption {
      type = types.bool;
      default = false;
      description = "Enable the Resilio Sync Web UI";
    };

    checkForUpdates = mkOption {
      type = types.bool;
      default = false;
      description = "Check for updates automatically";
    };

    downloadLimit = mkOption {
      type = types.int;
      default = 0;
      description = "Download speed limit in KB/s (0 for unlimited)";
    };

    uploadLimit = mkOption {
      type = types.int;
      default = 0;
      description = "Upload speed limit in KB/s (0 for unlimited)";
    };

    deviceName = mkOption {
      type = types.str;
      description = "Device name to display to other Resilio Sync users";
      example = "NixOS Server";
    };

    listeningPort = mkOption {
      type = types.int;
      default = 4444;
      description = "Port to listen for connections";
    };

    sharedFolders = mkOption {
      type = types.listOf sharedFolderOpts;
      default = [ ];
      description = "List of shared folder configurations";
    };
  };

  config = mkIf cfg.enable {
    # Configure the built-in NixOS resilio service
    services.resilio = {
      enable = true;
      enableWebUI = cfg.enableWebUI;
      checkForUpdates = cfg.checkForUpdates;
      downloadLimit = cfg.downloadLimit;
      uploadLimit = cfg.uploadLimit;
      deviceName = cfg.deviceName;
      listeningPort = cfg.listeningPort;

      # Pass through the shared folders configuration
      sharedFolders = cfg.sharedFolders;
    };

    # Create directories for all shared folders - properly append to existing rules
    systemd.tmpfiles.rules = folderRules;

    # Add resilio-sync to system packages
    environment.systemPackages = [ pkgs.resilio-sync ];

    # Open firewall port for Resilio Sync
    networking.firewall.allowedTCPPorts = [ cfg.listeningPort ];

    # Add rslsync user to ghuntley's group to allow access to ghuntley's files
    users.users.rslsync.extraGroups = [ "ghuntley" ];

    # Set umask for the resilio service to ensure created files have group read/write permissions
    systemd.services.resilio.serviceConfig = {
      UMask = "0002"; # Ensures files created by rslsync have group read/write permissions
    };
  };
}
