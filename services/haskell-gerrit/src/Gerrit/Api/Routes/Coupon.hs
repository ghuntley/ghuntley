{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Routes.Coupon
    ( CouponAPI
    , couponRoutes
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)
import Data.Time (UTCTime)
import Servant

import Gerrit.Api.Handlers.Coupon
import Gerrit.Models.Coupon
import Gerrit.Utils.Auth
import Gerrit.Utils.Error

-- | API specification for coupon operations
type CouponAPI =
    -- POST /api/v1/coupons
    "api" :> "v1" :> "coupons"
        :> RequireAuth
        :> ReqBody '[JSON] CreateCouponRequest
        :> Post '[JSON] CouponResponse

    -- PUT /api/v1/coupons/:coupon_id
    :<|> "api" :> "v1" :> "coupons" :> Capture "coupon_id" Text
        :> RequireAuth
        :> ReqBody '[JSON] UpdateCouponRequest
        :> Put '[JSON] CouponResponse

    -- GET /api/v1/coupons/:coupon_id
    :<|> "api" :> "v1" :> "coupons" :> Capture "coupon_id" Text
        :> RequireAuth
        :> Get '[JSON] CouponResponse

    -- GET /api/v1/coupons
    :<|> "api" :> "v1" :> "coupons"
        :> RequireAuth
        :> QueryParam "status" CouponStatus
        :> QueryParam "include_expired" Bool
        :> QueryParam "offset" Int
        :> QueryParam "limit" Int
        :> Get '[JSON] CouponListResponse

    -- POST /api/v1/coupons/apply
    :<|> "api" :> "v1" :> "coupons" :> "apply"
        :> RequireAuth
        :> ReqBody '[JSON] ApplyCouponRequest
        :> Post '[JSON] Double

    -- DELETE /api/v1/coupons/:coupon_id
    :<|> "api" :> "v1" :> "coupons" :> Capture "coupon_id" Text
        :> RequireAuth
        :> Delete '[JSON] CouponResponse

    -- GET /api/v1/coupons/:coupon_id/usage
    :<|> "api" :> "v1" :> "coupons" :> Capture "coupon_id" Text :> "usage"
        :> RequireAuth
        :> QueryParam' '[Required] "start_time" UTCTime
        :> QueryParam' '[Required] "end_time" UTCTime
        :> Get '[JSON] [(UTCTime, Int)]

-- | Server implementation of the coupon API
couponRoutes :: ConnectionPool -> ServerT CouponAPI Handler
couponRoutes pool =
    handleCreateCouponRoute
    :<|> handleUpdateCouponRoute
    :<|> handleGetCouponRoute
    :<|> handleListCouponsRoute
    :<|> handleApplyCouponRoute
    :<|> handleDeactivateCouponRoute
    :<|> handleGetCouponUsageRoute
  where
    handleCreateCouponRoute userId req = do
        -- Check if user has admin privileges
        requireAdmin userId
        result <- liftIO $ handleCreateCoupon pool req
        case result of
            Left err -> throwError $ toServantError err
            Right response -> return response

    handleUpdateCouponRoute userId couponId req = do
        -- Check if user has admin privileges
        requireAdmin userId
        result <- liftIO $ handleUpdateCoupon pool couponId req
        case result of
            Left err -> throwError $ toServantError err
            Right response -> return response

    handleGetCouponRoute userId couponId = do
        -- Check if user has admin privileges
        requireAdmin userId
        result <- liftIO $ handleGetCoupon pool couponId
        case result of
            Left err -> throwError $ toServantError err
            Right response -> return response

    handleListCouponsRoute userId mStatus mIncludeExpired mOffset mLimit = do
        -- Check if user has admin privileges
        requireAdmin userId
        let offset = fromMaybe 0 mOffset
            limit = fromMaybe 50 mLimit
            includeExpired = fromMaybe False mIncludeExpired
        result <- liftIO $ handleListCoupons pool mStatus includeExpired offset limit
        case result of
            Left err -> throwError $ toServantError err
            Right response -> return response

    handleApplyCouponRoute userId req = do
        -- Any authenticated user can apply a coupon
        result <- liftIO $ handleApplyCoupon pool req
        case result of
            Left err -> throwError $ toServantError err
            Right amount -> return amount

    handleDeactivateCouponRoute userId couponId = do
        -- Check if user has admin privileges
        requireAdmin userId
        result <- liftIO $ handleDeactivateCoupon pool couponId
        case result of
            Left err -> throwError $ toServantError err
            Right response -> return response

    handleGetCouponUsageRoute userId couponId start end = do
        -- Check if user has admin privileges
        requireAdmin userId
        result <- liftIO $ handleGetCouponUsage pool couponId start end
        case result of
            Left err -> throwError $ toServantError err
            Right usage -> return usage
