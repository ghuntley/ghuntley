<!--
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Features

## Core Review System

### Change Management
- Create and manage code changes
- Support for multiple revisions per change
- Automatic patch set generation
- Change status tracking (Open, Merged, Abandoned)
- Change dependencies tracking

### Merge Queue
- Multi-VCS support (Git, Mercurial, JJ)
- Priority-based queuing
- Dependency-aware merging
- Automatic conflict detection
- Retry handling with configurable limits
- Queue metrics and monitoring
- Status tracking and notifications
- Concurrent merge processing
- Queue state persistence
- Validation hooks integration

### Stacked Diffs
- Support for dependent/stacked changes
- Automatic dependency graph generation
- Cascading updates for dependent changes
- Dependency cycle detection
- Transitive dependency tracking
- Smart rebasing of stacked changes
- Conflict detection and resolution
- Partial stack submission
- Stack visualization
- Stack-aware review workflow

### Code Review
- Inline code comments
- File-level comments
- Multi-line comment support
- Comment threads and discussions
- Comment resolution tracking

### Review Workflow
- Configurable review labels (e.g., Code-Review, Verified)
- Customizable voting ranges
- Submit requirements configuration
- Automated CI integration
- Review dashboard

## Organization Management

### Enterprise Features
- Multi-enterprise support
- Enterprise-wide settings
- Enterprise branding customization
- Enterprise-level access control
- Enterprise usage analytics

### Organization Features
- Multiple organizations per enterprise
- Organization visibility control (public, private, internal)
- Organization-level settings
- Custom organization roles
- Resource usage tracking

### Team Management
- Team creation and management
- Team hierarchy support
- Team permissions
- Team member roles (maintainer, member)
- Team access control

## Authentication & Authorization

### Authentication Methods
- Local authentication
- LDAP integration
- OAuth provider support
- Single Sign-On (SSO)
- Multi-factor authentication (MFA)

### Authorization
- Role-based access control (RBAC)
- Fine-grained permissions
- Access control lists (ACLs)
- API token management
- Session management

### Security Features
- Audit logging
- Security event tracking
- IP allowlisting
- Rate limiting
- Automated security scanning

## Project Management

### Project Features
- Project templates
- Project visibility control
- Project settings management
- Project statistics
- Project archiving

### Repository Management
- Multiple repository types (Git, Mercurial, JJ)
- Repository mirroring
- Repository statistics
- Branch protection rules
- Tag management

### Code Hosting
- Web-based code browsing
- Syntax highlighting
- Code search
- File history viewing
- Blame view

## Billing & Subscription

### Plan Management
- Multiple billing plans
- Custom plan creation
- Per-user pricing
- Feature-based plans
- Plan comparison

### Coupon System
- Coupon creation and management
- Multiple discount types:
  - Percentage discounts
  - Fixed amount discounts
- Coupon restrictions:
  - Usage limits
  - Validity period
  - Minimum/maximum amount
  - Plan-specific coupons
- Coupon validation
- Coupon usage tracking

### Enterprise Billing
- Enterprise-level billing
- Multiple payment methods
- Automated billing cycles
- Usage-based billing
- Tax ID support
- Custom billing addresses

### Invoice Management
- Automated invoice generation
- Invoice customization
- Multiple invoice statuses
- Line item details
- Coupon application
- Invoice history

### Payment Processing
- Multiple payment methods
- Secure payment processing
- Transaction tracking
- Payment status monitoring
- Refund handling

### Billing Analytics
- Usage tracking
- Revenue analytics
- Subscription metrics
- Churn analysis
- Growth tracking

## Integration & Extensibility

### API Integration
- RESTful API
- Webhook support
- Event system
- Custom integrations
- API documentation

### CI/CD Integration
- Jenkins integration
- GitHub Actions support
- GitLab CI support
- Custom CI system integration
- Build status reporting

### External Tool Integration
- IDE plugins
- Command-line tools
- Chat integrations (Slack, Discord)
- Issue tracker integration
- Documentation tools

## Monitoring & Analytics

### System Monitoring
- Performance monitoring
- Error tracking
- Resource usage monitoring
- Health checks
- Alerting system

