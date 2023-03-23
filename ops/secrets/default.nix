# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

args:
let mkSecrets = import ./mkSecrets.nix args; in
mkSecrets ./. (import ./secrets.nix) // { inherit mkSecrets; }
