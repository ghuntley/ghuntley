# Copyright (c) 2019 Vincent Ambo
# Copyright (c) 2020-2021 The TVL Authors
# Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: MIT

# Logic for generating Buildkite pipelines from Nix build targets read
# by //nix/readTree.
#
# It outputs a "YAML" (actually JSON) file which is evaluated and
# submitted to Buildkite at the start of each build.
#
# The structure of the file that is being created is documented here:
#   https://buildkite.com/docs/pipelines/defining-steps
{ depot, pkgs, ... }:

let
  inherit (builtins)
    attrValues
    concatLists
    concatStringsSep
    elem
    foldl'
    hasAttr
    hashString
    isString
    length
    listToAttrs
    mapAttrs
    toJSON
    unsafeDiscardStringContext;

  inherit (pkgs) lib runCommand writeText;
  inherit (depot.nix.readTree) mkLabel;

  inherit (depot.nix) dependency-analyzer;
in
rec {
  # Create a unique key for the buildkite pipeline based on the given derivation
  # or drvPath. A consequence of using such keys is that every derivation may
  # only be exposed as a single, unique step in the pipeline.
  keyForDrv = drvOrPath:
    let
      drvPath =
        if lib.isDerivation drvOrPath then drvOrPath.drvPath
        else if lib.isString drvOrPath then drvOrPath
        else builtins.throw "keyForDrv: expected string or derivation";

      # Only use the drv hash to prevent escaping problems. Buildkite also has a
      # limit of 100 characters on keys.
    in
    "drv-" + (builtins.substring 0 32
      (builtins.baseNameOf (unsafeDiscardStringContext drvPath))
    );

  # Given an arbitrary attribute path generate a Nix expression which obtains
  # this from the root of depot (assumed to be ./.). Attributes may be any
  # Nix strings suitable as attribute names, not just Nix literal-safe strings.
  mkBuildExpr = attrPath:
    let
      descend = expr: attr: "builtins.getAttr \"${attr}\" (${expr})";
    in
    foldl' descend "import ./. {}" attrPath;

  # Determine whether to skip a target if it has not diverged from the
  # HEAD branch.
  shouldSkip = { parentTargetMap ? { }, label, drvPath }:
    if (hasAttr label parentTargetMap) && parentTargetMap."${label}".drvPath == drvPath
    then "Target has not changed."
    else false;

  # Create build command for an attribute path pointing to a derivation.
  mkBuildCommand = { attrPath, drvPath, outLink ? "result" }: concatStringsSep " " [
    # If the nix build fails, the Nix command's exit status should be used.
    "set -o pipefail;"

    # First try to realise the drvPath of the target so we don't evaluate twice.
    # Nix has no concept of depending on a derivation file without depending on
    # at least one of its `outPath`s, so we need to discard the string context
    # if we don't want to build everything during pipeline construction.
    #
    # To make this more uniform with how nix-build(1) works, we call realpath(1)
    # on nix-store(1)'s output since it has the habit of printing the path of the
    # out link, not the store path.
    "(nix-store --realise '${drvPath}' --add-root '${outLink}' --indirect | xargs -r realpath)"

    # Since we don't gcroot the derivation files, they may be deleted by the
    # garbage collector. In that case we can reevaluate and build the attribute
    # using nix-build.
    "|| (test ! -f '${drvPath}' && nix-build -E '${mkBuildExpr attrPath}' --show-trace --out-link '${outLink}')"
  ];

  # Attribute path of a target relative to the depot root. Needs to take into
  # account whether the target is a physical target (which corresponds to a path
  # in the filesystem) or the subtarget of a physical target.
  targetAttrPath = target:
    target.__readTree
    ++ lib.optionals (target ? __subtarget) [ target.__subtarget ];

  # Given a derivation (identified by drvPath) that is part of the list of
  # targets passed to mkPipeline, determine all derivations that it depends on
  # and are also part of the pipeline. Finally, return the keys of the steps
  # that build them. This is used to populate `depends_on` in `mkStep`.
  #
  # See //nix/dependency-analyzer for documentation on the structure of `targetDepMap`.
  getTargetPipelineDeps = targetDepMap: drvPath:
    builtins.map keyForDrv (targetDepMap.${drvPath}.knownDeps or [ ]);

  # Create a pipeline step from a single target.
  mkStep = { headBranch, parentTargetMap, targetDepMap, target, cancelOnBuildFailing }:
    let
      label = mkLabel target;
      drvPath = unsafeDiscardStringContext target.drvPath;
    in
    {
      label = ":nix: " + label;
      key = keyForDrv target;
      skip = shouldSkip { inherit label drvPath parentTargetMap; };
      command = mkBuildCommand {
        attrPath = targetAttrPath target;
        inherit drvPath;
      };
      env.READTREE_TARGET = label;
      cancel_on_build_failing = cancelOnBuildFailing;

      # Add a dependency on the initial static pipeline step which
      # always runs. This allows build steps uploaded in batches to
      # start running before all batches have been uploaded.
      depends_on = [ ":init:" ]
      ++ getTargetPipelineDeps targetDepMap drvPath
      ++ lib.optionals (target ? meta.ci.buildkiteExtraDeps) target.meta.ci.buildkiteExtraDeps;
    } // lib.optionalAttrs (target ? meta.timeout) {
      timeout_in_minutes = target.meta.timeout / 60;
      # Additional arguments to set on the step.
      # Keep in mind these *overwrite* existing step args, not extend. Use with caution.
    } // lib.optionalAttrs (target ? meta.ci.buildkiteExtraStepArgs) target.meta.ci.buildkiteExtraStepArgs;

  # Helper function to inelegantly divide a list into chunks of at
  # most n elements.
  #
  # This works by assigning each element a chunk ID based on its
  # index, and then grouping all elements by their chunk ID.
  chunksOf = n: list:
    let
      chunkId = idx: toString (idx / n + 1);
      assigned = lib.imap1 (idx: value: { inherit value; chunk = chunkId idx; }) list;
      unchunk = mapAttrs (_: elements: map (e: e.value) elements);
    in
    unchunk (lib.groupBy (e: e.chunk) assigned);

  # Define a build pipeline chunk as a JSON file, using the pipeline
  # format documented on
  # https://buildkite.com/docs/pipelines/defining-steps.
  makePipelineChunk = name: chunkId: chunk: rec {
    filename = "${name}-chunk-${chunkId}.json";
    path = writeText filename (toJSON {
      steps = chunk;
    });
  };

  # Split the pipeline into chunks of at most 192 steps at once, which
  # are uploaded sequentially. This is because of a limitation in the
  # Buildkite backend which struggles to process more than a specific
  # number of chunks at once.
  pipelineChunks = name: steps:
    attrValues (mapAttrs (makePipelineChunk name) (chunksOf 192 steps));

  # Create a pipeline structure for the given targets.
  mkPipeline =
    {
      # HEAD branch of the repository on which release steps, GC
      # anchoring and other "mainline only" steps should run.
      headBranch
    , # List of derivations as read by readTree (in most cases just the
      # output of readTree.gather) that should be built in Buildkite.
      #
      # These are scheduled as the first build steps and run as fast as
      # possible, in order, without any concurrency restrictions.
      drvTargets
    , # Derivation map of a parent commit. Only targets which no longer
      # correspond to the content of this map will be built. Passing an
      # empty map will always build all targets.
      parentTargetMap ? { }
    , # A list of plain Buildkite step structures to run alongside the
      # build for all drvTargets, but before proceeding with any
      # post-build actions such as status reporting.
      #
      # Can be used for things like code formatting checks.
      additionalSteps ? [ ]
    , # A list of plain Buildkite step structures to run after all
      # previous steps succeeded.
      #
      # Can be used for status reporting steps and the like.
      postBuildSteps ? [ ]
      # The list of phases known by the current Buildkite
      # pipeline. Dynamic pipeline chunks for each phase are uploaded
      # to Buildkite on execution of static part of the
      # pipeline. Phases selection is hard-coded in the static
      # pipeline.
      #
      # Pipeline generation will fail when an extra step with
      # unregistered phase is added.
      #
      # Common scenarios for different phase:
      #   - "build" - main phase for building all Nix targets
      #   - "release" - pushing artifacts to external repositories
      #   - "deploy" - updating external deployment configurations
    , phases ? [ "build" "release" ]
      # Build phases that are active for this invocation (i.e. their
      # steps should be generated).
      #
      # This can be used to disable outputting parts of a pipeline if,
      # for example, build and release phases are created in separate
      # eval contexts.
      #
      # TODO(tazjin): Fail/warn if unknown phase is requested.
    , activePhases ? phases
      # Setting this attribute to true cancels dynamic pipeline steps
      # as soon as the build is marked as failing.
      #
      # To enable this feature one should enable "Fail Fast" setting
      # at Buildkite pipeline or on organization level.
    , cancelOnBuildFailing ? false
    }:
    let
      # List of phases to include.
      enabledPhases = lib.intersectLists activePhases phases;

      # Is the 'build' phase included? This phase is treated specially
      # because it always contains the plain Nix builds, and some
      # logic/optimisation depends on knowing whether is executing.
      buildEnabled = elem "build" enabledPhases;

      # Dependency relations between the `drvTargets`. See also //nix/dependency-analyzer.
      targetDepMap =
        let
          # Only calculate dependencies between drvTargets that were not part of
          # the previous pipeline (per parentTargetMap). Unchanged targets will
          # be skipped (assumed already built), so it's useless to emit deps
          # on their steps.
          changedDrvTargets = builtins.filter
            (target:
              parentTargetMap.${mkLabel target}.drvPath or null != target.drvPath
            )
            drvTargets;
        in
        dependency-analyzer (dependency-analyzer.drvsToPaths changedDrvTargets);

      # Convert a target into all of its steps, separated by build
      # phase (as phases end up in different chunks).
      targetToSteps = target:
        let
          mkStepArgs = {
            inherit headBranch parentTargetMap targetDepMap target cancelOnBuildFailing;
          };
          step = mkStep mkStepArgs;

          # Same step, but with an override function applied. This is
          # used in mkExtraStep if the extra step needs to modify the
          # parent derivation somehow.
          #
          # Note that this will never affect the label.
          overridable = f: mkStep (mkStepArgs // { target = (f target); });

          # Split extra steps by phase.
          splitExtraSteps = lib.groupBy ({ phase, ... }: phase)
            (attrValues (mapAttrs (normaliseExtraStep phases overridable)
              (target.meta.ci.extraSteps or { })));

          extraSteps = mapAttrs
            (_: steps:
              map (mkExtraStep (targetAttrPath target) buildEnabled) steps)
            splitExtraSteps;
        in
        if !buildEnabled then extraSteps
        else extraSteps // {
          build = [ step ] ++ (extraSteps.build or [ ]);
        };

      # Combine all target steps into step lists per phase.
      #
      # TODO(tazjin): Refactor when configurable phases show up.
      globalSteps = {
        build = additionalSteps;
        release = postBuildSteps;
      };

      phasesWithSteps = lib.zipAttrsWithNames enabledPhases (_: concatLists)
        ((map targetToSteps drvTargets) ++ [ globalSteps ]);

      # Generate pipeline chunks for each phase.
      chunks = foldl'
        (acc: phase:
          let phaseSteps = phasesWithSteps.${phase} or [ ]; in
          if phaseSteps == [ ]
          then acc
          else acc ++ (pipelineChunks phase phaseSteps))
        [ ]
        enabledPhases;

    in
    runCommand "buildkite-pipeline" { } ''
      mkdir $out
      echo "Generated ${toString (length chunks)} pipeline chunks"
      ${
        lib.concatMapStringsSep "\n"
          (chunk: "cp ${chunk.path} $out/${chunk.filename}") chunks
      }
    '';

  # Create a drvmap structure for the given targets, containing the
  # mapping of all target paths to their derivations. The mapping can
  # be persisted for future use.
  mkDrvmap = drvTargets: writeText "drvmap.json" (toJSON (listToAttrs (map
    (target: {
      name = mkLabel target;
      value = {
        drvPath = unsafeDiscardStringContext target.drvPath;

        # Include the attrPath in the output to reconstruct the drv
        # without parsing the human-readable label.
        attrPath = targetAttrPath target;
      };
    })
    drvTargets)));

  # Implementation of extra step logic.
  #
  # Each target extra step is an attribute specified in
  # `meta.ci.extraSteps`. Its attribute name will be used as the step
  # name on Buildkite.
  #
  #   command (required): A command that will be run in the depot
  #     checkout when this step is executed. Should be a derivation
  #     resulting in a single executable file, e.g. through
  #     pkgs.writeShellScript.
  #
  #   label (optional): Human-readable label for this step to display
  #     in the Buildkite UI instead of the attribute name.
  #
  #   prompt (optional): Setting this blocks the step until confirmed
  #     by a human. Should be a string which is displayed for
  #     confirmation. These steps always run after the main build is
  #     done and have no influence on CI status.
  #
  #   needsOutput (optional): If set to true, the parent derivation
  #     will be built in the working directory before running the
  #     command. Output will be available as 'result'.
  #     TODO: Figure out multiple-output derivations.
  #
  #   parentOverride (optional): A function (drv -> drv) to override
  #     the parent's target definition when preparing its output. Only
  #     used in extra steps that use needsOutput.
  #
  #   branches (optional): Git references (branches, tags ... ) on
  #     which this step should be allowed to run. List of strings.
  #
  #   alwaysRun (optional): If set to true, this step will always run,
  #     even if its parent has not been rebuilt.
  #
  # Note that gated steps are independent of each other.

  # Create a gated step in a step group, independent from any other
  # steps.
  mkGatedStep = { step, label, parent, prompt }: {
    inherit (step) depends_on;
    group = label;
    skip = parent.skip or false;

    steps = [
      {
        inherit prompt;
        branches = step.branches or [ ];
        block = ":radio_button: Run ${label}? (from ${parent.env.READTREE_TARGET})";
      }

      # The explicit depends_on of the wrapped step must be removed,
      # otherwise its dependency relationship with the gate step will
      # break.
      (builtins.removeAttrs step [ "depends_on" ])
    ];
  };

  # Validate and normalise extra step configuration before actually
  # generating build steps, in order to use user-provided metadata
  # during the pipeline generation.
  normaliseExtraStep = phases: overridableParent: key:
    { command
    , label ? key
    , needsOutput ? false
    , parentOverride ? (x: x)
    , branches ? null
    , alwaysRun ? false
    , prompt ? false
    , softFail ? false
    , phase ? "build"
    , skip ? false
    , agents ? null
    }:
    let
      parent = overridableParent parentOverride;
      parentLabel = parent.env.READTREE_TARGET;

      validPhase = lib.throwIfNot (elem phase phases) ''
        In step '${label}' (from ${parentLabel}):

        Phase '${phase}' is not valid.

        Known phases: ${concatStringsSep ", " phases}
      ''
        phase;
    in
    {
      inherit
        alwaysRun
        branches
        command
        key
        label
        needsOutput
        parent
        parentLabel
        softFail
        skip
        agents;

      phase = validPhase;

      prompt = lib.throwIf (prompt != false && phase == "build") ''
        In step '${label}' (from ${parentLabel}):

        The 'prompt' feature can not be used by steps in the "build"
        phase, because CI builds should not be gated on manual human
        approvals.
      ''
        prompt;
    };

  # Create the Buildkite configuration for an extra step, optionally
  # wrapping it in a gate group.
  mkExtraStep = parentAttrPath: buildEnabled: cfg:
    let
      # ATTN: needs to match an entry in .gitignore so that the tree won't get dirty
      commandScriptLink = "nix-buildkite-extra-step-command-script";

      step = {
        key = "extra-step-" + hashString "sha1" "${cfg.label}-${cfg.parentLabel}";
        label = ":gear: ${cfg.label} (from ${cfg.parentLabel})";
        skip =
          let
            # When parent doesn't have skip attribute set, default to false
            parentSkip = cfg.parent.skip or false;
            # Extra step skip parameter can be string explaining the
            # skip reason.
            extraStepSkip = if builtins.isString cfg.skip then true else cfg.skip;
            # Don't run if extra step is explicitly set to skip. If
            # parameter is not set or equal to false, follow parent behavior.
            skip' = if extraStepSkip then cfg.skip else parentSkip;
          in
          if cfg.alwaysRun then false else skip';

        depends_on = lib.optional
          (buildEnabled && !cfg.alwaysRun && !cfg.needsOutput)
          cfg.parent.key;

        command = ''
          set -ueo pipefail
          ${lib.optionalString cfg.needsOutput
            "echo '~~~ Preparing build output of ${cfg.parentLabel}'"
          }
          ${lib.optionalString cfg.needsOutput cfg.parent.command}
          echo '--- Building extra step script'
          command_script="$(${
            # Using command substitution in this way assumes the script drv only has one output
            assert builtins.length cfg.command.outputs == 1;
            mkBuildCommand {
              # script is exposed at <parent>.meta.ci.extraSteps.<key>.command
              attrPath =
                parentAttrPath
                ++ [ "meta" "ci" "extraSteps" cfg.key "command" ];
              drvPath = unsafeDiscardStringContext cfg.command.drvPath;
              # make sure it doesn't conflict with result (from needsOutput)
              outLink = commandScriptLink;
            }
          })"
          echo '+++ Running extra step script'
          # ATTN: buildkite substitutes this variable outside of the execution for some reason
          exec "\$command_script"
        '';

        soft_fail = cfg.softFail;
      } // (lib.optionalAttrs (cfg.agents != null) { inherit (cfg) agents; })
      // (lib.optionalAttrs (cfg.branches != null) {
        branches = lib.concatStringsSep " " cfg.branches;
      });
    in
    if (isString cfg.prompt)
    then
      mkGatedStep
        {
          inherit step;
          inherit (cfg) label parent prompt;
        }
    else step;
}
