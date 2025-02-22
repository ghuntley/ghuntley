-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

-- Create coupon types enum
CREATE TYPE coupon_type AS ENUM (
    'percentage_discount',
    'fixed_amount_discount',
    'trial_extension'
);

-- Create coupon status enum
CREATE TYPE coupon_status AS ENUM (
    'active',
    'expired',
    'depleted',
    'deactivated'
);

-- Create coupons table
CREATE TABLE coupons (
    coupon_id TEXT PRIMARY KEY,
    code TEXT NOT NULL,
    description TEXT,
    discount_type coupon_type NOT NULL,
    status coupon_status NOT NULL DEFAULT 'active',
    restrictions JSONB,
    max_usage INTEGER,
    current_usage INTEGER NOT NULL DEFAULT 0,
    valid_from TIMESTAMP WITH TIME ZONE NOT NULL,
    valid_until TIMESTAMP WITH TIME ZONE,
    created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_coupon_code UNIQUE (code)
);

-- Create coupon usage table
CREATE TABLE coupon_usage (
    usage_id TEXT PRIMARY KEY,
    coupon_id TEXT NOT NULL REFERENCES coupons(coupon_id) ON DELETE CASCADE,
    enterprise_id TEXT NOT NULL REFERENCES enterprises(enterprise_id) ON DELETE CASCADE,
    billing_plan_id TEXT NOT NULL REFERENCES billing_plans(billing_plan_id) ON DELETE CASCADE,
    discount_amount DECIMAL(10,2) NOT NULL,
    applied_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX idx_coupons_status ON coupons(status);
CREATE INDEX idx_coupons_valid_until ON coupons(valid_until);
CREATE INDEX idx_coupon_usage_coupon_id ON coupon_usage(coupon_id);
CREATE INDEX idx_coupon_usage_enterprise_id ON coupon_usage(enterprise_id);
CREATE INDEX idx_coupon_usage_applied_at ON coupon_usage(applied_at);

-- Create trigger to update the updated timestamp
CREATE OR REPLACE FUNCTION update_coupons_updated_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_coupons_updated
    BEFORE UPDATE ON coupons
    FOR EACH ROW
    EXECUTE FUNCTION update_coupons_updated_column();
