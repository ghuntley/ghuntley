// Copyright (c) 2019 Vincent Ambo
// Copyright (c) 2020-2021 The TVL Authors
// SPDX-License-Identifier: MIT

//! This file implements the rendering logic of cheddar with public
//! functions for syntax-highlighting code and for turning Markdown
//! into HTML with TVL extensions.
use comrak::arena_tree::Node;
use comrak::nodes::{Ast, AstNode, NodeCodeBlock, NodeHtmlBlock, NodeValue};
use comrak::{format_html, parse_document, Arena, ComrakOptions};
use lazy_static::lazy_static;
use regex::Regex;
use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::OsStr;
use std::io::{BufRead, Write};
use std::path::Path;
use std::{env, io};
use syntect::dumps::from_binary;
use syntect::easy::HighlightLines;
use syntect::highlighting::{Theme, ThemeSet};
use syntect::parsing::{SyntaxReference, SyntaxSet};
use syntect::util::LinesWithEndings;

use syntect::html::{
    append_highlighted_html_for_styled_line, start_highlighted_html_snippet, IncludeBackground,
};

#[cfg(test)]
mod tests;

lazy_static! {
    // Load syntaxes lazily. Initialisation might not be required in
    // the case of Markdown rendering (if there's no code blocks
    // within the document).
    //
    // Note that the syntax set is included from the path pointed to
    // by the BAT_SYNTAXES environment variable at compile time. This
    // variable is populated by Nix and points to TVL's syntax set.
    static ref SYNTAXES: SyntaxSet = from_binary(include_bytes!(env!("BAT_SYNTAXES")));
    pub static ref THEMES: ThemeSet = ThemeSet::load_defaults();

    // Configure Comrak's Markdown rendering with all the bells &
    // whistles!
    static ref MD_OPTS: ComrakOptions = {
        let mut options = ComrakOptions::default();

        // Enable non-standard Markdown features:
        options.extension.strikethrough = true;
        options.extension.tagfilter = true;
        options.extension.table = true;
        options.extension.autolink = true;
        options.extension.tasklist = true;
        options.extension.header_ids = Some(String::new()); // yyeeesss!
        options.extension.footnotes = true;
        options.extension.description_lists = true;
        options.extension.front_matter_delimiter = Some("---".to_owned());

        // Required for tagfilter
        options.render.unsafe_ = true;

        options
    };

    // Configures a map of specific filenames to languages, for cases
    // where the detection by extension or other heuristics fails.
    static ref FILENAME_OVERRIDES: HashMap<&'static str, &'static str> = {
        let mut map = HashMap::new();
        // rules.pl is the canonical name of the submit rule file in
        // Gerrit, which is written in Prolog.
        map.insert("rules.pl", "Prolog");
        map
    };

    // Default shortlink set used in cheddar (i.e. TVL's shortlinks)
    static ref TVL_LINKS: Vec<Shortlink> = vec![
        // TVL shortlinks for bugs and changelists (e.g. b/123,
        // cl/123). Coincidentally these have the same format, which
        // makes the initial implementation easy.
        Shortlink {
            pattern: Regex::new(r#"\b(?P<type>b|cl)/(?P<dest>\d+)\b"#).unwrap(),
            replacement: "[$type/$dest](https://$type.tvl.fyi/$dest)",
        },
        Shortlink {
            pattern: Regex::new(r#"\br/(?P<dest>\d+)\b"#).unwrap(),
            replacement: "[r/$dest](https://code.tvl.fyi/commit/?id=refs/r/$dest)",
        }
    ];
}

/// Structure that describes a single shortlink that should be
/// automatically highlighted. Highlighting is performed as a string
/// replacement over input Markdown.
pub struct Shortlink {
    /// Short link pattern to recognise. Make sure to anchor these
    /// correctly.
    pub pattern: Regex,

    /// Replacement string, as per the documentation of
    /// [`Regex::replace`].
    pub replacement: &'static str,
}

// HTML fragment used when rendering inline blocks in Markdown documents.
// Emulates the GitHub style (subtle background hue and padding).
const BLOCK_PRE: &str = "<pre style=\"background-color:#f6f8fa;padding:16px;\">\n";

fn should_continue(res: &io::Result<usize>) -> bool {
    match *res {
        Ok(n) => n > 0,
        Err(_) => false,
    }
}

// This function is taken from the Comrak documentation.
fn iter_nodes<'a, F>(node: &'a AstNode<'a>, f: &F)
where
    F: Fn(&'a AstNode<'a>),
{
    f(node);
    for c in node.children() {
        iter_nodes(c, f);
    }
}

// Many of the syntaxes in the syntax list have random capitalisations, which
// means that name matching for the block info of a code block in HTML fails.
//
// Instead, try finding a syntax match by comparing case insensitively (for
// ASCII characters, anyways).
fn find_syntax_case_insensitive(info: &str) -> Option<&'static SyntaxReference> {
    // TODO(tazjin): memoize this lookup
    SYNTAXES
        .syntaxes()
        .iter()
        .rev()
        .find(|&s| info.eq_ignore_ascii_case(&s.name))
}

// Replaces code-block inside of a Markdown AST with HTML blocks rendered by
// syntect. This enables static (i.e. no JavaScript) syntax highlighting, even
// of complex languages.
fn highlight_code_block(code_block: &NodeCodeBlock) -> NodeValue {
    let theme = &THEMES.themes["InspiredGitHub"];
    let info = String::from_utf8_lossy(&code_block.info);

    let syntax = find_syntax_case_insensitive(&info)
        .or_else(|| SYNTAXES.find_syntax_by_extension(&info))
        .unwrap_or_else(|| SYNTAXES.find_syntax_plain_text());

    let code = String::from_utf8_lossy(&code_block.literal);

    let rendered = {
        // Write the block preamble manually to get exactly the
        // desired layout:
        let mut hl = HighlightLines::new(syntax, theme);
        let mut buf = BLOCK_PRE.to_string();

        for line in LinesWithEndings::from(&code) {
            let regions = hl.highlight(line, &SYNTAXES);
            append_highlighted_html_for_styled_line(&regions[..], IncludeBackground::No, &mut buf);
        }

        buf.push_str("</pre>");
        buf
    };

    let mut block = NodeHtmlBlock::default();
    block.literal = rendered.into_bytes();

    NodeValue::HtmlBlock(block)
}

// Supported callout elements (which each have their own distinct rendering):
enum Callout {
    Todo,
    Warning,
    Question,
    Tip,
}

// Determine whether the first child of the supplied node contains a text that
// should cause a callout section to be rendered.
fn has_callout<'a>(node: &Node<'a, RefCell<Ast>>) -> Option<Callout> {
    match node.first_child().map(|c| c.data.borrow()) {
        Some(child) => match &child.value {
            NodeValue::Text(text) => {
                if text.starts_with(b"TODO") {
                    return Some(Callout::Todo);
                } else if text.starts_with(b"WARNING") {
                    return Some(Callout::Warning);
                } else if text.starts_with(b"QUESTION") {
                    return Some(Callout::Question);
                } else if text.starts_with(b"TIP") {
                    return Some(Callout::Tip);
                }

                None
            }
            _ => None,
        },
        _ => None,
    }
}

