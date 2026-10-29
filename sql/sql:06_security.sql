SET search_path TO v2, public;

DROP ROLE IF EXISTS app_user;
DROP ROLE IF EXISTS seller_portal;
DROP ROLE IF EXISTS finance_user;
DROP ROLE IF EXISTS dba_admin;

CREATE ROLE app_user WITH LOGIN PASSWORD 'AppUserSecurePass123!';
GRANT USAGE ON SCHEMA v2 TO app_user;
GRANT SELECT, INSERT, UPDATE ON v2.orders, v2.order_items, v2.payments, v2.flash_sale_items TO app_user;
GRANT SELECT, UPDATE ON v2.products TO app_user;
GRANT SELECT ON v2.customers, v2.sellers, v2.categories, v2.flash_sale_events TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA v2 TO app_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA v2 TO app_user;

CREATE ROLE seller_portal WITH LOGIN PASSWORD 'SellerPortalPass123!';
GRANT USAGE ON SCHEMA v2 TO seller_portal;
GRANT SELECT, UPDATE ON v2.products TO seller_portal;
GRANT SELECT ON v2.order_items, v2.categories TO seller_portal;

CREATE ROLE finance_user WITH LOGIN PASSWORD 'FinanceUserPass123!';
GRANT USAGE ON SCHEMA v2 TO finance_user;
GRANT SELECT ON v2.orders, v2.order_items, v2.payments TO finance_user;
GRANT SELECT ON ALL MATERIALIZED VIEWS IN SCHEMA v2 TO finance_user;

CREATE ROLE dba_admin WITH LOGIN PASSWORD 'DbaAdminPass123!';
GRANT ALL PRIVILEGES ON SCHEMA v2 TO dba_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA v2 TO dba_admin;

CREATE OR REPLACE FUNCTION v2.fn_mask_email(p_email VARCHAR)
RETURNS VARCHAR 
LANGUAGE plpgsql 
IMMUTABLE 
SECURITY DEFINER
SET search_path = v2, pg_temp
AS $$
BEGIN
    IF p_email IS NULL OR POSITION('@' IN p_email) = 0 THEN
        RETURN '***@***.com';
    END IF;
    RETURN REGEXP_REPLACE(p_email, '(?<=.{2}).(?=.*@)', '*', 'g');
END;
$$;

CREATE OR REPLACE FUNCTION v2.fn_mask_phone(p_phone VARCHAR)
RETURNS VARCHAR 
LANGUAGE plpgsql 
IMMUTABLE 
SECURITY DEFINER
SET search_path = v2, pg_temp
AS $$
BEGIN
    IF p_phone IS NULL OR LENGTH(p_phone) < 7 THEN
        RETURN '08**********';
    END IF;
    RETURN SUBSTRING(p_phone FROM 1 FOR 4) || REPEAT('*', LENGTH(p_phone) - 7) || SUBSTRING(p_phone FROM LENGTH(p_phone) - 2 FOR 3);
END;
$$;

CREATE OR REPLACE VIEW v2.vw_customer_pii_masked AS
SELECT 
    customer_id,
    v2.fn_mask_email(email) AS masked_email,
    v2.fn_mask_phone(phone) AS masked_phone,
    created_at
FROM v2.customer_pii;

GRANT SELECT ON v2.vw_customer_pii_masked TO app_user, finance_user, seller_portal;

ALTER TABLE v2.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE v2.products FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seller_product_isolation_policy ON v2.products;
CREATE POLICY seller_product_isolation_policy ON v2.products
    FOR ALL
    TO seller_portal
    USING (seller_id = NULLIF(CURRENT_SETTING('app.current_seller_id', true), '')::INT);

DROP POLICY IF EXISTS app_user_product_policy ON v2.products;
CREATE POLICY app_user_product_policy ON v2.products
    FOR ALL
    TO app_user, dba_admin, finance_user
    USING (true);

CREATE TABLE IF NOT EXISTS v2.audit_logs (
    audit_id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(50) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    record_id VARCHAR(100) NOT NULL,
    old_data JSONB,
    new_data JSONB,
    changed_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

GRANT SELECT ON v2.audit_logs TO dba_admin, finance_user;
REVOKE UPDATE, DELETE, INSERT ON v2.audit_logs FROM app_user, seller_portal, finance_user;

CREATE OR REPLACE FUNCTION v2.fn_audit_product_changes()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = v2, pg_temp
AS $$
BEGIN
    IF (OLD.price IS DISTINCT FROM NEW.price) OR (OLD.stock IS DISTINCT FROM NEW.stock) THEN
        INSERT INTO v2.audit_logs (table_name, operation, record_id, old_data, new_data, changed_by)
        VALUES (
            'products',
            TG_OP,
            OLD.product_id::VARCHAR,
            jsonb_build_object('price', OLD.price, 'stock', OLD.stock),
            jsonb_build_object('price', NEW.price, 'stock', NEW.stock),
            CURRENT_USER
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_products ON v2.products;
CREATE TRIGGER trg_audit_products
    AFTER UPDATE ON v2.products
    FOR EACH ROW
    EXECUTE FUNCTION v2.fn_audit_product_changes();