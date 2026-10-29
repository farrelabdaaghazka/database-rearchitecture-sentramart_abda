CREATE SCHEMA IF NOT EXISTS v2;
SET search_path TO v2, public;

CREATE TYPE seller_type_enum AS ENUM ('regular', 'star', 'official');
CREATE TYPE customer_tier_enum AS ENUM ('bronze', 'silver', 'gold', 'platinum');
CREATE TYPE order_status_enum AS ENUM ('CREATED', 'PAID', 'SHIPPED', 'DELIVERED', 'CANCELLED', 'REFUNDED');
CREATE TYPE payment_status_enum AS ENUM ('PENDING', 'SUCCESS', 'FAILED', 'EXPIRED', 'REFUNDED');

CREATE TABLE categories (
    category_id INT PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL
);

CREATE TABLE sellers (
    seller_id INT PRIMARY KEY,
    seller_name VARCHAR(150) NOT NULL,
    seller_type seller_type_enum NOT NULL DEFAULT 'regular',
    city VARCHAR(100) NOT NULL,
    province VARCHAR(100) NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    rating NUMERIC(3,2) NOT NULL DEFAULT 0.00 CHECK (rating >= 0.00 AND rating <= 5.00)
);

CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    city VARCHAR(100) NOT NULL,
    province VARCHAR(100) NOT NULL,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tier customer_tier_enum NOT NULL DEFAULT 'bronze'
);

CREATE TABLE customer_pii (
    customer_id INT PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(30) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_customer_pii_customers FOREIGN KEY (customer_id) 
        REFERENCES customers(customer_id) ON DELETE CASCADE
);

CREATE TABLE products (
    product_id INT PRIMARY KEY,
    seller_id INT NOT NULL,
    category_id INT NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    price NUMERIC(15,2) NOT NULL CHECK (price >= 0),
    stock INT NOT NULL CHECK (stock >= 0),
    is_flash_sale BOOLEAN NOT NULL DEFAULT FALSE,
    attributes JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_products_sellers FOREIGN KEY (seller_id) REFERENCES sellers(seller_id),
    CONSTRAINT fk_products_categories FOREIGN KEY (category_id) REFERENCES categories(category_id)
);

CREATE TABLE orders (
    order_id BIGINT NOT NULL,
    customer_id INT NOT NULL,
    order_date TIMESTAMPTZ NOT NULL,
    status order_status_enum NOT NULL DEFAULT 'CREATED',
    shipping_fee NUMERIC(15,2) NOT NULL DEFAULT 0.00 CHECK (shipping_fee >= 0),
    discount NUMERIC(15,2) NOT NULL DEFAULT 0.00 CHECK (discount >= 0),
    total_amount NUMERIC(15,2) NOT NULL CHECK (total_amount >= 0),
    voucher_code VARCHAR(50),
    shipping_city VARCHAR(100) NOT NULL,
    PRIMARY KEY (order_date, order_id),
    CONSTRAINT fk_orders_customers FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
) PARTITION BY RANGE (order_date);

CREATE TABLE orders_2024 PARTITION OF orders
    FOR VALUES FROM ('2024-01-01 00:00:00+00') TO ('2025-01-01 00:00:00+00');

CREATE TABLE orders_2025 PARTITION OF orders
    FOR VALUES FROM ('2025-01-01 00:00:00+00') TO ('2026-01-01 00:00:00+00');

CREATE TABLE orders_2026 PARTITION OF orders
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');

CREATE TABLE orders_default PARTITION OF orders DEFAULT;

CREATE TABLE order_items (
    order_item_id BIGINT NOT NULL,
    order_date TIMESTAMPTZ NOT NULL,
    order_id BIGINT NOT NULL,
    product_id INT NOT NULL,
    seller_id INT NOT NULL,
    qty INT NOT NULL CHECK (qty > 0),
    unit_price NUMERIC(15,2) NOT NULL CHECK (unit_price >= 0),
    subtotal NUMERIC(15,2) NOT NULL CHECK (subtotal >= 0),
    PRIMARY KEY (order_date, order_item_id),
    CONSTRAINT fk_order_items_orders FOREIGN KEY (order_date, order_id) 
        REFERENCES orders(order_date, order_id) ON DELETE CASCADE,
    CONSTRAINT fk_order_items_products FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT fk_order_items_sellers FOREIGN KEY (seller_id) REFERENCES sellers(seller_id)
) PARTITION BY RANGE (order_date);

CREATE TABLE order_items_2024 PARTITION OF order_items
    FOR VALUES FROM ('2024-01-01 00:00:00+00') TO ('2025-01-01 00:00:00+00');

CREATE TABLE order_items_2025 PARTITION OF order_items
    FOR VALUES FROM ('2025-01-01 00:00:00+00') TO ('2026-01-01 00:00:00+00');

CREATE TABLE order_items_2026 PARTITION OF order_items
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');

CREATE TABLE order_items_default PARTITION OF order_items DEFAULT;

CREATE TABLE payments (
    payment_id BIGINT PRIMARY KEY,
    order_date TIMESTAMPTZ NOT NULL,
    order_id BIGINT NOT NULL,
    method VARCHAR(50) NOT NULL,
    amount NUMERIC(15,2) NOT NULL CHECK (amount >= 0),
    status payment_status_enum NOT NULL DEFAULT 'PENDING',
    gateway_ref VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    paid_at TIMESTAMPTZ,
    CONSTRAINT fk_payments_orders FOREIGN KEY (order_date, order_id) 
        REFERENCES orders(order_date, order_id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX uq_payments_success_gateway_ref 
    ON payments (gateway_ref) 
    WHERE status = 'SUCCESS' AND gateway_ref IS NOT NULL;

CREATE TABLE flash_sale_events (
    event_id VARCHAR(50) PRIMARY KEY,
    event_name VARCHAR(150) NOT NULL,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_flash_sale_dates CHECK (end_at > start_at)
);

CREATE TABLE flash_sale_items (
    event_id VARCHAR(50) NOT NULL,
    product_id INT NOT NULL,
    flash_price NUMERIC(15,2) NOT NULL CHECK (flash_price >= 0),
    quota INT NOT NULL CHECK (quota >= 0),
    PRIMARY KEY (event_id, product_id),
    CONSTRAINT fk_fsi_events FOREIGN KEY (event_id) REFERENCES flash_sale_events(event_id) ON DELETE CASCADE,
    CONSTRAINT fk_fsi_products FOREIGN KEY (product_id) REFERENCES products(product_id)
);

CREATE INDEX idx_products_seller_id ON products(seller_id);
CREATE INDEX idx_products_category_id ON products(category_id);
CREATE INDEX idx_products_attributes_gin ON products USING GIN (attributes);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_payments_order_lookup ON payments(order_date, order_id);