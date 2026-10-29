SET search_path TO v2, public;


CREATE OR REPLACE FUNCTION v2.fn_checkout_flash_sale(
    p_customer_id INT,
    p_event_id VARCHAR(50),
    p_product_id INT,
    p_qty INT,
    p_shipping_fee NUMERIC(15,2),
    p_discount NUMERIC(15,2),
    p_shipping_city VARCHAR(100)
)
RETURNS TABLE (
    out_order_id INT,
    out_status VARCHAR(50),
    out_message VARCHAR(255)
) AS $$
DECLARE
    v_quota INT;
    v_flash_price NUMERIC(15,2);
    v_order_id BIGINT;
    v_order_item_id BIGINT;
    v_order_date TIMESTAMPTZ := NOW();
    v_subtotal NUMERIC(15,2);
    v_seller_id INT;
BEGIN
    SELECT seller_id INTO v_seller_id
    FROM v2.products
    WHERE product_id = p_product_id;

    IF v_seller_id IS NULL THEN
        RETURN QUERY SELECT NULL::INT, 'FAILED'::VARCHAR, 'Product not found'::VARCHAR;
        RETURN;
    END IF;

    SELECT quota, flash_price INTO v_quota, v_flash_price
    FROM v2.flash_sale_items
    WHERE event_id = p_event_id AND product_id = p_product_id
    FOR UPDATE;

    IF v_quota IS NULL OR v_quota < p_qty THEN
        RETURN QUERY SELECT NULL::INT, 'FAILED'::VARCHAR, 'Insufficient flash sale quota'::VARCHAR;
        RETURN;
    END IF;

    UPDATE v2.flash_sale_items
    SET quota = quota - p_qty
    WHERE event_id = p_event_id AND product_id = p_product_id;

    UPDATE v2.products
    SET stock = stock - p_qty
    WHERE product_id = p_product_id AND stock >= p_qty;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Insufficient main product stock';
    END IF;

    v_subtotal := v_flash_price * p_qty;
    v_order_id := (SELECT COALESCE(MAX(order_id), 0) + 1 FROM v2.orders);
    v_order_item_id := (SELECT COALESCE(MAX(order_item_id), 0) + 1 FROM v2.order_items);

    INSERT INTO v2.orders (
        order_id, customer_id, order_date, status, 
        shipping_fee, discount, total_amount, shipping_city
    ) VALUES (
        v_order_id, p_customer_id, v_order_date, 'CREATED'::v2.order_status_enum,
        p_shipping_fee, p_discount, (v_subtotal + p_shipping_fee - p_discount), p_shipping_city
    );

    INSERT INTO v2.order_items (
        order_item_id, order_date, order_id, product_id, seller_id, qty, unit_price, subtotal
    ) VALUES (
        v_order_item_id, v_order_date, v_order_id, p_product_id, v_seller_id, p_qty, v_flash_price, v_subtotal
    );

    RETURN QUERY SELECT v_order_id::INT, 'SUCCESS'::VARCHAR, 'Order created successfully'::VARCHAR;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION v2.fn_process_payment_callback(
    p_order_id INT,
    p_order_date TIMESTAMPTZ,
    p_method VARCHAR(50),
    p_amount NUMERIC(15,2),
    p_gateway_ref VARCHAR(100)
)
RETURNS TABLE (
    out_payment_id BIGINT,
    out_status VARCHAR(50),
    out_message VARCHAR(255)
) AS $$
DECLARE
    v_existing_id BIGINT;
    v_new_payment_id BIGINT;
