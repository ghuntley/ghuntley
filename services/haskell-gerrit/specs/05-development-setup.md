<!--
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Development Setup

## Prerequisites
- GHC 9.2 or later
- PostgreSQL 12 or later (for PostgreSQL backend)
- SQLite 3.35.0 or later (for SQLite backend)
- Git 2.25 or later

## Database Configuration

### PostgreSQL Backend
```bash
# Environment Variables for PostgreSQL
GERRIT_DB_BACKEND=postgresql
GERRIT_DB_HOST=localhost
GERRIT_DB_NAME=gerrit
GERRIT_DB_USER=gerrit
GERRIT_DB_PASS=gerrit_password
```

### SQLite Backend
```bash
# Environment Variables for SQLite
GERRIT_DB_BACKEND=sqlite
GERRIT_DB_PATH=/path/to/gerrit.db
```

### Common Environment Variables
```bash
GERRIT_PORT=8080
GERRIT_GIT_PATH=/var/lib/gerrit/git
GERRIT_JWT_SECRET=your-secret-key
GERRIT_JWT_EXPIRY=86400
```

## Build and Run

### With PostgreSQL
```bash
# Install dependencies
cabal update
cabal build

# Set up database
createdb haskell-gerrit
cabal run migrate

# Start server
cabal run haskell-gerrit
```

### With SQLite
```bash
# Install dependencies
cabal update
cabal build

# The database file will be created automatically
# Just ensure the directory exists
mkdir -p $(dirname $GERRIT_DB_PATH)

# Start server (migrations run automatically)
cabal run haskell-gerrit
```

## Testing

### Test Suite
- Unit tests for core functionality
- Property testing with QuickCheck
- Integration tests for API endpoints
- Migration tests for database schema
- Backend-specific tests for PostgreSQL and SQLite

### Test Configuration
```haskell
data TestConfig = TestConfig
    { testDbConfig :: DatabaseConfig
    , testGitPath :: FilePath
    , testJWTConfig :: JWTConfig
    }

-- Example PostgreSQL test config
postgresTestConfig :: TestConfig
postgresTestConfig = TestConfig
    { testDbConfig = DatabaseConfig
        { dbBackend = PostgreSQL
        , dbHost = Just "localhost"
        , dbName = "gerrit_test"
        , dbUser = Just "gerrit"
        , dbPassword = Just "test_password"
        , dbPoolSize = 10
        }
    , testGitPath = "/tmp/gerrit-test/git"
    , testJWTConfig = defaultJWTConfig
    }

-- Example SQLite test config
sqliteTestConfig :: TestConfig
sqliteTestConfig = TestConfig
    { testDbConfig = DatabaseConfig
        { dbBackend = SQLite
        , dbHost = Nothing
        , dbName = "/tmp/gerrit-test/gerrit.db"
        , dbUser = Nothing
        , dbPassword = Nothing
        , dbPoolSize = 10
        }
    , testGitPath = "/tmp/gerrit-test/git"
    , testJWTConfig = defaultJWTConfig
    }
```

### Running Tests
```bash
# Run all tests
cabal test

# Run PostgreSQL-specific tests
GERRIT_DB_BACKEND=postgresql cabal test

# Run SQLite-specific tests
GERRIT_DB_BACKEND=sqlite cabal test
```
