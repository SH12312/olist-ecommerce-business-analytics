-- CHECK 01: Primary identifier integrity

SELECT
    'Orders' AS dataset,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_ids,
    SUM(CASE
        WHEN order_id IS NULL OR TRIM(order_id) = ''
        THEN 1 ELSE 0
    END) AS missing_ids
FROM olist_orders_dataset

UNION ALL

SELECT
    'Customers',
    COUNT(*),
    COUNT(DISTINCT customer_id),
    SUM(CASE
        WHEN customer_id IS NULL OR TRIM(customer_id) = ''
        THEN 1 ELSE 0
    END)
FROM olist_customers_dataset

UNION ALL

SELECT
    'Products',
    COUNT(*),
    COUNT(DISTINCT product_id),
    SUM(CASE
        WHEN product_id IS NULL OR TRIM(product_id) = ''
        THEN 1 ELSE 0
    END)
FROM olist_products_dataset

UNION ALL

SELECT
    'Sellers',
    COUNT(*),
    COUNT(DISTINCT seller_id),
    SUM(CASE
        WHEN seller_id IS NULL OR TRIM(seller_id) = ''
        THEN 1 ELSE 0
    END)
FROM olist_sellers_dataset;


-- CHECK 02: Unmatched foreign keys

SELECT
    'Orders without matching customer' AS issue,
    COUNT(*) AS affected_rows
FROM olist_orders_dataset o
LEFT JOIN olist_customers_dataset c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL

UNION ALL

SELECT
    'Items without matching order',
    COUNT(*)
FROM olist_order_items_dataset i
LEFT JOIN olist_orders_dataset o
    ON i.order_id = o.order_id
WHERE o.order_id IS NULL

UNION ALL

SELECT
    'Items without matching product',
    COUNT(*)
FROM olist_order_items_dataset i
LEFT JOIN olist_products_dataset p
    ON i.product_id = p.product_id
WHERE p.product_id IS NULL

UNION ALL

SELECT
    'Items without matching seller',
    COUNT(*)
FROM olist_order_items_dataset i
LEFT JOIN olist_sellers_dataset s
    ON i.seller_id = s.seller_id
WHERE s.seller_id IS NULL

UNION ALL

SELECT
    'Payments without matching order',
    COUNT(*)
FROM olist_order_payments_dataset p
LEFT JOIN olist_orders_dataset o
    ON p.order_id = o.order_id
WHERE o.order_id IS NULL

UNION ALL

SELECT
    'Reviews without matching order',
    COUNT(*)
FROM olist_order_reviews_dataset r
LEFT JOIN olist_orders_dataset o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;


-- CHECK 03: One-to-many relationships

SELECT
    'Orders with multiple items' AS metric,
    COUNT(*) AS order_count
FROM (
    SELECT order_id
    FROM olist_order_items_dataset
    GROUP BY order_id
    HAVING COUNT(*) > 1
)

UNION ALL

SELECT
    'Orders with multiple payments',
    COUNT(*)
FROM (
    SELECT order_id
    FROM olist_order_payments_dataset
    GROUP BY order_id
    HAVING COUNT(*) > 1
)

UNION ALL

SELECT
    'Orders with multiple reviews',
    COUNT(*)
FROM (
    SELECT order_id
    FROM olist_order_reviews_dataset
    GROUP BY order_id
    HAVING COUNT(*) > 1
);


-- CHECK 04A: Order status distribution
SELECT
    order_status,
    COUNT(*) AS order_count
FROM olist_orders_dataset
GROUP BY order_status
ORDER BY order_count DESC;


-- CHECK 04B: Historical coverage
SELECT
    MIN(order_purchase_timestamp) AS first_purchase,
    MAX(order_purchase_timestamp) AS last_purchase,
    MIN(order_delivered_customer_date) AS first_delivery,
    MAX(order_delivered_customer_date) AS last_delivery
FROM olist_orders_dataset;


-- CHECK 05: Delivery timestamp integrity
SELECT
    order_status,
    COUNT(*) AS total_orders,

    SUM(CASE
        WHEN NULLIF(TRIM(order_delivered_customer_date), '') IS NULL
        THEN 1 ELSE 0
    END) AS missing_actual_delivery,

    SUM(CASE
        WHEN NULLIF(TRIM(order_estimated_delivery_date), '') IS NULL
        THEN 1 ELSE 0
    END) AS missing_estimated_delivery,

    SUM(CASE
        WHEN julianday(order_delivered_customer_date)
             < julianday(order_purchase_timestamp)
        THEN 1 ELSE 0
    END) AS delivered_before_purchase

FROM olist_orders_dataset
GROUP BY order_status
ORDER BY total_orders DESC;


