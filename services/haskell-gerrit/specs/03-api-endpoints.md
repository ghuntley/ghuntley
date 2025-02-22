# API Endpoints

## Overview

The Gerrit API is organized into several domains, each handling specific functionality:

1. Authentication and Authorization
2. User Management
3. Organization Management
4. Enterprise Features
5. Change Management
6. Stack Management
7. Billing
8. Alerts and Monitoring

## API Versioning

The API uses semantic versioning and is currently at v1. All endpoints are prefixed with the version:

```
/api/v1/...
```

Version information is also included in response headers:
```
X-API-Version: 1.0.0
X-API-Deprecated: false
X-API-Sunset-Date: null
```

## Base URL

All API endpoints are prefixed with `/api/v1`.

## Authentication Methods

The API supports three authentication methods:

1. **Bearer Token**
   ```
   Authorization: Bearer <token>
   ```

2. **API Key**
   ```
   X-API-Key: <api_key>
   ```

3. **OAuth2**
   ```
   Authorization: Bearer <oauth_token>
   ```

## Authorization Levels

The API uses role-based access control (RBAC) with the following roles:

- `owner`: Full system access
- `admin`: Administrative access
- `member`: Standard user access
- `guest`: Limited read access

## Authentication

### LDAP Authentication

```
POST /api/auth/ldap/login
```

Authenticates a user using LDAP credentials.

**Request:**
```json
{
  "username": "jdoe",
  "password": "secure_password"
}
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIs...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
    "expires_in": 3600,
    "user": {
      "id": "usr_123",
      "username": "jdoe",
      "email": "jdoe@example.com",
      "roles": ["member"]
    }
  }
}
```

### OAuth Authentication

```
GET /api/auth/oauth/{provider}/login
POST /api/auth/oauth/{provider}/refresh
GET /api/auth/oauth/{provider}/callback
```

Handles OAuth-based authentication with various providers.

**OAuth Refresh Request:**
```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIs..."
}
```

**OAuth Refresh Response:**
```json
{
  "status": "success",
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIs...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
    "expires_in": 3600
  }
}
```

## Token Management

### Token Types and Lifecycle

```json
// GET /api/v1/auth/token/info
Response: (200 OK)
{
  "status": "success",
  "data": {
    "token_types": {
      "access_token": {
        "expiration": "1h",
        "refresh_allowed": true,
        "scope": ["read", "write", "delete"],
        "rotation_policy": "on_refresh"
      },
      "refresh_token": {
        "expiration": "30d",
        "refresh_allowed": false,
        "rotation_policy": "on_use"
      },
      "api_key": {
        "expiration": "unlimited",
        "refresh_allowed": false,
        "scope": ["read", "write"],
        "rotation_policy": "manual"
      }
    },
    "security_policies": {
      "max_active_tokens": 5,
      "max_refresh_count": 100,
      "require_rotation": true,
      "ip_binding": "optional",
      "device_binding": "optional"
    }
  }
}

// POST /api/v1/auth/token/refresh
Request:
{
  "refresh_token": "rt_abc123...",
  "device_id": "device_xyz789...",  // Optional
  "ip_binding": "192.168.1.1"       // Optional
}

Response: (200 OK)
{
  "status": "success",
  "data": {
    "access_token": "at_def456...",
    "refresh_token": "rt_ghi789...",  // New refresh token if rotation is enabled
    "token_type": "Bearer",
    "expires_in": 3600,
    "scope": ["read", "write", "delete"],
    "refresh_count": 1,
    "refresh_limit": 100
  }
}

// POST /api/v1/auth/token/revoke
Request:
{
  "token": "at_def456...",
  "revoke_refresh_token": true,  // Optional, defaults to false
  "revoke_all_sessions": false   // Optional, defaults to false
}

Response: (200 OK)
{
  "status": "success",
  "data": {
    "revoked_tokens": 1,
    "affected_sessions": 1
  }
}

// GET /api/v1/auth/token/active
Response: (200 OK)
{
  "status": "success",
  "data": {
    "active_tokens": [
      {
        "token_id": "at_def456...",
        "type": "access_token",
        "issued_at": "2025-03-15T14:30:00Z",
        "expires_at": "2025-03-15T15:30:00Z",
        "last_used_at": "2025-03-15T14:45:00Z",
        "scope": ["read", "write", "delete"],
        "device_info": {
          "device_id": "device_xyz789...",
          "device_type": "mobile",
          "last_ip": "192.168.1.1"
        }
      }
    ],
    "pagination": {
      "total": 1,
      "limit": 10,
      "offset": 0
    }
  }
}
```

### Token Error Responses

```json
// 401 Unauthorized - Expired Token
{
  "status": "error",
  "error": {
    "code": "token_expired",
    "message": "The access token has expired",
    "details": {
      "expired_at": "2025-03-15T15:30:00Z",
      "token_type": "access_token",
      "can_refresh": true
    }
  }
}

// 401 Unauthorized - Invalid Token
{
  "status": "error",
  "error": {
    "code": "token_invalid",
    "message": "The token is invalid or has been revoked",
    "details": {
      "reason": "token_revoked",
      "revoked_at": "2025-03-15T15:00:00Z"
    }
  }
}

// 401 Unauthorized - Invalid Refresh Token
{
  "status": "error",
  "error": {
    "code": "refresh_token_invalid",
    "message": "The refresh token is invalid or has expired",
    "details": {
      "reason": "max_refresh_exceeded",
      "refresh_count": 100,
      "refresh_limit": 100
    }
  }
}
```

### Token Security Events

```json
// GET /api/v1/auth/token/events
Response: (200 OK)
{
  "status": "success",
  "data": {
    "events": [
      {
        "event_type": "token_issued",
        "token_id": "at_def456...",
        "timestamp": "2025-03-15T14:30:00Z",
        "device_info": {
          "device_id": "device_xyz789...",
          "ip_address": "192.168.1.1"
        }
      },
      {
        "event_type": "token_refreshed",
        "token_id": "at_def456...",
        "timestamp": "2025-03-15T15:30:00Z",
        "refresh_count": 1
      },
      {
        "event_type": "token_revoked",
        "token_id": "at_def456...",
        "timestamp": "2025-03-15T16:30:00Z",
        "reason": "user_initiated"
      }
    ],
    "pagination": {
      "total": 3,
      "limit": 10,
      "offset": 0
    }
  }
}
```

## Token Rotation Strategies

### Automatic Token Rotation

```json
// POST /api/v1/auth/token/rotate
Request:
{
  "token_id": "at_def456...",
  "rotation_type": "automatic",
  "rotation_policy": {
    "interval": "24h",
    "grace_period": "1h",
    "max_active_tokens": 2
  }
}

Response: (200 OK)
{
  "status": "success",
  "data": {
    "old_token": {
      "token_id": "at_def456...",
      "status": "grace_period",
      "expires_at": "2025-03-15T15:30:00Z"
    },
    "new_token": {
      "token_id": "at_ghi789...",
      "status": "active",
      "expires_at": "2025-03-16T14:30:00Z"
    },
    "rotation_schedule": {
      "next_rotation": "2025-03-16T14:30:00Z",
      "grace_period_end": "2025-03-15T15:30:00Z"
    }
  }
}

// GET /api/v1/auth/token/rotation-status
Response: (200 OK)
{
  "status": "success",
  "data": {
    "active_tokens": [
      {
        "token_id": "at_ghi789...",
        "status": "active",
        "created_at": "2025-03-15T14:30:00Z",
        "expires_at": "2025-03-16T14:30:00Z"
      },
      {
        "token_id": "at_def456...",
        "status": "grace_period",
        "created_at": "2025-03-14T14:30:00Z",
        "expires_at": "2025-03-15T15:30:00Z"
      }
    ],
    "rotation_history": [
      {
        "timestamp": "2025-03-15T14:30:00Z",
        "event": "token_rotated",
        "old_token_id": "at_def456...",
        "new_token_id": "at_ghi789..."
      }
    ]
  }
}
```

