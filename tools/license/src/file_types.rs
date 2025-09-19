// Copyright 2024 Otter Infrastructure
// SPDX-License-Identifier: Apache-2.0

use std::path::Path;

#[derive(Debug, Clone)]
pub struct CommentStyle {
    pub start: &'static str,
    pub middle: &'static str,
    pub end: &'static str,
}

impl CommentStyle {
    pub fn new(start: &'static str, middle: &'static str, end: &'static str) -> Self {
        Self { start, middle, end }
    }
}

pub fn get_comment_style(path: &Path) -> Option<CommentStyle> {
    let filename = path.file_name()?.to_string_lossy();
    let filename_lower = filename.to_lowercase();
    
    // Get the extension, or use the full filename if no extension
    let ext = path
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_else(|| filename_lower.clone());

    match ext.as_str() {
        // C-style block comments
        "c" | "h" => Some(CommentStyle::new("/*", " * ", " */")),
        "java" | "kt" | "kts" | "scala" => Some(CommentStyle::new("/*", " * ", " */")),
        "gv" => Some(CommentStyle::new("/*", " * ", " */")),

        // JavaScript/CSS style block comments  
        "css" | "scss" | "sass" | "less" => Some(CommentStyle::new("/**", " * ", " */")),
        "js" | "mjs" | "cjs" | "jsx" | "ts" | "tsx" => Some(CommentStyle::new("/**", " * ", " */")),

        // C++ style line comments
        "cc" | "cpp" | "cxx" | "c++" | "hh" | "hpp" | "hxx" | "h++" => Some(CommentStyle::new("", "// ", "")),
        "cs" => Some(CommentStyle::new("", "// ", "")),
        "dart" => Some(CommentStyle::new("", "// ", "")),
        "go" => Some(CommentStyle::new("", "// ", "")),
        "groovy" | "gradle" => Some(CommentStyle::new("", "// ", "")),
        "hcl" => Some(CommentStyle::new("", "// ", "")),
        "m" | "mm" => Some(CommentStyle::new("", "// ", "")),
        "php" => Some(CommentStyle::new("", "// ", "")),
        "proto" => Some(CommentStyle::new("", "// ", "")),
        "rs" => Some(CommentStyle::new("", "// ", "")),
        "swift" => Some(CommentStyle::new("", "// ", "")),
        "v" | "sv" => Some(CommentStyle::new("", "// ", "")),

        // Shell/Python style hash comments
        "awk" | "sh" | "bash" | "zsh" => Some(CommentStyle::new("", "# ", "")),
        "py" | "pyx" | "pxd" => Some(CommentStyle::new("", "# ", "")),
        "rb" | "ru" => Some(CommentStyle::new("", "# ", "")),
        "pl" => Some(CommentStyle::new("", "# ", "")),
        "tcl" => Some(CommentStyle::new("", "# ", "")),
        "yaml" | "yml" => Some(CommentStyle::new("", "# ", "")),
        "toml" => Some(CommentStyle::new("", "# ", "")),
        "tf" => Some(CommentStyle::new("", "# ", "")),
        "nix" => Some(CommentStyle::new("", "# ", "")),
        "bzl" | "bazel" => Some(CommentStyle::new("", "# ", "")),
        "dockerfile" => Some(CommentStyle::new("", "# ", "")),
        "ex" | "exs" => Some(CommentStyle::new("", "# ", "")),
        "graphql" => Some(CommentStyle::new("", "# ", "")),
        "jl" => Some(CommentStyle::new("", "# ", "")),
        "raku" => Some(CommentStyle::new("", "# ", "")),
        "pp" => Some(CommentStyle::new("", "# ", "")),

        // Lisp style semicolon comments
        "el" | "lisp" | "scm" => Some(CommentStyle::new("", ";; ", "")),

        // Erlang style percent comments
        "erl" => Some(CommentStyle::new("", "% ", "")),

        // SQL/Haskell style double dash comments
        "hs" => Some(CommentStyle::new("", "-- ", "")),
        "lua" => Some(CommentStyle::new("", "-- ", "")),
        "sql" | "sdl" => Some(CommentStyle::new("", "-- ", "")),

        // HTML/XML style comments
        "html" | "htm" | "vue" | "xml" => Some(CommentStyle::new("<!--", " ", "-->")),
        "wxi" | "wxl" | "wxs" => Some(CommentStyle::new("<!--", " ", "-->")),

        // Jinja2 style comments
        "j2" => Some(CommentStyle::new("{#", "", "#}")),

        // OCaml style comments
        "ml" | "mli" | "mll" | "mly" => Some(CommentStyle::new("(**", "   ", "*)")),

        // PowerShell style comments
        "ps1" | "psm1" => Some(CommentStyle::new("<#", " ", "#>")),

        // Vim script comments
        "vim" => Some(CommentStyle::new("", r#"" "#, "")),

        // Markdown files using HTML comments
        "md" | "markdown" => Some(CommentStyle::new("<!--", " ", "-->")),

        // Special cases for files without extensions
        _ if filename_lower == "gemfile" => Some(CommentStyle::new("", "# ", "")),
        _ if filename_lower == "dockerfile" => Some(CommentStyle::new("", "# ", "")),
        _ if filename_lower == "build" => Some(CommentStyle::new("", "# ", "")),
        _ if filename_lower.starts_with("dockerfile") => Some(CommentStyle::new("", "# ", "")),
        _ if filename_lower == "cmakelists.txt" => Some(CommentStyle::new("", "# ", "")),
        _ if filename_lower.ends_with(".cmake.in") || filename_lower.ends_with(".cmake") => {
            Some(CommentStyle::new("", "# ", ""))
        }

        // Unknown file type
        _ => None,
    }
}