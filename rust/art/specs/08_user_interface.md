# Art: User Interface

## Overview

Art's user interface is designed to provide a clean, responsive, and accessible way to browse Git repositories. The UI is completely server-side rendered with absolutely no JavaScript, focusing on performance, accessibility, and simplicity.

## Design Principles

The Art user interface follows these core principles:

1. **Server-Side Rendering Only**: All UI content is rendered on the server, with no JavaScript being sent to the client. This approach ensures maximum compatibility across browsers and devices, as well as improved performance and accessibility.

2. **Minimalist Design**: Clean and uncluttered interface that focuses on content.

3. **Content-First Approach**: Repository content takes center stage, with minimal UI chrome.

4. **Progressive Enhancement**: Basic functionality works without JavaScript, with graceful degradation for older browsers.

5. **Responsive Layout**: Adapts to different screen sizes, from mobile to desktop.

6. **Accessible Design**: Follows WCAG 2.1 AA guidelines for accessibility.

7. **Performance-Focused**: Optimized for fast loading and rendering times.

## Technology Stack

- **HTML5**: Semantic markup for content structure
- **CSS3**: Styling with modern CSS features
- **HTTP**: Standard HTTP requests and responses for all interactions
- **No JavaScript**: No client-side scripting is used at all
- **Server-Side Templating**: Templates rendered entirely on the server

## UI Layout

### Global Layout

```
┌───────────────────────────────────────────────────┐
│                      Header                        │
├───────────────────────────────────────────────────┤
│                                                   │
│                                                   │
│                                                   │
│                   Main Content                    │
│                                                   │
│                                                   │
│                                                   │
├───────────────────────────────────────────────────┤
│                      Footer                        │
└───────────────────────────────────────────────────┘
```

### Repository Layout

```
┌───────────────────────────────────────────────────┐
│                      Header                        │
├───────────────────────────────────────────────────┤
│                                                   │
│  ┌─────────────┐                                  │
│  │             │                                  │
│  │  Sidebar    │           Content Area           │
│  │             │                                  │
│  │             │                                  │
│  └─────────────┘                                  │
│                                                   │
├───────────────────────────────────────────────────┤
│                      Footer                        │
└───────────────────────────────────────────────────┘
```

## Components

### Header

- Repository title/breadcrumb navigation
- Search box (with server-side search)
- Links to key sections (Browse, Commits, Branches, Tags)
- Authentication status (if applicable)

### Footer

- Version information
- Link to Art documentation
- Link to source code repository
- Legal information

### Sidebar (Repository View)

- Repository description
- Owner information
- Last updated time
- Default branch
- Quick links to branches and tags
- Clone URL

### Content Area

Dynamically displays the current view:
- Repository summary
- File browser
- File viewer
- Commit history
- Diff view
- Blame view

## Key Views

### Repository Index

Lists all accessible repositories with summary information:
- Repository name
- Description
- Owner
- Last updated time
- Default branch
- Clone URL

### Repository Home

Displays repository overview:
- README content (rendered)
- Recent commits
- Branch overview
- Repository stats

### File Browser

Navigable directory structure:
- Path breadcrumb
- List of files and directories
- File size and last modification
- READMEs rendered inline (optional)

### File Viewer

Displays file content:
- Syntax highlighted code
- Line numbers
- Raw file download option
- File history link
- Blame view link

### Commit History

Lists commits with details:
- Commit hash (short)
- Author
- Date
- Commit message
- Pagination controls

### Commit Details

Shows detailed commit information:
- Complete commit hash
- Author details
- Committer details
- Commit message (full)
- Parent commit(s)
- Diff of changes

### Diff View

Displays differences between versions:
- File-by-file changes
- Added/removed/modified files
- Line-by-line comparison
- Context controls

### Blame View

Shows line-by-line attribution:
- Line number
- Commit hash
- Author
- Date
- Line content

## Interaction Patterns

All interactions are implemented through standard HTTP requests and responses, with no JavaScript:

### Navigation

- Standard href links between pages
- Form submissions for search and filtering
- Server-side processing for all requests

### Form Submissions

- GET for search and filter operations
- POST for operations that modify data
- Redirects after successful form submission

### State Management

- URL parameters for state (e.g., current page, filters)
- Server session for user authentication
- HTTP cookies for minimal state persistence

## Responsive Design

The UI adapts to different screen sizes:

### Desktop (>= 1024px)

- Full sidebar displayed
- Multi-column layouts where appropriate
- Expanded navigation and information

### Tablet (768px - 1023px)

- Collapsible sidebar (toggled through links)
- Adapted layouts for medium screens
- Optimized navigation for touch

### Mobile (< 768px)

- Stacked layouts
- Hidden sidebar (accessible via menu)
- Touch-friendly targets
- Simplified navigation

## Accessibility Features

Art provides comprehensive accessibility features to ensure the application is usable by people with disabilities:

### Screen Reader Compatibility

- **ARIA Attributes**: Proper ARIA roles, states, and properties are used throughout the UI.
- **Semantic HTML**: Semantic HTML elements are used for better structure and meaning.
- **Text Alternatives**: All non-text content has appropriate text alternatives.
- **Focus Management**: Focus is managed properly for interactive elements.

### Keyboard Navigation

- **Keyboard Shortcuts**: Common operations can be performed using keyboard shortcuts.
- **Focus Indicators**: Visible focus indicators are provided for all interactive elements.
- **Skip Links**: Skip links are provided to bypass repeated content.
- **Logical Tab Order**: Interactive elements follow a logical tab order.

