// Copyright 2019-2020 Google LLC.
// SPDX-License-Identifier: Apache-2.0
//
// besadii is a small CLI tool that is invoked as a hook by various
// programs to cause CI-related actions.
//
// It supports the following modes & operations:
//
// Gerrit (ref-updated) hook:
// - Trigger Buildkite CI builds
//
// Buildkite (post-command) hook:
// - Submit CL verification status back to Gerrit
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log/syslog"
	"net/http"
	"net/mail"
	"os"
	"os/user"
	"path"
	"regexp"
	"strconv"
	"strings"
)

// Regular expression to extract change ID out of a URL
var changeIdRegexp = regexp.MustCompile(`^.*/(\d+)$`)

// Regular expression to check if gerritChangeName valid. The
// limitation could be what is allowed for a git branch name. For now
// we want to have a stricter limitation for readability and ease of
// use.
var gerritChangeNameRegexp = `^[a-z0-9]+$`
var gerritChangeNameCheck = regexp.MustCompile(gerritChangeNameRegexp)

// besadii configuration file structure
type config struct {
	// Required configuration for Buildkite<>Gerrit monorepo
	// integration.
	Repository       string `json:"repository"`
	Branch           string `json:"branch"`
	GerritUrl        string `json:"gerritUrl"`
	GerritUser       string `json:"gerritUser"`
	GerritPassword   string `json:"gerritPassword"`
	GerritLabel      string `json:"gerritLabel"`
	BuildkiteOrg     string `json:"buildkiteOrg"`
	BuildkiteProject string `json:"buildkiteProject"`
	BuildkiteToken   string `json:"buildkiteToken"`
	GerritChangeName string `json:"gerritChangeName"`
}

// buildTrigger represents the information passed to besadii when it
// is invoked as a Gerrit hook.
//
// https://gerrit.googlesource.com/plugins/hooks/+/HEAD/src/main/resources/Documentation/hooks.md
type buildTrigger struct {
	project string
	ref     string
	commit  string
	author  string
	email   string

	changeId string
	patchset string
}

type Author struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

// Build is the representation of a Buildkite build as described on
// https://buildkite.com/docs/apis/rest-api/builds#create-a-build
type Build struct {
	Commit string            `json:"commit"`
	Branch string            `json:"branch"`
	Author Author            `json:"author"`
	Env    map[string]string `json:"env"`
}

// BuildResponse is the representation of Buildkite's success response
// after triggering a build. This has many fields, but we only need
// one of them.
type buildResponse struct {
	WebUrl string `json:"web_url"`
}

// reviewInput is a struct representing the data submitted to Gerrit
// to post a review on a CL.
//
// https://gerrit-review.googlesource.com/Documentation/rest-api-changes.html#review-input
type reviewInput struct {
	Message                        string         `json:"message"`
	Labels                         map[string]int `json:"labels,omitempty"`
	OmitDuplicateComments          bool           `json:"omit_duplicate_comments"`
	IgnoreDefaultAttentionSetRules bool           `json:"ignore_default_attention_set_rules"`
	Tag                            string         `json:"tag"`
	Notify                         string         `json:"notify,omitempty"`
}

func defaultConfigLocation() (string, error) {
	usr, err := user.Current()
	if err != nil {
		return "", fmt.Errorf("failed to get current user: %w", err)
	}

	return path.Join(usr.HomeDir, "besadii.json"), nil
}

func loadConfig() (*config, error) {
	configPath := os.Getenv("BESADII_CONFIG")

	if configPath == "" {
		var err error
		configPath, err = defaultConfigLocation()
		if err != nil {
			return nil, fmt.Errorf("failed to get config location: %w", err)
		}
	}

	configJson, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to load besadii config: %w", err)
	}

	var cfg config
	err = json.Unmarshal(configJson, &cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal besadii config: %w", err)
	}

	// The default Gerrit label to set is 'Verified', unless specified otherwise.
	if cfg.GerritLabel == "" {
		cfg.GerritLabel = "Verified"
	}

	// The default text referring to a Gerrit Change in BuildKite.
	if cfg.GerritChangeName == "" {
		cfg.GerritChangeName = "cl"
	}
	if !gerritChangeNameCheck.MatchString(cfg.GerritChangeName) {
		return nil, fmt.Errorf("invalid 'gerritChangeName': %s", cfg.GerritChangeName)
	}

	if cfg.Repository == "" || cfg.Branch == "" {
		return nil, fmt.Errorf("missing repository configuration (required: repository, branch)")
	}

	if cfg.GerritUrl == "" || cfg.GerritUser == "" || cfg.GerritPassword == "" {
		return nil, fmt.Errorf("missing Gerrit configuration (required: gerritUrl, gerritUser, gerritPassword)")
	}

	if cfg.BuildkiteOrg == "" || cfg.BuildkiteProject == "" || cfg.BuildkiteToken == "" {
		return nil, fmt.Errorf("mising Buildkite configuration (required: buildkiteOrg, buildkiteProject, buildkiteToken)")
	}

	return &cfg, nil
}

