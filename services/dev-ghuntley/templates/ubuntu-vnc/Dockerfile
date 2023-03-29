# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

FROM fredblgr/ubuntu-novnc:20.04

# Add a user `ubuntu` so that you're not developing as the `root` user
RUN useradd ubuntu \
    --create-home \
    --shell=/bin/bash \
    --uid=1000 \
    --user-group && \
	mkdir -p /etc/sudoers.d && \
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >>/etc/sudoers.d/nopasswd && \
	groupadd docker && \
	usermod -aG docker ubuntu

# Install packages from apt repositories
ARG DEBIAN_FRONTEND="noninteractive"

# Update ubuntu
RUN apt-get update
RUN rm -rf /etc/ca-certificates.conf \
    && apt-get install --yes ca-certificates software-properties-common
RUN apt-get upgrade --yes

# Install Docker
RUN apt-get install --yes \
	  ca-certificates curl gnupg lsb-release software-properties-common && \
    mkdir -m 0755 -p /etc/apt/keyrings && \
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
  	apt-get update && apt-get install --yes docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && \
	# Delete package cache to avoid consuming space in layer
	apt-get clean

RUN apt-get update && apt-get install --yes \
	apt-transport-https \
	apt-utils \
	bash \
	bash-completion \
	bat \
	bats \
	bind9-dnsutils \
	build-essential \
	ca-certificates \
	cmake \
	crypto-policies \
	curl \
	fd-find \
	file \
	git \
	gnupg \
	graphviz \
	htop \
	httpie \
	inetutils-tools \
	iproute2 \
	iputils-ping \
	iputils-tracepath \
	jq \
	language-pack-en \
	less \
	lsb-release \
	man \
	meld \
	net-tools \
	openssh-server \
	openssl \
	pkg-config \
	python3 \
	python3-pip \
	rsync \
	shellcheck \
	strace \
	stow \
	sudo \
	tcptraceroute \
	termshark \
	tmux \
	traceroute \
	vim \
	wget \
	xauth \
	zip \
	ncdu \
	asciinema \
	zsh \
	neovim \
	fish \
	unzip \
	zstd && \
	# Delete package cache to avoid consuming space in layer
	apt-get clean && \
	# Configure FIPS-compliant policies
	update-crypto-policies --set FIPS

# Install starship
RUN curl -sS https://starship.rs/install.sh | sh -s -- --yes

# See https://github.com/cli/cli/issues/6175#issuecomment-1235984381 for proof
# the apt repository is unreliable
RUN curl -L https://github.com/cli/cli/releases/download/v2.25.0/gh_2.25.0_linux_amd64.deb -o gh.deb && \
	dpkg -i gh.deb

# Install Lazygit
# See https://github.com/jesseduffield/lazygit#ubuntu
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep '"tag_name":' |  sed -E 's/.*"v*([^"]+)".*/\1/') && \
	curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" && \
	tar xf lazygit.tar.gz -C /usr/local/bin lazygit

# Adjust OpenSSH config
RUN echo "PermitUserEnvironment yes" >>/etc/ssh/sshd_config && \
	echo "X11Forwarding yes" >>/etc/ssh/sshd_config && \
	echo "X11UseLocalhost no" >>/etc/ssh/sshd_config

# Install Nix
RUN addgroup --system nixbld \
  && adduser ubuntu nixbld \
  && for i in $(seq 1 30); do useradd -ms /bin/bash nixbld$i &&  adduser nixbld$i nixbld; done \
  && mkdir -m 0755 /nix && chown ubuntu /nix \
  && mkdir -p /etc/nix && echo 'sandbox = false' > /etc/nix/nix.conf

CMD /bin/bash -l
USER ubuntu
ENV USER ubuntu
WORKDIR /home/ubuntu

RUN USERNAME='ubuntu' touch .bash_profile \
 && curl https://nixos.org/releases/nix/nix-2.9.2/install | sh

RUN echo '. /home/ubuntu/.nix-profile/etc/profile.d/nix.sh' >> /home/ubuntu/.bashrc
RUN mkdir -p /home/ubuntu/.config/nixpkgs && echo '{ allowUnfree = true; }' >> /home/ubuntu/.config/nixpkgs/config.nix

# Install cachix
RUN . /home/ubuntu/.nix-profile/etc/profile.d/nix.sh \
  && nix-env -iA cachix -f https://cachix.org/api/v1/install \
  && cachix use cachix

# Install direnv
RUN . /home/ubuntu/.nix-profile/etc/profile.d/nix.sh \
  && nix-env -i direnv \
  && direnv hook bash >> /home/ubuntu/.bashrc

# Install devenv
RUN . /home/ubuntu/.nix-profile/etc/profile.d/nix.sh \
	nix-env -iA cachix -f https://cachix.org/api/v1/install && \
    cachix use devenv && \
    nix-env -if https://github.com/cachix/devenv/tarball/latest

# Start SSH service
EXPOSE 22
CMD ["/usr/sbin/sshd","-D"]

# Run as
USER root
