# Simple jq script to extract all TODO comments in the code base from
# ripgrep's JSON output.
#
# This assumes that the filter used is something like 'TODO\(\w+\):'

# Capture the username and todo entry from an input string.
def capture_todo:
  capture("TODO\\((?<user>\\w+)\\):\\s+(?<todo>.*)$");

# Construct a structure with only the fields we need to populate the
# page.
def simplify_match:
  .data as $data
  | (.data.submatches[0].match.text | capture_todo) as $capture
  | {
     file: ($data | .path.text | sub("/nix/store/.+-depot/"; "")),
     line: ($data | .line_number),
     todo: ($capture | .todo),
     user: ($capture | .user),
     };

# Group all matches first by the user and return them in sorted order
# by the file in which they appear. This matches the presentation
# order on the website.
def group_by_user: .
    | group_by(.user)
    | map(sort_by(.file));

# main:
map(select(.type == "match") | simplify_match) | group_by_user
