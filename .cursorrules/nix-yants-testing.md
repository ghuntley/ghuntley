name: Nix Yants Testing Format
description: Rules for writing tests using yants testing library
tags: [nix, testing, yants]
files: ["*/tests/default.nix"]

# Yants Testing Format

When writing tests using yants, follow these conventions:

1. Basic test file structure:
```nix
{ depot, pkgs, ... }:

let
  inherit (pkgs) lib;
  inherit (depot.nix.runTestsuite)
    runTestsuite
    it
    assertEq
    assertThrows;

  # Import the module being tested
  module = import ../default.nix { inherit depot pkgs; };

  # Test suite structure
  testSuiteName = it "descriptive test suite name" [
    # Individual test cases go here
  ];

in
runTestsuite "module-name" [ testSuiteName ]
```

2. Test case patterns:

Testing values:
```nix
(assertEq "descriptive test name"
  expectedValue
  actualValue)
```

Testing for failures:
```nix
(assertThrows "descriptive failure test name"
  (expression that should fail))
```

3. When testing derivations:
```nix
# Create mock derivations for testing
mockDrv = pkgs.runCommand "mock-name" {} ''
  mkdir -p $out/expected/path
  echo "mock content" > $out/expected/path/file
'';

# Test derivation outputs
(assertEq "test derivation output"
  "expected-value"
  (builtins.readFile "${derivation}/path/to/output"))
```

4. Best practices:
- Place tests in a test/ subdirectory
- Name the main test file default.nix
- Group related tests into test suites using `it`
- Write descriptive test names that explain the expectation
- Add comments explaining complex test setups
- Mock external dependencies when needed
- Handle error cases gracefully

5. Common patterns:
```nix
# Testing file existence
(assertEq "file exists"
  true
  (builtins.pathExists "${drv}/path/to/file"))

# Testing command output
(let
  result = builtins.readFile (
    pkgs.runCommand "test-output" {
      nativeBuildInputs = [ dependencies ];
    } ''
      ${command} > $out
    ''
  );
in
  assertEq "command output matches"
    expectedOutput
    result)
```

6. Test organization:
- Group related tests into logical suites
- Order tests from simple to complex
- Include both positive and negative test cases
- Test edge cases and error conditions
- Document test dependencies and setup requirements

7. Running tests:
```bash
# Run tests for a specific module
depot build //path/to/tests

# Example:
depot build //nix/harmonia/tests

# The test will:
# 1. Build and evaluate all test cases
# 2. Report success or failure for each test
# 3. Show detailed error messages for failures
# 4. Exit with non-zero status if any test fails
```
