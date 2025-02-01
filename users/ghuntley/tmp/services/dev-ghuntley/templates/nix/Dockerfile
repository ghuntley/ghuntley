# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

FROM nixos/nix:2.14.0

RUN nix-channel --update

# Install baseline packages
RUN nix-env -iA \
    nixpkgs.ack \
    nixpkgs.curl \
    nixpkgs.docker \
    nixpkgs.dos2unix \
    nixpkgs.git-lfs \
    nixpkgs.git \
    nixpkgs.gnupg \
    nixpkgs.gnused \
    nixpkgs.gnumake \
    nixpkgs.htop \
    nixpkgs.iftop \
    nixpkgs.inetutils \
    nixpkgs.iotop \
    nixpkgs.lazygit \
    nixpkgs.lsof \
    nixpkgs.nixpkgs-fmt \
    nixpkgs.p7zip \
    nixpkgs.rpl \
    nixpkgs.shadow \
    nixpkgs.sudo \
    nixpkgs.starship \
    nixpkgs.stow \
    nixpkgs.tmux \
    nixpkgs.tree \
    nixpkgs.unzip \
    nixpkgs.wget \
    nixpkgs.zip

# # Add a user `ghuntley` so that you're not developing as the `root` user
# RUN touch /etc/passwd && \
#     nix-shell -p '(import <nixpkgs> {}).shadow.override { }' --run 'useradd ghuntley' && \
# 	  mkdir -p /etc/sudoers.d && \
#     echo "ghuntley ALL=(ALL) NOPASSWD:ALL" >>/etc/sudoers.d/nopasswd

# Install cachix
RUN nix-env -iA cachix -f https://cachix.org/api/v1/install \
    && cachix use cachix

# Install direnv
RUN nix-env -i direnv \
    && direnv hook bash >> /root/.bashrc

# Install devenv
RUN nix-env -iA cachix -f https://cachix.org/api/v1/install && \
    cachix use devenv && \
    nix-env -if https://github.com/cachix/devenv/tarball/latest


# Run as
USER root
