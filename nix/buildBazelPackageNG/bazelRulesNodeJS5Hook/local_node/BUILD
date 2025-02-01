# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

load("@build_bazel_rules_nodejs//nodejs:toolchain.bzl", _node_toolchain = "node_toolchain")

package(default_visibility = ["//visibility:public"])

exports_files([
    "bin/node",
    "bin/npm",
])

_node_toolchain(
    name = "node_toolchain",
    target_tool_path = "__NODEJS__/bin/node",
    npm_path = "__NODEJS__/bin/npm",
)

toolchain(
    name = "nodejs",
    toolchain = ":node_toolchain",
    toolchain_type = "@build_bazel_rules_nodejs//nodejs:toolchain_type",
)