### Manual Token Rotation

```json
// POST /api/v1/auth/token/rotate
Request:
{
  "token_id": "at_def456...",
  "rotation_type": "manual",
  "invalidate_old": true,
  "device_binding": {
    "device_id": "device_xyz789...",
    "device_name": "Work Laptop"
  }
}

Response: (200 OK)
{
  "status": "success",
  "data": {
    "new_token": {
      "token_id": "at_jkl012...",
      "access_token": "eyJhbGciOiJIUzI1NiIs...",
      "expires_at": "2025-03-16T14:30:00Z"
    },
    "old_token": {
      "token_id": "at_def456...",
      "status": "revoked",
      "revoked_at": "2025-03-15T14:30:00Z"
    }
  }
}
```

## Token Scope Management

### Scope Definition and Validation

```json
// GET /api/v1/auth/scopes
Response: (200 OK)
{
  "status": "success",
  "data": {
    "available_scopes": {
      "user": {
        "read": "View user information",
        "write": "Modify user information",
        "delete": "Delete user account"
      },
      "changes": {
        "read": "View changes",
        "write": "Create and modify changes",
        "delete": "Delete changes",
        "review": "Review and comment on changes"
      },
      "admin": {
        "users": "Manage users",
        "organizations": "Manage organizations",
        "billing": "Access billing information"
      }
    },
    "scope_combinations": [
      {
        "name": "readonly",
        "scopes": ["user.read", "changes.read"],
        "description": "Read-only access"
      },
      {
        "name": "developer",
        "scopes": ["user.read", "changes.*"],
        "description": "Developer access"
      },
      {
        "name": "admin",
        "scopes": ["admin.*"],
        "description": "Administrative access"
      }
    ]
  }
}
```

### Token Scope Operations

```json
// POST /api/v1/auth/token/scope
Request:
{
  "token_id": "at_def456...",
  "operation": "modify",
  "scopes": {
    "add": ["changes.review"],
    "remove": ["admin.*"]
  }
}

Response: (200 OK)
{
  "status": "success",
  "data": {
    "token_id": "at_def456...",
    "current_scopes": ["user.read", "changes.read", "changes.review"],
    "changes": {
      "added": ["changes.review"],
      "removed": ["admin.users", "admin.organizations", "admin.billing"],
      "effective_time": "2025-03-15T14:30:00Z"
    }
  }
}

// GET /api/v1/auth/token/scope/audit
Response: (200 OK)
{
  "status": "success",
  "data": {
    "token_id": "at_def456...",
    "scope_history": [
      {
        "timestamp": "2025-03-15T14:30:00Z",
        "operation": "modify",
        "changes": {
          "added": ["changes.review"],
          "removed": ["admin.*"]
        },
        "requester": {
          "user_id": "usr_123",
          "ip_address": "192.168.1.1"
        }
      }
    ],
    "current_access_patterns": {
      "most_used_scopes": ["changes.read", "user.read"],
      "unused_scopes": ["changes.delete"],
      "last_used": {
        "changes.review": "2025-03-15T14:35:00Z",
        "user.read": "2025-03-15T14:40:00Z"
      }
    }
  }
}
```

## Token Security Best Practices

### Token Security Configuration

```json
// GET /api/v1/auth/security/config
Response: (200 OK)
{
  "status": "success",
  "data": {
    "token_policies": {
      "expiration": {
        "access_token": "1h",
        "refresh_token": "30d",
        "grace_period": "5m"
      },
      "rotation": {
        "mandatory_rotation": true,
        "max_token_age": "24h",
        "allow_grace_period": true
      },
      "scope_restrictions": {
        "max_scopes_per_token": 10,
        "restricted_scopes": ["admin.*"],
        "scope_approval_required": true
      }
    },
    "security_controls": {
      "ip_binding": {
        "enabled": true,
        "allow_multiple_ips": false,
        "ip_change_requires_reauth": true
      },
      "device_binding": {
        "enabled": true,
        "max_devices": 5,
        "require_device_verification": true
      },
      "mfa_requirements": {
        "enabled": true,
        "mfa_valid_period": "12h",
        "require_for_scope_change": true
      }
    }
  }
}
```

### Token Security Monitoring

```json
// POST /api/v1/auth/security/analyze
Request:
{
  "token_id": "at_def456...",
  "analysis_type": "security_audit"
}

Response: (200 OK)
{
  "status": "success",
  "data": {
    "token_security_score": 85,
    "risk_factors": [
      {
        "type": "scope_breadth",
        "severity": "medium",
        "description": "Token has broad scope access",
        "recommendation": "Consider reducing token scopes"
      },
      {
        "type": "rotation_age",
        "severity": "low",
        "description": "Token approaching rotation threshold",
        "recommendation": "Schedule rotation within 2 hours"
      }
    ],
    "security_events": [
      {
        "timestamp": "2025-03-15T14:20:00Z",
        "event_type": "ip_mismatch",
        "severity": "high",
        "details": {
          "expected_ip": "192.168.1.1",
          "actual_ip": "192.168.1.2"
        }
      }
    ],
    "compliance_status": {
      "compliant": true,
      "standards": [
        {
          "name": "OAuth 2.0",
          "status": "compliant"
        },
        {
          "name": "GDPR",
          "status": "compliant"
        }
      ]
    }
  }
}
```

### Security Incident Response

```json
// POST /api/v1/auth/security/incident
Request:
{
  "token_id": "at_def456...",
  "incident_type": "suspicious_activity",
  "action": "revoke_and_audit"
}

Response: (200 OK)
{
  "status": "success",
  "data": {
    "incident_id": "inc_123",
    "actions_taken": [
      {
        "action": "token_revocation",
        "timestamp": "2025-03-15T14:30:00Z",
        "status": "completed"
      },
      {
        "action": "security_audit",
        "timestamp": "2025-03-15T14:30:05Z",
        "status": "in_progress"
      }
    ],
    "affected_resources": {
      "tokens": ["at_def456..."],
      "sessions": ["sess_789"],
      "devices": ["device_xyz789..."]
    },
    "recommendations": [
      {
        "type": "security_review",
        "priority": "high",
        "description": "Review all active sessions and tokens"
      },
      {
        "type": "policy_update",
        "priority": "medium",
        "description": "Consider implementing stricter IP binding"
      }
    ]
  }
}
```

## User Management

### Required Authentication
All endpoints require a valid authentication token.

### Endpoint Authorization

**Current User**
```
GET /api/v1/auth/user
Authorization: Bearer token required
Minimum Role: guest
```

**User Operations**
```
GET /api/v1/auth/user/{userId}
Authorization: Bearer token required
Minimum Role: member
Required Permissions: user.read

PUT /api/v1/auth/user/{userId}
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: user.write

DELETE /api/v1/auth/user/{userId}
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: user.delete
```

**MFA Management**
```
All MFA endpoints
Authorization: Bearer token required
Minimum Role: member
Required Permissions: user.mfa.manage
Additional: Must be the user or an admin
```

## Organization Management

### Required Authentication
All endpoints require a valid authentication token.

### Endpoint Authorization

```
POST /api/v1/organizations
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: org.create

GET /api/v1/organizations/{orgId}
Authorization: Bearer token required
Minimum Role: member
Required Permissions: org.read

PUT /api/v1/organizations/{orgId}
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: org.write

DELETE /api/v1/organizations/{orgId}
Authorization: Bearer token required
Minimum Role: owner
Required Permissions: org.delete

GET /api/v1/organizations/{orgId}/members
Authorization: Bearer token required
Minimum Role: member
Required Permissions: org.members.read

POST /api/v1/organizations/{orgId}/members
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: org.members.write

DELETE /api/v1/organizations/{orgId}/members/{userId}
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: org.members.delete
```

**Create Organization Request:**
```json
{
  "name": "Example Corp",
  "display_name": "Example Corporation",
  "description": "A software development company",
  "visibility": "private"
}
```

