# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

FROM gitpod/workspace-full

# Install Nix
CMD /bin/bash -l
USER gitpod
ENV USER gitpod
WORKDIR /home/gitpod

# Install cachix
RUN . /home/gitpod/.nix-profile/etc/profile.d/nix.sh \
  && nix-env -iA cachix -f https://cachix.org/api/v1/install

# Use cachix
RUN . /home/gitpod/.nix-profile/etc/profile.d/nix.sh \
  && cachix use cachix \
  && cachix use niv

# Install direnv
RUN . /home/gitpod/.nix-profile/etc/profile.d/nix.sh \
  && nix-env -i direnv \
  && direnv hook bash >> /home/gitpod/.bashrc \
  && direnv hook zsh >> /home/gitpod/.zshrc

# Install lorri
RUN . /home/gitpod/.nix-profile/etc/profile.d/nix.sh \
  && nix-env -i lorri
