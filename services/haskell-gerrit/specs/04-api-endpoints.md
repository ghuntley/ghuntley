<!--
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# API Endpoints

## Overview

The Gerrit API is organized into domains that match our data model structure. Each domain has its own set of endpoints that handle specific functionality.

## API Documentation

The API is documented using OpenAPI/Swagger specification version 3.0. The documentation is available at:

```
GET    /api/docs/openapi.json          OpenAPI specification in JSON format
GET    /api/docs                       Interactive Swagger UI documentation
```

The interactive documentation provides:
- Complete API reference with all endpoints, parameters, and response formats
- Try-it-out functionality to test API calls directly from the browser
- Schema definitions for all request/response objects
- Authentication flow examples
- Code samples in multiple programming languages

### OpenAPI Features

The OpenAPI specification includes:

1. **Authentication**
   - JWT token-based authentication
   - Token format and expiry details
   - OAuth2 provider integration

2. **Request/Response Schemas**
   - Detailed JSON schemas for all requests and responses
   - Field-level validation rules and constraints
   - Example payloads for each endpoint

3. **Error Handling**
   - Standardized error response format
   - Error codes and descriptions
   - Validation error details

4. **Rate Limiting**
   - Rate limit headers and quotas
   - Per-endpoint rate limit rules
   - Rate limit status endpoints

5. **Pagination**
   - Cursor-based pagination parameters
   - Page size limits and defaults
   - Pagination metadata in responses

### Using the Interactive Documentation

The Swagger UI at `/api/docs` provides:

1. **Authentication**
   - "Authorize" button to input JWT token
   - Token validation and session management
   - Token refresh functionality

2. **Endpoint Testing**
   - "Try it out" button for each endpoint
   - Parameter input forms with validation
   - Request/response examples
   - Curl command generation

3. **Code Generation**
   - Client SDK generation in multiple languages
   - API client configuration examples
   - Authentication setup code

4. **Schema Browser**
   - Interactive schema documentation
   - Model relationship diagrams
   - Field descriptions and constraints

### API Client Libraries

The OpenAPI specification can be used to generate client libraries in various languages:

```bash
# Generate TypeScript client
openapi-generator generate -i /api/docs/openapi.json -g typescript-fetch -o ./client-ts

# Generate Python client
openapi-generator generate -i /api/docs/openapi.json -g python -o ./client-python

# Generate Go client
openapi-generator generate -i /api/docs/openapi.json -g go -o ./client-go
```

## Authentication Domain

### User Management
```
POST   /api/auth/register              Register new user
POST   /api/auth/login                 User login
POST   /api/auth/logout                User logout
GET    /api/auth/me                    Get current user
PUT    /api/auth/me                    Update current user
```

### MFA
```
POST   /api/auth/mfa/enable            Enable MFA
POST   /api/auth/mfa/disable           Disable MFA
POST   /api/auth/mfa/verify            Verify MFA code
GET    /api/auth/mfa/backup-codes      Get backup codes
POST   /api/auth/mfa/backup-codes      Generate new backup codes
```

### OAuth
```
GET    /api/auth/oauth/:provider        Initiate OAuth flow
GET    /api/auth/oauth/:provider/callback  OAuth callback
DELETE /api/auth/oauth/:provider        Remove OAuth connection
```

## Organization Domain

### Enterprise Management
```
GET    /api/enterprises                List enterprises
POST   /api/enterprises                Create enterprise
GET    /api/enterprises/:id            Get enterprise
PUT    /api/enterprises/:id            Update enterprise
DELETE /api/enterprises/:id            Delete enterprise
```

### Organization Management
```
GET    /api/enterprises/:id/organizations      List organizations
POST   /api/enterprises/:id/organizations      Create organization
GET    /api/organizations/:id                  Get organization
PUT    /api/organizations/:id                  Update organization
DELETE /api/organizations/:id                  Delete organization
```

### Team Management
```
GET    /api/organizations/:id/teams            List teams
POST   /api/organizations/:id/teams            Create team
GET    /api/teams/:id                          Get team
PUT    /api/teams/:id                          Update team
DELETE /api/teams/:id                          Delete team
GET    /api/teams/:id/members                  List team members
POST   /api/teams/:id/members                  Add team member
DELETE /api/teams/:id/members/:userId          Remove team member
```

## Project Domain

### Project Management
```
GET    /api/organizations/:id/projects         List projects
POST   /api/organizations/:id/projects         Create project
GET    /api/projects/:id                       Get project
PUT    /api/projects/:id                       Update project
DELETE /api/projects/:id                       Delete project
```

### Repository Management
```
GET    /api/projects/:id/repositories          List repositories
POST   /api/projects/:id/repositories          Create repository
GET    /api/repositories/:id                   Get repository
PUT    /api/repositories/:id                   Update repository
DELETE /api/repositories/:id                   Delete repository
```