// linkToChange creates the full link to a change's patchset in Gerrit
func linkToChange(cfg *config, changeId, patchset string) string {
	return fmt.Sprintf("%s/c/%s/+/%s/%s", cfg.GerritUrl, cfg.Repository, changeId, patchset)
}

// updateGerrit posts a comment on a Gerrit CL to indicate the current build status.
func updateGerrit(cfg *config, review reviewInput, changeId, patchset string) {
	body, _ := json.Marshal(review)
	reader := io.NopCloser(bytes.NewReader(body))

	url := fmt.Sprintf("%s/a/changes/%s/revisions/%s/review", cfg.GerritUrl, changeId, patchset)
	req, err := http.NewRequest("POST", url, reader)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to create an HTTP request: %s", err)
		os.Exit(1)
	}

	req.SetBasicAuth(cfg.GerritUser, cfg.GerritPassword)
	req.Header.Add("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to update %s on %s: %s", cfg.GerritChangeName, cfg.GerritUrl, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		fmt.Fprintf(os.Stderr, "received non-success response from Gerrit: %s (%v)", respBody, resp.Status)
	} else {
		fmt.Printf("Added CI status comment on %s", linkToChange(cfg, changeId, patchset))
	}
}

// Trigger a build of a given branch & commit on Buildkite
func triggerBuild(cfg *config, log *syslog.Writer, trigger *buildTrigger) error {
	env := make(map[string]string)
	branch := trigger.ref

	// Pass information about the originating Gerrit change to the
	// build, if it is for a patchset.
	//
	// This information is later used by besadii when invoked by Gerrit
	// to communicate the build status back to Gerrit.
	headBuild := true
	if trigger.changeId != "" && trigger.patchset != "" {
		env["GERRIT_CHANGE_URL"] = linkToChange(cfg, trigger.changeId, trigger.patchset)
		env["GERRIT_CHANGE_ID"] = trigger.changeId
		env["GERRIT_PATCHSET"] = trigger.patchset
		headBuild = false

		// The branch doesn't have to be a real ref (it's just used to
		// group builds), so make it the identifier for the CL.
		branch = fmt.Sprintf("%s/%v", cfg.GerritChangeName, strings.Split(trigger.ref, "/")[3])
	}

	build := Build{
		Commit: trigger.commit,
		Branch: branch,
		Env:    env,
		Author: Author{
			Name:  trigger.author,
			Email: trigger.email,
		},
	}

	body, _ := json.Marshal(build)
	reader := io.NopCloser(bytes.NewReader(body))

	bkUrl := fmt.Sprintf("https://api.buildkite.com/v2/organizations/%s/pipelines/%s/builds", cfg.BuildkiteOrg, cfg.BuildkiteProject)
	req, err := http.NewRequest("POST", bkUrl, reader)
	if err != nil {
		return fmt.Errorf("failed to create an HTTP request: %w", err)
	}

	req.Header.Add("Authorization", "Bearer "+cfg.BuildkiteToken)
	req.Header.Add("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		// This might indicate a temporary error on the Buildkite side.
		return fmt.Errorf("failed to send Buildkite request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read Buildkite response body: %w", err)
	}

	if resp.StatusCode != http.StatusCreated {
		return fmt.Errorf("received non-success response from Buildkite: %s (%v)", respBody, resp.Status)
	}

	var buildResp buildResponse
	err = json.Unmarshal(respBody, &buildResp)
	if err != nil {
		return fmt.Errorf("failed to unmarshal build response: %w", err)
	}

	fmt.Fprintf(log, "triggered build for ref %q at commit %q: %s", trigger.ref, trigger.commit, buildResp.WebUrl)

	// For builds of the HEAD branch there is nothing else to do
	if headBuild {
		return nil
	}

	// Report the status back to the Gerrit CL so that users can click
	// through to the running build.
	msg := fmt.Sprintf("Started build for patchset #%s on: %s", trigger.patchset, buildResp.WebUrl)
	review := reviewInput{
		Message:               msg,
		OmitDuplicateComments: true,
		Tag:                   "autogenerated:buildkite~trigger",

		// Do not update the attention set for this comment.
		IgnoreDefaultAttentionSetRules: true,

		Notify: "NONE",
	}
	updateGerrit(cfg, review, trigger.changeId, trigger.patchset)

	return nil
}

