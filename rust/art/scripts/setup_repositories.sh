#!/bin/bash
# Setup script for creating test repositories for Art

set -e

# Configuration
REPO_DIR="./repositories"
REPOS=("example" "demo" "test-project")

# Create repositories directory if it doesn't exist
mkdir -p "$REPO_DIR"

# Function to create a sample repository
create_repo() {
    local name=$1
    local dir="$REPO_DIR/$name"

    echo "Creating repository: $name"

    # Create directory if it doesn't exist
    if [ -d "$dir" ]; then
        echo "Repository $name already exists, skipping..."
        return 0
    fi

    # Initialize repository
    mkdir -p "$dir"
    cd "$dir"
    git init -q

    # Create a sample README.md
    cat > README.md << EOF
# $name

This is a sample repository for testing the Art Git browser.

## Features

- Sample code
- Example commits
- Test data

## Usage

This repository is intended for testing purposes only.
EOF

    # Create a sample .gitignore
    cat > .gitignore << EOF
# Compiled files
*.o
*.so
*.a
*.pyc
__pycache__/

# Editor files
.vscode/
.idea/
*.swp
*~

# OS files
.DS_Store
Thumbs.db
EOF

    # Add description
    echo "Sample $name repository for Art testing" > description

    # Create some sample code files
    mkdir -p src/

    # Create a sample Rust file
    cat > src/main.rs << EOF
//! Example application

fn main() {
    println!("Hello from $name!");

    // Calculate fibonacci numbers
    let n = 10;
    println!("Fibonacci({}) = {}", n, fibonacci(n));
}

/// Calculate the nth fibonacci number recursively
fn fibonacci(n: u32) -> u32 {
    if n <= 1 {
        n
    } else {
        fibonacci(n - 1) + fibonacci(n - 2)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fibonacci() {
        assert_eq!(fibonacci(0), 0);
        assert_eq!(fibonacci(1), 1);
        assert_eq!(fibonacci(2), 1);
        assert_eq!(fibonacci(3), 2);
        assert_eq!(fibonacci(4), 3);
        assert_eq!(fibonacci(5), 5);
    }
}
EOF

    # Create a sample Python file
    cat > src/example.py << EOF
#!/usr/bin/env python3
"""
Example Python script for testing Art Git browser
"""

def greet(name):
    """Return a greeting message"""
    return f"Hello, {name}!"

def main():
    """Main function"""
    print(greet("$name"))

    # Calculate factorial
    n = 5
    result = factorial(n)
    print(f"Factorial of {n} is {result}")

def factorial(n):
    """Calculate factorial of n recursively"""
    if n <= 1:
        return 1
    return n * factorial(n - 1)

if __name__ == "__main__":
    main()
EOF

    # Create license file
    cat > LICENSE << EOF
MIT License

Copyright (c) 2023 Art Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

    # Commit the initial files
    git add .
    git config user.name "Art Tester"
    git config user.email "art-test@example.com"
    git commit -q -m "Initial commit"

    # Make some additional changes
    mkdir -p docs
    cat > docs/getting-started.md << EOF
# Getting Started

This document provides instructions for getting started with $name.

## Installation

\`\`\`bash
git clone https://example.com/$name.git
cd $name
\`\`\`

## Usage

Run the application:

\`\`\`bash
cargo run
\`\`\`

## License

MIT License
EOF

    git add docs/getting-started.md
    git commit -q -m "Add documentation"

    # Create a branch
    git branch feature-branch

    # Make changes on main
    echo "# Additional information" >> README.md
    echo "" >> README.md
    echo "This repository is maintained by Art testers." >> README.md
    git add README.md
    git commit -q -m "Update README.md"

    # Switch to feature branch and make changes
    git checkout feature-branch
    mkdir -p tests
    cat > tests/test_main.rs << EOF
//! Tests for the main functionality

#[cfg(test)]
mod integration_tests {
    #[test]
    fn test_addition() {
        assert_eq!(2 + 2, 4);
    }

    #[test]
    fn test_subtraction() {
        assert_eq!(4 - 2, 2);
    }
}
EOF
    git add tests/test_main.rs
    git commit -q -m "Add tests"

    # Switch back to main
    git checkout main

    # Create a tag
    git tag -a v0.1.0 -m "Initial release"

    # Print summary
    echo "Repository $name created successfully."
    echo "  - Branches: $(git branch | wc -l | tr -d ' ')"
    echo "  - Tags: $(git tag | wc -l | tr -d ' ')"
    echo "  - Commits: $(git log --oneline | wc -l | tr -d ' ')"

    # Go back to original directory
    cd - > /dev/null
}

# Create example repositories
for repo in "${REPOS[@]}"; do
    create_repo "$repo"
done

echo ""
echo "All repositories created successfully in $REPO_DIR"
echo "You can now run Art to browse these repositories."