### Branch Management
```
GET    /api/repositories/:id/branches          List branches
POST   /api/repositories/:id/branches          Create branch
GET    /api/branches/:id                       Get branch
PUT    /api/branches/:id                       Update branch
DELETE /api/branches/:id                       Delete branch
```

## Review Domain

### Change Management
```
GET    /api/projects/:id/changes               List changes
POST   /api/projects/:id/changes               Create change
GET    /api/changes/:id                        Get change
PUT    /api/changes/:id                        Update change
DELETE /api/changes/:id                        Delete change
```

### Stack Management
```
GET    /api/projects/:id/stacks                List change stacks
POST   /api/projects/:id/stacks                Create change stack
GET    /api/stacks/:id                         Get stack details
PUT    /api/stacks/:id                         Update stack
DELETE /api/stacks/:id                         Delete stack
GET    /api/stacks/:id/changes                 List changes in stack
POST   /api/stacks/:id/changes                 Add change to stack
DELETE /api/stacks/:id/changes/:changeId       Remove change from stack
PUT    /api/stacks/:id/reorder                 Reorder changes in stack
POST   /api/stacks/:id/rebase                  Rebase entire stack
GET    /api/stacks/:id/dependencies            Get stack dependencies
POST   /api/stacks/:id/submit                  Submit entire stack
POST   /api/stacks/:id/submit-up-to/:changeId  Submit stack up to change
```

### Stack Operations
```
POST   /api/stacks/:id/check-conflicts         Check for conflicts in stack
POST   /api/stacks/:id/resolve-conflicts       Resolve stack conflicts
POST   /api/stacks/:id/sync                    Sync stack with remote
GET    /api/stacks/:id/graph                   Get stack dependency graph
POST   /api/stacks/:id/split/:changeId         Split stack at change
POST   /api/stacks/:id/merge/:stackId          Merge two stacks
```

### Merge Queue Operations
```
GET    /api/projects/:id/merge-queue                List merge queue items
POST   /api/projects/:id/merge-queue                Enqueue change
DELETE /api/projects/:id/merge-queue/:changeId      Dequeue change
GET    /api/projects/:id/merge-queue/status         Get queue status
GET    /api/projects/:id/merge-queue/metrics        Get queue metrics
GET    /api/projects/:id/merge-queue/items/:itemId  Get queue item details
PUT    /api/projects/:id/merge-queue/items/:itemId  Update queue item
```

### Revision Management
```
GET    /api/changes/:id/revisions              List revisions
POST   /api/changes/:id/revisions              Create revision
GET    /api/revisions/:id                      Get revision
PUT    /api/revisions/:id                      Update revision
```

### Review Management
```
GET    /api/revisions/:id/comments             List comments
POST   /api/revisions/:id/comments             Create comment
PUT    /api/comments/:id                       Update comment
DELETE /api/comments/:id                       Delete comment
POST   /api/revisions/:id/votes                Submit vote
GET    /api/revisions/:id/votes                List votes
```

## Billing Domain

### Plan Management
```
GET    /api/billing/plans                      List billing plans
POST   /api/billing/plans                      Create billing plan
GET    /api/billing/plans/:id                  Get billing plan
PUT    /api/billing/plans/:id                  Update billing plan
```

### Coupon Management
```
GET    /api/billing/coupons                    List coupons
POST   /api/billing/coupons                    Create coupon
GET    /api/billing/coupons/:id                Get coupon
PUT    /api/billing/coupons/:id                Update coupon
POST   /api/billing/coupons/validate           Validate coupon
```

### Enterprise Billing
```
GET    /api/enterprises/:id/billing            Get enterprise billing
POST   /api/enterprises/:id/billing            Create enterprise billing
PUT    /api/enterprises/:id/billing            Update enterprise billing
```

### Invoice Management
```
GET    /api/enterprises/:id/billing/invoices           List invoices
POST   /api/enterprises/:id/billing/invoices           Create invoice
GET    /api/enterprises/:id/billing/invoices/:id       Get invoice
PUT    /api/enterprises/:id/billing/invoices/:id       Update invoice
POST   /api/enterprises/:id/billing/invoices/:id/coupon Apply coupon to invoice
```

### Transaction Management
```
GET    /api/enterprises/:id/billing/invoices/:id/transactions    List transactions
POST   /api/enterprises/:id/billing/invoices/:id/transactions    Create transaction
GET    /api/enterprises/:id/billing/transactions/:id             Get transaction
```

## Administrative Domain

### System Administration
```
GET    /api/admin/system/health              Get system health status
GET    /api/admin/system/metrics             Get system performance metrics
GET    /api/admin/system/logs                Get system logs
GET    /api/admin/system/settings            Get system settings
PUT    /api/admin/system/settings            Update system settings
POST   /api/admin/system/backup              Create system backup
GET    /api/admin/system/backups             List system backups
POST   /api/admin/system/restore             Restore from backup
POST   /api/admin/system/maintenance         Schedule maintenance
GET    /api/admin/system/maintenance         Get maintenance schedule
```

