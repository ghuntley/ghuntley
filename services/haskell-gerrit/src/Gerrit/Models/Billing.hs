-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Gerrit.Models.Billing
    ( -- * Types
      BillingPlan(..)
    , BillingPlanId
    , EnterpriseBilling(..)
    , EnterpriseBillingId
    , BillingInvoice(..)
    , BillingInvoiceId
    , BillingTransaction(..)
    , BillingTransactionId
    , BillingStatus(..)
    , InvoiceStatus(..)
    , TransactionStatus(..)
    , DiscountType(..)
    , Coupon(..)
    , CouponId
    -- * Operations
    , createBillingPlan
    , getBillingPlanById
    , updateBillingPlan
    , listBillingPlans
    , createEnterpriseBilling
    , getEnterpriseBillingById
    , updateEnterpriseBilling
    , createBillingInvoice
    , getBillingInvoiceById
    , updateBillingInvoice
    , listEnterpriseInvoices
    , createBillingTransaction
    , getBillingTransactionById
    , listInvoiceTransactions
    , createCoupon
    , getCouponById
    , getCouponByCode
    , updateCoupon
    , listCoupons
    , validateCoupon
    , applyCoupon
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value, FromJSON(..), ToJSON(..))
import Data.Scientific (Scientific)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, addUTCTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.Enterprise (Enterprise)

-- | Billing status
data BillingStatus
    = Active
    | Suspended
    | Cancelled
    | PastDue
    deriving (Show, Read, Eq, Generic)
derivePersistField "BillingStatus"

-- | Invoice status
data InvoiceStatus
    = Draft
    | Pending
    | Paid
    | Overdue
    | Void
    deriving (Show, Read, Eq, Generic)
derivePersistField "InvoiceStatus"

-- | Transaction status
data TransactionStatus
    = Initiated
    | Processing
    | Completed
    | Failed
    | Refunded
    deriving (Show, Read, Eq, Generic)
derivePersistField "TransactionStatus"

-- | Discount type
data DiscountType
    = Percentage
    | FixedAmount
    | CustomDiscount Text
    deriving (Show, Read, Eq, Generic)
derivePersistField "DiscountType"

-- | Define the billing entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
BillingPlan
    planId Text
    name Text
    description Text
    price Double
    billingCycle Text
    features Value
    trialDays Int Maybe
    status BillingStatus
    created UTCTime
    updated UTCTime
    UniquePlanId planId
    deriving Show Eq Generic

EnterpriseBilling
    billingId Text
    enterpriseId Text
    planId Text
    status BillingStatus
    nextBillingDate UTCTime
    paymentMethod Value
    billingAddress Value
    taxInfo Value Maybe
    created UTCTime
    updated UTCTime
    UniqueBillingId billingId
    Foreign Enterprise enterpriseId References enterprises OnDeleteCascade
    Foreign BillingPlan planId References billingPlans OnDeleteCascade
    deriving Show Eq Generic

BillingInvoice
    invoiceId Text
    billingId Text
    amount Double
    tax Double
    total Double
    items Value
    status InvoiceStatus
    dueDate UTCTime
    paidAt UTCTime Maybe
    created UTCTime
    updated UTCTime
    UniqueInvoiceId invoiceId
    Foreign EnterpriseBilling billingId References enterpriseBillings OnDeleteCascade
    deriving Show Eq Generic

BillingTransaction
    transactionId Text
    invoiceId Text
    amount Double
    paymentMethod Value
    status TransactionStatus
    errorMessage Text Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueTransactionId transactionId
    Foreign BillingInvoice invoiceId References billingInvoices OnDeleteCascade
    deriving Show Eq Generic

Coupon
    couponId Text
    code Text
    description Text
    discountType DiscountType
    discountValue Double
    validFrom UTCTime
    validUntil UTCTime
    maxUses Int Maybe
    usedCount Int
    created UTCTime
    updated UTCTime
    UniqueCouponId couponId
    UniqueCouponCode code
    deriving Show Eq Generic
|]

-- | Create a new billing plan
createBillingPlan :: MonadIO m
                  => Text  -- ^ Name
                  -> Text  -- ^ Description
                  -> Double  -- ^ Price
                  -> Text  -- ^ Billing cycle
                  -> Value  -- ^ Features
                  -> Maybe Int  -- ^ Trial days
                  -> m (Entity BillingPlan)