**Create Organization Response:**
```json
{
  "status": "success",
  "data": {
    "id": "org_123",
    "name": "Example Corp",
    "display_name": "Example Corporation",
    "description": "A software development company",
    "visibility": "private",
    "created_at": "2025-02-22T12:00:00Z",
    "updated_at": "2025-02-22T12:00:00Z"
  }
}
```

**Add Member Request:**
```json
{
  "user_id": "usr_123",
  "role": "admin"
}
```

**Add Member Response:**
```json
{
  "status": "success",
  "data": {
    "organization_id": "org_123",
    "user_id": "usr_123",
    "role": "admin",
    "joined_at": "2025-02-22T12:00:00Z"
  }
}
```

## Enterprise Features

### Required Authentication
All endpoints require a valid authentication token.

### Endpoint Authorization

```
POST /api/v1/enterprises
Authorization: Bearer token required
Minimum Role: owner
Required Permissions: enterprise.create

GET /api/v1/enterprises/{enterpriseId}
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: enterprise.read

PUT /api/v1/enterprises/{enterpriseId}
Authorization: Bearer token required
Minimum Role: owner
Required Permissions: enterprise.write

DELETE /api/v1/enterprises/{enterpriseId}
Authorization: Bearer token required
Minimum Role: owner
Required Permissions: enterprise.delete

GET /api/v1/enterprises/{enterpriseId}/features
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: enterprise.features.read

PUT /api/v1/enterprises/{enterpriseId}/features
Authorization: Bearer token required
Minimum Role: owner
Required Permissions: enterprise.features.write
```

**Create Enterprise Request:**
```json
{
  "organization_id": "org_123",
  "tier": "professional",
  "license_key": "ent-pro-123-456",
  "features": {
    "max_users": 100,
    "max_projects": 50,
    "max_storage": 1000000000,
    "custom_domains": true,
    "sso": true
  }
}
```

**Create Enterprise Response:**
```json
{
  "status": "success",
  "data": {
    "id": "ent_123",
    "organization_id": "org_123",
    "tier": "professional",
    "status": "active",
    "features": {
      "max_users": 100,
      "max_projects": 50,
      "max_storage": 1000000000,
      "custom_domains": true,
      "sso": true
    },
    "valid_until": "2026-02-22T12:00:00Z",
    "created_at": "2025-02-22T12:00:00Z",
    "updated_at": "2025-02-22T12:00:00Z"
  }
}
```

## Change Management

### Required Authentication
All endpoints require a valid authentication token.

### Endpoint Authorization

```
POST /api/v1/changes
Authorization: Bearer token required
Minimum Role: member
Required Permissions: changes.create

GET /api/v1/changes/{changeId}
Authorization: Bearer token required
Minimum Role: guest
Required Permissions: changes.read

PUT /api/v1/changes/{changeId}
Authorization: Bearer token required
Minimum Role: member
Required Permissions: changes.write
Additional: Must be change owner or have admin role

DELETE /api/v1/changes/{changeId}
Authorization: Bearer token required
Minimum Role: member
Required Permissions: changes.delete
Additional: Must be change owner or have admin role

GET /api/v1/changes/{changeId}/revisions
Authorization: Bearer token required
Minimum Role: guest
Required Permissions: changes.revisions.read

POST /api/v1/changes/{changeId}/revisions
Authorization: Bearer token required
Minimum Role: member
Required Permissions: changes.revisions.create
Additional: Must be change owner or have admin role

GET /api/v1/changes/{changeId}/comments
Authorization: Bearer token required
Minimum Role: guest
Required Permissions: changes.comments.read

POST /api/v1/changes/{changeId}/comments
Authorization: Bearer token required
Minimum Role: member
Required Permissions: changes.comments.write

PUT /api/v1/changes/{changeId}/votes
Authorization: Bearer token required
Minimum Role: member
Required Permissions: changes.votes.write
```

**Create Change Request:**
```json
{
  "project_id": "proj_123",
  "branch": "feature/new-api",
  "subject": "Add new API endpoints",
  "description": "Implementing new API endpoints for user management",
  "owner_id": "usr_123"
}
```

**Create Change Response:**
```json
{
  "status": "success",
  "data": {
    "id": "chg_123",
    "project_id": "proj_123",
    "branch": "feature/new-api",
    "subject": "Add new API endpoints",
    "description": "Implementing new API endpoints for user management",
    "owner_id": "usr_123",
    "status": "draft",
    "created_at": "2025-02-22T12:00:00Z",
    "updated_at": "2025-02-22T12:00:00Z"
  }
}
```

**Add Comment Request:**
```json
{
  "revision_id": "rev_123",
  "message": "Please add error handling",
  "file_path": "src/api/handlers.rs",
  "line_number": 42
}
```

**Add Comment Response:**
```json
{
  "status": "success",
  "data": {
    "id": "com_123",
    "revision_id": "rev_123",
    "author_id": "usr_123",
    "message": "Please add error handling",
    "file_path": "src/api/handlers.rs",
    "line_number": 42,
    "created_at": "2025-02-22T12:00:00Z",
    "updated_at": "2025-02-22T12:00:00Z"
  }
}
```

## Stack Management

### Required Authentication
All endpoints require a valid authentication token.

### Endpoint Authorization

```
POST /api/v1/stacks
Authorization: Bearer token required
Minimum Role: member
Required Permissions: stacks.create

GET /api/v1/stacks/{stackId}
Authorization: Bearer token required
Minimum Role: guest
Required Permissions: stacks.read

PUT /api/v1/stacks/{stackId}
Authorization: Bearer token required
Minimum Role: member
Required Permissions: stacks.write
Additional: Must be stack owner or have admin role

DELETE /api/v1/stacks/{stackId}
Authorization: Bearer token required
Minimum Role: member
Required Permissions: stacks.delete
Additional: Must be stack owner or have admin role

GET /api/v1/stacks/{stackId}/dependencies
Authorization: Bearer token required
Minimum Role: guest
Required Permissions: stacks.dependencies.read

PUT /api/v1/stacks/{stackId}/dependencies
Authorization: Bearer token required
Minimum Role: member
Required Permissions: stacks.dependencies.write
Additional: Must be stack owner or have admin role
```

**Create Stack Request:**
```json
{
  "name": "Feature Stack",
  "description": "Implement new feature set",
  "owner_id": "usr_123",
  "repository_id": "repo_123",
  "base_branch": "main"
}
```

**Create Stack Response:**
```json
{
  "status": "success",
  "data": {
    "id": "stk_123",
    "name": "Feature Stack",
    "description": "Implement new feature set",
    "owner_id": "usr_123",
    "repository_id": "repo_123",
    "base_branch": "main",
    "status": "open",
    "created_at": "2025-02-22T12:00:00Z",
    "updated_at": "2025-02-22T12:00:00Z"
  }
}
```

**Update Dependencies Request:**
```json
{
  "dependencies": [
    {
      "parent_change_id": "chg_123",
      "child_change_id": "chg_124",
      "relation_type": "direct"
    }
  ]
}
```

**Update Dependencies Response:**
```json
{
  "status": "success",
  "data": {
    "stack_id": "stk_123",
    "dependencies": [
      {
        "id": "dep_123",
        "parent_change_id": "chg_123",
        "child_change_id": "chg_124",
        "relation_type": "direct",
        "created_at": "2025-02-22T12:00:00Z"
      }
    ]
  }
}
```

## Billing Management

### Required Authentication
All endpoints require a valid authentication token.

### Endpoint Authorization

```
GET /api/v1/billing/plans
Authorization: Bearer token required
Minimum Role: member
Required Permissions: billing.plans.read

POST /api/v1/billing/subscriptions
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: billing.subscriptions.create

GET /api/v1/billing/subscriptions/{subscriptionId}
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: billing.subscriptions.read

PUT /api/v1/billing/subscriptions/{subscriptionId}
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: billing.subscriptions.write

DELETE /api/v1/billing/subscriptions/{subscriptionId}
Authorization: Bearer token required
Minimum Role: owner
Required Permissions: billing.subscriptions.delete

GET /api/v1/billing/invoices
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: billing.invoices.read

GET /api/v1/billing/invoices/{invoiceId}
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: billing.invoices.read

POST /api/v1/billing/coupons
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: billing.coupons.create

GET /api/v1/billing/coupons/{couponId}
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: billing.coupons.read
```

