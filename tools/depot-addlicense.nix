{ depot
, pkgs
, ...
}:

let

  config = pkgs.writeText "depot-addlicense-config" ''
    Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
    SPDX-License-Identifier: Proprietary
  '';

  depot-addlicense = pkgs.writeShellScriptBin "depot-addlicense" ''
    exec ${depot.third_party.addlicense}/bin/addlicense -f ${config} ''${DEPOT_ROOT}
  '';

  check = pkgs.writeShellScriptBin "depot-addlicense-check" ''
    exec ${depot.third_party.addlicense}/bin/addlicense -chceck -f ${config} ''${DEPOT_ROOT}
  '';

in
depot-addlicense.overrideAttrs (_: {
  passthru.meta.ci.extraSteps.check = {
    label = "depot license header check";
    command = check;
    alwaysRun = true;
  };
})
