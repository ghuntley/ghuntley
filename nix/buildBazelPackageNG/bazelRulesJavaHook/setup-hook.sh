# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

prePatchHooks+=(_setupLocalJavaRepo)

javaVersions=(11 17 21)
javaPlatforms=(
  "linux" "linux_aarch64" "linux_ppc64le" "linux_s390x"
  "macos" "macos_aarch64"
  "win" "win_arm64")

_setupLocalJavaRepo() {
	for javaVersion in ${javaVersions[@]}; do
		for javaPlatform in ${javaPlatforms[@]}; do
			bazelFlagsArray+=(
				"--override_repository=remotejdk${javaVersion}_${javaPlatform}=@local_java@"
			)
		done
	done
}
