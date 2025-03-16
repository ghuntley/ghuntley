# Art: Git Operations

## Overview

Art provides support for Git operations over HTTPS, allowing users to clone, fetch, and push to repositories using standard Git clients. This document outlines the specifications for implementing Git protocol support, focusing on the Smart HTTP protocol implementation and repository maintenance best practices.

## Supported Git Operations

Art will support the following Git operations:

1. **Git Clone** - Allow users to clone repositories via HTTPS
2. **Git Fetch** - Support fetching updates from repositories
3. **Git Pull** - Enable pulling changes (fetch + merge/rebase)
4. **Git Push** - Support pushing changes to repositories
5. **Git LFS** - Basic support for Git Large File Storage protocol

## Git Repository Maintenance

Art implements routine Git repository maintenance following best practices for optimal performance:

### Automatic Maintenance Tasks

1. **Garbage Collection** - Regular `git gc` operations to clean up unnecessary files and optimize the repository
2. **Repacking** - Periodic `git repack` to consolidate loose objects into efficient packfiles
3. **Reference Updates** - Pruning of stale references and optimizing reference lookups
4. **Reflog Expiration** - Cleaning up obsolete reflog entries to reduce repository size
5. **Loose Object Cleanup** - Removing unreachable loose objects
6. **Pack File Optimization** - Creating optimal pack files with delta compression

### Maintenance Schedule

- **Light Maintenance**: Runs daily or after a configurable number of push operations
- **Full Maintenance**: Runs weekly or when repository metrics indicate the need
- **Emergency Maintenance**: Triggered if repository performance degrades beyond thresholds

### Maintenance Task Details

#### Git Garbage Collection

```bash
git gc --auto --prune=now
```

- Collects garbage and removes unreferenced objects
- Automatically determines if collection is necessary
- Prunes objects that are no longer reachable

#### Git Repacking

```bash
git repack -ad
```

- Creates new pack files with all objects (`-a`)
- Removes redundant pack files after repacking (`-d`)
- Optimizes pack file structure for performance

#### Delta Compression Optimization

```bash
git repack -Ad --window=250 --depth=250
```

- Aggressively optimize delta compression (`-A`)
- Remove redundant packs (`-d`)
- Use larger window and depth settings for better compression

### Post-Push Hooks

After each Git push operation:

1. Update SQLite metadata cache with new commit information
2. Expire relevant in-memory cache entries
3. Check if light maintenance tasks should be triggered
4. Update file tree information in the database

## Smart HTTP Protocol Implementation

Art will implement the Git Smart HTTP protocol, which is more efficient than the older "dumb" HTTP protocol. The Smart HTTP protocol supports bidirectional communication between client and server.

### Smart HTTP Endpoints

```
GET  /repo-name.git/info/refs?service=git-upload-pack    # For clone/fetch/pull
POST /repo-name.git/git-upload-pack                      # For clone/fetch/pull
GET  /repo-name.git/info/refs?service=git-receive-pack   # For push
POST /repo-name.git/git-receive-pack                     # For push
```

### Response Content Types

- `application/x-git-upload-pack-advertisement`
- `application/x-git-receive-pack-advertisement`
- `application/x-git-upload-pack-result`
- `application/x-git-receive-pack-result`

## Authentication and Authorization

Git operations will be secured using the following mechanisms:

### Authentication Methods

1. **HTTP Basic Authentication**
   - Username/password for basic authentication
   - Transmitted over HTTPS for security
   - Support for credential helpers in Git clients

2. **Token-based Authentication**
   - Long-lived tokens for automation and CI/CD
   - Passed as username with empty password or via HTTP header

### Authorization Controls

- Repository-level access control (read/write permissions)
- Branch protection rules for restricted branches
- User and group-based permission management
- Support for public repositories (no authentication for read access)

## Implementation Architecture

Art will implement Git operations using a layered approach:

