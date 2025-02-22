<!--
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Technical Implementation

## Database Layer

### Configuration

The database layer is configured through a comprehensive `DatabaseConfig` type that supports all PostgreSQL connection options:

```haskell
data DatabaseConfig = DatabaseConfig
    { dbHost :: Text              -- ^ Database host
    , dbPort :: Int              -- ^ Database port
    , dbName :: Text             -- ^ Database name
    , dbUser :: Text             -- ^ Database user
    , dbPassword :: Text         -- ^ Database password
    , dbPoolSize :: Int          -- ^ Size of the connection pool
    , dbPoolIdleTimeout :: NominalDiffTime    -- ^ Idle timeout for connections
    , dbPoolMaxLifetime :: NominalDiffTime    -- ^ Maximum lifetime of connections
    , dbPoolStripes :: Int       -- ^ Number of stripes (sub-pools)
    , dbLogLevel :: LogLevel     -- ^ Database logging level
    , dbEnableSSL :: Bool        -- ^ Enable SSL connections
    , dbSSLMode :: Text          -- ^ SSL mode (disable, allow, prefer, require, verify-ca, verify-full)
    , dbSSLCert :: Maybe Text    -- ^ Path to client certificate
    , dbSSLKey :: Maybe Text     -- ^ Path to client key
    , dbSSLRootCert :: Maybe Text -- ^ Path to root certificate
    }
```

Configuration is loaded from environment variables with sensible defaults:

   ```haskell
defaultConfig :: Config
defaultConfig = Config
    { configEnvironment = Development
    , configPort = 8080
    , configHost = "localhost"
    , configBaseUrl = "http://localhost:8080"
    , configSecretKey = "change-me-in-production"
    , configDatabase = DatabaseConfig
        { dbHost = "localhost"
        , dbPort = 5432
        , dbName = "gerrit"
        , dbUser = "gerrit"
        , dbPassword = "gerrit"
        , dbPoolSize = 10
        , dbPoolIdleTimeout = 300  -- 5 minutes
        , dbPoolMaxLifetime = 3600  -- 1 hour
        , dbPoolStripes = 2
        , dbLogLevel = LevelWarn
        , dbEnableSSL = False
        , dbSSLMode = "disable"
        , dbSSLCert = Nothing
        , dbSSLKey = Nothing
        , dbSSLRootCert = Nothing
        }
    -- ... other config fields ...
    }
```

### Connection Management

The database layer uses a connection pool for efficient connection management:

   ```haskell
-- Create a new connection pool
createConnPool :: MonadIO m => DatabaseConfig -> m (Either ConnectionError ConnectionPool)

-- Run an action with a connection pool
withConnPool :: MonadIO m
             => DatabaseConfig
             -> (ConnectionPool -> m a)
             -> m (Either ConnectionError a)

-- Properly close a connection pool
closeConnPool :: MonadIO m => ConnectionPool -> m ()

-- Run a database action
runDB :: (MonadReader r m, MonadIO m)
      => (r -> ConnectionPool)
      -> SqlPersistT IO a
      -> m (Either ConnectionError a)

-- Run a database action in a transaction
withTransaction :: (MonadReader r m, MonadIO m)
                => (r -> ConnectionPool)
                -> SqlPersistT IO a
                -> m (Either ConnectionError a)
```

### Error Handling

The database layer uses detailed error types for better error handling:

```haskell
data ConnectionError
    = ConnectionFailed Text
    | InvalidConfig Text
    | PoolCreationFailed Text
    | TransactionFailed Text
    | QueryFailed Text
    | UnknownError Text
    deriving (Show, Eq)

data MigrationError
    = DatabaseConnectionError Text
    | SchemaVersionError Text
    | MigrationExecutionError Text
    | UnknownMigrationError Text
    deriving (Show, Eq)
```

### Migration Management

Database migrations are tracked and versioned:

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
```

## Core Domains

### Change Management

Changes are the central entity in the system:

```haskell
data ChangeStatus = Draft | Open | Merged | Abandoned | Deferred
    deriving (Show, Eq, Generic)

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
|]
```

Key operations:

```haskell
createChange :: MonadIO m
             => Text  -- ^ Project ID
             -> Text  -- ^ Branch
             -> Text  -- ^ Subject
             -> Maybe Text  -- ^ Description
             -> Text  -- ^ Owner ID
             -> m (Either Error (Entity Change))

updateChangeStatus :: MonadIO m
                   => Text  -- ^ Change ID
                   -> ChangeStatus
                   -> m (Either Error ())

getChangeById :: MonadIO m
              => Text  -- ^ Change ID
              -> m (Either Error (Maybe (Entity Change)))

listChanges :: MonadIO m
            => [Filter Change]  -- ^ Filters
            -> [SelectOpt Change]  -- ^ Options
            -> m (Either Error [Entity Change])
