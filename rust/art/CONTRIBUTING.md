# Contributing to Art

Thank you for considering contributing to Art! This document provides guidelines and instructions for contributing to the project.

## Code of Conduct

Please be respectful and considerate when contributing to this project. We aim to foster an inclusive and welcoming community.

## How to Contribute

There are many ways to contribute to Art:

1. Reporting bugs
2. Suggesting enhancements
3. Writing documentation
4. Submitting code changes
5. Reviewing pull requests

## Development Setup

### Prerequisites

- Rust 1.70+ (with Cargo)
- Git
- SQLite development libraries

### Getting Started

1. Fork the repository on GitHub
2. Clone your fork locally:
```bash
git clone https://github.com/your-username/art.git
cd art
```

3. Add the original repository as an upstream remote:
```bash
git remote add upstream https://github.com/original-owner/art.git
```

4. Create a new branch for your changes:
```bash
git checkout -b feature/your-feature-name
```

### Running Tests

Run the regular tests:
```bash
cargo test
```

Run the integration tests:
```bash
# First, create test repositories
./scripts/setup_repositories.sh

# Then run the ignored tests
cargo test -- --ignored
```

## Code Style

- Follow the Rust style guidelines from the Rust Book.
- Use `cargo fmt` to format your code.
- Run `cargo clippy` to check for common mistakes.

## Making Changes

1. Make your changes to the codebase.
2. Write or update tests for the changes made.
3. Run the tests to ensure they pass.
4. Add documentation for new features or changes.
5. Commit your changes with a descriptive message:
```bash
git commit -m "feat: add new feature X"
```

Follow the [Conventional Commits](https://www.conventionalcommits.org/) format for commit messages:
- `feat:` for new features
- `fix:` for bug fixes
- `docs:` for documentation changes
- `style:` for formatting changes
- `refactor:` for code changes that neither add features nor fix bugs
- `test:` for adding or updating tests
- `chore:` for changes to the build process or auxiliary tools

## Submitting Changes

1. Push your changes to your fork:
```bash
git push origin feature/your-feature-name
```

2. Create a pull request from your fork to the original repository.
3. Describe the changes made and any issues addressed.
4. Wait for a maintainer to review your pull request.

## Pull Request Process

1. Ensure that all tests pass.
2. Update the documentation with details of changes if needed.
3. The pull request will be merged once it has been approved by a maintainer.

## Building Documentation

Generate and read the code documentation:
```bash
cargo doc --open
```

## Project Structure

- `src/`: Source code
  - `config.rs`: Configuration handling
  - `data/`: Data layer (Git, SQLite, cache)
  - `error.rs`: Error types
  - `http/`: HTTP server and routes
  - `template/`: Template rendering
  - `util/`: Utility functions
- `templates/`: HTML templates
- `static/`: Static assets (CSS, JavaScript)
- `tests/`: Integration tests
- `scripts/`: Helper scripts

## License

By contributing to Art, you agree that your contributions will be licensed under the project's MIT License.