```
┌─────────────────────────────────────────────────────────────┐
│                    HTTP Request Handler                     │
│                                                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  │
│  │     Authentication      │  │      Authorization      │  │
│  │        Handler          │  │         Handler         │  │
│  └─────────────────────────┘  └─────────────────────────┘  │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                    Git Protocol Service                      │
│                                                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  │
│  │    Git Upload Pack      │  │    Git Receive Pack     │  │
│  │        Service          │  │        Service          │  │
│  └─────────────────────────┘  └─────────────────────────┘  │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                    Git Repository Access                     │
│                                                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  │
│  │      Read Access        │  │      Write Access       │  │
│  │    (gitoxide impl)      │  │    (gitoxide impl)      │  │
│  └─────────────────────────┘  └─────────────────────────┘  │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                  Repository Maintenance                      │
│                                                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐  │
│  │    Routine Tasks        │  │    Performance          │  │
│  │    (GC, Repack)         │  │     Monitoring          │  │
│  └─────────────────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Implementation Components

1. **HTTP Request Handler**
   - Parses Git-specific HTTP requests
   - Routes to appropriate Git service
   - Manages content negotiation

2. **Authentication Handler**
   - Validates user credentials
   - Implements authentication methods
   - Manages authentication failures

3. **Authorization Handler**
   - Checks repository access permissions
   - Enforces branch protection rules
   - Validates reference permissions

4. **Git Protocol Services**
   - Implements Git upload-pack (for fetch/clone)
   - Implements Git receive-pack (for push)
   - Handles protocol negotiation

5. **Git Repository Access**
   - Uses gitoxide to access repositories
   - Handles object packing and transfer
   - Manages reference updates

6. **Repository Maintenance**
   - Schedules and executes maintenance tasks
   - Monitors repository performance metrics
   - Triggers maintenance based on repository state

## Request and Response Flow

### Clone/Fetch Flow

1. Client initiates request to `/repo-name.git/info/refs?service=git-upload-pack`
2. Server authenticates user (if required)
3. Server authorizes repository access
4. Server responds with reference advertisement
5. Client requests specific objects via POST to `/repo-name.git/git-upload-pack`
6. Server packs and returns requested objects
7. Client updates local repository

### Push Flow

1. Client initiates request to `/repo-name.git/info/refs?service=git-receive-pack`
2. Server authenticates user
3. Server authorizes repository write access
4. Server responds with reference advertisement
5. Client sends packfile via POST to `/repo-name.git/git-receive-pack`
6. Server unpacks objects and verifies them
7. Server updates references
8. Server returns success/failure response
9. Server triggers post-receive hooks
10. Server updates SQLite database cache
11. Server invalidates in-memory cache entries
12. Server schedules maintenance tasks if needed

## Integration with gitoxide

Art will use the gitoxide library for implementing Git functionality:

1. **Repository Access**
   - Use gitoxide's repository access APIs
   - Implement custom handling for Art's directory structure

2. **Object Transfer**
   - Leverage gitoxide's packfile generation
   - Use efficient transfer encoding

3. **Reference Management**
   - Update references using gitoxide APIs
   - Implement atomic reference updates

4. **Repository Maintenance**
   - Utilize gitoxide's maintenance capabilities
   - Implement performance-focused maintenance tasks

## Server-side Hooks

Art will support server-side Git hooks:

1. **pre-receive** - Run before references are updated
2. **update** - Run for each updated reference
3. **post-receive** - Run after all references are updated
   - Update SQLite database with new repository metadata
   - Invalidate relevant in-memory cache entries
   - Schedule maintenance tasks if needed

### Hook Execution Flow

1. Hook is triggered by Git operation
2. Hook code executes in isolated environment
3. Hook can accept or reject the operation
4. Results are logged and returned to client
5. Post-receive hooks update caches and schedule maintenance

## Security Considerations

### Transport Security

- All Git operations must use HTTPS
- Support for strong TLS ciphers
- HTTP Strict Transport Security (HSTS)

### Input Validation

- Validate all repository paths
- Sanitize reference names
- Verify packfile integrity

### Rate Limiting

- Implement per-user rate limits
- Apply connection limits for large repositories
- Protect against denial of service

### Audit Logging

- Log all Git operations using the tracing crate
- Record authentication attempts
- Track reference changes

## Performance Considerations

### Connection Handling

- Keep-alive connections for multiple requests
- Efficient connection pooling
- Timeout management

### Object Packing

- Optimize packfile generation
- Use delta compression
- Implement pack reuse when possible

### Pack File Optimization

- Repack with appropriate window and depth settings
- Monitor packfile efficiency
- Schedule repacks based on repository metrics

### Concurrent Operations

- Handle multiple simultaneous Git operations
- Implement appropriate locking mechanisms
- Manage resource usage during peak operations

### Performance Monitoring

- Track Git operation latency
- Monitor repository size and growth
- Measure packfile efficiency
- Detect performance degradation

## Client Compatibility

Art will ensure compatibility with:

- Git command line client (version 2.x+)
- Git GUI clients (GitKraken, SourceTree, etc.)
- IDE Git integrations (VS Code, JetBrains IDEs, etc.)
- Git libraries used in automation

## Testing Strategy

### Functional Testing

- Test all Git operations (clone, fetch, push)
- Verify authentication and authorization
- Test concurrent operations

### Performance Testing

- Measure operation performance with large repositories
- Test with various network conditions
- Evaluate resource usage under load

### Compatibility Testing

- Test with various Git client versions
- Verify behavior with common Git tools
- Ensure protocol conformance

## Monitoring and Metrics

### Git Operation Metrics

- Operation counts (clone, fetch, push)
- Operation latency
- Error rates
- Authentication success/failure rates

### Repository Metrics

- Repository size
- Number of objects
- Packfile efficiency
- Reference count

### Maintenance Metrics

- Maintenance task execution time
- Objects cleaned up
- Space reclaimed
- Pack compression ratio

All metrics will be exposed via the Prometheus endpoint for monitoring and alerting.

## Limitations and Considerations

- Maximum repository size recommendations
- Git LFS support limitations
- Handling of very large pushes/pulls
- Recommended client configurations

## Integration with Repository Browser

Git operations will be integrated with the repository browser:

- Display clone URLs prominently
- Show push/pull instructions
- Update repository browser after successful push
- Invalidate caches for affected content

## Future Enhancements

Potential enhancements for future versions:

- Enhanced Git LFS support
- Push notifications for repository updates
- Advanced branch protection rules
- Merge request integration
- Webhooks for Git operations
