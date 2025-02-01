# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# { config, lib, pkgs, ... }:

# {
#   nix = {
#     buildMachines = [{
#       hostName = "whitby.tvl.fyi";
#       sshUser = "aspen";
#       sshKey = "/root/.ssh/id_rsa";
#       system = "x86_64-linux";
#       maxJobs = 64;
#       supportedFeatures = [ "big-parallel" "kvm" "nixos-test" "benchmark" ];
#     }];

#     extraOptions = ''
#       builders-use-substitutes = true
#     '';

#     settings = {
#       substituters = [
#         "https://cache.nixos.org"
#       ];
#       trusted-substituters = [
#         "https://cache.nixos.org"
#         "ssh://nix-ssh@whitby.tvl.fyi"
#       ];
#     };
#   };

#   programs.ssh.knownHosts.whitby = {
#     extraHostNames = [ "whitby" "whitby.tvl.fyi" "49.12.129.211" ];
#     publicKeyFile = pkgs.writeText "whitby.pub" ''
#       ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILNh/w4BSKov0jdz3gKBc98tpoLta5bb87fQXWBhAl2I
#     '';
#   };
# }