**Create Subscription Request:**
```json
{
  "enterprise_id": "ent_123",
  "plan_id": "plan_pro_monthly",
  "payment_method_id": "pm_123",
  "billing_email": "billing@example.com",
  "billing_address": {
    "street": "123 Main St",
    "city": "Example City",
    "state": "EX",
    "postal_code": "12345",
    "country": "US"
  }
}
```

**Create Subscription Response:**
```json
{
  "status": "success",
  "data": {
    "id": "sub_123",
    "enterprise_id": "ent_123",
    "plan_id": "plan_pro_monthly",
    "status": "active",
    "current_period_start": "2025-02-22T12:00:00Z",
    "current_period_end": "2025-03-22T12:00:00Z",
    "billing_email": "billing@example.com",
    "billing_address": {
      "street": "123 Main St",
      "city": "Example City",
      "state": "EX",
      "postal_code": "12345",
      "country": "US"
    },
    "created_at": "2025-02-22T12:00:00Z",
    "updated_at": "2025-02-22T12:00:00Z"
  }
}
```

## Alerts and Monitoring

### Required Authentication
All endpoints require a valid authentication token.

### Endpoint Authorization

```
POST /api/v1/alerts
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: alerts.create

GET /api/v1/alerts/{alertId}
Authorization: Bearer token required
Minimum Role: member
Required Permissions: alerts.read

PUT /api/v1/alerts/{alertId}
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: alerts.write

DELETE /api/v1/alerts/{alertId}
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: alerts.delete

POST /api/v1/alert-rules
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: alerts.rules.create

GET /api/v1/alert-rules/{ruleId}
Authorization: Bearer token required
Minimum Role: member
Required Permissions: alerts.rules.read

PUT /api/v1/alert-rules/{ruleId}
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: alerts.rules.write

DELETE /api/v1/alert-rules/{ruleId}
Authorization: Bearer token required
Minimum Role: admin
Required Permissions: alerts.rules.delete
```

**Create Alert Rule Request:**
```json
{
  "name": "High CPU Usage",
  "description": "Alert when CPU usage exceeds threshold",
  "thresholds": {
    "cpu_usage": 90,
    "duration": 300
  },
  "severity": "warning",
  "enabled": true
}
```

**Create Alert Rule Response:**
```json
{
  "status": "success",
  "data": {
    "id": "rule_123",
    "name": "High CPU Usage",
    "description": "Alert when CPU usage exceeds threshold",
    "thresholds": {
      "cpu_usage": 90,
      "duration": 300
    },
    "severity": "warning",
    "enabled": true,
    "created_at": "2025-02-22T12:00:00Z",
    "updated_at": "2025-02-22T12:00:00Z"
  }
}
```

**Create Alert Request:**
```json
{
  "title": "CPU Usage Alert",
  "message": "CPU usage exceeded 90% for 5 minutes",
  "severity": "warning",
  "source": "system_monitor",
  "metadata": {
    "cpu_usage": 95,
    "duration": 300,
    "host": "server-1"
  }
}
```

**Create Alert Response:**
```json
{
  "status": "success",
  "data": {
    "id": "alert_123",
    "title": "CPU Usage Alert",
    "message": "CPU usage exceeded 90% for 5 minutes",
    "severity": "warning",
    "status": "active",
    "source": "system_monitor",
    "metadata": {
      "cpu_usage": 95,
      "duration": 300,
      "host": "server-1"
    },
    "created_at": "2025-02-22T12:00:00Z",
    "updated_at": "2025-02-22T12:00:00Z"
  }
}
```

## Common Response Formats

All API endpoints return responses in the following format:

```json
{
  "status": "success" | "error",
  "data": { ... },  // Response data for successful requests
  "error": {        // Error information for failed requests
    "code": "string",
    "message": "string",
    "details": { ... }
  }
}
```

## Error Handling

Common HTTP status codes:

- 200: Success
- 201: Created
- 400: Bad Request
- 401: Unauthorized
- 403: Forbidden
- 404: Not Found
- 409: Conflict
- 422: Unprocessable Entity
- 429: Too Many Requests
- 500: Internal Server Error

## Error Response Examples

### Authentication Errors

**Invalid Token (401 Unauthorized)**
```json
{
  "status": "error",
  "error": {
    "code": "invalid_token",
    "message": "The provided authentication token is invalid or expired",
    "details": {
      "token_type": "bearer",
      "error_type": "expired"
    }
  }
}
```

**Insufficient Permissions (403 Forbidden)**
```json
{
  "status": "error",
  "error": {
    "code": "insufficient_permissions",
    "message": "User does not have required permissions",
    "details": {
      "required_role": "admin",
      "required_permissions": ["org.write"],
      "user_role": "member",
      "user_permissions": ["org.read"]
    }
  }
}

**Rate Limit Exceeded (429 Too Many Requests)**
```json
{
  "status": "error",
  "error": {
    "code": "rate_limit_exceeded",
    "message": "API rate limit exceeded",
    "details": {
      "limit": 1000,
      "remaining": 0,
      "reset_at": "2025-02-22T12:30:00Z",
      "retry_after": 300
    }
  }
}
```

### Validation Errors

**Invalid Request (400 Bad Request)**
```json
{
  "status": "error",
  "error": {
    "code": "invalid_request",
    "message": "The request contains invalid parameters",
    "details": {
      "validation_errors": [
        {
          "field": "email",
          "error": "invalid_format",
          "message": "Invalid email format"
        },
        {
          "field": "role",
          "error": "invalid_value",
          "message": "Role must be one of: owner, admin, member, guest"
        }
      ]
    }
  }
}
```

**Resource Not Found (404 Not Found)**
```json
{
  "status": "error",
  "error": {
    "code": "not_found",
    "message": "The requested resource was not found",
    "details": {
      "resource_type": "organization",
      "resource_id": "org_123"
    }
  }
}
```

**Conflict Error (409 Conflict)**
```json
{
  "status": "error",
  "error": {
    "code": "resource_conflict",
    "message": "The request conflicts with existing data",
    "details": {
      "conflict_type": "unique_constraint",
      "field": "name",
      "value": "Example Corp"
    }
  }
}
```

## Rate Limiting

Rate limits vary based on authentication level and enterprise tier:

### Authentication Levels

1. **Unauthenticated**
   ```
   Limit: 60 requests per hour
   Burst: 10 requests per minute
   ```

2. **API Key (Basic)**
   ```
   Limit: 1,000 requests per hour
   Burst: 100 requests per minute
   ```

3. **Bearer Token**
   ```
   Limit: 5,000 requests per hour
   Burst: 500 requests per minute
   ```

### Enterprise Tiers

1. **Basic Tier**
   ```
   Limit: 10,000 requests per hour
   Burst: 1,000 requests per minute
   Concurrent connections: 10
   ```

2. **Professional Tier**
   ```
   Limit: 50,000 requests per hour
   Burst: 5,000 requests per minute
   Concurrent connections: 50
   ```

3. **Enterprise Tier**
   ```
   Limit: 200,000 requests per hour
   Burst: 20,000 requests per minute
   Concurrent connections: 200
   ```

4. **Custom Tier**
   ```
   Configurable limits based on contract
   ```

### Endpoint Categories

Different endpoints have different rate limits:

1. **Read Operations**
   - Higher limits (100% of base limit)
   - Example: GET requests

2. **Write Operations**
   - Medium limits (50% of base limit)
   - Example: POST, PUT requests

3. **Delete Operations**
   - Lower limits (25% of base limit)
   - Example: DELETE requests

4. **Special Operations**
   - Custom limits
   - Example: Bulk operations, exports

### Rate Limit Headers

All responses include rate limit headers:

```
X-RateLimit-Limit: Maximum requests per hour
X-RateLimit-Remaining: Remaining requests
X-RateLimit-Reset: Timestamp when limit resets
X-RateLimit-Used: Number of requests used
X-RateLimit-Resource: Resource being rate limited
```

### Rate Limit Response

When rate limit is exceeded:

```json
{
  "status": "error",
  "error": {
    "code": "rate_limit_exceeded",
    "message": "API rate limit exceeded",
    "details": {
      "limit": 5000,
      "remaining": 0,
      "reset_at": "2025-02-22T13:00:00Z",
      "retry_after": 1800,
      "limit_type": "hourly",
      "resource": "api_calls"
    }
  }
}
```

### Rate Limit Best Practices

1. **Exponential Backoff**
   - Start with a 1-second delay
   - Double delay on each retry
   - Maximum delay of 1 hour

2. **Conditional Requests**
   - Use If-Modified-Since header
   - Use If-None-Match header
   - Reduces unnecessary requests

3. **Bulk Operations**
   - Use batch endpoints when available
   - Reduces number of requests
   - Higher success rate

4. **Caching**
   - Honor Cache-Control headers
   - Implement local caching
   - Reduces unnecessary requests

## Pagination

List endpoints support pagination using:

```
?page=1&per_page=20
?cursor=next_page_token
```

Pagination metadata is included in responses:

```json
{
  "pagination": {
    "total": 100,
    "per_page": 20,
    "current_page": 1,
    "total_pages": 5,
    "next_cursor": "string"
  }
}
```

## Successful Response Examples

### Authentication Endpoints

```json
// POST /api/v1/auth/login/ldap
Request:
{
  "username": "jsmith",
  "password": "secure123"
}