BEGIN
    SELECT payment_id INTO v_existing_id
    FROM v2.payments
    WHERE gateway_ref = p_gateway_ref AND status = 'SUCCESS'
    FOR UPDATE;

    IF v_existing_id IS NOT NULL THEN
        RETURN QUERY SELECT v_existing_id, 'SKIPPED'::VARCHAR, 'Payment callback already processed (Idempotent)'::VARCHAR;
        RETURN;
    END IF;

    v_new_payment_id := (SELECT COALESCE(MAX(payment_id), 0) + 1 FROM v2.payments);

    INSERT INTO v2.payments (
        payment_id, order_date, order_id, method, amount, status, gateway_ref, created_at, paid_at
    ) VALUES (
        v_new_payment_id, p_order_date, p_order_id, p_method, p_amount, 'SUCCESS'::v2.payment_status_enum,
        p_gateway_ref, NOW(), NOW()
    );

    UPDATE v2.orders
    SET status = 'PAID'::v2.order_status_enum
    WHERE order_id = p_order_id AND order_date = p_order_date;

    RETURN QUERY SELECT v_new_payment_id, 'SUCCESS'::VARCHAR, 'Payment processed successfully'::VARCHAR;
EXCEPTION
    WHEN unique_violation THEN
        SELECT payment_id INTO v_existing_id
        FROM v2.payments
        WHERE gateway_ref = p_gateway_ref;
        
        RETURN QUERY SELECT v_existing_id, 'SKIPPED'::VARCHAR, 'Duplicate gateway reference blocked by constraint'::VARCHAR;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION v2.fn_checkout_multi_items(
    p_customer_id INT,
    p_product_ids INT[],
    p_qtys INT[],
    p_shipping_fee NUMERIC(15,2),
    p_shipping_city VARCHAR(100)
)
RETURNS TABLE (
    out_order_id INT,
    out_status VARCHAR(50)
) AS $$
DECLARE
    v_order_id BIGINT;
    v_order_item_id BIGINT;
    v_order_date TIMESTAMPTZ := NOW();
    v_total_amount NUMERIC(15,2) := 0;
    v_item_subtotal NUMERIC(15,2);
    v_prod RECORD;
    i INT;
    v_sorted_products INT[];
BEGIN
    SELECT ARRAY_AGG(p_id ORDER BY p_id ASC) INTO v_sorted_products
    FROM UNNEST(p_product_ids) AS p_id;

    FOR i IN 1..ARRAY_LENGTH(v_sorted_products, 1) LOOP
        PERFORM product_id 
        FROM v2.products 
        WHERE product_id = v_sorted_products[i] 
        FOR UPDATE;
    END LOOP;

    v_order_id := (SELECT COALESCE(MAX(order_id), 0) + 1 FROM v2.orders);

    INSERT INTO v2.orders (
        order_id, customer_id, order_date, status, 
        shipping_fee, discount, total_amount, shipping_city
    ) VALUES (
        v_order_id, p_customer_id, v_order_date, 'CREATED'::v2.order_status_enum,
        p_shipping_fee, 0, 0, p_shipping_city
    );

    FOR i IN 1..ARRAY_LENGTH(p_product_ids, 1) LOOP
        SELECT price, seller_id, stock INTO v_prod
        FROM v2.products
        WHERE product_id = p_product_ids[i];

        IF v_prod.stock < p_qtys[i] THEN
            RAISE EXCEPTION 'Stock overflow for product_id %', p_product_ids[i];
        END IF;

        UPDATE v2.products
        SET stock = stock - p_qtys[i]
        WHERE product_id = p_product_ids[i];

        v_item_subtotal := v_prod.price * p_qtys[i];
        v_total_amount := v_total_amount + v_item_subtotal;
        v_order_item_id := (SELECT COALESCE(MAX(order_item_id), 0) + 1 FROM v2.order_items);

        INSERT INTO v2.order_items (
            order_item_id, order_date, order_id, product_id, seller_id, qty, unit_price, subtotal
        ) VALUES (
            v_order_item_id, v_order_date, v_order_id, p_product_ids[i], v_prod.seller_id, p_qtys[i], v_prod.price, v_item_subtotal
        );
    END LOOP;

    UPDATE v2.orders
    SET total_amount = (v_total_amount + p_shipping_fee)
    WHERE order_id = v_order_id AND order_date = v_order_date;

    RETURN QUERY SELECT v_order_id::INT, 'SUCCESS'::VARCHAR;
END;
$$ LANGUAGE plpgsql;