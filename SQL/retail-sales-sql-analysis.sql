--Data Cleaning & Validation
--Customer Table
SELECT *
FROM customers;

ALTER TABLE customers
ADD signup_date2 DATE;

--Standardize Date Format
UPDATE customers
SET signup_date2 = CONVERT(DATE,signup_date);

--Categorical standardization was performed to ensure consistency in dimensional attributes and prevent grouping anomalies across reporting tools.
UPDATE  customers
SET city = 'Lagos'
WHERE city = 'lagos';

--Fix NULL emails
SELECT COUNT(*) AS missing_emails
FROM customers
WHERE email IS NULL;

UPDATE customers
SET email = 'N/A'
WHERE email IS NULL

--Inventory Table
SELECT *
FROM inventory;

ALTER TABLE inventory
ADD last_restock_date2 DATE;

--Standardize Date Format
UPDATE inventory
SET last_restock_date2 = CONVERT(DATE,last_restock_date);


--Orders Table
SELECT *
FROM orders

ALTER TABLE orders
ADD order_date2 DATE, delivery_date2 DATE;

--Standardize Date Format
UPDATE orders
SET order_date2 = CONVERT(DATE,order_date), delivery_date2 = CONVERT(DATE,delivery_date);


--Products Table
--Format Categories
--inconsistencies were identified between product names and assigned categories. A rule-based classification
--update was implemented using SQL pattern matching to ensure logical alignment between product taxonomy and category structure.
SELECT *
FROM products; 

UPDATE products 
    SET category =
        CASE
        WHEN product_name LIKE '%Earbuds%'      THEN 'Electronics'
        WHEN product_name LIKE '%Smart TV%'     THEN 'Electronics'
        WHEN product_name LIKE '%Laptop%'       THEN 'Electronics'
        WHEN product_name LIKE '%Smartphone%'   THEN 'Electronics'
        WHEN product_name LIKE '%Tablet%'       THEN 'Electronics'
        WHEN product_name LIKE '%Power Bank%'   THEN 'Electronics'
        WHEN product_name LIKE '%Camera%'       THEN 'Electronics'
        WHEN product_name LIKE '%Speaker%'      THEN 'Electronics'
       
        WHEN product_name LIKE '%Handbag%'      THEN 'Fashion'
        WHEN product_name LIKE '%Watch%'        THEN 'Fashion'
        
        WHEN product_name LIKE '%Cookware%'     THEN 'Home'
        WHEN product_name LIKE '%Air Fryer%'    THEN 'Home'
        WHEN product_name LIKE '%Kettle%'       THEN 'Home'
        WHEN product_name LIKE '%Microwave%'    THEN 'Home'
        WHEN product_name LIKE '%Chair%'        THEN 'Home'
        WHEN product_name LIKE '%Lamp%'         THEN 'Home'

        WHEN product_name LIKE '%Yoga%'         THEN 'Sports'
        WHEN product_name LIKE '%Jersey%'       THEN 'Sports'
        WHEN product_name LIKE '%Sneakers%'     THEN 'Sports'

        WHEN product_name LIKE '%Hair Dryer%'   THEN 'Beauty'

        ELSE category
    END;

--order_items table
--Detect invalid unit_price in order_items
SELECT *
FROM order_items
WHERE unit_price < 0;

--Detect zero quantity in order items
SELECT *
FROM order_items
WHERE quantity = 0

--zero quantity was detected
DELETE FROM order_items
WHERE quantity = 0;


--inventory table
--Detect negative inventory stock
SELECT *
FROM inventory
Where stock_quantity < 0 

--negative inventory stock was detected
UPDATE inventory
SET stock_quantity = 0
WHERE stock_quantity < 0


--Core Sales Analysis

--Total revenue for all completed orders.
--Calculate total revenue for all completed orders.
ALTER TABLE order_items
ADD revenue AS (quantity * unit_price);

SELECT *
FROM order_items;