Response: (200 OK)
{
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "user": {
    "id": "usr_123",
    "username": "jsmith",
    "email": "jsmith@example.com",
    "roles": ["member"]
  },
  "expires_at": "2025-01-01T00:00:00Z"
}

// GET /api/v1/auth/user
Response: (200 OK)
{
  "id": "usr_123",
  "username": "jsmith",
  "email": "jsmith@example.com",
  "roles": ["member"],
  "organizations": [
    {
      "id": "org_456",
      "name": "Engineering",
      "role": "member"
    }
  ]
}
```

### Change Management Endpoints

```json
// POST /api/v1/changes
Request:
{
  "project_id": "proj_789",
  "branch": "main",
  "subject": "Add new feature",
  "description": "Implements user requested feature X"
}

Response: (201 Created)
{
  "change_id": "I1234567890",
  "project_id": "proj_789",
  "branch": "main",
  "subject": "Add new feature",
  "description": "Implements user requested feature X",
  "owner": {
    "id": "usr_123",
    "username": "jsmith"
  },
  "status": "draft",
  "created_at": "2025-01-01T00:00:00Z",
  "updated_at": "2025-01-01T00:00:00Z"
}

// GET /api/v1/changes/{changeId}
Response: (200 OK)
{
  "change_id": "I1234567890",
  "project_id": "proj_789",
  "branch": "main",
  "subject": "Add new feature",
  "description": "Implements user requested feature X",
  "owner": {
    "id": "usr_123",
    "username": "jsmith"
  },
  "status": "open",
  "current_revision": {
    "revision_id": "r1234",
    "number": 1,
    "commit_id": "abc123"
  },
  "created_at": "2025-01-01T00:00:00Z",
  "updated_at": "2025-01-01T00:00:00Z"
}
```

### Stack Management Endpoints

```json
// POST /api/v1/stacks
Request:
{
  "name": "feature-x-stack",
  "description": "Complete feature X implementation",
  "repository_id": "repo_123",
  "base_branch": "main"
}

Response: (201 Created)
{
  "stack_id": "stack_456",
  "name": "feature-x-stack",
  "description": "Complete feature X implementation",
  "owner_id": "usr_123",
  "repository": {
    "id": "repo_123",
    "name": "main-repo"
  },
  "base_branch": "main",
  "status": "open",
  "changes": [],
  "created_at": "2025-01-01T00:00:00Z",
  "updated_at": "2025-01-01T00:00:00Z"
}

// POST /api/v1/stacks/{stackId}/dependencies
Request:
{
  "parent_change_id": "I1234567890",
  "child_change_id": "I9876543210",
  "relation_type": "direct"
}

Response: (201 Created)
{
  "dependency_id": "dep_789",
  "parent_change": {
    "id": "I1234567890",
    "subject": "Add feature X base"
  },
  "child_change": {
    "id": "I9876543210",
    "subject": "Add feature X UI"
  },
  "relation_type": "direct",
  "created_at": "2025-01-01T00:00:00Z"
}
```

### Organization Management Endpoints

```json
// POST /api/v1/organizations
Request:
{
  "name": "engineering",
  "display_name": "Engineering Team",
  "description": "Main engineering organization"
}

Response: (201 Created)
{
  "org_id": "org_456",
  "name": "engineering",
  "display_name": "Engineering Team",
  "description": "Main engineering organization",
  "visibility": "private",
  "created_at": "2025-01-01T00:00:00Z",
  "updated_at": "2025-01-01T00:00:00Z"
}

// POST /api/v1/organizations/{orgId}/members
Request:
{
  "user_id": "usr_789",
  "role": "member"
}

Response: (201 Created)
{
  "organization": {
    "id": "org_456",
    "name": "engineering"
  },
  "user": {
    "id": "usr_789",
    "username": "alice"
  },
  "role": "member",
  "created_at": "2025-01-01T00:00:00Z"
}
```

### Enterprise Management Endpoints

```json
// POST /api/v1/enterprises
Request:
{
  "organization_id": "org_456",
  "tier": "professional",
  "license_key": "ent-pro-123-456"
}

Response: (201 Created)
{
  "enterprise_id": "ent_123",
  "organization": {
    "id": "org_456",
    "name": "engineering"
  },
  "tier": "professional",
  "status": "active",
  "features": {
    "max_users": 100,
    "max_projects": 50,
    "advanced_security": true,
    "priority_support": true
  },
  "valid_until": "2026-01-01T00:00:00Z",
  "created_at": "2025-01-01T00:00:00Z",
  "updated_at": "2025-01-01T00:00:00Z"
}
```

### Billing Management Endpoints

```json
// POST /api/v1/billing/plans
Request:
{
  "name": "team-pro",
  "display_name": "Team Professional",
  "price_per_user": 10.00,
  "features": {
    "max_projects": 50,
    "advanced_security": true,
    "priority_support": true
  }
}

Response: (201 Created)
{
  "plan_id": "plan_123",
  "name": "team-pro",
  "display_name": "Team Professional",
  "price_per_user": 10.00,
  "features": {
    "max_projects": 50,
    "advanced_security": true,
    "priority_support": true
  },
  "created_at": "2025-01-01T00:00:00Z",
  "updated_at": "2025-01-01T00:00:00Z"
}

// POST /api/v1/billing/invoices
Request:
{
  "enterprise_id": "ent_123",
  "amount": 1000.00,
  "due_date": "2025-02-01T00:00:00Z",
  "line_items": [
    {
      "description": "10 users x $10.00",
      "amount": 1000.00
    }
  ]
}

Response: (201 Created)
{
  "invoice_id": "inv_456",
  "enterprise": {
    "id": "ent_123",
    "name": "Engineering Team"
  },
  "amount": 1000.00,
  "status": "pending",
  "due_date": "2025-02-01T00:00:00Z",
  "line_items": [
    {
      "description": "10 users x $10.00",
      "amount": 1000.00
    }
  ],
  "created_at": "2025-01-01T00:00:00Z",
  "updated_at": "2025-01-01T00:00:00Z"
}
```

### Alert Management Endpoints

```json
// POST /api/v1/alerts
Request:
{
  "title": "High CPU Usage",
  "message": "Server CPU usage exceeded 90%",
  "severity": "warning",
  "source": "monitoring"
}