createBillingPlan name description price cycle features trialDays = do
    now <- liftIO getCurrentTime
    let planId = generatePlanId name now
    let plan = BillingPlan
            { billingPlanPlanId = planId
            , billingPlanName = name
            , billingPlanDescription = description
            , billingPlanPrice = price
            , billingPlanBillingCycle = cycle
            , billingPlanFeatures = features
            , billingPlanTrialDays = trialDays
            , billingPlanStatus = Active
            , billingPlanCreated = now
            , billingPlanUpdated = now
            }
    runDB $ insertEntity plan

-- | Get billing plan by ID
getBillingPlanById :: MonadIO m
                   => Text  -- ^ Plan ID
                   -> m (Maybe (Entity BillingPlan))
getBillingPlanById planId =
    runDB $ getBy $ UniquePlanId planId

-- | Update billing plan
updateBillingPlan :: MonadIO m
                  => Entity BillingPlan
                  -> Text  -- ^ Name
                  -> Text  -- ^ Description
                  -> Double  -- ^ Price
                  -> Text  -- ^ Billing cycle
                  -> Value  -- ^ Features
                  -> BillingStatus  -- ^ Status
                  -> m (Entity BillingPlan)
updateBillingPlan (Entity key plan) name description price cycle features status = do
    now <- liftIO getCurrentTime
    let updatedPlan = plan
            { billingPlanName = name
            , billingPlanDescription = description
            , billingPlanPrice = price
            , billingPlanBillingCycle = cycle
            , billingPlanFeatures = features
            , billingPlanStatus = status
            , billingPlanUpdated = now
            }
    runDB $ replace key updatedPlan
    return $ Entity key updatedPlan

-- | List billing plans
listBillingPlans :: MonadIO m
                 => Maybe BillingStatus  -- ^ Status filter
                 -> Int  -- ^ Offset
                 -> Int  -- ^ Limit
                 -> m [Entity BillingPlan]
listBillingPlans mStatus offset limit = do
    let filters = maybe [] (\status -> [BillingPlanStatus ==. status]) mStatus
    runDB $ selectList filters [Asc BillingPlanName, OffsetBy offset, LimitTo limit]

-- | Create enterprise billing
createEnterpriseBilling :: MonadIO m
                       => ConnectionPool
                       -> Text  -- ^ Enterprise ID
                       -> Text  -- ^ Plan ID
                       -> Text  -- ^ Billing email
                       -> Value  -- ^ Billing address
                       -> Maybe Text  -- ^ Tax ID
                       -> m (Entity EnterpriseBilling)
createEnterpriseBilling pool enterpriseId planId email address taxId = do
    now <- liftIO getCurrentTime
    let billing = EnterpriseBilling
            { enterpriseBillingBillingId = generateBillingId enterpriseId now
            , enterpriseBillingEnterpriseId = enterpriseId
            , enterpriseBillingPlanId = planId
            , enterpriseBillingStatus = Active
            , enterpriseBillingPaymentMethodId = Nothing
            , enterpriseBillingEmail = email
            , enterpriseBillingAddress = address
            , enterpriseBillingTaxId = taxId
            , enterpriseBillingNextBillingDate = now
            , enterpriseBillingLastBillingDate = Nothing
            , enterpriseBillingCreated = now
            , enterpriseBillingUpdated = now
            }
    runSqlPool (insertEntity billing) pool

-- | Get enterprise billing
getEnterpriseBillingById :: MonadIO m
                        => ConnectionPool
                        -> Text  -- ^ Enterprise ID
                        -> m (Maybe (Entity EnterpriseBilling))
getEnterpriseBillingById pool enterpriseId =
    runSqlPool (getBy $ UniqueBillingId enterpriseId) pool

-- | Update enterprise billing
updateEnterpriseBilling :: MonadIO m
                       => ConnectionPool
                       -> Entity EnterpriseBilling
                       -> EnterpriseBilling
                       -> m (Entity EnterpriseBilling)
updateEnterpriseBilling pool (Entity billingKey _) billing = do
    now <- liftIO getCurrentTime
    let updatedBilling = billing { enterpriseBillingUpdated = now }
    runSqlPool (replace billingKey updatedBilling) pool
    return $ Entity billingKey updatedBilling

