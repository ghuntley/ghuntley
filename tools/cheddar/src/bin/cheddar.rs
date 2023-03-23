// Copyright (c) 2019 Vincent Ambo
// Copyright (c) 2020-2021 The TVL Authors
// SPDX-License-Identifier: MIT

//! This file defines the binary for cheddar, which can be interacted
//! with in two different ways:
//!
//! 1. As a CLI tool that acts as a cgit filter.
//! 2. As a long-running HTTP server that handles rendering requests
//!    (matching the SourceGraph protocol).
use clap::{App, Arg};
use rouille::{router, try_or_400, Response};
use serde::Deserialize;
use serde_json::json;
use std::collections::HashMap;
use std::io;

use cheddar::{format_code, format_markdown, THEMES};

// Server endpoint for rendering the syntax of source code. This
// replaces the 'syntect_server' component of Sourcegraph.
fn code_endpoint(request: &rouille::Request) -> rouille::Response {
    #[derive(Deserialize)]
    struct SourcegraphQuery {
        filepath: String,
        theme: String,
        code: String,
    }

    let query: SourcegraphQuery = try_or_400!(rouille::input::json_input(request));
    let mut buf: Vec<u8> = Vec::new();

    // We don't use syntect with the sourcegraph themes bundled
    // currently, so let's fall back to something that is kind of
    // similar (tm).
    let theme = &THEMES.themes[match query.theme.as_str() {
        "Sourcegraph (light)" => "Solarized (light)",
        _ => "Solarized (dark)",
    }];

    format_code(theme, &mut query.code.as_bytes(), &mut buf, &query.filepath);

    Response::json(&json!({
        "is_plaintext": false,
        "data": String::from_utf8_lossy(&buf)
    }))
}

// Server endpoint for rendering a Markdown file.
fn markdown_endpoint(request: &rouille::Request) -> rouille::Response {
    let mut texts: HashMap<String, String> = try_or_400!(rouille::input::json_input(request));

    for text in texts.values_mut() {
        let mut buf: Vec<u8> = Vec::new();
        format_markdown(&mut text.as_bytes(), &mut buf);
        *text = String::from_utf8_lossy(&buf).to_string();
    }

    Response::json(&texts)
}

fn highlighting_server(listen: &str) {
    println!("Starting syntax highlighting server on '{}'", listen);

    rouille::start_server(listen, move |request| {
        router!(request,
                // Markdown rendering route
                (POST) (/markdown) => {
                    markdown_endpoint(request)
                },

                // Code rendering route
                (POST) (/) => {
                    code_endpoint(request)
                },

                _ => {
                    rouille::Response::empty_404()
                },
        )
    });
}

fn main() {
    // Parse the command-line flags passed to cheddar to determine
    // whether it is running in about-filter mode (`--about-filter`)
    // and what file extension has been supplied.
    let matches = App::new("cheddar")
        .about("TVL's syntax highlighter")
        .arg(
            Arg::with_name("about-filter")
                .help("Run as a cgit about-filter (renders Markdown)")
                .long("about-filter")
                .takes_value(false),
        )
        .arg(
            Arg::with_name("sourcegraph-server")
                .help("Run as a Sourcegraph compatible web-server")
                .long("sourcegraph-server")
                .takes_value(false),
        )
        .arg(
            Arg::with_name("listen")
                .help("Address to listen on")
                .long("listen")
                .takes_value(true),
        )
        .arg(Arg::with_name("filename").help("File to render").index(1))
        .get_matches();

    if matches.is_present("sourcegraph-server") {
        highlighting_server(
            matches
                .value_of("listen")
                .expect("Listening address is required for server mode"),
        );
        return;
    }

    let filename = matches.value_of("filename").expect("filename is required");

    let stdin = io::stdin();
    let mut in_handle = stdin.lock();

    let stdout = io::stdout();
    let mut out_handle = stdout.lock();

    if matches.is_present("about-filter") && filename.ends_with(".md") {
        format_markdown(&mut in_handle, &mut out_handle);
    } else {
        format_code(
            &THEMES.themes["InspiredGitHub"],
            &mut in_handle,
            &mut out_handle,
            filename,
        );
    }
}
