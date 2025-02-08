// Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

group "default" {
  targets = ["build"]
}

target "build" {
  dockerfile = "./Dockerfile"
  output = ["type=docker"]
}