### User Administration
```
GET    /api/admin/users                      List all users
POST   /api/admin/users/bulk                 Bulk user operations
GET    /api/admin/users/:id/activity         Get user activity
PUT    /api/admin/users/:id/permissions      Update user permissions
GET    /api/admin/users/sessions             List active sessions
DELETE /api/admin/users/sessions/:id         Terminate session
GET    /api/admin/users/auth-logs            Get authentication logs
POST   /api/admin/users/:id/lock             Lock user account
POST   /api/admin/users/:id/unlock           Unlock user account
```

### Resource Management
```
GET    /api/admin/resources/usage            Get resource usage stats
GET    /api/admin/resources/storage          Get storage metrics
GET    /api/admin/resources/database         Get database metrics
GET    /api/admin/resources/cache            Get cache stats
POST   /api/admin/resources/cache/clear      Clear cache
GET    /api/admin/resources/jobs             List background jobs
POST   /api/admin/resources/jobs/:id/cancel  Cancel background job
POST   /api/admin/resources/cleanup          Run system cleanup
```

### Security Administration
```
GET    /api/admin/security/policies          List security policies
PUT    /api/admin/security/policies          Update security policies
GET    /api/admin/security/auth-providers    List auth providers
PUT    /api/admin/security/auth-providers    Update auth providers
GET    /api/admin/security/api-keys          List API keys
POST   /api/admin/security/api-keys          Create API key
DELETE /api/admin/security/api-keys/:id      Revoke API key
GET    /api/admin/security/rate-limits       Get rate limit config
PUT    /api/admin/security/rate-limits       Update rate limits
GET    /api/admin/security/ip-allowlist      Get IP allowlist
PUT    /api/admin/security/ip-allowlist      Update IP allowlist
GET    /api/admin/security/audit-logs        Get security audit logs
```

### Enterprise Administration
```
GET    /api/admin/enterprises/settings       Get enterprise settings
PUT    /api/admin/enterprises/settings       Update enterprise settings
GET    /api/admin/enterprises/licenses       List enterprise licenses
POST   /api/admin/enterprises/licenses       Add enterprise license
GET    /api/admin/enterprises/quotas         Get enterprise quotas
PUT    /api/admin/enterprises/quotas         Update enterprise quotas
GET    /api/admin/enterprises/analytics      Get enterprise analytics
GET    /api/admin/enterprises/reports        Generate enterprise reports
GET    /api/admin/enterprises/policies       List enterprise policies
PUT    /api/admin/enterprises/policies       Update enterprise policies
POST   /api/admin/enterprises/backup         Backup enterprise data
```

### Configuration Management
```
GET    /api/admin/config                     Get system configuration
PUT    /api/admin/config                     Update system configuration
GET    /api/admin/config/features            List feature flags
PUT    /api/admin/config/features            Update feature flags
GET    /api/admin/config/env                 Get environment variables
PUT    /api/admin/config/env                 Update environment variables
GET    /api/admin/config/services            List service configs
PUT    /api/admin/config/services/:id        Update service config
GET    /api/admin/config/email-templates     List email templates
PUT    /api/admin/config/email-templates/:id Update email template
GET    /api/admin/config/webhooks            List webhook configs
PUT    /api/admin/config/webhooks/:id        Update webhook config
```

### Maintenance Tools
```
POST   /api/admin/maintenance/database       Run database maintenance
POST   /api/admin/maintenance/cache          Run cache maintenance
POST   /api/admin/maintenance/storage        Run storage cleanup
POST   /api/admin/maintenance/logs           Rotate log files
POST   /api/admin/maintenance/index          Rebuild search index
POST   /api/admin/maintenance/migrate        Run data migration
GET    /api/admin/maintenance/diagnostics    Get system diagnostics
```

## Response Formats

### Success Response
```json
{
    "success": true,
    "data": {
        // Response data specific to the endpoint
    }
}
```

### Error Response
```json
{
    "success": false,
    "error": {
        "code": "ERROR_CODE",
        "message": "Human readable error message"
    }
}
```

## Authentication

All API endpoints except for authentication endpoints require a valid JWT token in the Authorization header:

```
Authorization: Bearer <token>
```

## Rate Limiting

API endpoints are rate limited based on the following rules:
- Authentication endpoints: 10 requests per minute
- Other endpoints: 60 requests per minute per user
- Webhook endpoints: 120 requests per minute per organization

## Pagination

List endpoints support pagination using the following query parameters:
- `page`: Page number (default: 1)
- `per_page`: Items per page (default: 20, max: 100)

Response includes pagination metadata:
```json
{
    "success": true,
    "data": [...],
    "pagination": {
        "total": 100,
        "per_page": 20,
        "current_page": 1,
        "last_page": 5
    }
}
```