### Color and Contrast

- **Color Contrast**: All text meets WCAG AA contrast requirements (4.5:1 for normal text, 3:1 for large text).
- **Color Independence**: Information is not conveyed by color alone.
- **High Contrast Mode**: A high contrast mode is available for users who need it.

### Accessibility Configuration

- **Font Size**: Users can adjust font size without breaking the layout.
- **Line Height**: Line height can be adjusted for better readability.
- **Reduced Motion**: Animations and transitions are reduced for users who prefer reduced motion.
- **Keyboard Navigation**: Keyboard navigation can be customized.

### Accessibility Guide and Resources

- **Accessibility Guide**: A comprehensive guide is available at `/accessibility/guide` that provides best practices and information on how to use Art's accessibility features.
- **Accessibility CSS**: A dedicated CSS file provides styles for accessibility features like skip links, focus indicators, and high contrast mode.
- **WCAG Compliance**: Art follows Web Content Accessibility Guidelines (WCAG) 2.1 Level AA.

### Automated Testing and Reporting

- **Accessibility Analysis**: HTML content can be analyzed for accessibility issues.
- **Color Contrast Checking**: Color combinations can be checked for sufficient contrast.
- **Accessibility Reports**: Detailed reports of accessibility issues are provided with references to WCAG guidelines.
- **Property-Based Testing**: All accessibility features are tested with property-based tests to ensure robustness.

## Implementation Details

### AccessibilityManager

The `AccessibilityManager` service provides:

- Content analysis for accessibility issues
- Color contrast calculation and remediation
- Enhancement of HTML content with accessibility attributes
- Metrics tracking for accessibility violations
- Configuration of accessibility features

### API Endpoints

The following API endpoints support accessibility features:

- `POST /format/accessible` - Format code with accessibility enhancements
- `POST /format/accessibility/analyze` - Analyze HTML for accessibility issues
- `POST /format/accessibility/enhance` - Generate an accessible version of HTML
- `POST /format/accessibility/contrast` - Check and improve color contrast
- `POST /format/accessibility/config` - Update accessibility features
- `GET /format/accessibility/config` - Get current accessibility features

### Configuration

Accessibility features can be configured via:

```toml
[format.accessibility]
min_contrast_ratio = 4.5
add_aria_attributes = true
add_tabindex = true
add_alt_text = true
add_role_attributes = true
check_heading_hierarchy = true
add_keyboard_shortcuts = false
optimize_for_screen_readers = true
```

## Visual Design

### Color Palette

- **Primary**: #2563EB (Royal Blue)
- **Secondary**: #D1D5DB (Light Gray)
- **Background**: #FFFFFF (White)
- **Text**: #111827 (Near Black)
- **Accent**: #3B82F6 (Blue)
- **Success**: #10B981 (Green)
- **Warning**: #F59E0B (Amber)
- **Error**: #EF4444 (Red)

### Typography

- **Primary Font**: System UI font stack for native feel
- **Monospace**: Monospace font for code and Git hashes
- **Base Size**: 16px
- **Scale**: 1.25 modular scale for headings

### Visual Hierarchy

- Clear content grouping
- Whitespace for separation
- Visual indicators for active/current items
- Consistent spacing system

## Server-Side Implementation

### Rendering Approach

- Templates rendered completely on the server
- No JavaScript sent to the client
- All links trigger full page requests
- Forms submit to server endpoints

### HTML Generation

- Clean, semantic HTML output
- Minimal markup for performance
- Separation of content and presentation
- Proper use of HTML5 elements

### CSS Strategy

- CSS files for styling
- No inline styles
- Responsive design with media queries
- CSS variables for theming
- Minimal CSS framework dependencies

## Performance Optimizations

### HTML Optimizations

- Minimized HTML output
- Efficient templating
- Deferred loading of non-critical content via HTTP/2 server push
- Browser caching of static assets

### CSS Optimizations

- Minified CSS
- Critical CSS inlined
- Media-specific stylesheets
- Reduced selector complexity

### HTTP Optimizations

- HTTP/2 support
- Cache headers for static assets
- Conditional requests (If-Modified-Since)
- Compressed responses (gzip/brotli)

## Example User Journeys

### Browsing a Repository

1. User navigates to repository index
2. User selects a repository
3. Server renders repository home page with README
4. User navigates to file browser
5. User selects a file to view
6. Server renders syntax-highlighted file content

### Viewing Commit History

1. User navigates to repository commits page
2. Server renders paginated commit list
3. User selects a specific commit
4. Server renders commit details with diff
5. User navigates to a different commit from parent/child links

### Exploring Code Changes

1. User views a commit diff
2. User explores changes file by file
3. User clicks on blame view for a specific file
4. Server renders blame information
5. User navigates to a specific commit from blame

## Implementation Notes

The UI implementation will favor:

- Simplicity over complexity
- Performance over feature richness
- Accessibility over visual embellishment
- Stateless design over stateful components
- HTTP standards over custom protocols

## Current Limitations

The purely server-side rendered approach without JavaScript has some limitations:

- No real-time updates (requires page refresh)
- No client-side interactivity
- No offline functionality
- Form submissions require full page loads

These limitations are accepted as tradeoffs for the benefits of a JavaScript-free approach: simplicity, accessibility, reliability, and minimal client requirements.
