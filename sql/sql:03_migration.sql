SET search_path TO v2, public;

TRUNCATE TABLE 
    v2.flash_sale_items,
    v2.flash_sale_events,
    v2.payments,
    v2.order_items,
    v2.orders,
    v2.products,
    v2.customer_pii,
    v2.customers,
    v2.sellers,
    v2.categories
CASCADE;

INSERT INTO v2.categories (category_id, category_name)
SELECT category_id, category_name 
FROM legacy.categories;

INSERT INTO v2.sellers (seller_id, seller_name, seller_type, city, province, joined_at, rating)
SELECT 
    seller_id, 
    seller_name, 
    LOWER(TRIM(seller_type))::v2.seller_type_enum, 
    city, 
    province, 
    joined_at AT TIME ZONE 'Asia/Jakarta', 
    rating::numeric(3,2)
FROM legacy.sellers;

INSERT INTO v2.customers (customer_id, full_name, city, province, registered_at, tier)
SELECT 
    customer_id, 
    full_name, 
    city, 
    province, 
    registered_at AT TIME ZONE 'Asia/Jakarta', 
    CASE 
        WHEN LOWER(TRIM(tier)) IN ('bronze', 'silver', 'gold', 'platinum') 
            THEN LOWER(TRIM(tier))::v2.customer_tier_enum
        ELSE 'bronze'::v2.customer_tier_enum
    END AS tier
FROM legacy.customers;

WITH cleaned_pii AS (
    SELECT 
        customer_id, 
        TRIM(email) AS email, 
        TRIM(phone) AS phone,
        ROW_NUMBER() OVER (PARTITION BY TRIM(LOWER(email)) ORDER BY customer_id ASC) AS email_rn,
        ROW_NUMBER() OVER (PARTITION BY TRIM(phone) ORDER BY customer_id ASC) AS phone_rn
    FROM legacy.customers
    WHERE email IS NOT NULL AND email != ''
      AND phone IS NOT NULL AND phone != ''
)
INSERT INTO v2.customer_pii (customer_id, email, phone)
SELECT customer_id, email, phone
FROM cleaned_pii
WHERE email_rn = 1 AND phone_rn = 1;

INSERT INTO v2.products (product_id, seller_id, category_id, product_name, price, stock, is_flash_sale, attributes, created_at)
SELECT 
    p.product_id,
    p.seller_id,
    p.category_id,
    p.product_name,
    p.price::numeric(15,2),
    GREATEST(p.stock, 0),
    p.is_flash_sale,
    COALESCE(
        jsonb_object_agg(pa.attr_name, pa.attr_value) FILTER (WHERE pa.attr_name IS NOT NULL),
        '{}'::jsonb
    ) AS attributes,
    p.created_at AT TIME ZONE 'Asia/Jakarta'
FROM legacy.products p
LEFT JOIN legacy.product_attributes pa ON p.product_id = pa.product_id
GROUP BY p.product_id, p.seller_id, p.category_id, p.product_name, p.price, p.stock, p.is_flash_sale, p.created_at;

