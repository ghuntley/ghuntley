#!/usr/bin/env bash
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

set -ueo pipefail

# Each Buildkite build stores the derivation target map as a pipeline
# artifact. To reduce the amount of work done by CI, each CI build is
# diffed against the latest such derivation map found for the
# repository.
#
# Note that this does not take into account when the currently
# processing CL was forked off from the canonical branch, meaning that
# things like nixpkgs updates in between will cause mass rebuilds in
# any case.
#
# If no map is found, the failure mode is not critical: We simply
# build all targets.

readonly REPO_ROOT=$(git rev-parse --show-toplevel)

: ${DRVMAP_PATH:=pipeline/drvmap.json}
: ${BUILDKITE_TOKEN_PATH:=~/buildkite-token}

# Runs a fairly complex Buildkite GraphQL query that attempts to fetch all
# pipeline-gen steps from the default branch, as long as one appears within the
# last 50 builds or so. The query restricts build states to running or passed
# builds, which means that it *should* be unlikely that nothing is found.
#
# There is no way to filter this more loosely (e.g. by saying "any recent build
# matching these conditions").
#
# The returned data structure is complex, and disassembled by a JQ script that
# first filters out all builds with no matching jobs (e.g. builds that are still
# in progress), and then filters those down to builds with artifacts, and then
# to drvmap artifacts specifically.
#
# If a recent drvmap was found, this returns its download URL. Otherwise, it
# returns the string "null".
function latest_drvmap_url {
    set -u
    curl 'https://graphql.buildkite.com/v1' \
         --silent \
         -H "Authorization: Bearer $(cat ${BUILDKITE_TOKEN_PATH})" \
         -H "Content-Type: application/json" \
         -d "{\"query\": \"{ pipeline(slug: \\\"$BUILDKITE_ORGANIZATION_SLUG/$BUILDKITE_PIPELINE_SLUG\\\") { builds(first: 50, branch: [\\\"%default\\\"], state: [RUNNING, PASSED]) { edges { node { jobs(passed: true, first: 1, type: [COMMAND], step: {key: [\\\"pipeline-gen\\\"]}) { edges { node { ... on JobTypeCommand { url artifacts { edges { node { downloadURL path }}}}}}}}}}}}\"}" | tee out.json | \
        jq -r '[.data.pipeline.builds.edges[] | select((.node.jobs.edges | length) > 0) | .node.jobs.edges[] | .node.artifacts[][] | select(.node.path == "pipeline/drvmap.json")][0].node.downloadURL'
}

readonly DOWNLOAD_URL=$(latest_drvmap_url)

if [[ ${DOWNLOAD_URL} != "null" ]]; then
    mkdir -p tmp
    curl -o tmp/parent-target-map.json ${DOWNLOAD_URL} && echo "downloaded parent derivation map" \
            || echo "failed to download derivation map!"
else
    echo "no derivation map found!"
fi