-- CHECK 06: Product category completeness
SELECT
    COUNT(*) AS total_products,

    SUM(CASE
        WHEN NULLIF(TRIM(p.product_category_name), '') IS NULL
        THEN 1 ELSE 0
    END) AS missing_category,

    SUM(CASE
        WHEN p.product_category_name IS NOT NULL
         AND TRIM(p.product_category_name) <> ''
         AND t.product_category_name IS NULL
        THEN 1 ELSE 0
    END) AS missing_translation

FROM olist_products_dataset p
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name;
	

-- CHECK 07: Customer identifier integrity

SELECT
    COUNT(*) AS customer_records,
    COUNT(DISTINCT customer_id) AS unique_customer_ids,
    COUNT(DISTINCT customer_unique_id) AS unique_buyers,

    SUM(CASE
        WHEN customer_unique_id IS NULL
          OR TRIM(customer_unique_id) = ''
        THEN 1 ELSE 0
    END) AS missing_unique_buyer_ids

FROM olist_customers_dataset;


-- CHECK 08: Orders missing items or payments
-- Group by status to distinguish valid exceptions.

SELECT
    o.order_status,
    COUNT(*) AS total_orders,

    SUM(CASE WHEN i.order_id IS NULL
        THEN 1 ELSE 0 END) AS orders_without_items,

    SUM(CASE WHEN p.order_id IS NULL
        THEN 1 ELSE 0 END) AS orders_without_payments

FROM olist_orders_dataset o

LEFT JOIN (
    SELECT DISTINCT order_id
    FROM olist_order_items_dataset
) i
    ON o.order_id = i.order_id

LEFT JOIN (
    SELECT DISTINCT order_id
    FROM olist_order_payments_dataset
) p
    ON o.order_id = p.order_id

GROUP BY o.order_status
ORDER BY total_orders DESC;


-- CHECK 09: Order-level financial reconciliation
-- Aggregate the two one-to-many tables separately.

WITH item_totals AS (
    SELECT
        order_id,
        SUM(price) AS item_sales,
        SUM(freight_value) AS freight
    FROM olist_order_items_dataset
    GROUP BY order_id
),

payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS payments
    FROM olist_order_payments_dataset
    GROUP BY order_id
),

order_reconciliation AS (
    SELECT
        o.order_id,
        o.order_status,
        i.item_sales,
        i.freight,
        p.payments,

        ROUND(
            p.payments - (i.item_sales + i.freight),
            2
        ) AS variance

    FROM olist_orders_dataset o

    LEFT JOIN item_totals i
        ON o.order_id = i.order_id

    LEFT JOIN payment_totals p
        ON o.order_id = p.order_id
)

SELECT
    order_status,
    COUNT(*) AS total_orders,

    SUM(CASE
        WHEN variance IS NOT NULL
         AND ABS(variance) > 0.01
        THEN 1 ELSE 0
    END) AS mismatched_orders,

    ROUND(SUM(item_sales), 2) AS total_item_sales,
    ROUND(SUM(freight), 2) AS total_freight,
    ROUND(SUM(payments), 2) AS total_payments,

    ROUND(SUM(
        CASE
            WHEN variance IS NOT NULL
            THEN variance
            ELSE 0
        END
    ), 2) AS total_variance

FROM order_reconciliation
GROUP BY order_status
ORDER BY total_orders DESC;


-- ====================================================
-- DATA VALIDATION FINDINGS | DAY 2
-- ====================================================
--
-- SOURCE INTEGRITY
-- 9 raw datasets imported with expected row counts.
-- Main entity identifiers are unique and nonmissing.
-- All 6 tested foreign-key relationships matched.
--
-- ANALYTICAL COHORT
-- 99,441 total orders; 96,478 delivered orders.
-- Delivered orders form the primary sales cohort.
--
-- DATA QUALITY
-- 8 delivered orders lack actual delivery timestamps.
-- 610 products lack source categories.
-- 13 products lack English category translations.
-- 1 delivered order lacks payment records.
-- 299 delivered orders have payment differences
-- exceeding R$0.01 under the reconciliation check.
--
-- ANALYTICAL DECISIONS
-- Use customer_unique_id for repeat-buyer analysis.
-- Preserve missing categories as 'Unknown'.
-- Exclude missing delivery dates from delivery KPIs.
-- Keep item sales separate from recorded payments.
-- Do not classify Item Sales Value as accounting
-- revenue, GMV, or profit without qualification.
-- Use safe aggregation to avoid duplicated values.
-- Verify historical month completeness before
-- interpreting growth trends.
--
-- FINAL VIEWS
-- vw_order_analytics: 99,441 rows.
-- vw_order_item_analytics: 112,650 rows.
-- Both passed grain and financial total checks.
-- ====================================================
