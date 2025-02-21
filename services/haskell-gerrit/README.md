# Haskell Gerrit

A Haskell implementation of a Gerrit-like code review system.

## Features

- Git repository management
- Code review workflow
- Inline commenting system
- User authentication and authorization
- REST API for client interactions
- Project and permission management

## Architecture

The system is built using:

- Servant for REST API
- Persistent for database management
- Git-simple for Git operations
- Yesod for web interface
- JWT for authentication
- PostgreSQL for data storage

## Development Setup

1. Install dependencies:
   ```bash
   cabal update
   cabal build
   ```

2. Set up the database:
   ```bash
   createdb haskell-gerrit
   cabal run migrate
   ```

3. Run the development server:
   ```bash
   cabal run haskell-gerrit
   ```

## Project Structure

```
src/
├── Api/           # REST API endpoints
├── Core/          # Core business logic
├── Database/      # Database models and migrations
├── Git/           # Git integration
├── Models/        # Data models
└── Web/           # Web interface
```

## License

MIT License - See LICENSE file for details

<!--
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->
