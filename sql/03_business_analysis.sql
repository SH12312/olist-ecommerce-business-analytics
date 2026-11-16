-- OBJECTIVE:
-- Identify commercial growth opportunities, customer
-- patterns, and operational improvement priorities.

-- ANALYTICAL RULES:
-- 1. Primary cohort: delivered orders.
-- 2. Item Sales Value excludes freight.
-- 3. Use purchase dates for monthly sales analysis.
-- 4. Use customer_unique_id for repeat buyers.
-- 5. Respect analytical view grain.
-- 6. Historical results do not establish causation.

-- =====================================================
-- SECTION 01 | HISTORICAL SALES PERFORMANCE

-- Monthly Item Sales Value and MoM Growth
-- Analytical window: January 2017 to August 2018 （Exclude Sep–Dec 2016 from primary growth comparisons	
-- due to Sparse startup observations and missing November activity）

WITH monthly_sales AS (
    SELECT
        strftime('%Y-%m', order_purchase_timestamp)
            AS purchase_month,
        COUNT(*) AS delivered_orders,
        SUM(item_sales_value) AS sales_value

    FROM vw_order_analytics

    WHERE order_status = 'delivered'
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'

    GROUP BY
        strftime('%Y-%m', order_purchase_timestamp)
),

sales_with_previous AS (
    SELECT
        purchase_month,
        delivered_orders,
        sales_value,

        LAG(sales_value) OVER (
            ORDER BY purchase_month
        ) AS previous_month_sales

    FROM monthly_sales
)

SELECT
    purchase_month,
    delivered_orders,

    ROUND(sales_value, 2) AS sales_value,

    ROUND(previous_month_sales, 2)
        AS previous_month_sales,

    ROUND(
        100.0 * (sales_value - previous_month_sales)
        / NULLIF(previous_month_sales, 0),
        2
    ) AS mom_growth_pct

FROM sales_with_previous

ORDER BY purchase_month;


-- Comparable-period YoY performance
-- January-August 2017 vs January-August 2018

WITH annual_comparison AS (
    SELECT
        strftime('%Y', order_purchase_timestamp)
            AS purchase_year,

        COUNT(*) AS delivered_orders,

        SUM(item_sales_value) AS sales_value

    FROM vw_order_analytics

    WHERE order_status = 'delivered'
      AND (
          (order_purchase_timestamp >= '2017-01-01'
           AND order_purchase_timestamp < '2017-09-01')
          OR
          (order_purchase_timestamp >= '2018-01-01'
           AND order_purchase_timestamp < '2018-09-01')
      )

    GROUP BY
        strftime('%Y', order_purchase_timestamp)
)

SELECT
    purchase_year,
    delivered_orders,
    ROUND(sales_value, 2) AS sales_value,

    ROUND(
        sales_value / NULLIF(delivered_orders, 0),
        2
    ) AS avg_order_value,

    ROUND(
        100.0 * (
            sales_value - LAG(sales_value) OVER (
                ORDER BY purchase_year
            )
        ) / NULLIF(
            LAG(sales_value) OVER (
                ORDER BY purchase_year
            ), 0
        ),
        2
    ) AS yoy_sales_growth_pct

FROM annual_comparison

ORDER BY purchase_year;


-- =====================================================
-- SECTION 02 | PRODUCT CATEGORY PERFORMANCE

-- Category Year-over-Year Growth
-- Jan-Aug 2017 vs Jan-Aug 2018

WITH category_comparison AS (
    SELECT
        category,

        SUM(
            CASE
                WHEN order_purchase_timestamp >= '2017-01-01'
                 AND order_purchase_timestamp < '2017-09-01'
                THEN item_sales_value
                ELSE 0
            END
        ) AS sales_2017,

        SUM(
            CASE
                WHEN order_purchase_timestamp >= '2018-01-01'
                 AND order_purchase_timestamp < '2018-09-01'
                THEN item_sales_value
                ELSE 0
            END
        ) AS sales_2018

    FROM vw_order_item_analytics

    WHERE order_status = 'delivered'
      AND (
          (order_purchase_timestamp >= '2017-01-01'
           AND order_purchase_timestamp < '2017-09-01')
          OR
          (order_purchase_timestamp >= '2018-01-01'
           AND order_purchase_timestamp < '2018-09-01')
      )

    GROUP BY category
)

SELECT
    category,

    ROUND(sales_2017, 2) AS sales_2017,

    ROUND(sales_2018, 2) AS sales_2018,

    ROUND(
        sales_2018 - sales_2017, 2
    ) AS absolute_growth,

    ROUND(
        100.0 * (sales_2018 - sales_2017)
        / NULLIF(sales_2017, 0),
        2
    ) AS yoy_growth_pct,

    ROUND(
        100.0 * sales_2018
        / SUM(sales_2018) OVER (),
        2
    ) AS contribution_2018_pct