Response: (201 Created)
{
  "alert_id": "alert_123",
  "title": "High CPU Usage",
  "message": "Server CPU usage exceeded 90%",
  "severity": "warning",
  "status": "active",
  "source": "monitoring",
  "created_at": "2025-01-01T00:00:00Z",
  "updated_at": "2025-01-01T00:00:00Z"
}

// POST /api/v1/alerts/rules
Request:
{
  "name": "cpu-usage-warning",
  "description": "Alert when CPU usage is high",
  "thresholds": {
    "warning": 80,
    "critical": 90
  }
}

Response: (201 Created)
{
  "rule_id": "rule_456",
  "name": "cpu-usage-warning",
  "description": "Alert when CPU usage is high",
  "enabled": true,
  "thresholds": {
    "warning": 80,
    "critical": 90
  },
  "created_at": "2025-01-01T00:00:00Z",
  "updated_at": "2025-01-01T00:00:00Z"
}
```

## Bulk Operations

Bulk operations allow processing multiple items in a single request to improve efficiency.

### Bulk Create Changes

```json
// POST /api/v1/changes/bulk
Request:
{
  "changes": [
    {
      "project_id": "proj_789",
      "branch": "feature/auth",
      "subject": "Add authentication",
      "description": "Implement OAuth authentication"
    },
    {
      "project_id": "proj_789",
      "branch": "feature/api",
      "subject": "Add API endpoints",
      "description": "Implement REST API endpoints"
    }
  ]
}

Response: (200 OK)
{
  "status": "success",
  "data": {
    "total": 2,
    "successful": 2,
    "failed": 0,
    "changes": [
      {
        "change_id": "I1234567890",
        "status": "created"
      },
      {
        "change_id": "I9876543210",
        "status": "created"
      }
    ]
  }
}
```

### Bulk Update Organization Members

```json
// PUT /api/v1/organizations/{orgId}/members/bulk
Request:
{
  "updates": [
    {
      "user_id": "usr_123",
      "role": "admin"
    },
    {
      "user_id": "usr_456",
      "role": "member"
    }
  ]
}

Response: (200 OK)
{
  "status": "success",
  "data": {
    "total": 2,
    "successful": 2,
    "failed": 0,
    "results": [
      {
        "user_id": "usr_123",
        "status": "updated",
        "role": "admin"
      },
      {
        "user_id": "usr_456",
        "status": "updated",
        "role": "member"
      }
    ]
  }
}
```

### Bulk Delete Alert Rules

```json
// DELETE /api/v1/alert-rules/bulk
Request:
{
  "rule_ids": ["rule_123", "rule_456", "rule_789"]
}

Response: (200 OK)
{
  "status": "success",
  "data": {
    "total": 3,
    "successful": 2,
    "failed": 1,
    "results": [
      {
        "rule_id": "rule_123",
        "status": "deleted"
      },
      {
        "rule_id": "rule_456",
        "status": "deleted"
      },
      {
        "rule_id": "rule_789",
        "status": "error",
        "error": {
          "code": "not_found",
          "message": "Rule not found"
        }
      }
    ]
  }
}
```

## Search and Filtering

The API supports advanced search and filtering capabilities across all list endpoints.

### Full-Text Search

```json
// GET /api/v1/changes/search?q=authentication+oauth&in=subject,description
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "change_id": "I1234567890",
      "subject": "Add OAuth authentication",
      "description": "Implement OAuth provider integration",
      "relevance_score": 0.95
    },
    // ... more matches ...
  ],
  "pagination": {
    "total": 15,
    "per_page": 20,
    "current_page": 1
  }
}
```

### Complex Filtering

```json
// GET /api/v1/changes?filter=status:open+owner:usr_123+project:proj_789+created_after:2025-01-01
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "change_id": "I1234567890",
      "status": "open",
      "owner": {
        "id": "usr_123",
        "username": "jsmith"
      },
      "project_id": "proj_789",
      "created_at": "2025-01-15T00:00:00Z"
    },
    // ... more filtered changes ...
  ]
}

// GET /api/v1/alerts?filter=severity:in:warning,critical+source:monitoring+created_between:2025-01-01,2025-01-31
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "alert_id": "alert_123",
      "severity": "critical",
      "source": "monitoring",
      "created_at": "2025-01-15T00:00:00Z"
    },
    // ... more filtered alerts ...
  ]
}
```

### Filter Operators

The API supports the following filter operators:

- Equality: `field:value`
- Inequality: `field:!value`
- Greater than: `field:>value`
- Less than: `field:<value`
- In list: `field:in:value1,value2`
- Not in list: `field:not_in:value1,value2`
- Between: `field:between:value1,value2`
- Contains: `field:contains:value`
- Starts with: `field:starts_with:value`
- Ends with: `field:ends_with:value`
- Is null: `field:is:null`
- Is not null: `field:is:not_null`

## Sorting and Ordering

All list endpoints support sorting by multiple fields with specified order.

### Single Field Sorting

```json
// GET /api/v1/changes?sort=created_at&order=desc
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "change_id": "I1234567890",
      "subject": "Latest change",
      "created_at": "2025-01-31T00:00:00Z"
    },
    // ... more changes sorted by creation date ...
  ]
}
```

### Multi-Field Sorting

```json
// GET /api/v1/alerts?sort=severity:desc,created_at:asc
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "alert_id": "alert_123",
      "severity": "critical",
      "created_at": "2025-01-15T00:00:00Z"
    },
    // ... more alerts sorted by severity and creation date ...
  ]
}
```

### Sorting with Relationships

```json
// GET /api/v1/organizations/members?sort=user.username:asc,role:desc
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "user": {
        "id": "usr_123",
        "username": "alice"
      },
      "role": "admin"
    },
    // ... more members sorted by username and role ...
  ]
}
```

Common sorting parameters:
```
?sort=field                    // Sort by a single field (default order: asc)
?sort=field:asc|desc          // Sort by a single field with specified order
?sort=field1:asc,field2:desc  // Sort by multiple fields with different orders
```

Sortable fields vary by endpoint and are documented in the respective endpoint sections.

## Resource-Specific Examples

### Stack Management

```json
// GET /api/v1/stacks?filter=status:open+has_conflicts:true+review_score:>=1
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "stack_id": "stk_123",
      "name": "Feature Stack",
      "status": "open",
      "conflict_state": "conflicts_detected",
      "changes": [
        {
          "change_id": "chg_123",
          "subject": "Add feature",
          "review_score": 2
        }
      ]
    }
  ]
}

// GET /api/v1/stacks?filter=dependency_type:direct+base_branch:main+owner:current
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "stack_id": "stk_456",
      "name": "Refactor Stack",
      "base_branch": "main",
      "dependencies": [
        {
          "parent_id": "chg_123",
          "child_id": "chg_124",
          "type": "direct"
        }
      ]
    }
  ]
}
```

### Change Management

```json
// GET /api/v1/changes?filter=reviewer:usr_123+vote_label:code-review+vote_value:>=1
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "change_id": "chg_789",
      "subject": "Fix bug",
      "votes": [
        {
          "user_id": "usr_123",
          "label": "code-review",
          "value": 2
        }
      ]
    }
  ]
}

