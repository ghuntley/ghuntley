-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

-- Invoice Management Schema

-- Invoice status enum
CREATE TYPE invoice_status AS ENUM ('draft', 'pending', 'paid', 'overdue', 'cancelled', 'refunded');

-- Invoices table
CREATE TABLE invoices (
    invoice_id TEXT PRIMARY KEY,
    enterprise_id TEXT REFERENCES enterprises(enterprise_id) ON DELETE SET NULL,
    organization_id TEXT REFERENCES organizations(organization_id) ON DELETE SET NULL,
    number TEXT NOT NULL,
    status invoice_status NOT NULL DEFAULT 'draft',
    currency TEXT NOT NULL,
    subtotal DOUBLE PRECISION NOT NULL,
    tax DOUBLE PRECISION NOT NULL,
    discount DOUBLE PRECISION NOT NULL,
    total DOUBLE PRECISION NOT NULL,
    items JSONB NOT NULL DEFAULT '[]',
    template JSONB,
    billing_address JSONB NOT NULL,
    payment_details JSONB,
    due_date TIMESTAMP WITH TIME ZONE NOT NULL,
    paid_date TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    metadata JSONB,
    created_by TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_invoice_number UNIQUE (number),
    CONSTRAINT valid_amounts CHECK (
        subtotal >= 0 AND
        tax >= 0 AND
        discount >= 0 AND
        total >= 0 AND
        total = subtotal + tax - discount
    )
);

-- Invoice history table
CREATE TABLE invoice_history (
    history_id TEXT PRIMARY KEY,
    invoice_id TEXT NOT NULL REFERENCES invoices(invoice_id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,
    old_value JSONB,
    new_value JSONB NOT NULL,
    reason TEXT,
    changed_by TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Invoice-coupon relationship table
CREATE TABLE invoice_coupons (
    invoice_id TEXT NOT NULL REFERENCES invoices(invoice_id) ON DELETE CASCADE,
    coupon_id TEXT NOT NULL REFERENCES coupons(coupon_id) ON DELETE CASCADE,
    applied_amount DOUBLE PRECISION NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (invoice_id, coupon_id),
    CONSTRAINT valid_applied_amount CHECK (applied_amount >= 0)
);

-- Indexes for performance
CREATE INDEX idx_invoices_enterprise ON invoices(enterprise_id) WHERE enterprise_id IS NOT NULL;
CREATE INDEX idx_invoices_organization ON invoices(organization_id) WHERE organization_id IS NOT NULL;
CREATE INDEX idx_invoices_status ON invoices(status);
CREATE INDEX idx_invoices_due_date ON invoices(due_date);
CREATE INDEX idx_invoices_paid_date ON invoices(paid_date) WHERE paid_date IS NOT NULL;
CREATE INDEX idx_invoices_created_at ON invoices(created_at);

CREATE INDEX idx_invoice_history_invoice ON invoice_history(invoice_id);
CREATE INDEX idx_invoice_history_timestamp ON invoice_history(timestamp);
CREATE INDEX idx_invoice_history_change_type ON invoice_history(change_type);

CREATE INDEX idx_invoice_coupons_coupon ON invoice_coupons(coupon_id);
CREATE INDEX idx_invoice_coupons_created ON invoice_coupons(created_at);

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_invoice_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_invoice_timestamp_trigger
    BEFORE UPDATE ON invoices
    FOR EACH ROW
    EXECUTE FUNCTION update_invoice_timestamp();

-- Trigger for invoice history tracking
CREATE OR REPLACE FUNCTION track_invoice_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO invoice_history (
            history_id,
            invoice_id,
            change_type,
            new_value,
            changed_by
        ) VALUES (
            gen_random_uuid()::text,
            NEW.invoice_id,
            'created',
            row_to_json(NEW)::jsonb,
            NEW.created_by
        );
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status IS DISTINCT FROM NEW.status THEN
            INSERT INTO invoice_history (
                history_id,
                invoice_id,
                change_type,
                old_value,
                new_value,
                changed_by
            ) VALUES (
                gen_random_uuid()::text,
                NEW.invoice_id,
                'status_changed',
                jsonb_build_object('status', OLD.status),
                jsonb_build_object('status', NEW.status),
                CURRENT_USER
            );
        END IF;

        IF OLD.total IS DISTINCT FROM NEW.total THEN
            INSERT INTO invoice_history (
                history_id,
                invoice_id,
                change_type,
                old_value,
                new_value,
                changed_by
            ) VALUES (
                gen_random_uuid()::text,
                NEW.invoice_id,
                'amount_changed',
                jsonb_build_object(
                    'subtotal', OLD.subtotal,
                    'tax', OLD.tax,
                    'discount', OLD.discount,
                    'total', OLD.total
                ),
                jsonb_build_object(
                    'subtotal', NEW.subtotal,
                    'tax', NEW.tax,
                    'discount', NEW.discount,
                    'total', NEW.total
                ),
                CURRENT_USER
            );
        END IF;

        IF OLD.paid_date IS NULL AND NEW.paid_date IS NOT NULL THEN
            INSERT INTO invoice_history (
                history_id,
                invoice_id,
                change_type,
                new_value,
                changed_by
            ) VALUES (
                gen_random_uuid()::text,
                NEW.invoice_id,
                'payment_received',
                jsonb_build_object(
                    'paid_date', NEW.paid_date,
                    'payment_details', NEW.payment_details
                ),
                CURRENT_USER
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER track_invoice_changes_trigger
    AFTER INSERT OR UPDATE ON invoices
    FOR EACH ROW
    EXECUTE FUNCTION track_invoice_changes();