SELECT 
    orders.status, 
    order_items.revenue 
FROM order_items
JOIN orders
    ON orders.order_id = order_items.order_id;

--Total revenue by month.
 SELECT 
     MONTH(orders.order_date2) AS sales_month, 
    ROUND(SUM(order_items.revenue),0) Total_revenue 
FROM order_items
JOIN orders
    ON orders.order_id = order_items.order_id
WHERE status = 'completed'
GROUP BY MONTH(orders.order_date2)
ORDER BY MONTH(orders.order_date2);

--Monthly revenue growth rate
WITH monthly_revenue AS (
    SELECT 
        MONTH(orders.order_date2) AS sales_month,
        YEAR(orders.order_date2) AS sales_year,
        SUM(order_items.revenue) AS total_revenue
    FROM order_items
    JOIN orders
        ON orders.order_id = order_items.order_id
    WHERE orders.status = 'Completed'
    GROUP BY MONTH(orders.order_date2), YEAR(orders.order_date2)
)

SELECT
    sales_year,
    sales_month,
    total_revenue,
    LAG(total_revenue) OVER (ORDER BY sales_month) AS prev_mth_rev,
    ROUND(
        (total_revenue - LAG(total_revenue) OVER (ORDER BY sales_month))
        / NULLIF(LAG(total_revenue) OVER (ORDER BY sales_month), 0) * 100,
        2
        ) AS revenue_growth_pct
FROM monthly_revenue
ORDER BY sales_month;

--top 10 products by total revenue.
--Products with multiple SKUs are aggregated by name for clarity.
SELECT 
    TOP 10 p.product_name, 
    ROUND(SUM(oi.revenue),0) AS total_revenue
FROM products p
INNER JOIN order_items oi
    ON p.product_id = oi.product_id
INNER JOIN orders o
    ON oi.order_id = o.order_id
WHERE o.status = 'completed'
GROUP BY p.product_name
ORDER BY total_revenue DESC;

--Find revenue by category.
SELECT 
    p.category, 
    ROUND(SUM(oi.revenue),0) AS  total_revenue
FROM products p
INNER JOIN order_items oi
    ON p.product_id = oi.product_id
INNER JOIN orders o
    ON oi.order_id = o.order_id
WHERE o.status = 'completed'
GROUP BY p.category
ORDER BY total_revenue DESC;

--Average Order Value (AOV).
SELECT 
    ROUND(SUM(revenue)/COUNT(DISTINCT oi.order_id),0) AS aov
FROM order_items oi
INNER JOIN orders o
ON oi.order_id = o.order_id
WHERE o.status = 'completed';

--total orders and revenue by city.
SELECT 
    c.city, 
    COUNT(DISTINCT o.order_id) AS total_order, 
    ROUND(SUM(oi.revenue),0) AS total_revenue
FROM customers c
INNER JOIN orders o
    ON c.customer_id = o.customer_id
INNER JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.status ='completed'
GROUP BY city
ORDER BY total_order, total_revenue;

--Rank customers by total spending
WITH customer_spending AS (
    SELECT 
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name,
    SUM(oi.revenue) AS total_spending
FROM customers c
INNER JOIN orders o
    ON c.customer_id = o.customer_id
INNER JOIN order_items oi
    ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.first_name, c.last_name)

SELECT 
    customer_id,
    full_name,
    total_spending,
    RANK() OVER(ORDER BY total_spending DESC) AS spending_rank
FROM customer_spending;


--Profitability Analysis
--total profit for each product.
SELECT 
    p.product_name,
    SUM((p.selling_price - p.cost_price) * oi.quantity) AS total_profit
FROM products p
INNER JOIN order_items oi
    ON p.product_id = oi.product_id
GROUP BY p.product_id, p.product_name
ORDER BY total_profit DESC;