-- | Create billing invoice
createBillingInvoice :: MonadIO m
                    => ConnectionPool
                    -> Text  -- ^ Enterprise ID
                    -> Scientific  -- ^ Amount
                    -> UTCTime  -- ^ Due date
                    -> Value  -- ^ Line items
                    -> Maybe Text  -- ^ Coupon ID
                    -> m (Entity BillingInvoice)
createBillingInvoice pool enterpriseId amount dueDate lineItems couponId = do
    now <- liftIO getCurrentTime
    let invoice = BillingInvoice
            { billingInvoiceInvoiceId = generateInvoiceId enterpriseId now
            , billingInvoiceEnterpriseId = enterpriseId
            , billingInvoiceAmount = amount
            , billingInvoiceStatus = Draft
            , billingInvoiceDueDate = dueDate
            , billingInvoicePaidDate = Nothing
            , billingInvoiceLineItems = lineItems
            , billingInvoiceCouponId = couponId
            , billingInvoiceDiscountAmount = Nothing
            , billingInvoiceFinalAmount = amount
            , billingInvoicePaymentDetails = Nothing
            , billingInvoiceCreated = now
            , billingInvoiceUpdated = now
            }
    runSqlPool (insertEntity invoice) pool

-- | Get billing invoice by ID
getBillingInvoiceById :: MonadIO m
                     => ConnectionPool
                     -> Text  -- ^ Invoice ID
                     -> m (Maybe (Entity BillingInvoice))
getBillingInvoiceById pool invoiceId =
    runSqlPool (getBy $ UniqueInvoiceId invoiceId) pool

-- | Update billing invoice
updateBillingInvoice :: MonadIO m
                    => ConnectionPool
                    -> Entity BillingInvoice
                    -> BillingInvoice
                    -> m (Entity BillingInvoice)
updateBillingInvoice pool (Entity invoiceKey _) invoice = do
    now <- liftIO getCurrentTime
    let updatedInvoice = invoice { billingInvoiceUpdated = now }
    runSqlPool (replace invoiceKey updatedInvoice) pool
    return $ Entity invoiceKey updatedInvoice

-- | List enterprise invoices
listEnterpriseInvoices :: MonadIO m
                      => ConnectionPool
                      -> Text  -- ^ Enterprise ID
                      -> m [Entity BillingInvoice]
listEnterpriseInvoices pool enterpriseId =
    runSqlPool (selectList [BillingInvoiceEnterpriseId ==. enterpriseId] [Desc BillingInvoiceCreated]) pool

-- | Create billing transaction
createBillingTransaction :: MonadIO m
                       => ConnectionPool
                       -> Text  -- ^ Invoice ID
                       -> Scientific  -- ^ Amount
                       -> Text  -- ^ Payment method
                       -> Value  -- ^ Payment details
                       -> m (Entity BillingTransaction)
createBillingTransaction pool invoiceId amount method details = do
    now <- liftIO getCurrentTime
    let transaction = BillingTransaction
            { billingTransactionTransactionId = generateTransactionId invoiceId now
            , billingTransactionInvoiceId = invoiceId
            , billingTransactionAmount = amount
            , billingTransactionStatus = Initiated
            , billingTransactionPaymentMethod = method
            , billingTransactionPaymentDetails = details
            , billingTransactionCreated = now
            }
    runSqlPool (insertEntity transaction) pool

-- | Get billing transaction by ID
getBillingTransactionById :: MonadIO m
                        => ConnectionPool
                        -> Text  -- ^ Transaction ID
                        -> m (Maybe (Entity BillingTransaction))
getBillingTransactionById pool transactionId =
    runSqlPool (getBy $ UniqueTransactionId transactionId) pool

-- | List invoice transactions
listInvoiceTransactions :: MonadIO m
                       => ConnectionPool
                       -> Text  -- ^ Invoice ID
                       -> m [Entity BillingTransaction]
listInvoiceTransactions pool invoiceId =
    runSqlPool (selectList [BillingTransactionInvoiceId ==. invoiceId] [Desc BillingTransactionCreated]) pool

-- | Create coupon
createCoupon :: MonadIO m
             => Text  -- ^ Code
             -> Text  -- ^ Description
             -> DiscountType  -- ^ Discount type
             -> Double  -- ^ Discount value
             -> UTCTime  -- ^ Valid from
             -> UTCTime  -- ^ Valid until
             -> Maybe Int  -- ^ Max uses
             -> m (Entity Coupon)
