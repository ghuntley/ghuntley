// Copyright (c) 2019 Vincent Ambo
// Copyright (c) 2020-2021 The TVL Authors
// SPDX-License-Identifier: MIT

use super::*;
use std::io::BufReader;

// Markdown rendering expectation, ignoring leading and trailing
// whitespace in the input and output.
fn expect_markdown(input: &str, expected: &str) {
    let mut input_buf = BufReader::new(input.trim().as_bytes());
    let mut out_buf: Vec<u8> = vec![];
    format_markdown(&mut input_buf, &mut out_buf);

    let out_string = String::from_utf8(out_buf).expect("output should be UTF8");
    assert_eq!(out_string.trim(), expected.trim());
}

#[test]
fn renders_simple_markdown() {
    expect_markdown("hello", "<p>hello</p>\n");
}

#[test]
fn renders_callouts() {
    expect_markdown(
        "TODO some task.",
        r#"<p class="cheddar-callout cheddar-todo">
TODO some task.
</p>
"#,
    );

    expect_markdown(
        "WARNING: be careful",
        r#"<p class="cheddar-callout cheddar-warning">
WARNING: be careful
</p>
"#,
    );

    expect_markdown(
        "TIP: note the thing",
        r#"<p class="cheddar-callout cheddar-tip">
TIP: note the thing
</p>
"#,
    );
}

#[test]
fn renders_code_snippets() {
    expect_markdown(
        r#"
Code:
```nix
toString 42
```
"#,
        r#"
<p>Code:</p>
<pre style="background-color:#f6f8fa;padding:16px;">
<span style="color:#62a35c;">toString </span><span style="color:#0086b3;">42
</span></pre>
"#,
    );
}

#[test]
fn highlights_bug_link() {
    expect_markdown(
        "Please look at b/123.",
        "<p>Please look at <a href=\"https://b.tvl.fyi/123\">b/123</a>.</p>",
    );
}

#[test]
fn highlights_cl_link() {
    expect_markdown(
        "Please look at cl/420.",
        "<p>Please look at <a href=\"https://cl.tvl.fyi/420\">cl/420</a>.</p>",
    );
}

#[test]
fn highlights_r_link() {
    expect_markdown(
        "Fixed in r/3268.",
        "<p>Fixed in <a href=\"https://code.tvl.fyi/commit/?id=refs/r/3268\">r/3268</a>.</p>",
    );
}

#[test]
fn highlights_multiple_shortlinks() {
    expect_markdown(
        "Please look at cl/420, b/123.",
        "<p>Please look at <a href=\"https://cl.tvl.fyi/420\">cl/420</a>, <a href=\"https://b.tvl.fyi/123\">b/123</a>.</p>",
    );

    expect_markdown(
        "b/213/cl/213 are different things",
        "<p><a href=\"https://b.tvl.fyi/213\">b/213</a>/<a href=\"https://cl.tvl.fyi/213\">cl/213</a> are different things</p>",
    );
}

#[test]
fn ignores_invalid_shortlinks() {
    expect_markdown("b/abc is not a real bug", "<p>b/abc is not a real bug</p>");
}
