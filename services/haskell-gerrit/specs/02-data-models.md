<!--
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Data Models

## Domain Overview

The Gerrit system is built around several core domains:

1. **Core Review Domain**: Manages changes, revisions, comments, and votes
2. **Organization Domain**: Handles organizations, teams, and member management
3. **Enterprise Domain**: Enterprise-level features and licensing
4. **Billing Domain**: Subscription plans and payment processing
5. **Administrative Domain**: System configuration and monitoring
6. **Stack Domain**: Change stacks and dependencies
7. **Alert Domain**: System alerts and notifications
8. **Audit Domain**: Comprehensive audit logging

## Database Design

### PostgreSQL with Persistent

The system uses PostgreSQL as the primary database, leveraging the `persistent` library for type-safe database operations. This provides:

- Type-safe database operations with compile-time checks
- Automatic schema migrations with version tracking
- Proper transaction support with ACID guarantees
- Connection pooling with configurable settings
- Query optimization and prepared statements
- Foreign key relationships with cascade behavior

### Core Types

```haskell
-- Core ID type
type EntityId = Text

-- Timestamp wrapper
data Timestamp = Timestamp
    { createdAt :: UTCTime
    , updatedAt :: UTCTime
    }

-- Common status types
data ChangeStatus = Draft | Open | Merged | Abandoned | Deferred
data Visibility = Public | Private | Internal
data Role = Owner | Admin | Member | Guest
data Permission = Read | Write | Execute | Delete | Grant
data ResourceType = ChangeResource | RevisionResource | CommentResource | VoteResource
                 | OrganizationResource | EnterpriseResource | AdminResource
                 | AlertResource | StackResource | BillingResource
data ActionType = Create | Read | Update | Delete | Grant | Revoke
                | Enable | Disable | Configure
```

### Core Review Domain

```haskell
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Change
    changeId Text
    projectId Text
    branch Text
    subject Text
    description Text Maybe
    ownerId Text
    status ChangeStatus
    created UTCTime
    updated UTCTime
    UniqueChangeId changeId
    deriving Show Eq Generic

Revision
    revisionId Text
    changeId Text
    number Int
    commitId Text
    uploaderId Text
    description Text Maybe
    created UTCTime
    updated UTCTime
    UniqueRevisionId revisionId
    UniqueChangeRevision changeId number
    Foreign Change changeId References changes OnDeleteCascade
    deriving Show Eq Generic

Comment
    commentId Text
    revisionId Text
    authorId Text
    commentType CommentType
    message Text
    filePath Text Maybe
    lineNumber Int Maybe
    resolved Bool default=false
    resolvedBy Text Maybe
    resolvedAt UTCTime Maybe
    created UTCTime
    updated UTCTime
    UniqueCommentId commentId
    Foreign Revision revisionId References revisions OnDeleteCascade
    deriving Show Eq Generic

Vote
    voteId Text
    revisionId Text
    voterId Text
    label VoteLabel
    value VoteValue
    message Text Maybe
    created UTCTime
    updated UTCTime
    UniqueVoteId voteId
    UniqueVoteConstraint revisionId voterId label
    Foreign Revision revisionId References revisions OnDeleteCascade
    deriving Show Eq Generic
|]

data VoteLabel = CodeReview | Verified | Architecture | Security | Performance
data VoteValue = VoteBlock | VoteReject | VoteNeutral | VoteApprove | VoteSubmit
data CommentType = Inline | General | Reply Text
```

### Stack Domain

```haskell
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
ChangeStack
    stackId Text
    name Text
    description Text Maybe
    ownerId Text
    repositoryId Text
    baseBranch Text
    status StackStatus
    created UTCTime
    updated UTCTime
    UniqueStackId stackId
    deriving Show Eq Generic

StackDependency
    dependencyId Text
    stackId Text
    parentChangeId Text
    childChangeId Text
    relationType RelationType
    created UTCTime
    UniqueDependencyId dependencyId
    UniqueStackDependency stackId parentChangeId childChangeId
    Foreign ChangeStack stackId References stacks OnDeleteCascade
    Foreign Change parentChangeId References changes OnDeleteCascade
    Foreign Change childChangeId References changes OnDeleteCascade
    deriving Show Eq Generic

StackState
    stateId Text
    stackId Text
    changeId Text
    status Text
    rebaseState RebaseState Maybe
    conflictState ConflictState Maybe
    lastSyncHash Text Maybe
    created UTCTime
    updated UTCTime
    UniqueStateId stateId
    UniqueStackState stackId changeId
    Foreign ChangeStack stackId References stacks OnDeleteCascade
    Foreign Change changeId References changes OnDeleteCascade
    deriving Show Eq Generic
|]

data StackStatus = StackOpen | StackSubmitting | StackSubmitted | StackAbandoned
data RelationType = DirectDependency | IndirectDependency | WeakDependency
data RebaseState = RebaseNeeded | RebaseInProgress | RebaseCompleted | RebaseFailed Text
data ConflictState = NoConflicts | ConflictsDetected | ConflictsResolved | ConflictsUnresolvable
```

### Enterprise Domain

```haskell
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Enterprise
    enterpriseId Text
    orgId Text
    tier EnterpriseTier
    status EnterpriseStatus
    licenseKey Text
    validUntil UTCTime
    features Value
    maxUsers Int Maybe
    maxProjects Int Maybe
    maxStorage Int64 Maybe
    customFeatures Value Maybe
    created UTCTime
    updated UTCTime
    UniqueEnterpriseId enterpriseId
    Foreign Organization orgId References organizations OnDeleteCascade
    deriving Show Eq Generic

EnterpriseAudit
    auditId Text
    enterpriseId Text
    action Text
    details Value
    performedBy Text
    timestamp UTCTime
    UniqueEnterpriseAuditId auditId
    Foreign Enterprise enterpriseId References enterprises OnDeleteCascade
    deriving Show Eq Generic
|]

data EnterpriseTier = Basic | Professional | Enterprise | Custom Text
data EnterpriseStatus = Active | Suspended | Expired | Cancelled
```

