# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

# Helper script to run a CRFO approval using depot-interventions.
#
# Use as 'crfo-approve $CL_ID $PATCHSET $REAL_USER $ON_BEHALF_OF'.
#
# Set credential in GERRIT_TOKEN envvar.
{ pkgs, ... }:

pkgs.writeShellScriptBin "gerrit-crfo-approve" ''
  set -ueo pipefail

  if (($# != 4)) || [[ -z ''${GERRIT_TOKEN-} ]]; then
    cat >&2 <<'EOF'
  crfo-approve - Helper script to CRFO approve a Ponderoos CL

  Requires membership in depot-interventions to work.

  Gerrit HTTP credential must be set in GERRIT_TOKEN envvar.

  Usage:
    crfo-approve $CL_ID $PATCHSET $REAL_USER $ON_BEHALF_OF
  EOF
    exit 1
  fi

  export PATH="${pkgs.lib.makeBinPath [ pkgs.httpie pkgs.jq ]}:''${PATH}"

  readonly CL_ID="''${1}"
  readonly PATCHSET="''${2}"
  readonly REAL_USER="''${3}"
  readonly TOKEN="''${GERRIT_TOKEN}"
  readonly ON_BEHALF_OF="''${4}"
  readonly URL="https://cl.ponderoos.com/a/changes/''${CL_ID}/revisions/''${PATCHSET}/review"

  # First we need to find the account ID for the user
  ACC_RESPONSE=$(http --check-status 'https://cl.ponderoos.com/accounts/' "q==name:''${ON_BEHALF_OF}" | tail -n +2)
  ACC_LENGTH=$(echo "''${ACC_RESPONSE}" | jq 'length')

  if [[ ''${ACC_LENGTH} -ne 1 ]]; then
      echo "Did not find a unique account ID for ''${ON_BEHALF_OF}"
      exit 1
  fi

  ACC_ID=$(jq -n --argjson response "''${ACC_RESPONSE}" '$response[0]._account_id')
  echo "using account ID ''${ACC_ID} for ''${ON_BEHALF_OF}"

  http --check-status -a "''${REAL_USER}:''${TOKEN}" POST "''${URL}" \
    message="CRFO on behalf of ''${ON_BEHALF_OF}" \
    'labels[Code-Review]=+2' \
    on_behalf_of="''${ACC_ID}" \
    "add_to_attention_set[0][user]=''${ACC_ID}" \
    "add_to_attention_set[0][reason]=CRFO approval through depot-interventions"
''
