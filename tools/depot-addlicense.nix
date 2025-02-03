# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

{ depot
, pkgs
, ...
}:

let

  config = pkgs.writeText "depot-addlicense-config" ''
    Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
    SPDX-License-Identifier: Proprietary
  '';

  depot-addlicense = pkgs.writeShellScriptBin "depot-addlicense" ''
    if [ $# -eq 0 ]; then
      # No arguments provided, use DEPOT_ROOT
      exec ${pkgs.addlicense}/bin/addlicense -f ${config} ''${DEPOT_ROOT}
    else
      # Arguments provided, use them as file paths
      exec ${pkgs.addlicense}/bin/addlicense -f ${config} "$@"
    fi
  '';

  check = pkgs.writeShellScriptBin "depot-addlicense-check" ''
    exec ${pkgs.addlicense}/bin/addlicense -check -f ${config} ''${DEPOT_ROOT}
  '';

in
depot-addlicense.overrideAttrs (_: {
  passthru.meta.ci.extraSteps.check = {
    label = "depot license header check";
    command = check;
    alwaysRun = true;
  };
})
