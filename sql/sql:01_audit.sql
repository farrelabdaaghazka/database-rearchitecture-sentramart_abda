SET search_path = legacy, public;
SET statement_timeout = '60s';

BEGIN TRANSACTION READ ONLY ISOLATION LEVEL REPEATABLE READ;

SELECT 'customers' AS table_name, COUNT(*)::bigint AS row_count FROM legacy.customers
UNION ALL SELECT 'sellers', COUNT(*) FROM legacy.sellers
UNION ALL SELECT 'products', COUNT(*) FROM legacy.products
UNION ALL SELECT 'product_attributes', COUNT(*) FROM legacy.product_attributes
UNION ALL SELECT 'orders', COUNT(*) FROM legacy.orders
UNION ALL SELECT 'order_items', COUNT(*) FROM legacy.order_items
UNION ALL SELECT 'payments', COUNT(*) FROM legacy.payments
UNION ALL SELECT 'flash_sale_items', COUNT(*) FROM legacy.flash_sale_items;

SELECT 
    COUNT(*)::bigint AS total_orders,
    MIN(order_date) AS min_order_timestamp,
    MAX(order_date) AS max_order_timestamp
FROM legacy.orders;

SELECT 
    status, 
    COUNT(*)::bigint AS order_count,
    ROUND((COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ()), 2) AS percentage
FROM legacy.orders
GROUP BY status
ORDER BY order_count DESC;

WITH target_event AS (
    SELECT event_id 
    FROM legacy.flash_sale_events 
    WHERE start_at >= '2025-12-12 20:00:00'::timestamp 
      AND start_at <= '2025-12-12 20:30:00'::timestamp
    LIMIT 1
),
event_sales AS (
    SELECT 
        oi.product_id,
        SUM(oi.qty)::integer AS total_units_sold
    FROM legacy.orders o
    JOIN legacy.order_items oi ON o.order_id = oi.order_id
    WHERE o.order_date >= '2025-12-12 20:00:00'::timestamp 
      AND o.order_date <= '2025-12-12 20:30:00'::timestamp
      AND o.status != 'CANCELLED'
    GROUP BY oi.product_id
)
SELECT 
    fsi.product_id,
    p.product_name,
    fsi.quota AS flash_sale_quota,
    COALESCE(es.total_units_sold, 0) AS total_units_sold,
    (COALESCE(es.total_units_sold, 0) - fsi.quota) AS oversold_units,
    p.stock AS current_db_stock
FROM legacy.flash_sale_items fsi
JOIN legacy.products p ON fsi.product_id = p.product_id
LEFT JOIN event_sales es ON fsi.product_id = es.product_id
WHERE fsi.event_id = (SELECT event_id FROM target_event)
  AND (COALESCE(es.total_units_sold, 0) > fsi.quota OR p.stock < 0)
ORDER BY oversold_units DESC;

WITH duplicate_successful_payments AS (
    SELECT 
        p.order_id,
        COUNT(*)::integer AS success_callback_count,
        SUM(p.amount)::numeric(15,2) AS total_captured_amount,
        MAX(o.total_amount)::numeric(15,2) AS expected_single_payment
    FROM legacy.payments p
    JOIN legacy.orders o ON p.order_id = o.order_id
    WHERE p.status = 'SUCCESS'
    GROUP BY p.order_id
    HAVING COUNT(*) > 1
)
SELECT 
    COUNT(order_id)::integer AS double_charged_orders_count,
    SUM(total_captured_amount - expected_single_payment)::numeric(15,2) AS total_overcharged_amount_idr
FROM duplicate_successful_payments;

WITH calculated_order_totals AS (
    SELECT 
        o.order_id,
        o.total_amount::numeric(15,2) AS recorded_total_amount,
        (COALESCE(SUM(oi.subtotal), 0) + o.shipping_fee - COALESCE(o.discount, 0))::numeric(15,2) AS computed_total_amount
    FROM legacy.orders o
    LEFT JOIN legacy.order_items oi ON o.order_id = oi.order_id
    GROUP BY o.order_id, o.total_amount, o.shipping_fee, o.discount
)
SELECT 
    COUNT(*)::integer AS mismatched_orders_count,
    SUM(ABS(recorded_total_amount - computed_total_amount))::numeric(15,2) AS total_variance_idr
FROM calculated_order_totals
WHERE recorded_total_amount != computed_total_amount;

SELECT 
    COUNT(*)::integer AS negative_stock_products_count,
    MIN(stock)::integer AS minimum_stock_value
FROM legacy.products
WHERE stock < 0;

SELECT 
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type,
    kcu.column_name
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu 
  ON tc.constraint_name = kcu.constraint_name 
 AND tc.table_schema = kcu.table_schema
WHERE tc.table_schema = 'legacy' 
  AND tc.table_name IN ('products', 'payments')
ORDER BY tc.table_name, tc.constraint_type;

SELECT 
    kcu.table_name,
    kcu.column_name AS fk_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu 
  ON tc.constraint_name = kcu.constraint_name
WHERE tc.table_schema = 'legacy' 
  AND tc.constraint_type = 'FOREIGN KEY'
  AND NOT EXISTS (
      SELECT 1 
      FROM pg_indexes pi
      WHERE pi.schemaname = 'legacy' 
        AND pi.tablename = kcu.table_name
        AND pi.indexdef LIKE '%' || kcu.column_name || '%'
  )
ORDER BY kcu.table_name, kcu.column_name;

COMMIT;