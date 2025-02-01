//! Copyright (c) 2019 Vincent Ambo
//! Copyright (c) 2020-2021 The TVL Authors
//! SPDX-License-Identifier: MIT

//! gerrit-autosubmit connects to a Gerrit instance and submits the
//! longest chain of changes in which all ancestors are ready and
//! marked for autosubmit.
//!
//! It works like this:
//!
//! * it fetches all changes the Gerrit query API considers
//!   submittable (i.e. all requirements fulfilled), and that have the
//!   `Autosubmit` label set
//!
//! * it filters these changes down to those that are _actually_
//!   submittable (in Gerrit API terms: that have an active Submit button)
//!
//! * it filters out those that would submit ancestors that are *not*
//!   marked with the `Autosubmit` label
//!
//! * it submits the longest chain
//!
//! After that it just loops.

use anyhow::{Context, Result};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::{thread, time};

mod gerrit {
    use anyhow::{anyhow, Context, Result};
    use serde::Deserialize;
    use serde_json::Value;
    use std::collections::HashMap;
    use std::env;

    pub struct Config {
        gerrit_url: String,
        username: String,
        password: String,
    }

    impl Config {
        pub fn from_env() -> Result<Self> {
            Ok(Config {
                gerrit_url: env::var("GERRIT_URL")
                    .context("Gerrit base URL (no trailing slash) must be set in GERRIT_URL")?,
                username: env::var("GERRIT_USERNAME")
                    .context("Gerrit username must be set in GERRIT_USERNAME")?,
                password: env::var("GERRIT_PASSWORD")
                    .context("Gerrit password must be set in GERRIT_PASSWORD")?,
            })
        }
    }

    #[derive(Deserialize)]
    pub struct ChangeInfo {
        pub id: String,
        pub revisions: HashMap<String, Value>,
    }

    #[derive(Deserialize)]
    pub struct Action {
        #[serde(default)]
        pub enabled: bool,
    }

    const GERRIT_RESPONSE_PREFIX: &str = ")]}'";

    pub fn get<T: serde::de::DeserializeOwned>(cfg: &Config, endpoint: &str) -> Result<T> {
        let response = crimp::Request::get(&format!("{}/a{}", cfg.gerrit_url, endpoint))
            .user_agent("gerrit-autosubmit")?
            .basic_auth(&cfg.username, &cfg.password)?
            .send()?
            .error_for_status(|r| anyhow!("request failed with status {}", r.status))?;

        let result: T = serde_json::from_slice(&response.body[GERRIT_RESPONSE_PREFIX.len()..])?;
        Ok(result)
    }

    pub fn submit(cfg: &Config, change_id: &str) -> Result<()> {
        crimp::Request::post(&format!(
            "{}/a/changes/{}/submit",
            cfg.gerrit_url, change_id
        ))
        .user_agent("gerrit-autosubmit")?
        .basic_auth(&cfg.username, &cfg.password)?
        .send()?
        .error_for_status(|r| anyhow!("submit failed with status {}", r.status))?;

        Ok(())
    }
}

#[derive(Debug)]
struct SubmittableChange {
    id: String,
    revision: String,
}

fn list_submittable(cfg: &gerrit::Config) -> Result<Vec<SubmittableChange>> {
    let mut out = Vec::new();

    let changes: Vec<gerrit::ChangeInfo> = gerrit::get(
        &cfg,
        "/changes/?q=is:submittable+label:Autosubmit+-is:wip+is:open&o=SKIP_DIFFSTAT&o=CURRENT_REVISION",
    )
    .context("failed to list submittable changes")?;

    for change in changes.into_iter() {
        out.push(SubmittableChange {
            id: change.id,
            revision: change
                .revisions
                .into_keys()
                .next()
                .context("change had no current revision")?,
        });
    }

    Ok(out)
}

fn is_submittable(cfg: &gerrit::Config, change: &SubmittableChange) -> Result<bool> {
    let response: HashMap<String, gerrit::Action> = gerrit::get(
        cfg,
        &format!(
            "/changes/{}/revisions/{}/actions",
            change.id, change.revision
        ),
    )
    .context("failed to fetch actions for change")?;

    match response.get("submit") {
        None => Ok(false),
        Some(action) => Ok(action.enabled),
    }
}

fn submitted_with(cfg: &gerrit::Config, change_id: &str) -> Result<HashSet<String>> {
    let response: Vec<gerrit::ChangeInfo> =
        gerrit::get(cfg, &format!("/changes/{}/submitted_together", change_id))
            .context("failed to fetch related change list")?;

    Ok(response.into_iter().map(|c| c.id).collect())
}

fn autosubmit(cfg: &gerrit::Config) -> Result<bool> {
    let mut submittable_changes: HashSet<String> = Default::default();

    for change in list_submittable(&cfg)? {
        if !is_submittable(&cfg, &change)? {
            continue;
        }

        submittable_changes.insert(change.id.clone());
    }

    let mut chains: BTreeMap<usize, String> = Default::default();
    for change_id in &submittable_changes {
        let ancestors = submitted_with(&cfg, &change_id)?;
        if ancestors.is_subset(&submittable_changes) {
            chains.insert(
                if ancestors.is_empty() {
                    1
                } else {
                    ancestors.len()
                },
                change_id.clone(),
            );
        }
    }

    // BTreeMap::last_key_value gives us the value associated with the
    // largest key, i.e. with the longest submittable chain of changes.
    if let Some((count, change_id)) = chains.last_key_value() {
        println!(
            "submitting change {} with chain length {}",
            change_id, count
        );

        gerrit::submit(cfg, change_id).context("while submitting")?;

        Ok(true)
    } else {
        println!("nothing ready for autosubmit, waiting ...");
        Ok(false)
    }
}

fn main() -> Result<()> {
    let cfg = gerrit::Config::from_env()?;

    loop {
        if !autosubmit(&cfg)? {
            thread::sleep(time::Duration::from_secs(30));
        }
    }
}