// Replace instances of known shortlinks in the input document with
// Markdown syntax for a highlighted link.
fn linkify_shortlinks(mut text: String, shortlinks: &[Shortlink]) -> String {
    for link in shortlinks {
        text = link
            .pattern
            .replace_all(&text, link.replacement)
            .to_string();
    }

    return text;
}

fn format_callout_paragraph(callout: Callout) -> NodeValue {
    let class = match callout {
        Callout::Todo => "cheddar-todo",
        Callout::Warning => "cheddar-warning",
        Callout::Question => "cheddar-question",
        Callout::Tip => "cheddar-tip",
    };

    let mut block = NodeHtmlBlock::default();
    block.literal = format!("<p class=\"cheddar-callout {}\">", class).into_bytes();
    NodeValue::HtmlBlock(block)
}

pub fn format_markdown_with_shortlinks<R: BufRead, W: Write>(
    reader: &mut R,
    writer: &mut W,
    shortlinks: &[Shortlink],
) {
    let document = {
        let mut buffer = String::new();
        reader
            .read_to_string(&mut buffer)
            .expect("reading should work");
        buffer
    };

    let arena = Arena::new();
    let root = parse_document(&arena, &linkify_shortlinks(document, shortlinks), &MD_OPTS);

    // This node must exist with a lifetime greater than that of the parsed AST
    // in case that callouts are encountered (otherwise insertion into the tree
    // is not possible).
    let mut p_close_value = NodeHtmlBlock::default();
    p_close_value.literal = b"</p>".to_vec();

    let p_close_node = Ast::new(NodeValue::HtmlBlock(p_close_value));
    let p_close = Node::new(RefCell::new(p_close_node));

    // Special features of Cheddar are implemented by traversing the
    // arena and reacting on nodes that we might want to modify.
    iter_nodes(root, &|node| {
        let mut ast = node.data.borrow_mut();
        let new = match &ast.value {
            // Syntax highlighting is implemented by replacing the
            // code block node with literal HTML.
            NodeValue::CodeBlock(code) => Some(highlight_code_block(code)),

            NodeValue::Paragraph => {
                if let Some(callout) = has_callout(node) {
                    node.insert_after(&p_close);
                    Some(format_callout_paragraph(callout))
                } else {
                    None
                }
            }
            _ => None,
        };

        if let Some(new_value) = new {
            ast.value = new_value
        }
    });

    format_html(root, &MD_OPTS, writer).expect("Markdown rendering failed");
}

