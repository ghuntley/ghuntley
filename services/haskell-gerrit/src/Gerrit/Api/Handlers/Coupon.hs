{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.Coupon
    ( -- * Request Types
      CreateCouponRequest(..)
    , UpdateCouponRequest(..)
    , ApplyCouponRequest(..)
      -- * Response Types
    , CouponResponse(..)
    , CouponUsageResponse(..)
    , CouponListResponse(..)
      -- * Handlers
    , handleCreateCoupon
    , handleUpdateCoupon
    , handleGetCoupon
    , handleListCoupons
    , handleApplyCoupon
    , handleDeactivateCoupon
    , handleGetCouponUsage
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics

import Gerrit.Models.Coupon
import Gerrit.Models.Types
import Gerrit.Services.Coupon
import Gerrit.Utils.Error
import Gerrit.Utils.Time

-- | Request to create a new coupon
data CreateCouponRequest = CreateCouponRequest
    { createCode :: Text
    , createDescription :: Maybe Text
    , createDiscountType :: CouponType
    , createRestrictions :: Maybe CouponRestriction
    , createMaxUsage :: Maybe Int
    , createValidFrom :: UTCTime
    , createValidUntil :: Maybe UTCTime
    } deriving (Show, Generic)

instance FromJSON CreateCouponRequest
instance ToJSON CreateCouponRequest

-- | Request to update an existing coupon
data UpdateCouponRequest = UpdateCouponRequest
    { updateDescription :: Maybe Text
    , updateRestrictions :: Maybe CouponRestriction
    , updateMaxUsage :: Maybe Int
    , updateValidUntil :: Maybe UTCTime
    } deriving (Show, Generic)

instance FromJSON UpdateCouponRequest
instance ToJSON UpdateCouponRequest

-- | Request to apply a coupon
data ApplyCouponRequest = ApplyCouponRequest
    { applyCouponCode :: Text
    , applyEnterpriseId :: Text
    , applyBillingPlanId :: Text
    , applyAmount :: Double
    } deriving (Show, Generic)

instance FromJSON ApplyCouponRequest
instance ToJSON ApplyCouponRequest

-- | Response for coupon operations
data CouponResponse = CouponResponse
    { couponId :: Text
    , couponCode :: Text
    , couponDescription :: Maybe Text
    , couponDiscountType :: CouponType
    , couponStatus :: CouponStatus
    , couponRestrictions :: Maybe CouponRestriction
    , couponMaxUsage :: Maybe Int
    , couponCurrentUsage :: Int
    , couponValidFrom :: UTCTime
    , couponValidUntil :: Maybe UTCTime
    , couponCreated :: UTCTime
    , couponUpdated :: UTCTime
    } deriving (Show, Generic)

instance ToJSON CouponResponse

-- | Response for coupon usage
data CouponUsageResponse = CouponUsageResponse
    { usageId :: Text
    , usageCouponId :: Text
    , usageEnterpriseId :: Text
    , usageBillingPlanId :: Text
    , usageDiscountAmount :: Double
    , usageAppliedAt :: UTCTime
    } deriving (Show, Generic)

instance ToJSON CouponUsageResponse

-- | Response for listing coupons
data CouponListResponse = CouponListResponse
    { coupons :: [CouponResponse]
    , totalCount :: Int
    } deriving (Show, Generic)

instance ToJSON CouponListResponse

-- | Convert Coupon entity to CouponResponse
toCouponResponse :: Entity Coupon -> CouponResponse
toCouponResponse (Entity _ coupon) = CouponResponse
    { couponId = couponCouponId coupon
    , couponCode = couponCode coupon
    , couponDescription = couponDescription coupon
    , couponDiscountType = couponDiscountType coupon
    , couponStatus = couponStatus coupon
    , couponRestrictions = case couponRestrictions coupon of
        Just val -> fromJSON val
        Nothing -> Nothing
    , couponMaxUsage = couponMaxUsage coupon
    , couponCurrentUsage = couponCurrentUsage coupon
    , couponValidFrom = couponValidFrom coupon
    , couponValidUntil = couponValidUntil coupon
    , couponCreated = couponCreated coupon
    , couponUpdated = couponUpdated coupon
    }

-- | Convert CouponUsage entity to CouponUsageResponse
toCouponUsageResponse :: Entity CouponUsage -> CouponUsageResponse
toCouponUsageResponse (Entity _ usage) = CouponUsageResponse
    { usageId = couponUsageUsageId usage
    , usageCouponId = couponUsageCouponId usage
    , usageEnterpriseId = couponUsageEnterpriseId usage
    , usageBillingPlanId = couponUsageBillingPlanId usage
    , usageDiscountAmount = couponUsageDiscountAmount usage
    , usageAppliedAt = couponUsageAppliedAt usage
    }

-- | Handle creating a new coupon
handleCreateCoupon :: MonadIO m
                   => ConnectionPool
                   -> CreateCouponRequest
                   -> m (Either ServiceError CouponResponse)
handleCreateCoupon pool CreateCouponRequest{..} = do
    result <- createCoupon pool
        createCode
        createDescription
        createDiscountType
        (toJSON <$> createRestrictions)
        createMaxUsage
        createValidFrom
        createValidUntil
    return $ case result of
        Left err -> Left err
        Right entity -> Right $ toCouponResponse entity

-- | Handle updating an existing coupon
handleUpdateCoupon :: MonadIO m
                   => ConnectionPool
                   -> Text  -- ^ Coupon ID
                   -> UpdateCouponRequest
                   -> m (Either ServiceError CouponResponse)
handleUpdateCoupon pool couponId UpdateCouponRequest{..} = do
    result <- updateCoupon pool
        couponId
        updateDescription
        (toJSON <$> updateRestrictions)
        updateMaxUsage
        updateValidUntil
    return $ case result of
        Left err -> Left err
        Right entity -> Right $ toCouponResponse entity

-- | Handle getting a coupon by ID
handleGetCoupon :: MonadIO m
                => ConnectionPool
                -> Text  -- ^ Coupon ID
                -> m (Either ServiceError CouponResponse)
handleGetCoupon pool couponId = do
    result <- getCouponById pool couponId
    return $ case result of
        Nothing -> Left $ NotFoundError "Coupon not found"
        Just entity -> Right $ toCouponResponse entity

-- | Handle listing coupons
handleListCoupons :: MonadIO m
                  => ConnectionPool
                  -> Maybe CouponStatus  -- ^ Filter by status
                  -> Bool  -- ^ Include expired
                  -> Int  -- ^ Offset
                  -> Int  -- ^ Limit
                  -> m (Either ServiceError CouponListResponse)
handleListCoupons pool mStatus includeExpired offset limit = do
    coupons <- listCoupons pool mStatus includeExpired offset limit
    total <- countCoupons pool mStatus includeExpired
    return $ Right CouponListResponse
        { coupons = map toCouponResponse coupons
        , totalCount = total
        }

-- | Handle applying a coupon
handleApplyCoupon :: MonadIO m
                  => ConnectionPool
                  -> ApplyCouponRequest
                  -> m (Either ServiceError Double)
handleApplyCoupon pool ApplyCouponRequest{..} = do
    result <- validateCoupon pool
        applyCouponCode
        applyAmount
        applyEnterpriseId
        applyBillingPlanId
    case result of
        Left err -> return $ Left $ ValidationError err
        Right couponEntity -> do
            discountResult <- applyCoupon pool
                couponEntity
                applyEnterpriseId
                applyBillingPlanId
                applyAmount
            return $ case discountResult of
                Left err -> Left $ ValidationError err
                Right amount -> Right amount

-- | Handle deactivating a coupon
handleDeactivateCoupon :: MonadIO m
                       => ConnectionPool
                       -> Text  -- ^ Coupon ID
                       -> m (Either ServiceError CouponResponse)
handleDeactivateCoupon pool couponId = do
    result <- getCouponById pool couponId
    case result of
        Nothing -> return $ Left $ NotFoundError "Coupon not found"
        Just entity -> do
            deactivated <- deactivateCoupon pool entity
            return $ Right $ toCouponResponse deactivated

-- | Handle getting coupon usage statistics
handleGetCouponUsage :: MonadIO m
                     => ConnectionPool
                     -> Text  -- ^ Coupon ID
                     -> UTCTime  -- ^ Start time
                     -> UTCTime  -- ^ End time
                     -> m (Either ServiceError [(UTCTime, Int)])
handleGetCouponUsage pool couponId start end = do
    result <- getCouponById pool couponId
    case result of
        Nothing -> return $ Left $ NotFoundError "Coupon not found"
        Just _ -> do
            usage <- trackCouponUsage pool couponId start end
            return $ Right usage