FROM category_comparison

ORDER BY sales_2018 DESC;


-- =====================================================
-- SECTION 03 | GEOGRAPHIC MARKET PERFORMANCE

-- Customer-state commercial performance
-- Jan-Aug 2017 vs Jan-Aug 2018

WITH state_sales AS (
    SELECT
        customer_state,

        SUM(
            CASE
                WHEN order_purchase_timestamp >= '2017-01-01'
                 AND order_purchase_timestamp < '2017-09-01'
                THEN item_sales_value
                ELSE 0
            END
        ) AS sales_2017,

        SUM(
            CASE
                WHEN order_purchase_timestamp >= '2018-01-01'
                 AND order_purchase_timestamp < '2018-09-01'
                THEN item_sales_value
                ELSE 0
            END
        ) AS sales_2018,

        COUNT(DISTINCT
            CASE
                WHEN order_purchase_timestamp >= '2018-01-01'
                 AND order_purchase_timestamp < '2018-09-01'
                THEN order_id
            END
        ) AS orders_2018

    FROM vw_order_analytics

    WHERE order_status = 'delivered'
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'

    GROUP BY customer_state
)

SELECT
    customer_state,

    ROUND(sales_2017, 2) AS sales_2017,

    ROUND(sales_2018, 2) AS sales_2018,

    orders_2018,

    ROUND(
        sales_2018 - sales_2017, 2
    ) AS absolute_growth,

    ROUND(
        100.0 * (sales_2018 - sales_2017)
        / NULLIF(sales_2017, 0),
        2
    ) AS yoy_growth_pct,

    ROUND(
        100.0 * sales_2018
        / SUM(sales_2018) OVER (),
        2
    ) AS contribution_2018_pct

FROM state_sales

ORDER BY sales_2018 DESC;


-- Priority Category x State Performance
-- Jan-Aug 2017 vs Jan-Aug 2018

WITH market_performance AS (
    SELECT
        customer_state,
        category,

        SUM(
            CASE
                WHEN order_purchase_timestamp >= '2017-01-01'
                 AND order_purchase_timestamp < '2017-09-01'
                THEN item_sales_value
                ELSE 0
            END
        ) AS sales_2017,

        SUM(
            CASE
                WHEN order_purchase_timestamp >= '2018-01-01'
                 AND order_purchase_timestamp < '2018-09-01'
                THEN item_sales_value
                ELSE 0
            END
        ) AS sales_2018

    FROM vw_order_item_analytics

    WHERE order_status = 'delivered'
      AND customer_state IN ('SP', 'MG', 'RJ')
      AND category IN (
          'health_beauty',
          'watches_gifts',
          'housewares',
          'cool_stuff'
      )
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'

    GROUP BY
        customer_state,
        category
)

SELECT
    customer_state,
    category,

    ROUND(sales_2017, 2) AS sales_2017,
    ROUND(sales_2018, 2) AS sales_2018,

    ROUND(
        sales_2018 - sales_2017, 2
    ) AS absolute_growth,

    ROUND(
        100.0 * (sales_2018 - sales_2017)
        / NULLIF(sales_2017, 0),
        2
    ) AS yoy_growth_pct

FROM market_performance

ORDER BY sales_2018 DESC;


-- =====================================================
-- SECTION 04 | CUSTOMER PURCHASING BEHAVIOR

-- Observed repeat purchasing among delivered orders
-- Full available historical observation period

WITH customer_purchases AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS order_count,
        SUM(item_sales_value) AS total_sales_value

    FROM vw_order_analytics

    WHERE order_status = 'delivered'
      AND customer_unique_id IS NOT NULL

    GROUP BY customer_unique_id
),

customer_segments AS (
    SELECT
        CASE
            WHEN order_count = 1 THEN 'One-Time Buyer'
            ELSE 'Repeat Buyer'
        END AS buyer_type,

        COUNT(*) AS unique_buyers,
        SUM(order_count) AS total_orders,
        SUM(total_sales_value) AS sales_value

    FROM customer_purchases

    GROUP BY buyer_type
)

SELECT
    buyer_type,
    unique_buyers,
    total_orders,

    ROUND(sales_value, 2) AS sales_value,

    ROUND(
        100.0 * unique_buyers
        / SUM(unique_buyers) OVER (),
        2
    ) AS buyer_share_pct,

    ROUND(
        100.0 * sales_value
        / NULLIF(SUM(sales_value) OVER (), 0),
        2
    ) AS sales_share_pct

FROM customer_segments

ORDER BY unique_buyers DESC;


-- =====================================================
-- SECTION 05 | DELIVERY & CUSTOMER SATISFACTION

-- Overall delivery performance
-- Full historical delivered-order cohort

