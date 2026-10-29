SET search_path TO v2, public;

-- Q1 (Target SLA: < 10 ms)
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT o.order_id, o.order_date, o.status, o.total_amount,
       COUNT(oi.order_item_id) AS jumlah_item
FROM v2.orders o
JOIN v2.order_items oi ON oi.order_date = o.order_date AND oi.order_id = o.order_id
WHERE o.customer_id = 13211
GROUP BY o.order_id, o.order_date, o.status, o.total_amount
ORDER BY o.order_date DESC
LIMIT 20;

-- Q2 (Target SLA: < 30 ms)
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT date_trunc('day', o.order_date) AS tanggal,
       COUNT(DISTINCT o.order_id)      AS jumlah_order,
       SUM(oi.subtotal)                AS omzet
FROM v2.order_items oi
JOIN v2.orders o ON o.order_date = oi.order_date AND o.order_id = oi.order_id
WHERE oi.seller_id = 579
  AND o.order_date >= '2025-11-01' AND o.order_date < '2025-12-01'
  AND o.status IN ('PAID', 'SHIPPED', 'DELIVERED')
GROUP BY 1
ORDER BY 1;

-- Q3 (Target SLA: < 10 ms)
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT p.product_id, p.product_name, p.price
FROM v2.products p
WHERE p.category_id = 1
  AND p.price BETWEEN 2000000 AND 5000000
  AND p.stock > 0
  AND p.attributes @> '{"ram_gb": "8", "network": "5G"}'
ORDER BY p.price
LIMIT 50;

-- Q4 (Target SLA: < 10 ms)
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT COUNT(*) AS jumlah_order, SUM(total_amount) AS gmv
FROM v2.orders
WHERE order_date >= '2025-12-12 00:00:00+00' 
  AND order_date < '2025-12-13 00:00:00+00'
  AND status = 'DELIVERED';

-- Q5 (Target SLA: < 20 ms)
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT category_name, SUM(gross_revenue) AS total_revenue
FROM v2.mv_daily_category_revenue
WHERE transaction_date >= '2025-12-01' AND transaction_date <= '2025-12-31'
GROUP BY category_name
ORDER BY total_revenue DESC
LIMIT 10;

-- Q6 (Target SLA: < 5 ms)
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT payment_id, order_id, method, amount, created_at
FROM v2.payments
WHERE status = 'PENDING'
  AND created_at < TIMESTAMPTZ '2025-12-31 23:59:59+07' - INTERVAL '24 hours'
ORDER BY created_at;

-- Q7 (Target SLA: < 2 ms)
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT payment_id, order_id, status
FROM v2.payments
WHERE gateway_ref = 'PGEB8D85CE168E8B';

-- Q8 (Target SLA: < 50 ms)
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT transaction_date, category_name, shipping_city, total_orders, gross_revenue
FROM v2.mv_daily_category_revenue
WHERE transaction_date >= '2025-01-01' AND transaction_date < '2026-01-01'
ORDER BY transaction_date DESC, gross_revenue DESC;