{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

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

module Gerrit.Models.Coupon
    ( -- * Types
      Coupon(..)
    , CouponType(..)
    , CouponStatus(..)
    , CouponRestriction(..)
    , CouponUsage(..)
      -- * Operations
    , createCoupon
    , validateCoupon
    , applyCoupon
    , getCouponById
    , listCoupons
    , deactivateCoupon
    , trackCouponUsage
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), FromJSON(..), ToJSON(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime, addUTCTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.Enterprise (Enterprise)
import Gerrit.Models.Billing (BillingPlan)

-- | Coupon discount types
data CouponType
    = PercentageDiscount Double  -- ^ Percentage off (0-100)
    | FixedAmountDiscount Double -- ^ Fixed amount off
    | TrialExtension Int        -- ^ Extend trial by days
    deriving (Show, Read, Eq, Generic)
derivePersistField "CouponType"

-- | Coupon status
data CouponStatus
    = Active
    | Expired
    | Depleted
    | Deactivated
    deriving (Show, Read, Eq, Generic)
derivePersistField "CouponStatus"

-- | Coupon restrictions
data CouponRestriction = CouponRestriction
    { minAmount :: Maybe Double
    , maxAmount :: Maybe Double
    , validPlans :: Maybe [Text]
    , validEnterprises :: Maybe [Text]
    } deriving (Show, Eq, Generic)
instance ToJSON CouponRestriction
instance FromJSON CouponRestriction

-- | Define the Coupon entities using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Coupon
    couponId Text
    code Text
    description Text Maybe
    discountType CouponType
    status CouponStatus default=Active
    restrictions Value Maybe
    maxUsage Int Maybe
    currentUsage Int default=0
    validFrom UTCTime
    validUntil UTCTime Maybe
    created UTCTime
    updated UTCTime
    UniqueCouponId couponId
    UniqueCouponCode code
    deriving Show Eq Generic

CouponUsage
    usageId Text
    couponId Text
    enterpriseId Text
    billingPlanId Text
    discountAmount Double
    appliedAt UTCTime
    UniqueUsageId usageId
    Foreign Coupon couponId References coupons OnDeleteCascade
    Foreign Enterprise enterpriseId References enterprises OnDeleteCascade
    Foreign BillingPlan billingPlanId References billing_plans OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create a new coupon
createCoupon :: MonadIO m
             => ConnectionPool
             -> Text  -- ^ Code
             -> Maybe Text  -- ^ Description
             -> CouponType  -- ^ Discount type
             -> Maybe Value  -- ^ Restrictions
             -> Maybe Int  -- ^ Max usage
             -> UTCTime  -- ^ Valid from
             -> Maybe UTCTime  -- ^ Valid until
             -> m (Entity Coupon)
createCoupon pool code desc discountType restrictions maxUsage validFrom validUntil = do
    now <- liftIO getCurrentTime
    let couponId = generateCouponId code now
    let coupon = Coupon
            { couponCouponId = couponId
            , couponCode = code
            , couponDescription = desc
            , couponDiscountType = discountType
            , couponStatus = Active
            , couponRestrictions = restrictions
            , couponMaxUsage = maxUsage
            , couponCurrentUsage = 0
            , couponValidFrom = validFrom
            , couponValidUntil = validUntil
            , couponCreated = now
            , couponUpdated = now
            }
    runSqlPool (insertEntity coupon) pool

-- | Validate a coupon
validateCoupon :: MonadIO m
               => ConnectionPool
               -> Text  -- ^ Coupon code
               -> Double  -- ^ Amount to apply to
               -> Text  -- ^ Enterprise ID
               -> Text  -- ^ Plan ID
               -> m (Either Text (Entity Coupon))
validateCoupon pool code amount enterpriseId planId = do
    now <- liftIO getCurrentTime
    result <- runSqlPool (getBy $ UniqueCouponCode code) pool
    case result of
        Nothing -> return $ Left "Coupon not found"
        Just entity@(Entity _ coupon) -> do
            -- Check status
            if couponStatus coupon /= Active
                then return $ Left "Coupon is not active"
                else do
                    -- Check validity period
                    let validFrom = couponValidFrom coupon
                    let validUntil = couponValidUntil coupon
                    if now < validFrom
                        then return $ Left "Coupon is not yet valid"
                        else case validUntil of
                            Just endDate | now > endDate ->
                                return $ Left "Coupon has expired"
                            _ -> do
                                -- Check usage limits
                                case couponMaxUsage coupon of
                                    Just maxUsage | couponCurrentUsage coupon >= maxUsage ->
                                        return $ Left "Coupon usage limit reached"
                                    _ -> do
                                        -- Check restrictions
                                        case couponRestrictions coupon of
                                            Nothing -> return $ Right entity
                                            Just restrictions -> validateRestrictions restrictions
  where
    validateRestrictions :: MonadIO m => Value -> m (Either Text (Entity Coupon))
    validateRestrictions restrictions = do
        -- Implementation of restriction validation
        -- This would check min/max amounts, valid plans, and valid enterprises
        return $ Right entity -- Placeholder

-- | Apply a coupon
applyCoupon :: MonadIO m
            => ConnectionPool
            -> Entity Coupon
            -> Text  -- ^ Enterprise ID
            -> Text  -- ^ Plan ID
            -> Double  -- ^ Amount
            -> m (Either Text Double)  -- ^ Returns discounted amount
applyCoupon pool (Entity key coupon) enterpriseId planId amount = do
    now <- liftIO getCurrentTime
    -- Calculate discount
    let discountAmount = case couponDiscountType coupon of
            PercentageDiscount pct -> amount * (pct / 100)
            FixedAmountDiscount amt -> amt
            TrialExtension _ -> 0

    -- Record usage
    usageId <- generateUsageId (couponCouponId coupon) enterpriseId now
    let usage = CouponUsage
            { couponUsageUsageId = usageId
            , couponUsageCouponId = couponCouponId coupon
            , couponUsageEnterpriseId = enterpriseId
            , couponUsageBillingPlanId = planId
            , couponUsageDiscountAmount = discountAmount
            , couponUsageAppliedAt = now
            }

    -- Update coupon usage count
    let updatedCoupon = coupon { couponCurrentUsage = couponCurrentUsage coupon + 1 }

    runSqlPool (do
        insertEntity usage
        replace key updatedCoupon
        ) pool

    return $ Right discountAmount

-- | Get coupon by ID
getCouponById :: MonadIO m
              => ConnectionPool
              -> Text  -- ^ Coupon ID
              -> m (Maybe (Entity Coupon))
getCouponById pool couponId =
    runSqlPool (getBy $ UniqueCouponId couponId) pool

-- | List coupons with filtering
listCoupons :: MonadIO m
            => ConnectionPool
            -> Maybe CouponStatus  -- ^ Filter by status
            -> Bool  -- ^ Include expired
            -> Int  -- ^ Offset
            -> Int  -- ^ Limit
            -> m [Entity Coupon]
listCoupons pool mStatus includeExpired offset limit = do
    now <- liftIO getCurrentTime
    let filters = concat
            [ maybe [] (\status -> [CouponStatus ==. status]) mStatus
            , if not includeExpired
                then [CouponValidUntil ==. Nothing] ||.
                     [CouponValidUntil >. Just now]
                else []
            ]
    runSqlPool (selectList filters [Desc CouponCreated, OffsetBy offset, LimitTo limit]) pool

-- | Deactivate a coupon
deactivateCoupon :: MonadIO m
                 => ConnectionPool
                 -> Entity Coupon
                 -> m (Entity Coupon)
deactivateCoupon pool (Entity key coupon) = do
    now <- liftIO getCurrentTime
    let updatedCoupon = coupon
            { couponStatus = Deactivated
            , couponUpdated = now
            }
    runSqlPool (replace key updatedCoupon) pool
    return $ Entity key updatedCoupon

-- | Track coupon usage
trackCouponUsage :: MonadIO m
                 => ConnectionPool
                 -> Text  -- ^ Coupon ID
                 -> UTCTime  -- ^ Start time
                 -> UTCTime  -- ^ End time
                 -> m [(UTCTime, Int)]  -- ^ List of (timestamp, usage count)
trackCouponUsage pool couponId start end = do
    usages <- runSqlPool (selectList
        [ CouponUsageCouponId ==. couponId
        , CouponUsageAppliedAt >=. start
        , CouponUsageAppliedAt <=. end
        ] [Asc CouponUsageAppliedAt]) pool
    return $ map (\(Entity _ usage) ->
        (couponUsageAppliedAt usage, 1)) usages

-- Helper functions for generating IDs
generateCouponId :: Text -> UTCTime -> Text
generateCouponId code timestamp =
    "cpn_" <> Text.filter isAllowed code <> "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])
    formatTime = Text.pack . show

generateUsageId :: Text -> Text -> UTCTime -> m Text
generateUsageId couponId enterpriseId timestamp =
    "cpu_" <> Text.filter isAllowed (couponId <> "_" <> enterpriseId) <>
    "_" <> formatTime timestamp
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])
    formatTime = Text.pack . show