// Gerrit passes more flags than we want, but Rob Pike decided[0] in
// 2013 that the Go art project will not allow users to ignore flags
// because he "doesn't like it". This function allows users to ignore
// flags.
//
// [0]: https://github.com/golang/go/issues/6112#issuecomment-66083768
func ignoreFlags(ignore []string) {
	for _, f := range ignore {
		flag.String(f, "", "flag to ignore")
	}
}

// Extract the username & email from Gerrit's uploader flag and set it
// on the trigger struct, for display in Buildkite.
func extractChangeUploader(uploader string, trigger *buildTrigger) error {
	// Gerrit passes the uploader in another extra layer of quotes.
	uploader, err := strconv.Unquote(uploader)
	if err != nil {
		return fmt.Errorf("failed to unquote email - forgot quotes on manual invocation?: %w", err)
	}

	// Extract the uploader username & email from the input passed by
	// Gerrit (in RFC 5322 format).
	addr, err := mail.ParseAddress(uploader)
	if err != nil {
		return fmt.Errorf("invalid change uploader (%s): %w", uploader, err)
	}

	trigger.author = addr.Name
	trigger.email = addr.Address

	return nil
}

// Extract the buildtrigger struct out of the flags passed to besadii
// when invoked as Gerrit's 'patchset-created' hook. This hook is used
// for triggering CI on in-progress CLs.
func buildTriggerFromPatchsetCreated(cfg *config) (*buildTrigger, error) {
	// Information that needs to be returned
	var trigger buildTrigger

	// Information that is only needed for parsing
	var targetBranch, changeUrl, uploader, kind string

	flag.StringVar(&trigger.project, "project", "", "Gerrit project")
	flag.StringVar(&trigger.commit, "commit", "", "commit hash")
	flag.StringVar(&trigger.patchset, "patchset", "", "patchset ID")

	flag.StringVar(&targetBranch, "branch", "", "CL target branch")
	flag.StringVar(&changeUrl, "change-url", "", "HTTPS URL of change")
	flag.StringVar(&uploader, "uploader", "", "Change uploader name & email")
	flag.StringVar(&kind, "kind", "", "Kind of patchset")

	// patchset-created also passes various flags which we don't need.
	ignoreFlags([]string{"topic", "change", "uploader-username", "change-owner", "change-owner-username"})

	flag.Parse()

	// Ignore patchsets which do not contain code changes
	if kind == "NO_CODE_CHANGE" || kind == "NO_CHANGE" {
		return nil, nil
	}

	// Parse username & email
	err := extractChangeUploader(uploader, &trigger)
	if err != nil {
		return nil, err
	}

	// If the patchset is not for the HEAD branch of the monorepo, then
	// we can ignore it. It might be some other kind of change
	// (refs/meta/config or Gerrit-internal), but it is not an error.
	if trigger.project != cfg.Repository || targetBranch != cfg.Branch {
		return nil, nil
	}

	// Change ID is not directly passed in the numeric format, so we
	// need to extract it out of the URL
	matches := changeIdRegexp.FindStringSubmatch(changeUrl)
	trigger.changeId = matches[1]

	// Construct the CL ref from which the build should happen.
	changeId, _ := strconv.Atoi(trigger.changeId)
	trigger.ref = fmt.Sprintf(
		"refs/changes/%02d/%s/%s",
		changeId%100, trigger.changeId, trigger.patchset,
	)

	return &trigger, nil
}