// GET /api/v1/changes?filter=has_comments:true+comment_type:inline+file_path:contains:src/api
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "change_id": "chg_101",
      "subject": "Update API",
      "comments": [
        {
          "id": "com_123",
          "type": "inline",
          "file_path": "src/api/handlers.rs",
          "line_number": 42
        }
      ]
    }
  ]
}
```

## Advanced Filtering Scenarios

### Combined Filters with OR Conditions

```json
// GET /api/v1/alerts?filter=(severity:critical,warning)+AND+(source:monitoring+OR+source:security)
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "alert_id": "alt_123",
      "severity": "critical",
      "source": "monitoring"
    },
    {
      "alert_id": "alt_124",
      "severity": "warning",
      "source": "security"
    }
  ]
}
```

### Nested Relationship Filtering

```json
// GET /api/v1/organizations?filter=members.role:admin+AND+teams.count:>5+AND+projects.visibility:public
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "org_id": "org_123",
      "name": "Engineering",
      "member_count": {
        "total": 10,
        "admins": 2
      },
      "team_count": 6,
      "public_projects": 3
    }
  ]
}
```

### Time-Based Filtering with Aggregates

```json
// GET /api/v1/changes?filter=created_between:2025-01-01,2025-01-31+AND+comments.count:>5+AND+avg_review_score:>1
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "change_id": "chg_123",
      "created_at": "2025-01-15T00:00:00Z",
      "comment_count": 7,
      "review_metrics": {
        "average_score": 1.5,
        "total_reviews": 3
      }
    }
  ]
}
```

## Bulk Operation Error Handling

### Partial Success Scenarios

```json
// POST /api/v1/changes/bulk
Request:
{
  "changes": [
    {
      "project_id": "proj_123",
      "branch": "feature/1",
      "subject": "Valid change"
    },
    {
      "project_id": "invalid_proj",
      "branch": "feature/2",
      "subject": "Invalid project"
    },
    {
      "project_id": "proj_123",
      "branch": "protected/branch",
      "subject": "Protected branch"
    }
  ]
}

Response: (207 Multi-Status)
{
  "status": "partial_success",
  "data": {
    "total": 3,
    "successful": 1,
    "failed": 2,
    "results": [
      {
        "index": 0,
        "status": "success",
        "change_id": "chg_123"
      },
      {
        "index": 1,
        "status": "error",
        "error": {
          "code": "invalid_project",
          "message": "Project not found"
        }
      },
      {
        "index": 2,
        "status": "error",
        "error": {
          "code": "permission_denied",
          "message": "Cannot create change in protected branch"
        }
      }
    ]
  }
}
```

### Validation Error Handling

```json
// PUT /api/v1/organizations/org_123/members/bulk
Request:
{
  "updates": [
    {
      "user_id": "usr_123",
      "role": "invalid_role"
    },
    {
      "user_id": "usr_456",
      "role": "admin"
    },
    {
      "user_id": "nonexistent",
      "role": "member"
    }
  ]
}

Response: (400 Bad Request)
{
  "status": "error",
  "error": {
    "code": "validation_failed",
    "message": "Some updates failed validation",
    "details": {
      "failed_items": [
        {
          "index": 0,
          "field": "role",
          "error": "invalid_value",
          "message": "Role must be one of: owner, admin, member, guest"
        },
        {
          "index": 2,
          "field": "user_id",
          "error": "not_found",
          "message": "User not found"
        }
      ],
      "valid_items": [1]
    }
  }
}
```

### Transaction Rollback Scenarios

```json
// POST /api/v1/alert-rules/bulk
Request:
{
  "rules": [
    {
      "name": "CPU Alert",
      "threshold": 90
    },
    {
      "name": "Memory Alert",
      "threshold": 85
    },
    {
      "name": "CPU Alert",  // Duplicate name
      "threshold": 95
    }
  ]
}

Response: (409 Conflict)
{
  "status": "error",
  "error": {
    "code": "transaction_failed",
    "message": "Operation rolled back due to unique constraint violation",
    "details": {
      "conflicting_item": {
        "index": 2,
        "field": "name",
        "value": "CPU Alert",
        "constraint": "unique_rule_name"
      },
      "rollback_info": {
        "successful_items": [0, 1],
        "rolled_back": true,
        "reason": "maintain_data_consistency"
      }
    }
  }
}
```

## Additional Resource-Specific Examples

### Enterprise Management

```json
// GET /api/v1/enterprises?filter=tier:professional+AND+status:active+AND+features.sso:true
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "enterprise_id": "ent_123",
      "organization": {
        "id": "org_456",
        "name": "Engineering"
      },
      "tier": "professional",
      "status": "active",
      "features": {
        "sso": true,
        "max_users": 100,
        "max_projects": 50
      },
      "usage_metrics": {
        "current_users": 45,
        "current_projects": 20,
        "storage_used": 5000000
      }
    }
  ]
}

// GET /api/v1/enterprises?filter=valid_until_within:30d+AND+usage.users:>80%
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "enterprise_id": "ent_789",
      "tier": "professional",
      "valid_until": "2025-03-15T00:00:00Z",
      "usage_metrics": {
        "current_users": 85,
        "max_users": 100,
        "usage_percentage": 85
      },
      "alerts": [
        {
          "type": "license_expiring",
          "days_remaining": 25
        },
        {
          "type": "user_limit_warning",
          "message": "Approaching user limit"
        }
      ]
    }
  ]
}
```

### Billing Management

```json
// GET /api/v1/billing/invoices?filter=status:in:pending,overdue+AND+amount:>1000+AND+due_within:7d
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "invoice_id": "inv_123",
      "enterprise_id": "ent_456",
      "amount": 1500.00,
      "status": "pending",
      "due_date": "2025-02-28T00:00:00Z",
      "line_items": [
        {
          "description": "Professional Plan - 15 users",
          "unit_price": 100.00,
          "quantity": 15,
          "amount": 1500.00
        }
      ],
      "payment_attempts": [
        {
          "date": "2025-02-21T00:00:00Z",
          "status": "failed",
          "reason": "insufficient_funds"
        }
      ]
    }
  ]
}

// GET /api/v1/billing/subscriptions?filter=plan:professional+AND+renewal_within:30d+AND+auto_renew:false
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "subscription_id": "sub_123",
      "enterprise_id": "ent_456",
      "plan": {
        "id": "plan_pro",
        "name": "Professional"
      },
      "current_period_end": "2025-03-15T00:00:00Z",
      "auto_renew": false,
      "usage_summary": {
        "licensed_users": 15,
        "active_users": 12,
        "cost_per_user": 100.00,
        "total_cost": 1500.00
      }
    }
  ]
}
```

## Complex Filtering Patterns

### Nested Logic Expressions

```json
// GET /api/v1/changes?filter=(status:open+AND+reviewers.count:>=2)+OR+(status:draft+AND+owner:current)
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "change_id": "chg_123",
      "status": "open",
      "reviewers": [
        {"id": "usr_1", "status": "approved"},
        {"id": "usr_2", "status": "commented"},
        {"id": "usr_3", "status": "pending"}
      ]
    },
    {
      "change_id": "chg_456",
      "status": "draft",
      "owner": {
        "id": "current_user",
        "username": "jsmith"
      }
    }
  ]
}
```

### Aggregate Conditions

```json
// GET /api/v1/organizations?filter=teams.any(members.count:>5+AND+projects.count:>3)+AND+billing.status:active
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "org_id": "org_123",
      "name": "Engineering",
      "teams": [
        {
          "id": "team_1",
          "name": "Frontend",
          "member_count": 8,
          "project_count": 4
        },
        {
          "id": "team_2",
          "name": "Backend",
          "member_count": 6,
          "project_count": 5
        }
      ],
      "billing": {
        "status": "active",
        "plan": "enterprise"
      }
    }
  ]
}
```

### Pattern Matching and Regular Expressions

```json
// GET /api/v1/changes?filter=subject:matches:"^(feat|fix|docs)\\(.+\\):.*"+AND+files.any(path:matches:"^src/.*\\.rs$")
Response: (200 OK)
{
  "status": "success",
  "data": [
    {
      "change_id": "chg_123",
      "subject": "feat(api): add new endpoints",
      "files": [
        {
          "path": "src/api/handlers.rs",
          "changes": "+50/-10"
        }
      ]
    }
  ]
}
```

## Bulk Operation Metrics

### Success/Failure Statistics

```json
// POST /api/v1/changes/bulk/stats
Request:
{
  "time_range": {
    "start": "2025-01-01T00:00:00Z",
    "end": "2025-01-31T23:59:59Z"
  },
  "group_by": ["status", "error_type", "day"]
}