--top 5 most profitable products.
WITH profitability AS (
SELECT 
    p.product_id, 
    p.product_name,
   SUM((p.selling_price - p.cost_price) * oi.quantity) AS total_profit
FROM products p
INNER JOIN order_items oi
    ON p.product_id = oi.product_id
GROUP BY p.product_id, p.product_name
)

SELECT 
    TOP 5 product_name,
    total_profit
FROM profitability
ORDER BY total_profit DESC;


--profit margin percentage by category.
WITH kpi AS(
    SELECT p.category,
        SUM((p.selling_price - p.cost_price) * oi.quantity) AS total_profit,
        SUM(oi.revenue) AS total_revenue
    FROM products p
    INNER JOIN order_items oi
        ON p.product_id = oi.product_id
    GROUP BY p.category
)

SELECT category, ROUND((total_profit/total_revenue) * 100, 2) AS profit_margin_pct 
FROM kpi 
ORDER BY profit_margin_pct DESC;

--products generating high revenue but low profit margin.
WITH product_margins AS(
    SELECT 
        p.product_name,
        SUM((p.selling_price - p.cost_price) * oi.quantity) AS total_profit,
        SUM(oi.revenue) AS total_revenue,
        ROUND( SUM((p.selling_price - p.cost_price) * oi.quantity)/ SUM(oi.revenue) * 100, 2) AS profit_margin_pct
    FROM products p
    INNER JOIN order_items oi
        ON p.product_id = oi.product_id
    GROUP BY p.product_name
),

quartiles AS(
    SELECT DISTINCT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY profit_margin_pct) OVER() AS p25,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY profit_margin_pct) OVER() AS median,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY profit_margin_pct) OVER() AS p75
    FROM product_margins
)

SELECT pm.product_name, pm.total_revenue, pm.profit_margin_pct,
    CASE 
    WHEN pm.profit_margin_pct < p25                 THEN 'low margin'
    WHEN pm.profit_margin_pct BETWEEN p25 AND p75   THEN 'medium margin'
    ELSE 'high margin'
    END AS margin_classification
FROM product_margins pm
CROSS JOIN quartiles q
ORDER BY pm.total_revenue DESC;

--total profit lost from returned orders.
SELECT
    SUM((p.selling_price - p.cost_price) * oi.quantity) AS lost_profit
FROM products p
INNER JOIN order_items oi
    ON p.product_id = oi.product_id
INNER JOIN orders o
    ON oi.order_id = o.order_id
WHERE o.status = 'returned';


--total profit lost from returned orders by category.
SELECT
    p.category,
    SUM((p.selling_price - p.cost_price) * oi.quantity) AS lost_profit
FROM products p
INNER JOIN order_items oi
    ON p.product_id = oi.product_id
INNER JOIN orders o
    ON oi.order_id = o.order_id
WHERE o.status = 'returned'
GROUP BY p.category
ORDER BY lost_profit DESC;

--Inventory Analysis

--products below reorder level.
SELECT
    product_id,
    stock_quantity,
    reorder_level
FROM inventory
WHERE stock_quantity < reorder_level;

--days since last restock.
SELECT
    product_id,
    last_restock_date2,
    DATEDIFF(DAY, last_restock_date2, GETDATE()) AS days_since_restock
FROM inventory

--slow-moving products; Products with high stock but low sales volume.
--High ratio → slow moving inventory.
SELECT
    TOP 10 p.product_name,
    i.stock_quantity stock, 
    SUM(oi.quantity) AS quanity_sold, 
    ROUND(i.stock_quantity * 1.0 / NULLIF(SUM(oi.quantity),0),2) AS ratio
FROM inventory i
INNER JOIN order_items oi
    ON i.product_id = oi.product_id
INNER JOIN products p
    ON i.product_id = p.product_id
GROUP BY p.product_name, i.stock_quantity
ORDER BY ratio DESC;

----inventory turnover ratio per product.
SELECT
    i.product_id,
    i.stock_quantity,
    SUM(oi.quantity) AS total_sold,
    SUM(i.stock_quantity) * 1.0 / NULLIF(i.stock_quantity,0) AS turnover_ratio
