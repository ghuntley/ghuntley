# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT


args:
let mkSecrets = import ./mkSecrets.nix args; in
mkSecrets ./. (import ./secrets.nix) // { inherit mkSecrets; }
