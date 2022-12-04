# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

{ depot, ... }:

(with depot.ops.machines; [
  prd-bne-ca
  prd-bne-code
  prd-bne-ts
  prd-bne-time
  prd-bne-proxy
  prd-bne-smtp
  prd-fsn1-dc11-1880953
])
