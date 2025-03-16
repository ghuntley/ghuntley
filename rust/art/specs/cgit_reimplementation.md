# Technical Specifications: Cgit Re-implementation

## Overview
This document outlines the technical specifications for a re-implementation of the cgit Git repository browser. The implementation will use the gitoxide library for Git operations and provide a modern, efficient web interface for Git repositories.

## Features

### Core Git Functionality
- Built on [gitoxide](https://github.com/GitoxideLabs/gitoxide), a pure Rust implementation of Git
- Support for all standard Git operations through a web interface
- Git push via HTTPS with authentication support
- Repository cloning via HTTPS

### Repository Browser Features
1. **Commit History Viewer**
   - Chronological list of commits with author, date, and commit message
   - Pagination support for large repositories
   - Branch selection for viewing branch-specific history
   - Support for filtering commits by author, date range, and search terms

2. **Commit Tree Visualization**
   - Graphical representation of the commit tree showing branching and merging
   - Interactive navigation through the commit tree
   - Ability to visualize the relationship between branches and commits

3. **File Browser**
   - Directory structure navigation
   - File content viewing with syntax highlighting
   - Support for viewing different versions of files at specific commits
   - README rendering with Markdown support
   - Support for displaying binary files (images, PDFs) when possible

4. **Blame View**
   - Line-by-line attribution of changes to specific commits and authors
   - Integrated with commit history for easy navigation to the relevant commit
   - Visual indication of code age and authorship

5. **Diff Viewer**
   - Side-by-side and unified diff views
   - Syntax highlighting in diffs
   - Ability to view changes between arbitrary commits, branches, or tags

### Performance Optimizations

#### SQLite Metadata Storage
- Store repository metadata in SQLite database:
  - Commits (hash, author, date, message, parent commits)
  - Branches (name, head commit)
  - Tags (name, target, message, tagger)
  - File tree structure for quick navigation
  - Blame information for frequently accessed files

#### Metadata Reindexing
- Configurable reindexing interval (default: 5 minutes)
- Background process to update database when repository changes
- Smart detection of repository changes to avoid unnecessary reindexing
- Expected performance improvement: up to 97% faster load times for large repositories

#### In-Memory Cache
- Cache for rendered READMEs, improving load times for repository homepages
- Diff caching for frequently accessed comparisons
- LRU (Least Recently Used) cache eviction policy
- Configurable cache size limits

### Code Visualization

#### Syntax Highlighting
- Support for popular programming languages:
  - Rust, C, C++, Python, JavaScript, TypeScript, Go, Java, Ruby
  - HTML, CSS, XML, JSON, YAML, TOML
  - Bash, PowerShell, and other shell scripts
  - Markdown, ReStructuredText
- Theme support for light and dark modes
- Line numbering and code folding

#### Markdown Rendering
- GitHub-flavored Markdown support
- Syntax highlighting in code blocks
- Support for tables, diagrams, and other extended Markdown features

### Web Interface

#### Frontend Requirements
- Responsive design for desktop and mobile devices
- Accessibility compliance
- Support for modern browsers (Chrome, Firefox, Safari, Edge)
- Progressive enhancement for older browsers

#### Backend Requirements
- RESTful API for all operations
- JSON responses for easy integration with other tools
- Authentication and authorization for sensitive operations
- Rate limiting to prevent abuse

## Technical Architecture

### Component Structure
1. **Git Backend**
   - Gitoxide integration layer
   - Repository access and management
   - Git operation handlers

2. **Database Layer**
   - SQLite schema design
   - Query optimization
   - Migration management

3. **Caching System**
   - In-memory cache implementation
   - Cache invalidation strategies
   - Cache size management

4. **Web Server**
   - HTTP(S) server implementation
   - Request routing
   - Authentication middleware
   - Static file serving

5. **Frontend**
   - HTML templates
   - CSS styling
   - JavaScript for interactive elements
   - Web components for reusable UI elements

### Data Flow
1. User requests repository information
2. System checks in-memory cache for requested data
3. If not in cache, system queries SQLite database
4. If not in database or data is stale, system uses gitoxide to retrieve from Git repository
5. Data is processed, cached, and returned to user

## Configuration

### Repository Settings
- Repository path configuration
- Branch display preferences
- README rendering options
- Default view settings

### System Settings
- Cache size limits
- Reindexing interval (default: 5 minutes)
- Authentication methods
- HTTPS certificate configuration
- Rate limiting thresholds

## Deployment Considerations

### System Requirements
- Rust compiler (stable channel)
- SQLite 3.x
- Git repositories with read access (write access for push functionality)
- Sufficient disk space for SQLite database

### Security Considerations
- Authentication for write operations
- Input sanitization to prevent XSS and injection attacks
- Rate limiting to prevent DoS attacks

## Development Roadmap

### Phase 1: Core Functionality
- Repository browsing (files, commits)
- Basic syntax highlighting
- SQLite integration
- Initial caching mechanism

### Phase 2: Advanced Features
- Blame view
- Commit tree visualization
- Advanced syntax highlighting
- Markdown rendering

### Phase 3: Performance Optimization
- Cache tuning
- Query optimization
- Reindexing strategy refinement

### Phase 4: Git Push and Authentication
- HTTPS push support
- Authentication integration
- Repository write operations

## Testing Strategies
- Unit tests for core components
- Integration tests for Git operations
- Performance benchmarks against original cgit
- Security testing for authentication and authorization
- Browser compatibility testing
