# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, ... }:

(with depot.infra.machines; [
  workbench
  crowbar
  prybar
])

  (with depot.services.ghuntley.machines; [
    com-ghuntley
    com-ghuntley-media
  ])