```

### Review Process

Reviews are managed through revisions, comments, and votes:

```haskell
data VoteLabel = CodeReview | Verified | Architecture | Security | Performance
    deriving (Show, Eq, Generic)

data VoteValue = VoteBlock | VoteReject | VoteNeutral | VoteApprove | VoteSubmit
    deriving (Show, Eq, Generic)

share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
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
```

### Change Stacks

Change stacks allow managing dependent changes:

```haskell
data StackStatus = StackOpen | StackSubmitting | StackSubmitted | StackAbandoned
    deriving (Show, Eq, Generic)

data RelationType = DirectDependency | IndirectDependency | WeakDependency
    deriving (Show, Eq, Generic)

data RebaseState = RebaseNeeded | RebaseInProgress | RebaseCompleted | RebaseFailed Text
    deriving (Show, Eq, Generic)

data ConflictState = NoConflicts | ConflictsDetected | ConflictsResolved | ConflictsUnresolvable
    deriving (Show, Eq, Generic)

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
```

### Enterprise Features

Enterprise features are managed through a dedicated domain:

```haskell
data EnterpriseTier = Basic | Professional | Enterprise | Custom Text
    deriving (Show, Eq, Generic)

data EnterpriseStatus = Active | Suspended | Expired | Cancelled
    deriving (Show, Eq, Generic)

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
```

### Billing Management

Billing features support subscription management:

```haskell
data BillingStatus = Active | Suspended | Cancelled
    deriving (Show, Eq, Generic)

data InvoiceStatus = Draft | Pending | Paid | Failed | Void
    deriving (Show, Eq, Generic)

data TransactionStatus = Success | TransactionFailed | TransactionPending | Refunded
    deriving (Show, Eq, Generic)

data DiscountType = Percentage | FixedAmount
    deriving (Show, Eq, Generic)

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
```

### Alert System

The alert system manages system notifications:

```haskell
data AlertSeverity = Critical | Warning | Info
    deriving (Show, Eq, Generic)

data AlertStatus = Active | Acknowledged | Resolved
    deriving (Show, Eq, Generic)

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
```

## Performance Optimizations

### Database Indexing

The system uses a comprehensive indexing strategy:

1. **Primary Keys**
   - All entities have unique primary keys
   - Primary keys are automatically indexed

2. **Foreign Keys**
   - All foreign key relationships are indexed
   - Cascade delete behavior where appropriate

3. **Composite Indexes**
   - Unique constraints create composite indexes
   - Common query patterns are indexed

4. **Additional Indexes**
   - Status fields for filtering
   - Timestamp fields for sorting
   - Search fields for text search

### Connection Pool Management

Connection pooling is optimized for performance:

1. **Pool Configuration**
   - Configurable pool size
   - Multiple stripes for better concurrency
   - Idle timeout management
   - Maximum connection lifetime

2. **Connection Reuse**
   - Connections are reused when possible
   - Automatic connection cleanup
   - Connection health checks

3. **Transaction Management**
   - Proper transaction isolation
   - Automatic rollback on errors
   - Connection release on completion

### Query Optimization

Queries are optimized for performance:

1. **Prepared Statements**
   - All common queries use prepared statements
   - Statement caching for better performance

2. **Efficient Joins**
   - Foreign key relationships for efficient joins
   - Proper join order optimization
   - Index usage for join conditions

3. **Pagination**
   - All list operations support pagination
   - Cursor-based pagination for large datasets
   - Efficient count queries

4. **Caching**
   - Query result caching where appropriate
   - Cache invalidation on updates
   - Cache size management

## Security Considerations

### Database Security

1. **Connection Security**
   - SSL/TLS support for all connections
   - Certificate validation
   - Multiple SSL modes supported

2. **Authentication**
   - Strong password policies
   - Connection pooling with secure credentials
   - Role-based access control

3. **Audit Logging**
   - All operations are logged
   - Detailed audit trail
   - Secure log storage

### Data Protection

1. **Encryption**
   - Sensitive data is encrypted
   - Proper key management
   - Secure configuration storage

2. **Access Control**
   - Fine-grained permissions
   - Role-based access
   - Resource ownership tracking

3. **Input Validation**
   - All input is validated
   - SQL injection prevention
   - XSS prevention

## Monitoring and Maintenance

### Health Checks

1. **Connection Health**
   - Pool statistics monitoring
   - Connection timeout tracking
   - Error rate monitoring

2. **Performance Metrics**
   - Query performance tracking
   - Resource usage monitoring
   - Throughput measurements

3. **Error Tracking**
   - Detailed error logging
   - Error categorization
   - Alert thresholds

### Maintenance Tasks

1. **Database Maintenance**
   - Regular vacuum operations
   - Index maintenance
   - Statistics updates

2. **Backup Management**
   - Regular backups
   - Point-in-time recovery
   - Backup verification

3. **Schema Management**
   - Version-controlled migrations
   - Rollback support
   - Migration testing
