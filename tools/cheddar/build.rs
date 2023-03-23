// Copyright (c) 2019 Vincent Ambo
// Copyright (c) 2020-2021 The TVL Authors
// SPDX-License-Identifier: MIT

//! Build script that can be used outside of Nix builds to inject the
//! BAT_SYNTAXES variable when building in development mode.
//!
//! Note that this script assumes that cheddar is in a checkout of the
//! TVL depot.

use std::process::Command;

static BAT_SYNTAXES: &str = "BAT_SYNTAXES";
static ERROR_MESSAGE: &str = r#"Failed to build syntax set.

When building during development, cheddar expects to be in a checkout
of the TVL depot. This is required to automatically build the syntax
highlighting files that are needed at compile time.

As cheddar can not automatically detect the location of the syntax
files, you must set the `BAT_SYNTAXES` environment variable to the
right path.

The expected syntax files are at //third_party/bat_syntaxes in the
depot."#;

fn main() {
    // Do nothing if the variable is already set (e.g. via Nix)
    if let Ok(_) = std::env::var(BAT_SYNTAXES) {
        return;
    }

    // Otherwise ask Nix to build it and inject the result.
    let output = Command::new("nix-build")
        .arg("-A")
        .arg("third_party.bat_syntaxes")
        // ... assuming cheddar is at //tools/cheddar ...
        .arg("../..")
        .output()
        .expect(ERROR_MESSAGE);

    if !output.status.success() {
        eprintln!(
            "{}\nNix output: {}",
            ERROR_MESSAGE,
            String::from_utf8_lossy(&output.stderr)
        );
        return;
    }

    let out_path = String::from_utf8(output.stdout)
        .expect("Nix returned invalid output after building syntax set");

    // Return an instruction to Cargo that will set the environment
    // variable during rustc calls.
    //
    // https://doc.rust-lang.org/cargo/reference/build-scripts.html#cargorustc-envvarvalue
    println!("cargo:rustc-env={}={}", BAT_SYNTAXES, out_path.trim());
}
