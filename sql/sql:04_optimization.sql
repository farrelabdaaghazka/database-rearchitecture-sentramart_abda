SET search_path TO v2, public;

CREATE INDEX IF NOT EXISTS idx_orders_customer_date 
ON v2.orders (customer_id, order_date DESC);

CREATE INDEX IF NOT EXISTS idx_order_items_order_fk 
ON v2.order_items (order_id, order_date);

CREATE INDEX IF NOT EXISTS idx_order_items_seller_composite 
ON v2.order_items (seller_id, order_date) INCLUDE (subtotal, order_id);

CREATE INDEX IF NOT EXISTS idx_orders_seller_active_status 
ON v2.orders (order_date, status, order_id);

CREATE INDEX IF NOT EXISTS idx_products_attributes_gin 
ON v2.products USING gin (attributes jsonb_path_ops);

CREATE INDEX IF NOT EXISTS idx_products_cat_price_stock 
ON v2.products (category_id, price, stock) INCLUDE (product_name);

CREATE INDEX IF NOT EXISTS idx_orders_status_date 
ON v2.orders (status, order_date) INCLUDE (total_amount);

CREATE INDEX IF NOT EXISTS idx_payments_pending_timestamptz 
ON v2.payments (created_at) INCLUDE (payment_id, order_id, method, amount)
WHERE status = 'PENDING';

CREATE INDEX IF NOT EXISTS idx_payments_gateway_ref_pure 
ON v2.payments (gateway_ref) INCLUDE (payment_id, order_id, status);

CREATE INDEX IF NOT EXISTS idx_customer_pii_email ON v2.customer_pii (email);
CREATE INDEX IF NOT EXISTS idx_customer_pii_phone ON v2.customer_pii (phone);

DROP MATERIALIZED VIEW IF EXISTS v2.mv_daily_category_revenue CASCADE;

CREATE MATERIALIZED VIEW v2.mv_daily_category_revenue AS
SELECT 
    o.order_date::date AS transaction_date,
    c.category_name,
    o.shipping_city,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(o.total_amount)::numeric(15,2) AS gross_revenue
FROM v2.orders o
JOIN v2.order_items oi ON oi.order_date = o.order_date AND oi.order_id = o.order_id
JOIN v2.products p ON p.product_id = oi.product_id
JOIN v2.categories c ON c.category_id = p.category_id
WHERE o.status IN ('DELIVERED', 'SHIPPED', 'PAID')
GROUP BY o.order_date::date, c.category_name, o.shipping_city;

CREATE UNIQUE INDEX idx_mv_daily_cat_rev 
ON v2.mv_daily_category_revenue (transaction_date DESC, gross_revenue DESC, category_name, shipping_city);

REFRESH MATERIALIZED VIEW CONCURRENTLY v2.mv_daily_category_revenue;