Response: (200 OK)
{
  "status": "success",
  "data": {
    "total_operations": 1250,
    "success_rate": 94.5,
    "metrics": {
      "by_status": {
        "success": 1181,
        "partial_success": 45,
        "failure": 24
      },
      "by_error_type": {
        "validation_error": 15,
        "permission_denied": 8,
        "resource_conflict": 1
      },
      "daily_trends": [
        {
          "date": "2025-01-01",
          "total": 40,
          "success": 38,
          "failure": 2
        }
      ]
    },
    "performance": {
      "average_duration_ms": 245,
      "p95_duration_ms": 500,
      "max_duration_ms": 1200
    }
  }
}
```

### Batch Processing Insights

```json
// GET /api/v1/billing/invoices/bulk/insights
Response: (200 OK)
{
  "status": "success",
  "data": {
    "processing_stats": {
      "total_batches": 150,
      "average_batch_size": 25,
      "success_rate": 98.5,
      "error_distribution": {
        "validation_errors": 45,
        "processing_errors": 12,
        "system_errors": 3
      }
    },
    "performance_metrics": {
      "average_processing_time": {
        "per_batch_ms": 450,
        "per_item_ms": 18
      },
      "resource_usage": {
        "average_cpu_percent": 35,
        "average_memory_mb": 256
      }
    },
    "optimization_suggestions": [
      {
        "type": "batch_size",
        "current": 25,
        "recommended": 40,
        "reason": "Current processing time indicates capacity for larger batches"
      },
      {
        "type": "retry_strategy",
        "current": "linear",
        "recommended": "exponential",
        "reason": "High success rate on retry attempts"
      }
    ]
  }
}
```

### Real-time Monitoring

```json
// GET /api/v1/enterprises/bulk/monitor
Response: (200 OK)
{
  "status": "success",
  "data": {
    "active_operations": {
      "total": 5,
      "by_type": {
        "creation": 2,
        "update": 2,
        "deletion": 1
      },
      "by_status": {
        "in_progress": 3,
        "queued": 2
      }
    },
    "queue_metrics": {
      "current_queue_size": 8,
      "average_wait_time_ms": 120,
      "processing_rate": 15.5
    },
    "health_metrics": {
      "system_status": "healthy",
      "current_load": 0.65,
      "error_rate": 0.02,
      "availability": 0.998
    },
    "alerts": [
      {
        "type": "performance",
        "level": "warning",
        "message": "Processing rate below threshold",
        "threshold": 20,
        "current_value": 15.5
      }
    ]
  }
}
```

## Token Usage Analytics

### Token Usage Statistics

```json
// GET /api/v1/auth/token/analytics
Response: (200 OK)
{
  "status": "success",
  "data": {
    "active_tokens": {
      "total": 15,
      "by_type": {
        "access_token": 8,
        "refresh_token": 5,
        "api_key": 2
      },
      "by_status": {
        "active": 12,
        "grace_period": 2,
        "expiring_soon": 1
      }
    },
    "usage_metrics": {
      "total_requests": 1250,
      "unique_tokens": 10,
      "avg_requests_per_token": 125,
      "by_scope": {
        "user.read": 450,
        "changes.read": 350,
        "changes.write": 200,
        "admin.*": 250
      },
      "by_endpoint": {
        "/api/v1/changes": 400,
        "/api/v1/users": 300,
        "/api/v1/organizations": 250,
        "other": 300
      }
    },
    "time_series": {
      "interval": "1h",
      "data_points": [
        {
          "timestamp": "2025-03-15T14:00:00Z",
          "requests": 120,
          "unique_tokens": 5,
          "error_rate": 0.02
        },
        {
          "timestamp": "2025-03-15T15:00:00Z",
          "requests": 150,
          "unique_tokens": 7,
          "error_rate": 0.01
        }
      ]
    }
  }
}
```

### Token Health Metrics

```json
// GET /api/v1/auth/token/health
Response: (200 OK)
{
  "status": "success",
  "data": {
    "token_health": {
      "overall_score": 92,
      "metrics": {
        "rotation_compliance": 95,
        "scope_utilization": 88,
        "error_rate": 98,
        "security_score": 90
      }
    },
    "security_events": {
      "total": 5,
      "by_severity": {
        "high": 1,
        "medium": 2,
        "low": 2
      },
      "recent_events": [
        {
          "timestamp": "2025-03-15T14:20:00Z",
          "type": "multiple_ip_access",
          "severity": "medium",
          "token_id": "at_def456...",
          "details": {
            "expected_ip": "192.168.1.1",
            "actual_ip": "192.168.1.2"
          }
        }
      ]
    },
    "performance_metrics": {
      "avg_response_time": 120,
      "p95_response_time": 250,
      "error_rate": 0.02,
      "rate_limit_hits": 10
    }
  }
}
```

### Token Usage Patterns

```json
// GET /api/v1/auth/token/patterns
Response: (200 OK)
{
  "status": "success",
  "data": {
    "access_patterns": {
      "by_time": {
        "peak_hours": ["09:00", "14:00", "16:00"],
        "low_activity_hours": ["23:00", "04:00"],
        "weekday_distribution": {
          "Monday": 22,
          "Tuesday": 25,
          "Wednesday": 20,
          "Thursday": 18,
          "Friday": 15
        }
      },
      "by_location": {
        "primary_locations": [
          {
            "ip_range": "192.168.1.0/24",
            "request_count": 800,
            "unique_tokens": 8
          }
        ],
        "unusual_locations": [
          {
            "ip": "10.0.0.50",
            "request_count": 5,
            "first_seen": "2025-03-15T10:00:00Z"
          }
        ]
      },
      "by_user_agent": {
        "browsers": {
          "Chrome": 45,
          "Firefox": 30,
          "Safari": 25
        },
        "platforms": {
          "Windows": 40,
          "MacOS": 35,
          "Linux": 25
        },
        "api_clients": {
          "curl": 15,
          "postman": 10,
          "custom": 75
        }
      }
    },
    "scope_patterns": {
      "common_combinations": [
        {
          "scopes": ["user.read", "changes.read"],
          "usage_count": 500,
          "token_count": 5
        }
      ],
      "unused_scopes": [
        {
          "scope": "admin.billing",
          "last_used": "2025-03-10T14:30:00Z",
          "token_count": 2
        }
      ],
      "over_privileged_tokens": [
        {
          "token_id": "at_def456...",
          "unused_scopes": ["admin.*"],
          "recommendation": "Consider reducing token scope"
        }
      ]
    }
  }
}
```

### Token Usage Reports

```json
// POST /api/v1/auth/token/reports
Request:
{
  "report_type": "usage_analysis",
  "time_range": {
    "start": "2025-03-01T00:00:00Z",
    "end": "2025-03-15T23:59:59Z"
  },
  "filters": {
    "token_types": ["access_token", "api_key"],
    "scopes": ["user.*", "changes.*"],
    "min_requests": 100
  },
  "aggregation": {
    "time_interval": "1d",
    "include_patterns": true,
    "include_security_events": true
  }
}

Response: (200 OK)
{
  "status": "success",
  "data": {
    "report_id": "rep_789",
    "generated_at": "2025-03-15T15:00:00Z",
    "summary": {
      "total_tokens": 12,
      "total_requests": 15000,
      "unique_users": 8,
      "security_events": 5
    },
    "usage_trends": {
      "daily_stats": [
        {
          "date": "2025-03-01",
          "requests": 1000,
          "unique_tokens": 8,
          "error_rate": 0.01
        }
      ],
      "peak_usage": {
        "max_requests": 1500,
        "timestamp": "2025-03-10T14:00:00Z",
        "contributing_factors": [
          "deployment activity",
          "batch operations"
        ]
      }
    },
    "recommendations": [
      {
        "type": "security",
        "priority": "high",
        "message": "Consider rotating tokens older than 30 days",
        "affected_tokens": ["at_def456..."]
      },
      {
        "type": "performance",
        "priority": "medium",
        "message": "Optimize batch operations to reduce rate limiting",
        "affected_endpoints": ["/api/v1/changes/bulk"]
      }
    ]
  }
}
```

<!--
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->
