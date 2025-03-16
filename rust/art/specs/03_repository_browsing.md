# Art: Repository Browsing

## Overview

Repository browsing is a core functionality of Art, providing users with the ability to explore Git repositories, view files, navigate directories, examine commit history, and see detailed commit information. This document outlines the specifications for the repository browsing features.

## Repository Index

The repository index is the main entry point that displays all available repositories.

### Features

- List all repositories with key metadata
- Sort by name, last updated, or description
- Filter repositories by name or other criteria
- Display repository descriptions and last activity
- Show repository owner and creation date
- Support pagination for large repository lists

### UI Elements

```
┌─────────────────────────────────────────────────────────────────┐
│ Repository Index                                       [Search] │
├─────────────────────────────────────────────────────────────────┤
│ Name                    Description         Last Update  Owner  │
├─────────────────────────────────────────────────────────────────┤
│ project-alpha           Main project repo   2023-06-15   alice  │
│ project-beta            Beta testing repo   2023-06-10   bob    │
│ documentation           Project docs        2023-06-05   carol  │
│ ...                                                             │
└─────────────────────────────────────────────────────────────────┘
```

## Repository Home

The repository home page displays an overview of a specific repository.

### Features

- Repository name, description, and URL
- README content (rendered Markdown)
- Recent commits summary
- Branch and tag information
- Clone URL information
- Repository statistics (commits, contributors, size)

### UI Elements

```
┌─────────────────────────────────────────────────────────────────┐
│ project-alpha                                                   │
│ Main project repository for Alpha team                          │
├─────────────────────────────────────────────────────────────────┤
│ [Files] [Commits] [Branches] [Tags] [About]                     │
├─────────────────────────────────────────────────────────────────┤
│ Clone: https://git.example.com/project-alpha.git                │
├─────────────────────────────────────────────────────────────────┤
│ README.md                                                       │
│ ═════════                                                       │
│                                                                 │
│ # Project Alpha                                                 │
│                                                                 │
│ This is the main repository for Project Alpha...                │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ Recent Commits                                                  │
│ ──────────────                                                  │
│ • Fix bug in module X (alice, 2 hours ago)                      │
│ • Update dependencies (bob, 1 day ago)                          │
│ • Add new feature Y (carol, 3 days ago)                         │
└─────────────────────────────────────────────────────────────────┘
```

## File Browser

The file browser allows users to navigate through directories and view file contents.

### Features

- Directory structure navigation
- Breadcrumb navigation showing current path
- File content viewing with syntax highlighting
- File metadata (size, last updated, etc.)
- Raw file download
- Ability to view specific revisions of files
- Support for viewing binary files when possible

### UI Elements

```
┌─────────────────────────────────────────────────────────────────┐
│ project-alpha/src/main.rs @ main                                │
├─────────────────────────────────────────────────────────────────┤
│ [Files] [Commits] [Branches] [Tags] [About]                     │
├─────────────────────────────────────────────────────────────────┤
│ Path: / src / main.rs                                 [Raw]     │
├─────────────────────────────────────────────────────────────────┤
│ 1  fn main() {                                                  │
│ 2      println!("Hello, world!");                               │
│ 3      run_app();                                               │
│ 4  }                                                            │
│ 5                                                               │
│ 6  fn run_app() {                                               │
│ 7      // Application logic here                                │
│ 8  }                                                            │
└─────────────────────────────────────────────────────────────────┘
```

### Directory View

```
┌─────────────────────────────────────────────────────────────────┐
│ project-alpha/src @ main                                        │
├─────────────────────────────────────────────────────────────────┤
│ [Files] [Commits] [Branches] [Tags] [About]                     │
├─────────────────────────────────────────────────────────────────┤
│ Path: / src /                                                   │
├─────────────────────────────────────────────────────────────────┤
│ Name                 Last Commit                      Size      │
├─────────────────────────────────────────────────────────────────┤
│ 📁 models/           Update models (2 days ago)        -        │
│ 📁 controllers/      Add new controller (1 week ago)   -        │
│ 📁 utils/            Fix utility function (3 days ago) -        │
│ 📄 main.rs           Initial commit (1 month ago)     2.3 KB    │
│ 📄 config.rs         Update config (5 days ago)       1.1 KB    │
│ 📄 errors.rs         Add error handling (2 weeks ago) 3.7 KB    │
└─────────────────────────────────────────────────────────────────┘
```

