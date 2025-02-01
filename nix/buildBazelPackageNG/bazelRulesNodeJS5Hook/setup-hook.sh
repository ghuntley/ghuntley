# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# SPDX-License-Identifier: MIT

prePatchHooks+=(_setupLocalNodeRepos)
preBuildHooks+=(_setupYarnCache)

case "$bazelPhase" in
	cache)
		postInstallHooks+=(_copyYarnCache)
		;;
	build)
		preBuildHooks+=(_linkYarnCache)
		;;
	*)
		echo "Unexpected bazelPhase '$bazelPhase' (want cache or build)" >&2
		exit 1
		;;
esac


_setupLocalNodeRepos() {
	cp -R @local_node@ $HOME/local_node
	chmod -R +w $HOME/local_node
	substituteInPlace $HOME/local_node/bin/node \
		--replace-fail '__NODEJS__' '@nodejs@'
	substituteInPlace $HOME/local_node/bin/npm \
		--replace-fail '__NODEJS__' '@nodejs@'
	substituteInPlace $HOME/local_node/BUILD \
		--replace-fail '__NODEJS__' '@nodejs@'
	chmod -R +x $HOME/local_node/bin/*

	cp -R @local_yarn@ $HOME/local_yarn
	chmod -R +w $HOME/local_yarn
	substituteInPlace $HOME/local_yarn/bin/yarn \
		--replace-fail '__YARN__' '@yarn@'
	chmod -R +x $HOME/local_yarn/bin/*

	bazelFlagsArray+=(
		"--override_repository=build_bazel_rules_nodejs=@rulesNodeJS@"

		"--override_repository=nodejs_linux_amd64=$HOME/local_node"
		"--override_repository=nodejs_linux_arm64=$HOME/local_node"
		"--override_repository=nodejs_linux_s390x=$HOME/local_node"
		"--override_repository=nodejs_linux_ppc64le=$HOME/local_node"
		"--override_repository=nodejs_darwin_amd64=$HOME/local_node"
		"--override_repository=nodejs_darwin_arm64=$HOME/local_node"
		"--override_repository=nodejs_windows_amd64=$HOME/local_node"
		"--override_repository=nodejs_windows_arm64=$HOME/local_node"
		"--override_repository=nodejs=$HOME/local_node"

		"--override_repository=yarn=$HOME/local_yarn"
	)
}

_setupYarnCache() {
	@yarn@/bin/yarn config set cafile "@cacert@/etc/ssl/certs/ca-bundle.crt"
	@yarn@/bin/yarn config set yarn-offline-mirror "$HOME/yarn-offline-mirror"
}

_copyYarnCache() {
	cp -R "$HOME/yarn-offline-mirror" "$out/yarn-offline-mirror"
}

_linkYarnCache() {
	ln -sf "$cache/yarn-offline-mirror" "$HOME/yarn-offline-mirror"
}