FROM inventory i
INNER JOIN order_items oi
    ON i.product_id = oi.product_id
GROUP BY i.product_id, i.stock_quantity
ORDER BY turnover_ratio DESC;

----products that frequently go out of stock
SELECT
    i.product_id,
    i.stock_quantity,
    SUM(oi.quantity) AS quanity_sold , 
    i.stock_quantity* 1.0 / NULLIF(SUM(oi.quantity),0) AS ratio
FROM inventory i
INNER JOIN order_items oi
    ON i.product_id = oi.product_id
WHERE i.stock_quantity = 0
GROUP BY i.product_id, i.stock_quantity
ORDER BY ratio ASC;


--products with highest return rate. (Returned orders ÷ total orders per product)
WITH r_orders AS(
    SELECT
        p.product_name,
        COUNT(DISTINCT o.order_id) AS returned_orders
    FROM products p
    INNER JOIN order_items oi
        ON p.product_id = oi.product_id
    INNER JOIN orders o
        ON oi.order_id = o.order_id
    WHERE o.status = 'returned'
    GROUP BY p.product_name),

t_orders AS(
    SELECT
        p.product_name,
        COUNT(o.order_id) AS total_orders
    FROM products p
    INNER JOIN order_items oi
        ON p.product_id = oi.product_id
    INNER JOIN orders o
        ON oi.order_id = o.order_id
    GROUP BY p.product_name)

SELECT
    r.product_name,
    CAST(r.returned_orders AS FLOAT) / t.total_orders AS return_rate
FROM r_orders r
INNER JOIN t_orders t
    ON r.product_name = t.product_name
ORDER BY return_rate DESC;

--customer segmentation
WITH c_details AS (
    SELECT 
        c.customer_id, 
        CONCAT(c.first_name, ' ', c.last_name) AS full_name, 
        SUM(oi.revenue) AS revenue
    FROM customers c
    INNER JOIN orders o
        ON c.customer_id = o.customer_id
    INNER JOIN order_items oi
        ON o.order_id = oi.order_id
    GROUP BY c.customer_id, c.first_name, c.last_name),

quartiles AS(
    SELECT DISTINCT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY revenue) OVER() AS p25,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY revenue) OVER() AS median,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY revenue) OVER() AS p75
    FROM c_details)

SELECT
    cd.customer_id, 
    cd.full_name, 
    cd.revenue,
    CASE
    WHEN cd.revenue < q.p25                     THEN 'low_value'
    WHEN cd.revenue BETWEEN q.p25 AND  q.p75    THEN 'medium_value'
    ELSE 'high_value'
    END AS segment
FROM c_details cd
CROSS JOIN quartiles q
ORDER BY cd.revenue DESC;


--KPI's
--succesful orders
SELECT
    ROUND(SUM(oi.revenue),0) AS total_revenue,
    ROUND(SUM((p.selling_price - p.cost_price) * oi.quantity),0) AS total_profit,
    COUNT(DISTINCT o.order_id) AS total_order, 
    ROUND(SUM(revenue)/COUNT(DISTINCT oi.order_id),0) AS aov
FROM customers c
INNER JOIN orders o
    ON c.customer_id = o.customer_id
INNER JOIN order_items oi
    ON o.order_id = oi.order_id
INNER JOIN products p
    ON oi.product_id = p.product_id
WHERE o.status = 'completed';

SELECT
    p.product_name,
    SUM(oi.revenue) AS total_revenue,
    SUM((p.selling_price - p.cost_price) * oi.quantity) AS total_profit,
    SUM((p.selling_price - p.cost_price) * oi.quantity) * 100.0 
        / SUM(oi.revenue) AS profit_margin
FROM products p
JOIN order_items oi
    ON p.product_id = oi.product_id
GROUP BY
    p.product_name;