createCoupon code description discountType discountValue validFrom validUntil maxUses = do
    now <- liftIO getCurrentTime
    let couponId = generateCouponId code now
    let coupon = Coupon
            { couponCouponId = couponId
            , couponCode = code
            , couponDescription = description
            , couponDiscountType = discountType
            , couponDiscountValue = discountValue
            , couponValidFrom = validFrom
            , couponValidUntil = validUntil
            , couponMaxUses = maxUses
            , couponUsedCount = 0
            , couponCreated = now
            , couponUpdated = now
            }
    runDB $ insertEntity coupon

-- | Get coupon by ID
getCouponById :: MonadIO m
             => ConnectionPool
             -> Text  -- ^ Coupon ID
             -> m (Maybe (Entity Coupon))
getCouponById pool couponId =
    runSqlPool (getBy $ UniqueCouponId couponId) pool

-- | Get coupon by code
getCouponByCode :: MonadIO m
                => ConnectionPool
                -> Text  -- ^ Coupon code
                -> m (Maybe (Entity Coupon))
getCouponByCode pool code =
    runSqlPool (getBy $ UniqueCouponCode code) pool

-- | Update coupon
updateCoupon :: MonadIO m
            => ConnectionPool
            -> Entity Coupon
            -> Coupon
            -> m (Entity Coupon)
updateCoupon pool (Entity couponKey _) coupon = do
    now <- liftIO getCurrentTime
    let updatedCoupon = coupon { couponUpdated = now }
    runSqlPool (replace couponKey updatedCoupon) pool
    return $ Entity couponKey updatedCoupon

-- | List coupons
listCoupons :: MonadIO m
           => ConnectionPool
           -> m [Entity Coupon]
listCoupons pool =
    runSqlPool (selectList [] [Desc CouponCreated]) pool

-- | Validate coupon
validateCoupon :: MonadIO m
               => Text  -- ^ Coupon code
               -> m (Either Text (Entity Coupon))
validateCoupon code = runDB $ do
    now <- liftIO getCurrentTime
    couponM <- getBy $ UniqueCouponCode code
    case couponM of
        Nothing -> return $ Left "Invalid coupon code"
        Just coupon@(Entity _ c) ->
            if couponValidFrom c > now
                then return $ Left "Coupon not yet valid"
                else if couponValidUntil c < now
                    then return $ Left "Coupon expired"
                    else case couponMaxUses c of
                        Just maxUses ->
                            if couponUsedCount c >= maxUses
                                then return $ Left "Coupon usage limit reached"
                                else return $ Right coupon
                        Nothing -> return $ Right coupon

-- | Apply a coupon to an amount
applyCoupon :: MonadIO m
            => Entity Coupon
            -> Double  -- ^ Original amount
            -> m Double  -- ^ Discounted amount
applyCoupon (Entity _ coupon) amount =
    case couponDiscountType coupon of
        Percentage ->
            let discount = amount * (couponDiscountValue coupon / 100)
            in return $ amount - discount
        FixedAmount ->
            return $ amount - couponDiscountValue coupon
        CustomDiscount _ ->
            -- Custom discount logic would go here
            return amount

-- Helper functions for generating IDs
generatePlanId :: Text -> UTCTime -> Text
generatePlanId name timestamp =
    "plan_" <> Text.filter isAllowed name <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateBillingId :: Text -> UTCTime -> Text
generateBillingId enterpriseId timestamp =
    "billing-" <> enterpriseId <> "-" <> formatTime timestamp
  where
    formatTime = Text.pack . show

generateInvoiceId :: Text -> UTCTime -> Text
generateInvoiceId enterpriseId timestamp =
    "invoice-" <> enterpriseId <> "-" <> formatTime timestamp
  where
    formatTime = Text.pack . show

generateTransactionId :: Text -> UTCTime -> Text
generateTransactionId invoiceId timestamp =
    "txn-" <> invoiceId <> "-" <> formatTime timestamp
  where
    formatTime = Text.pack . show

generateCouponId :: Text -> UTCTime -> Text
generateCouponId code timestamp =
    "coupon-" <> code <> "-" <> formatTime timestamp
  where
    formatTime = Text.pack . show