// Extract the buildtrigger struct out of the flags passed to besadii
// when invoked as Gerrit's 'change-merged' hook. This hook is used
// for triggering HEAD builds after change submission.
func buildTriggerFromChangeMerged(cfg *config) (*buildTrigger, error) {
	// Information that needs to be returned
	var trigger buildTrigger

	// Information that is only needed for parsing
	var targetBranch, submitter string

	flag.StringVar(&trigger.project, "project", "", "Gerrit project")
	flag.StringVar(&trigger.commit, "commit", "", "Commit hash")
	flag.StringVar(&submitter, "submitter", "", "Submitter email & username")
	flag.StringVar(&targetBranch, "branch", "", "CL target branch")

	// Ignore extra flags passed by change-merged
	ignoreFlags([]string{"change", "topic", "change-url", "submitter-username", "newrev", "change-owner", "change-owner-username"})

	flag.Parse()

	// Parse username & email
	err := extractChangeUploader(submitter, &trigger)
	if err != nil {
		return nil, err
	}

	// If the patchset is not for the HEAD branch of the monorepo, then
	// we can ignore it.
	if trigger.project != cfg.Repository || targetBranch != cfg.Branch {
		return nil, nil
	}

	trigger.ref = "refs/heads/" + targetBranch

	return &trigger, nil
}

func gerritHookMain(cfg *config, log *syslog.Writer, trigger *buildTrigger) {
	if trigger == nil {
		// The hook was not for something we care about.
		os.Exit(0)
	}

	err := triggerBuild(cfg, log, trigger)

	if err != nil {
		log.Err(fmt.Sprintf("failed to trigger Buildkite build: %s", err))
	}
}

func postCommandMain(cfg *config) {
	changeId := os.Getenv("GERRIT_CHANGE_ID")
	patchset := os.Getenv("GERRIT_PATCHSET")

	if changeId == "" || patchset == "" {
		// If these variables are unset, but the hook was invoked, the
		// build was most likely for a branch and not for a CL - no status
		// needs to be reported back to Gerrit!
		fmt.Printf("This isn't a %s build, nothing to do. Have a nice day!\n", cfg.GerritChangeName)
		return
	}

	if os.Getenv("BUILDKITE_LABEL") != ":duck:" {
		// this is not the build stage, don't do anything.
		return
	}

	var vote int
	var verb string
	var notify string

	if os.Getenv("BUILDKITE_COMMAND_EXIT_STATUS") == "0" {
		vote = 1 // automation passed: +1 in Gerrit
		verb = "passed"
		notify = "NONE"
	} else {
		vote = -1
		verb = "failed"
		notify = "OWNER"
	}

	msg := fmt.Sprintf("Build of patchset %s %s: %s", patchset, verb, os.Getenv("BUILDKITE_BUILD_URL"))
	review := reviewInput{
		Message:               msg,
		OmitDuplicateComments: true,
		Labels: map[string]int{
			cfg.GerritLabel: vote,
		},

		// Update the attention set if we are failing this patchset.
		IgnoreDefaultAttentionSetRules: vote == 1,

		Tag: "autogenerated:buildkite~result",

		Notify: notify,
	}
	updateGerrit(cfg, review, changeId, patchset)
}

func main() {
	// Logging happens in syslog because it's almost impossible to get
	// output out of Gerrit hooks otherwise.
	log, err := syslog.New(syslog.LOG_INFO|syslog.LOG_USER, "besadii")
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to open syslog: %s\n", err)
		os.Exit(1)
	}

	log.Info(fmt.Sprintf("besadii called with arguments: %v", os.Args))

	bin := path.Base(os.Args[0])
	cfg, err := loadConfig()

	if err != nil {
		log.Crit(fmt.Sprintf("besadii configuration error: %v", err))
		os.Exit(4)
	}

	if bin == "patchset-created" {
		trigger, err := buildTriggerFromPatchsetCreated(cfg)
		if err != nil {
			log.Crit(fmt.Sprintf("failed to parse 'patchset-created' invocation from args: %v", err))
			os.Exit(1)
		}
		gerritHookMain(cfg, log, trigger)
	} else if bin == "change-merged" {
		trigger, err := buildTriggerFromChangeMerged(cfg)
		if err != nil {
			log.Crit(fmt.Sprintf("failed to parse 'change-merged' invocation from args: %v", err))
			os.Exit(1)
		}
		gerritHookMain(cfg, log, trigger)
	} else if bin == "post-command" {
		postCommandMain(cfg)
	} else {
		fmt.Fprintf(os.Stderr, "besadii does not know how to be invoked as %q, sorry!", bin)
		os.Exit(1)
	}
}