### Alert Domain

```haskell
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Alert
    alertId Text
    title Text
    message Text
    severity AlertSeverity
    status AlertStatus
    source Text
    timestamp UTCTime
    acknowledgedBy Text Maybe
    acknowledgedAt UTCTime Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueAlertId alertId
    deriving Show Eq Generic

AlertRule
    ruleId Text
    name Text
    description Text
    enabled Bool
    thresholds Value
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueAlertRuleId ruleId
    UniqueAlertRuleName name
    deriving Show Eq Generic
|]

data AlertSeverity = Critical | Warning | Info
data AlertStatus = Active | Acknowledged | Resolved
```

### Billing Domain

```haskell
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
BillingPlan
    planId Text
    name Text
    displayName Text
    description Text Maybe
    pricePerUser Scientific
    features Value
    created UTCTime
    updated UTCTime
    UniquePlanId planId
    deriving Show Eq Generic

EnterpriseBilling
    billingId Text
    enterpriseId Text
    planId Text
    status BillingStatus
    paymentMethodId Text Maybe
    email Text
    address Value
    taxId Text Maybe
    nextBillingDate UTCTime
    lastBillingDate UTCTime Maybe
    created UTCTime
    updated UTCTime
    UniqueBillingId billingId
    Foreign Enterprise enterpriseId
    Foreign BillingPlan planId
    deriving Show Eq Generic

BillingInvoice
    invoiceId Text
    enterpriseId Text
    amount Scientific
    status InvoiceStatus
    dueDate UTCTime
    paidDate UTCTime Maybe
    lineItems Value
    couponId Text Maybe
    discountAmount Scientific Maybe
    finalAmount Scientific
    paymentDetails Value Maybe
    created UTCTime
    updated UTCTime
    UniqueInvoiceId invoiceId
    Foreign EnterpriseBilling enterpriseId
    deriving Show Eq Generic

Coupon
    couponId Text
    code Text
    description Text Maybe
    discountType DiscountType
    discountValue Scientific
    validFrom UTCTime
    validUntil UTCTime Maybe
    maxUses Int Maybe
    currentUses Int
    minAmount Scientific Maybe
    maxAmount Scientific Maybe
    allowedPlans [Text] Maybe
    created UTCTime
    updated UTCTime
    UniqueCouponId couponId
    UniqueCouponCode code
    deriving Show Eq Generic
|]

data BillingStatus = Active | Suspended | Cancelled
data InvoiceStatus = Draft | Pending | Paid | Failed | Void
data TransactionStatus = Success | TransactionFailed | TransactionPending | Refunded
data DiscountType = Percentage | FixedAmount
```

### Migration Management

```haskell
share [mkPersist sqlSettings] [persistLowerCase|
MigrationHistory
    version Int
    name Text
    appliedAt UTCTime
    details Value Maybe
    UniqueMigrationVersion version
    deriving Show Eq Generic
|]

data MigrationStatus
    = MigrationNeeded [Text]  -- List of pending migrations
    | MigrationUpToDate       -- No migrations needed
    | MigrationFailed MigrationError  -- Migration failed with error

data MigrationError
    = DatabaseConnectionError Text
    | SchemaVersionError Text
    | MigrationExecutionError Text
    | UnknownMigrationError Text
```

## Database Operations

### Connection Management

```haskell
-- Database configuration
data DatabaseConfig = DatabaseConfig
    { dbHost :: Text
    , dbPort :: Int
    , dbName :: Text
    , dbUser :: Text
    , dbPassword :: Text
    , dbPoolSize :: Int
    , dbPoolIdleTimeout :: NominalDiffTime
    , dbPoolMaxLifetime :: NominalDiffTime
    , dbPoolStripes :: Int
    , dbLogLevel :: LogLevel
    , dbEnableSSL :: Bool
    , dbSSLMode :: Text
    , dbSSLCert :: Maybe Text
    , dbSSLKey :: Maybe Text
    , dbSSLRootCert :: Maybe Text
    }

-- Connection pool management
createConnPool :: MonadIO m => DatabaseConfig -> m (Either ConnectionError ConnectionPool)
withConnPool :: MonadIO m => DatabaseConfig -> (ConnectionPool -> m a) -> m (Either ConnectionError a)
closeConnPool :: MonadIO m => ConnectionPool -> m ()
runDB :: (MonadReader r m, MonadIO m) => (r -> ConnectionPool) -> SqlPersistT IO a -> m (Either ConnectionError a)
withTransaction :: (MonadReader r m, MonadIO m) => (r -> ConnectionPool) -> SqlPersistT IO a -> m (Either ConnectionError a)
```

## Performance Considerations

1. **Indexing Strategy**
   - Primary keys are automatically indexed
   - Foreign keys are indexed for efficient joins
   - Composite indexes for unique constraints
   - Additional indexes on frequently queried fields

2. **Connection Pooling**
   - Configurable pool size and stripes
   - Idle timeout management
   - Maximum connection lifetime
   - Connection reuse optimization

3. **Query Optimization**
   - Prepared statements
   - Efficient joins through foreign keys
   - Pagination support
   - Proper transaction isolation

4. **Migration Management**
   - Version tracking
   - Automatic schema updates
   - Migration history logging
   - Rollback support

5. **Error Handling**
   - Type-safe operations
   - Detailed error types
   - Transaction rollback
   - Connection error recovery

6. **Audit Logging**
   - Comprehensive action tracking
   - Resource versioning
   - Change history
   - Performance impact consideration