### Usage Analytics
- User activity tracking
- Code review metrics
- Repository statistics
- Performance analytics
- Custom reports

### Audit & Compliance
- Audit logging
- Compliance reporting
- Security scanning
- Access tracking
- Policy enforcement

## Administrative Dashboard

### System Administration
- Global system settings management
- System health monitoring
- Performance metrics visualization
- Error logs and debugging tools
- System maintenance controls
- Backup and restore management
- System updates and maintenance scheduling
- Database backend support:
  - PostgreSQL for enterprise deployments
  - SQLite for small/local deployments
  - Automatic schema migrations
  - Database-specific optimizations
  - Backup and restore utilities
  - Performance monitoring
  - Integrity checking

### User Administration
- User account management
- Bulk user operations
- User activity monitoring
- User permissions management
- User session management
- User authentication logs
- Account lockout management

### Resource Management
- Server resource monitoring
- Storage usage tracking
- Database performance metrics
- Cache management
- Job queue monitoring
- Background task management
- System cleanup tools

### Metrics Dashboard
- Real-time system metrics:
  - Request metrics:
    - Total requests and active connections
    - Request duration and response size
    - Per-endpoint request counts and latencies
    - Rate limit violations
  - Database metrics:
    - Active connections and query counts
    - Query duration and error rates
    - Per-operation metrics (inserts, updates, selects)
    - Connection pool statistics
  - Error tracking:
    - API errors by type and endpoint
    - Database operation errors
    - Validation errors
    - Rate limit violations
  - Git operations:
    - Operation counts and error rates
    - Repository statistics
    - Performance metrics
  - Cache performance:
    - Hit/miss ratios
    - Cache size and utilization
    - Eviction rates
    - Cache efficiency metrics
- Visualization features:
  - Interactive time-series graphs
  - Real-time updates (5-minute intervals)
  - Customizable date ranges
  - Metric correlation analysis
  - Threshold alerts
  - Export capabilities (CSV, JSON)
- Administrative tools:
  - Metric threshold configuration
  - Alert setup and management
  - Historical data analysis
  - Performance optimization insights
  - Capacity planning tools
- Integration capabilities:
  - Prometheus metrics endpoint
  - Grafana dashboard templates
  - Custom metrics export
  - Alert webhook integration
  - Third-party monitoring support

### Security Administration
- Security policy management
- Access control configuration
- Authentication provider settings
- API key management
- Rate limit configuration
- IP allowlist management
- Security audit logs

### Enterprise Administration
- Enterprise-wide settings
- License management
- Enterprise quota management
- Enterprise-wide analytics
- Cross-enterprise reporting
- Enterprise policy enforcement
- Enterprise backup management

### Configuration Management
- System configuration editor
- Feature flag management
- Environment variable management
- Service configuration
- Integration settings
- Email template management
- Webhook configuration

### Maintenance Tools
- Database maintenance
- Cache maintenance
- Storage cleanup
- Log rotation
- Index rebuilding
- Data migration tools
- System diagnostics

### Notification System
- Multiple notification channels:
  - Slack integration with custom channels and formatting
  - Email notifications via SMTP or API
  - Microsoft Teams integration with rich message cards
  - Discord integration with embeds and webhooks
  - PagerDuty integration for incident management
- Channel-specific features:
  - Slack:
    - Webhook and token-based authentication
    - Default channel configuration
    - Rich message formatting
    - Custom channel routing
  - Email:
    - SMTP server support with TLS/STARTTLS
    - API-based email service integration
    - Customizable sender information
    - HTML and plain text formats
    - Multiple recipient support
  - Microsoft Teams:
    - Webhook-based integration
    - Rich message cards
    - Adaptive card support
    - Action button integration
  - Discord:
    - Webhook-based integration
    - Rich embeds with custom formatting
    - Role mentions and notifications
  - PagerDuty:
    - Event API v2 integration
    - Configurable incident priorities
    - Automatic incident creation
    - Alert severity mapping
- Notification Features:
  - Alert creation notifications
  - Alert acknowledgment updates
  - Status change notifications
  - Alert deletion notifications
  - Configurable templates
  - Priority-based routing
  - Rate limiting and batching
  - Error handling and retries
  - Delivery status tracking
