# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

FROM alpine

# Add a user `ghuntley` so that you're not developing as the `root` user
RUN adduser ghuntley -G wheel; echo 'ghuntley:Hunter2' | chpasswd \
	&& mkdir -p /etc/sudoers.d \
	&& echo "ghuntley ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ghuntley \
    && chmod 0440 /etc/sudoers.d/ghuntley

RUN apk add asciinema \
			bash \
			bats \
			btop \
			curl \
			direnv \
			docker \
			git \
			lazygit \
      make \
			neovim \
			openssh \
			stow \
			sudo \
			tmux \
			unzip \
			zip \
			zsh

# Install starship
RUN curl -sS https://starship.rs/install.sh | sh -s -- --yes

# Adjust OpenSSH config
RUN echo "PermitUserEnvironment yes" >>/etc/ssh/sshd_config && \
	echo "X11Forwarding yes" >>/etc/ssh/sshd_config && \
	echo "X11UseLocalhost no" >>/etc/ssh/sshd_config

# Start SSH service
EXPOSE 22
CMD ["/usr/sbin/sshd","-D"]

# Run as
USER ghuntley