pub fn format_markdown<R: BufRead, W: Write>(reader: &mut R, writer: &mut W) {
    format_markdown_with_shortlinks(reader, writer, &TVL_LINKS)
}

fn find_syntax_for_file(filename: &str) -> &'static SyntaxReference {
    (*FILENAME_OVERRIDES)
        .get(filename)
        .and_then(|name| SYNTAXES.find_syntax_by_name(name))
        .or_else(|| {
            Path::new(filename)
                .extension()
                .and_then(OsStr::to_str)
                .and_then(|s| SYNTAXES.find_syntax_by_extension(s))
        })
        .unwrap_or_else(|| SYNTAXES.find_syntax_plain_text())
}

pub fn format_code<R: BufRead, W: Write>(
    theme: &Theme,
    reader: &mut R,
    writer: &mut W,
    filename: &str,
) {
    let mut linebuf = String::new();

    // Get the first line, we might need it for syntax identification.
    let mut read_result = reader.read_line(&mut linebuf);
    let syntax = find_syntax_for_file(filename);

    let mut hl = HighlightLines::new(syntax, theme);
    let (mut outbuf, bg) = start_highlighted_html_snippet(theme);

    // Rather than using the `lines` iterator, read each line manually
    // and maintain buffer state.
    //
    // This is done because the syntax highlighter requires trailing
    // newlines to be efficient, and those are stripped in the lines
    // iterator.
    while should_continue(&read_result) {
        let regions = hl.highlight(&linebuf, &SYNTAXES);

        append_highlighted_html_for_styled_line(
            &regions[..],
            IncludeBackground::IfDifferent(bg),
            &mut outbuf,
        );

        // immediately output the current state to avoid keeping
        // things in memory
        write!(writer, "{}", outbuf).expect("write should not fail");

        // merry go round again
        linebuf.clear();
        outbuf.clear();
        read_result = reader.read_line(&mut linebuf);
    }

    writeln!(writer, "</pre>").expect("write should not fail");
}