INSERT INTO v2.orders (order_id, customer_id, order_date, status, shipping_fee, discount, total_amount, voucher_code, shipping_city)
WITH order_item_totals AS (
    SELECT 
        order_id,
        COALESCE(SUM(subtotal), 0)::numeric(15,2) AS computed_item_total
    FROM legacy.order_items
    GROUP BY order_id
)
SELECT 
    o.order_id,
    o.customer_id,
    o.order_date AT TIME ZONE 'Asia/Jakarta',
    CASE 
        WHEN UPPER(TRIM(o.status)) IN ('CREATED', 'PAID', 'SHIPPED', 'DELIVERED', 'CANCELLED', 'REFUNDED') 
            THEN UPPER(TRIM(o.status))::v2.order_status_enum
        WHEN UPPER(TRIM(o.status)) IN ('COMPLETED', 'FINISHED', 'SUCCESS', 'SELESAI') 
            THEN 'DELIVERED'::v2.order_status_enum
        WHEN UPPER(TRIM(o.status)) IN ('PROCESSING', 'PROCESS', 'PENDING', 'DIPROSES') 
            THEN 'PAID'::v2.order_status_enum
        WHEN UPPER(TRIM(o.status)) IN ('EXPIRED', 'BATAL', 'FAILED') 
            THEN 'CANCELLED'::v2.order_status_enum
        ELSE 'CREATED'::v2.order_status_enum
    END AS status,
    o.shipping_fee::numeric(15,2),
    COALESCE(o.discount, 0)::numeric(15,2),
    (COALESCE(oit.computed_item_total, 0) + o.shipping_fee::numeric(15,2) - COALESCE(o.discount, 0)::numeric(15,2))::numeric(15,2) AS total_amount,
    o.voucher_code,
    o.shipping_city
FROM legacy.orders o
LEFT JOIN order_item_totals oit ON o.order_id = oit.order_id;

INSERT INTO v2.order_items (order_item_id, order_date, order_id, product_id, seller_id, qty, unit_price, subtotal)
SELECT 
    oi.order_item_id,
    vo.order_date,
    oi.order_id,
    oi.product_id,
    oi.seller_id,
    oi.qty,
    oi.unit_price::numeric(15,2),
    oi.subtotal::numeric(15,2)
FROM legacy.order_items oi
JOIN v2.orders vo ON oi.order_id = vo.order_id;

WITH clean_payments AS (
    SELECT 
        p.payment_id,
        vo.order_date AS converted_order_date,
        p.order_id,
        p.method,
        p.amount::numeric(15,2) AS amount,
        CASE 
            WHEN UPPER(TRIM(p.status)) IN ('PENDING', 'SUCCESS', 'FAILED', 'EXPIRED', 'REFUNDED') 
                THEN UPPER(TRIM(p.status))
            WHEN UPPER(TRIM(p.status)) IN ('PAID', 'COMPLETED', 'BERHASIL') 
                THEN 'SUCCESS'
            WHEN UPPER(TRIM(p.status)) IN ('GAGAL', 'ERROR') 
                THEN 'FAILED'
            ELSE 'PENDING'
        END AS clean_status,
        NULLIF(TRIM(p.gateway_ref), '') AS clean_gateway_ref,
        p.created_at AT TIME ZONE 'Asia/Jakarta' AS created_at,
        p.paid_at AT TIME ZONE 'Asia/Jakarta' AS paid_at
    FROM legacy.payments p
    JOIN v2.orders vo ON p.order_id = vo.order_id
),
deduped_payments AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (
            PARTITION BY order_id, clean_status
            ORDER BY paid_at ASC NULLS LAST, payment_id ASC
        ) AS rn_order
    FROM clean_payments
)
INSERT INTO v2.payments (payment_id, order_date, order_id, method, amount, status, gateway_ref, created_at, paid_at)
SELECT 
    payment_id,
    converted_order_date,
    order_id,
    method,
    amount,
    clean_status::v2.payment_status_enum,
    clean_gateway_ref,
    created_at,
    paid_at
FROM deduped_payments
WHERE clean_status != 'SUCCESS' OR rn_order = 1
ON CONFLICT (payment_id) DO NOTHING;

INSERT INTO v2.flash_sale_events (event_id, event_name, start_at, end_at)
SELECT 
    event_id, 
    event_name, 
    start_at AT TIME ZONE 'Asia/Jakarta', 
    end_at AT TIME ZONE 'Asia/Jakarta'
FROM legacy.flash_sale_events;

INSERT INTO v2.flash_sale_items (event_id, product_id, flash_price, quota)
SELECT 
    event_id, 
    product_id, 
    flash_price::numeric(15,2), 
    quota
FROM legacy.flash_sale_items;