# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, ... }:

(with depot.ops.machines; [
  ghuntley-net
  ghuntley-com
  ghuntley-dev
])