SELECT
    COUNT(*) AS delivered_orders,

    COUNT(delivery_days) AS valid_delivery_durations,

    ROUND(
        AVG(delivery_days), 2
    ) AS avg_delivery_days,

    SUM(
        CASE WHEN delivered_on_time = 1
        THEN 1 ELSE 0 END
    ) AS on_time_orders,

    SUM(
        CASE WHEN delivered_on_time = 0
        THEN 1 ELSE 0 END
    ) AS late_orders,

    ROUND(
        100.0 * SUM(
            CASE WHEN delivered_on_time = 1
            THEN 1 ELSE 0 END
        )
        / NULLIF(COUNT(delivered_on_time), 0),
        2
    ) AS on_time_rate_pct,

    ROUND(
        100.0 * SUM(
            CASE WHEN delivered_on_time = 0
            THEN 1 ELSE 0 END
        )
        / NULLIF(COUNT(delivered_on_time), 0),
        2
    ) AS late_rate_pct,

    ROUND(
        AVG(avg_review_score), 2
    ) AS avg_review_score

FROM vw_order_analytics

WHERE order_status = 'delivered';


-- Delivery Timeliness vs Customer Satisfaction
-- Full historical delivered-order cohort

SELECT
    CASE
        WHEN delivered_on_time = 1 THEN 'On-Time'
        WHEN delivered_on_time = 0 THEN 'Late'
    END AS delivery_group,

    COUNT(*) AS total_orders,

    COUNT(avg_review_score) AS reviewed_orders,

    ROUND(
        AVG(delivery_days), 2
    ) AS avg_delivery_days,

    ROUND(
        AVG(avg_review_score), 2
    ) AS avg_review_score,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN avg_review_score <= 2 THEN 1
                ELSE 0
            END
        )
        / NULLIF(COUNT(avg_review_score), 0),
        2
    ) AS low_review_rate_pct

FROM vw_order_analytics

WHERE order_status = 'delivered'
  AND delivered_on_time IN (0, 1)

GROUP BY delivered_on_time

ORDER BY delivered_on_time DESC;


-- Delivery Performance by Customer State
-- Full historical delivered-order cohort

SELECT
    customer_state,

    COUNT(*) AS delivered_orders,

    COUNT(delivered_on_time) AS valid_delivery_records,

    ROUND(
        AVG(delivery_days), 2
    ) AS avg_delivery_days,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN delivered_on_time = 0 THEN 1
                ELSE 0
            END
        )
        / NULLIF(COUNT(delivered_on_time), 0),
        2
    ) AS late_delivery_rate_pct,

    ROUND(
        AVG(avg_review_score), 2
    ) AS avg_review_score,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN avg_review_score <= 2 THEN 1
                ELSE 0
            END
        )
        / NULLIF(COUNT(avg_review_score), 0),
        2
    ) AS low_review_rate_pct

FROM vw_order_analytics

WHERE order_status = 'delivered'

GROUP BY customer_state

ORDER BY delivered_orders DESC;


-- Supplemental Historical Inputs
SELECT
    SUM(CASE
        WHEN customer_state = 'RJ'
         AND delivered_on_time = 0
        THEN 1 ELSE 0
    END) AS rj_late_orders,

    SUM(CASE
        WHEN customer_state = 'RJ'
         AND delivered_on_time IS NOT NULL
        THEN 1 ELSE 0
    END) AS rj_valid_delivery_records,

    COUNT(item_sales_value)
        AS orders_with_sales_value,

    ROUND(AVG(item_sales_value), 2)
        AS avg_delivered_order_item_sales

FROM vw_order_analytics
WHERE order_status = 'delivered';



-- =====================================================
-- SECTION 06 | PRELIMINARY MANAGEMENT INSIGHTS
-- =====================================================
--
-- RECOMMENDATION 1: TARGETED COMMERCIAL GROWTH
-- SP x Health & Beauty generated R$298,148 in Item
-- Sales Value during Jan-Aug 2018 (+312.83% YoY).
-- Action: Test targeted merchandising and seller
-- development initiatives in this market.
-- Risk: Growth does not establish incremental demand
-- or profitability.
--
-- RECOMMENDATION 2: DELIVERY RELIABILITY
-- RJ had a 12.11% historical late-delivery rate,
-- compared with 4.49% in SP.
-- Late orders averaged 2.27 review points versus
-- 4.29 for on-time orders.
-- Action: Investigate carriers, seller dispatch
-- delays, and delivery bottlenecks in RJ.
-- Risk: Observational association, not causation.
--
-- RECOMMENDATION 3: REPEAT PURCHASING
-- Only 3.00% of observed buyers placed at least two
-- delivered orders during the available history.
-- Action: Pilot targeted repeat-purchase initiatives
-- with an appropriate control group.
-- Risk: Limited observation window; this is not
-- a formal customer retention rate.
--
-- All recommendations remain preliminary until
-- scenario modeling and final executive review.
