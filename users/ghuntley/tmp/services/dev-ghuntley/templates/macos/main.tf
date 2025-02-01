# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.8.3"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.2"
    }
  }
}

provider "docker" {
#  host = "tcp://100.94.74.63:2375"
}

data "coder_workspace" "me" {
}


resource "coder_agent" "main" {
  arch                   = "amd64"
  os                     = "darwin"
  login_before_ready     = false
  startup_script_timeout = 180
  startup_script         = <<-EOT
    set -e

    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.8.3
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &

  EOT
}


resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  dns   = ["1.1.1.1"]
  devices {
    host_path = "/dev/kvm"
  }
  network_mode = "host"
  env   = ["OSX_COMMANDS=/bin/bash -c 'export CODER_AGENT_TOKEN=${coder_agent.main.token} && ${coder_agent.main.init_script}'", "TERMS_OF_USE=i_agree", "EXTRA=-display none -vnc 0.0.0.0:5900,password=off"]
  image = "sickcodes/docker-osx:auto"
  hostname = data.coder_workspace.me.name
  name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"

  # host {
  #   host = "host.docker.internal"
  #   ip   = "host-gateway"
  # }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace.me.owner
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace.me.owner_id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}


resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  url          = "http://localhost:13337/?folder=/"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}
