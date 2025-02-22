{-|
Module      : Gerrit.Web.Routes.Admin
Description : Administrative routes
Copyright   : (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>
License     : Proprietary
Maintainer  : ghuntley@ghuntley.com
Stability   : experimental
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

module Gerrit.Web.Routes.Admin
    ( adminRoutes
    ) where

import Yesod

import Gerrit.Web.Admin

-- | Administrative routes
adminRoutes :: [ResourceTree App]
adminRoutes =
    [ -- System Administration
      [resourcePattern|/api/admin/system/health|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getSystemHealthR
        }
    , [resourcePattern|/api/admin/system/metrics|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getSystemMetricsR
        }
    , [resourcePattern|/api/admin/system/settings|]
        { resourceMethods = ["GET", "PUT"]
        , resourceGet = Just getSystemSettingsR
        , resourcePut = Just putSystemSettingsR
        }
    , [resourcePattern|/api/admin/system/backup|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postSystemBackupR
        }
    , [resourcePattern|/api/admin/system/backups|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getSystemBackupsR
        }
    , [resourcePattern|/api/admin/system/restore|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postSystemRestoreR
        }
    , [resourcePattern|/api/admin/system/maintenance|]
        { resourceMethods = ["GET", "POST"]
        , resourceGet = Just getSystemMaintenanceR
        , resourcePost = Just postSystemMaintenanceR
        }

    -- User Administration
    , [resourcePattern|/api/admin/users|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getUsersR
        }
    , [resourcePattern|/api/admin/users/bulk|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postUsersBulkR
        }
    , [resourcePattern|/api/admin/users/#Text/activity|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getUserActivityR
        }
    , [resourcePattern|/api/admin/users/#Text/permissions|]
        { resourceMethods = ["PUT"]
        , resourcePut = Just putUserPermissionsR
        }
    , [resourcePattern|/api/admin/users/sessions|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getUserSessionsR
        }
    , [resourcePattern|/api/admin/users/sessions/#Text|]
        { resourceMethods = ["DELETE"]
        , resourceDelete = Just deleteUserSessionR
        }
    , [resourcePattern|/api/admin/users/auth-logs|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getUserAuthLogsR
        }
    , [resourcePattern|/api/admin/users/#Text/lock|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postUserLockR
        }
    , [resourcePattern|/api/admin/users/#Text/unlock|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postUserUnlockR
        }

    -- Resource Management
    , [resourcePattern|/api/admin/resources/usage|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getResourceUsageR
        }
    , [resourcePattern|/api/admin/resources/storage|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getResourceStorageR
        }
    , [resourcePattern|/api/admin/resources/database|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getResourceDatabaseR
        }
    , [resourcePattern|/api/admin/resources/cache|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getResourceCacheR
        }
    , [resourcePattern|/api/admin/resources/cache/clear|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postResourceCacheClearR
        }
    , [resourcePattern|/api/admin/resources/jobs|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getResourceJobsR
        }
    , [resourcePattern|/api/admin/resources/jobs/#Text/cancel|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postResourceJobCancelR
        }
    , [resourcePattern|/api/admin/resources/cleanup|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postResourceCleanupR
        }

    -- Security Administration
    , [resourcePattern|/api/admin/security/policies|]
        { resourceMethods = ["GET", "PUT"]
        , resourceGet = Just getSecurityPoliciesR
        , resourcePut = Just putSecurityPoliciesR
        }
    , [resourcePattern|/api/admin/security/auth-providers|]
        { resourceMethods = ["GET", "PUT"]
        , resourceGet = Just getAuthProvidersR
        , resourcePut = Just putAuthProvidersR
        }
    , [resourcePattern|/api/admin/security/api-keys|]
        { resourceMethods = ["GET", "POST"]
        , resourceGet = Just getApiKeysR
        , resourcePost = Just postApiKeysR
        }
    , [resourcePattern|/api/admin/security/api-keys/#Text|]
        { resourceMethods = ["DELETE"]
        , resourceDelete = Just deleteApiKeyR
        }
    , [resourcePattern|/api/admin/security/rate-limits|]
        { resourceMethods = ["GET", "PUT"]
        , resourceGet = Just getRateLimitsR
        , resourcePut = Just putRateLimitsR
        }
    , [resourcePattern|/api/admin/security/ip-allowlist|]
        { resourceMethods = ["GET", "PUT"]
        , resourceGet = Just getIpAllowlistR
        , resourcePut = Just putIpAllowlistR
        }
    , [resourcePattern|/api/admin/security/audit-logs|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getSecurityAuditLogsR
        }

    -- Enterprise Administration
    , [resourcePattern|/api/admin/enterprises/settings|]
        { resourceMethods = ["GET", "PUT"]
        , resourceGet = Just getEnterpriseSettingsR
        , resourcePut = Just putEnterpriseSettingsR
        }
    , [resourcePattern|/api/admin/enterprises/licenses|]
        { resourceMethods = ["GET", "POST"]
        , resourceGet = Just getEnterpriseLicensesR
        , resourcePost = Just postEnterpriseLicenseR
        }
    , [resourcePattern|/api/admin/enterprises/quotas|]
        { resourceMethods = ["GET", "PUT"]
        , resourceGet = Just getEnterpriseQuotasR
        , resourcePut = Just putEnterpriseQuotasR
        }
    , [resourcePattern|/api/admin/enterprises/analytics|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getEnterpriseAnalyticsR
        }
    , [resourcePattern|/api/admin/enterprises/reports|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getEnterpriseReportsR
        }
    , [resourcePattern|/api/admin/enterprises/policies|]
        { resourceMethods = ["GET", "PUT"]
        , resourceGet = Just getEnterprisePoliciesR
        , resourcePut = Just putEnterprisePoliciesR
        }
    , [resourcePattern|/api/admin/enterprises/backup|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postEnterpriseBackupR
        }

    -- Configuration Management
    , [resourcePattern|/api/admin/config|]
        { resourceMethods = ["GET", "PUT"]
        , resourceGet = Just getConfigR
        , resourcePut = Just putConfigR
        }
    , [resourcePattern|/api/admin/config/features|]
        { resourceMethods = ["GET", "PUT"]
        , resourceGet = Just getFeaturesR
        , resourcePut = Just putFeaturesR
        }
    , [resourcePattern|/api/admin/config/env|]
        { resourceMethods = ["GET", "PUT"]
        , resourceGet = Just getEnvVarsR
        , resourcePut = Just putEnvVarsR
        }
    , [resourcePattern|/api/admin/config/services|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getServicesR
        }
    , [resourcePattern|/api/admin/config/services/#Text|]
        { resourceMethods = ["PUT"]
        , resourcePut = Just putServiceR
        }
    , [resourcePattern|/api/admin/config/email-templates|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getEmailTemplatesR
        }
    , [resourcePattern|/api/admin/config/email-templates/#Text|]
        { resourceMethods = ["PUT"]
        , resourcePut = Just putEmailTemplateR
        }
    , [resourcePattern|/api/admin/config/webhooks|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getWebhooksR
        }
    , [resourcePattern|/api/admin/config/webhooks/#Text|]
        { resourceMethods = ["PUT"]
        , resourcePut = Just putWebhookR
        }

    -- Maintenance Tools
    , [resourcePattern|/api/admin/maintenance/database|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postMaintenanceDatabaseR
        }
    , [resourcePattern|/api/admin/maintenance/cache|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postMaintenanceCacheR
        }
    , [resourcePattern|/api/admin/maintenance/storage|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postMaintenanceStorageR
        }
    , [resourcePattern|/api/admin/maintenance/logs|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postMaintenanceLogsR
        }
    , [resourcePattern|/api/admin/maintenance/index|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postMaintenanceIndexR
        }
    , [resourcePattern|/api/admin/maintenance/migrate|]
        { resourceMethods = ["POST"]
        , resourcePost = Just postMaintenanceMigrateR
        }
    , [resourcePattern|/api/admin/maintenance/diagnostics|]
        { resourceMethods = ["GET"]
        , resourceGet = Just getMaintenanceDiagnosticsR
        }
    ]