## Commit History

The commit history view shows a list of commits for a repository.

### Features

- Chronological list of commits
- Pagination for large commit histories
- Filter by branch or tag
- Search commit messages
- Show commit author, date, and message
- Display commit hash
- Link to commit details

### UI Elements

```
┌─────────────────────────────────────────────────────────────────┐
│ project-alpha: Commits                                          │
├─────────────────────────────────────────────────────────────────┤
│ [Files] [Commits] [Branches] [Tags] [About]                     │
├─────────────────────────────────────────────────────────────────┤
│ Branch: main                                      [Filter: ▼]   │
├─────────────────────────────────────────────────────────────────┤
│ a1b2c3d • Fix bug in module X                                   │
│ Author: Alice <alice@example.com>                               │
│ Date: June 15, 2023, 14:30                                      │
├─────────────────────────────────────────────────────────────────┤
│ e5f6g7h • Update dependencies                                   │
│ Author: Bob <bob@example.com>                                   │
│ Date: June 14, 2023, 10:15                                      │
├─────────────────────────────────────────────────────────────────┤
│ i9j0k1l • Add new feature Y                                     │
│ Author: Carol <carol@example.com>                               │
│ Date: June 12, 2023, 09:45                                      │
├─────────────────────────────────────────────────────────────────┤
│ ... more commits ...                            [Next Page ▶]   │
└─────────────────────────────────────────────────────────────────┘
```

## Commit Detail

The commit detail view shows detailed information about a specific commit.

### Features

- Complete commit message
- Author information
- Committer information (if different from author)
- Commit date and time
- Parent commit(s)
- File changes summary
- Detailed diff view
- Navigate to previous/next commit

### UI Elements

```
┌─────────────────────────────────────────────────────────────────┐
│ project-alpha: Commit a1b2c3d                                   │
├─────────────────────────────────────────────────────────────────┤
│ [Files] [Commits] [Branches] [Tags] [About]                     │
├─────────────────────────────────────────────────────────────────┤
│ Commit: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t                │
│ Author: Alice <alice@example.com>                               │
│ Date: June 15, 2023, 14:30                                      │
│ Parents: e5f6g7h (main)                                         │
├─────────────────────────────────────────────────────────────────┤
│ Fix bug in module X                                             │
│                                                                 │
│ This commit fixes a critical bug in the X module that caused    │
│ errors when processing large inputs. The issue was related to   │
│ buffer overflow in the parsing function.                        │
├─────────────────────────────────────────────────────────────────┤
│ Changed Files                                                   │
│ • src/modules/x.rs (+15, -7)                                    │
│ • tests/x_test.rs (+23, -0)                                     │
├─────────────────────────────────────────────────────────────────┤
│ Diff: src/modules/x.rs                                          │
│ @@ -35,14 +35,22 @@                                            │
│  fn parse_input(input: &str) -> Result<ParsedData, Error> {     │
│ -    let buffer = [0; 256];                                     │
│ +    let mut buffer = Vec::with_capacity(input.len() * 2);      │
│      ...                                                         │
└─────────────────────────────────────────────────────────────────┘
```

## Blame View

The blame view shows line-by-line commit information for a file.

### Features

- Line-by-line commit attribution
- Show commit hash, author, and date per line
- Link to commit details
- Syntax highlighting for file content
- Option to view previous versions of the file
- Navigation between file revisions

### UI Elements

```
┌─────────────────────────────────────────────────────────────────┐
│ project-alpha: Blame src/main.rs                                │
├─────────────────────────────────────────────────────────────────┤
│ [Files] [Commits] [Branches] [Tags] [About]                     │
├─────────────────────────────────────────────────────────────────┤
│ Path: / src / main.rs                                  [Raw]    │
├─────────────────────────────────────────────────────────────────┤
│ a1b2c3d Alice  2023-06-15 │ 1  fn main() {                      │
│ a1b2c3d Alice  2023-06-15 │ 2      println!("Hello, world!");   │
│ e5f6g7h Bob    2023-06-10 │ 3      run_app();                   │
│ a1b2c3d Alice  2023-06-15 │ 4  }                                │
│                           │ 5                                    │
│ i9j0k1l Carol  2023-06-05 │ 6  fn run_app() {                   │
│ i9j0k1l Carol  2023-06-05 │ 7      // Application logic here    │
│ i9j0k1l Carol  2023-06-05 │ 8  }                                │
└─────────────────────────────────────────────────────────────────┘
```

