name: Nix Documentation Format
description: Rules for documenting Nix files
tags: [nix, documentation, style]
files: ["*.nix"]

# Nix Documentation Format

When documenting Nix files, follow these conventions:

1. Module-level documentation goes at the top of the file after the license header:
```nix
# Copyright notice...
# SPDX-License...

# One-line description of the module's purpose.
#
# Longer description if needed, explaining key concepts.
#
# Example:
#   let
#     foo = ...;
#   in
#     # Example usage
#     foo arg
```

2. Function documentation goes immediately above the function:
```nix
# functionName :: type1 -> type2
#
# One-line description of what the function does.
#
# Arguments:
#   arg1: Description of first argument
#   arg2: Description of second argument
#
# Returns:
#   Description of return value
#
# Example:
#   functionName arg1 arg2
functionName = arg1: arg2: ...
```

3. Important implementation details should be documented inline:
```nix
let
  # Explanation of why this value is needed
  someValue = 42;
in
```

4. Always include:
- Type signature (if applicable)
- Description
- Arguments (if any)
- Return value (if applicable)
- Example usage

5. Keep documentation concise but complete - every exported value should be documented.
