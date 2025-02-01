# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary

# Generates a simple web view of open TODOs in the depot.
#
# Only TODOs that match the form 'TODO($username)' are considered, and
# only for users that are known to us.
{ depot, lib, pkgs, ... }:

let
  inherit (pkgs)
    jq
    ripgrep
    runCommand
    writeTextFile
    ;

  inherit (builtins)
    elem
    filter
    fromJSON
    head
    readFile
    map
    ;

  inherit (lib) concatStringsSep;

  inherit (depot.nix.yants)
    defun
    int
    string
    struct
    ;

  knownUsers = map (u: u.username) depot.users;

  todo = struct {
    file = string;
    line = int;
    todo = string;
    user = string;
  };

  allTodos = fromJSON (readFile (runCommand "depot-todos.json" { } ''
    ${ripgrep}/bin/rg --json 'TODO\(\w+\):.*$' ${depot.path} | \
      ${jq}/bin/jq -s -f ${./extract-todos.jq} > $out
  ''));

  knownUserTodos = filter (todos: elem (head todos).user knownUsers) allTodos;

  fileLink = defun [ todo string ] (t:
    ''<a style="color: inherit;"
         href="https://cs.tvl.fyi/depot/-/blob/${t.file}#L${toString t.line}">
      //${t.file}:${toString t.line}</a>'');

  todoElement = defun [ todo string ] (t: ''
    <p>${fileLink t}:</p>
    <blockquote>${t.todo}</blockquote>

  '');

  userParagraph = todos:
    let user = (head todos).user;
    in ''
      <p>
        <h3>
          <a style="color:inherit; text-decoration: none;"
             name="${user}"
             href="#${user}">${user}</a>
        </h3>
        ${concatStringsSep "\n" (map todoElement todos)}
      </p>
      <hr>
    '';

  staticUrl = "https://static.tvl.fyi/${depot.web.static.drvHash}";

in
writeTextFile {
  name = "tvl-todos";
  destination = "/index.html";
  text = ''
    <!DOCTYPE html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta name="description" content="TVL's todo-list">
      <link rel="stylesheet" type="text/css" media="all" href="${staticUrl}/tvl.css">
      <link rel="icon" type="image/webp" href="${staticUrl}/favicon.webp">
      <title>TVL's todo-list</title>
      <style>
        svg {
          max-width: inherit;
          height: auto;
        }
      </style>
    </head>
    <body class="dark">
      <header>
        <h1><a class="blog-title" href="/">The Virus Lounge's todo-list</a> </h1>
        <hr>
      </header>
      <main>
      ${concatStringsSep "\n" (map userParagraph knownUserTodos)}
      </main>
      <footer>
        <p class="footer">
          <a class="uncoloured-link" href="https://tvl.fyi">homepage</a>
          |
          <a class="uncoloured-link" href="https://cs.tvl.fyi/depot/-/blob/README.md">code</a>
          |
          <a class="uncoloured-link" href="https://cl.tvl.fyi">reviews</a>
        </p>
        <p class="lod">ಠ_ಠ</p>
      </footer>
    </body>
  '';
}