## Branch and Tag Views

Views for browsing branches and tags in the repository.

### Features

- List all branches/tags
- Show latest commit for each branch/tag
- Display creation date
- Allow filtering and searching
- Navigate to branch/tag content

### UI Elements

```
┌─────────────────────────────────────────────────────────────────┐
│ project-alpha: Branches                                         │
├─────────────────────────────────────────────────────────────────┤
│ [Files] [Commits] [Branches] [Tags] [About]                     │
├─────────────────────────────────────────────────────────────────┤
│ Name               Last Commit                     Updated      │
├─────────────────────────────────────────────────────────────────┤
│ main               Fix bug in module X (a1b2c3d)   2023-06-15  │
│ develop            Add test cases (m4n5o6p)        2023-06-14  │
│ feature/new-ui     Update UI components (q7r8s9t)  2023-06-10  │
│ bugfix/issue-123   Fix critical issue (u1v2w3x)    2023-06-05  │
└─────────────────────────────────────────────────────────────────┘
```

## Data Sources and Processing

### Repository Metadata

Repository metadata is stored in SQLite for fast access and includes:

- Repository name and description
- Owner information
- Creation date
- Last updated timestamp
- Default branch
- List of branches and tags
- Access permissions

### File Content Retrieval

File content is retrieved from Git repositories using the gitoxide library:

1. Request for a file arrives with path and revision information
2. Check cache for the content
3. If not cached, retrieve from repository using gitoxide
4. Apply syntax highlighting using a syntax highlighting library
5. Cache the highlighted content for future requests
6. Return to the user

### Commit History Processing

Commit history is processed as follows:

1. Request for commit history arrives with pagination parameters
2. Check SQLite metadata for commit basic information
3. Retrieve additional details from Git repository as needed
4. Format commit information for display
5. Cache results for subsequent requests
6. Return paginated results to the user

## Performance Optimizations

### Lazy Loading

- Implement lazy loading for commit details
- Defer loading of file diffs until requested
- Use pagination for large result sets

### Caching Strategy

- Cache rendered file content
- Cache syntax highlighted output
- Cache commit history pages
- Cache README renderings
- Use appropriate cache invalidation on repository updates

### Database Indexing

- Index repository metadata for fast lookups
- Optimize queries for commit history retrieval
- Use efficient search algorithms for filtering

## Responsive Design

The repository browsing interface will be designed to work on various screen sizes:

### Desktop

- Full feature set with expanded layout
- Side-by-side diff views
- Detailed metadata displays

### Tablet

- Adaptive layout with reorganized columns
- Collapsible sections for less important metadata
- Touch-friendly navigation

### Mobile

- Simplified views with essential information
- Stacked layouts instead of side-by-side
- Optimized touch targets for navigation

## Accessibility

The repository browsing interface will be designed with accessibility in mind:

- Semantic HTML structure
- Keyboard navigation support
- ARIA attributes for screen readers
- Sufficient color contrast
- Text resizing support
- Alternative text for visual elements

## Error Handling

The system will handle various error conditions gracefully:

- Repository not found
- File not found
- Invalid path
- Access denied
- Repository corruption
- Large file handling

Error messages will be clear, user-friendly, and actionable.

## Implementation Libraries

The repository browsing features will use the following libraries and components:

- gitoxide for Git repository access
- SQLite for metadata storage
- Syntax highlighting library (TBD, likely syntect)
- Markdown rendering library for READMEs
- Web template system for UI rendering

## Integration with Other Features

The repository browsing functionality integrates with:

- Git operations for cloning and pushing
- User authentication for access control
- Caching system for performance optimization
- API endpoints for programmatic access
