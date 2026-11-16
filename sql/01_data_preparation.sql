-- VIEW 01: ORDER-LEVEL ANALYTICS
-- Grain: One row per order
-- Purpose: Sales, customer, delivery, and satisfaction analysis

DROP VIEW IF EXISTS vw_order_analytics;

CREATE VIEW vw_order_analytics AS

WITH item_totals AS (
    SELECT
        order_id,
        COUNT(*) AS item_count,
        SUM(price) AS item_sales_value,
        SUM(freight_value) AS freight_value
    FROM olist_order_items_dataset
    GROUP BY order_id
),

payment_totals AS (
    SELECT
        order_id,
        COUNT(*) AS payment_count,
        SUM(payment_value) AS payment_value
    FROM olist_order_payments_dataset
    GROUP BY order_id
),

review_totals AS (
    SELECT
        order_id,
        COUNT(*) AS review_count,
        AVG(review_score) AS avg_review_score
    FROM olist_order_reviews_dataset
    GROUP BY order_id
)

SELECT
    -- Identifiers
    o.order_id,
    o.customer_id,
    c.customer_unique_id,

    -- Geography
    c.customer_city,
    c.customer_state,

    -- Status and dates
    o.order_status,
    o.order_purchase_timestamp,
    DATE(o.order_purchase_timestamp) AS purchase_date,
    STRFTIME('%Y-%m', o.order_purchase_timestamp)
        AS purchase_month,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    -- Sales and payments
    i.item_count,
    i.item_sales_value,
    i.freight_value,
    (i.item_sales_value + i.freight_value)
        AS item_plus_freight_value,

    p.payment_count,
    p.payment_value,

    ROUND(
        p.payment_value -
        (i.item_sales_value + i.freight_value),
        2
    ) AS payment_variance,

    CASE
        WHEN i.order_id IS NULL
            THEN 'Missing Items'
        WHEN p.order_id IS NULL
            THEN 'Missing Payment'
        WHEN ABS(
            p.payment_value -
            (i.item_sales_value + i.freight_value)
        ) > 0.01
            THEN 'Mismatch'
        ELSE 'Matched'
    END AS reconciliation_status,

    -- Delivery metrics
    ROUND(
        JULIANDAY(o.order_delivered_customer_date) -
        JULIANDAY(o.order_purchase_timestamp),
        2
    ) AS delivery_days,

    CASE
        WHEN o.order_delivered_customer_date IS NULL
            THEN NULL
        WHEN DATE(o.order_delivered_customer_date)
             <= DATE(o.order_estimated_delivery_date)
            THEN 1
        ELSE 0
    END AS delivered_on_time,

    -- Customer satisfaction
    r.review_count,
    r.avg_review_score

FROM olist_orders_dataset o

LEFT JOIN olist_customers_dataset c
    ON o.customer_id = c.customer_id

LEFT JOIN item_totals i
    ON o.order_id = i.order_id

LEFT JOIN payment_totals p
    ON o.order_id = p.order_id

LEFT JOIN review_totals r
    ON o.order_id = r.order_id;

	
-- VIEW 02: ITEM-LEVEL ANALYTICS
-- Grain: One row per order item
-- Purpose: Category, geography, and seller analysis

DROP VIEW IF EXISTS vw_order_item_analytics;

CREATE VIEW vw_order_item_analytics AS

SELECT
    -- Order and item identifiers
    i.order_id,
    i.order_item_id,
    i.product_id,
    i.seller_id,

    -- Customer information
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,

    -- Seller geography
    s.seller_city,
    s.seller_state,

    -- Order status and date
    o.order_status,
    o.order_purchase_timestamp,
    DATE(o.order_purchase_timestamp) AS purchase_date,
    STRFTIME('%Y-%m', o.order_purchase_timestamp)
        AS purchase_month,

    -- Product category
    p.product_category_name AS category_original,

    CASE
        WHEN p.product_category_name IS NULL
          OR TRIM(p.product_category_name) = ''
        THEN 'Unknown'
        ELSE COALESCE(
            t.product_category_name_english,
            p.product_category_name
        )
    END AS category,

    -- Financial measures
    i.price AS item_sales_value,
    i.freight_value,

    (i.price + i.freight_value)
        AS item_plus_freight_value

FROM olist_order_items_dataset i

LEFT JOIN olist_orders_dataset o
    ON i.order_id = o.order_id

LEFT JOIN olist_customers_dataset c
    ON o.customer_id = c.customer_id

LEFT JOIN olist_products_dataset p
    ON i.product_id = p.product_id

LEFT JOIN olist_sellers_dataset s
    ON i.seller_id = s.seller_id

LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name;

