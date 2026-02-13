CREATE TABLE online_retail (
    invoice_no      VARCHAR,
    stock_code      VARCHAR,
    description     TEXT,
    quantity        INT,
    invoice_date    TIMESTAMP,
    unit_price      NUMERIC(10, 2),
    customer_id     INT,
    country         VARCHAR
);

-- Checking columns
SELECT *
FROM online_retail
LIMIT (10);
--Analizar ventas, clientes y productos
--BASIC KPI'S
--REVENUE total
SELECT 
	SUM(unit_price * quantity) AS total_revenue
FROM online_retail
WHERE quantity > 0; --Excluimos devoluciones

--Number of Unique orders
SELECT 
	COUNT(DISTINCT invoice_no) AS total_orders
FROM online_retail;

--Number of Unique Customers

SELECT 
	COUNT(DISTINCT customer_id) AS total_customers
FROM online_retail
WHERE customer_id IS NOT NULL;


-- Temporal analysis
--REVENUE by MONTH
SELECT 
    EXTRACT(YEAR FROM invoice_date) AS year,
    EXTRACT(MONTH FROM invoice_date) AS month_num,
    TO_CHAR(invoice_date, 'FMMonth') AS month,
    SUM(unit_price * quantity) AS tot_revenue
FROM online_retail
WHERE quantity > 0
GROUP BY 
    EXTRACT(YEAR FROM invoice_date),
    EXTRACT(MONTH FROM invoice_date),
    TO_CHAR(invoice_date, 'FMMonth')
ORDER BY year, month_num;

-- MONTH BY MONTH GROWTH, % MoM. To compute month by month absolute growth. THe %MoM is also calculated.
WITH rev_month AS( 
	SELECT
		EXTRACT(YEAR FROM invoice_date) AS year,
    	EXTRACT(MONTH FROM invoice_date) AS month_num,
    	TO_CHAR(invoice_date, 'FMMonth') AS month,
    	SUM(unit_price * quantity) AS tot_revenue
FROM online_retail
WHERE quantity > 0
GROUP BY 
    EXTRACT(YEAR FROM invoice_date),
    EXTRACT(MONTH FROM invoice_date),
    TO_CHAR(invoice_date, 'FMMonth')
	),
month_growth AS(
	SELECT
		year,
		month_num,
		month,
		tot_revenue - LAG(tot_revenue) OVER (ORDER BY year, month_num) AS monthly_rev,
		ROUND((tot_revenue - LAG(tot_revenue) OVER (ORDER BY year, month_num))
            / LAG(tot_revenue) OVER (ORDER BY year, month_num) * 100, 2) AS perc_monthly_rev
	FROM rev_month		
	)
SELECT
	year,
    month,
    ROUND(monthly_rev, 2) AS monthly_growth,
    CONCAT(perc_monthly_rev, '%') AS perc_monthly_growth
FROM month_growth;

-- Top 10 products by revenue

SELECT
	stock_code,
	description,
	ROUND(SUM(unit_price * quantity), 2) AS revenue
FROM online_retail
WHERE quantity > 0
GROUP BY stock_code, description
ORDER BY revenue DESC
LIMIT(10);

--Top products by quantity

SELECT
	stock_code,
	description,
	SUM(quantity) AS tot_quant
FROM online_retail
WHERE quantity > 0
GROUP BY stock_code, description
ORDER BY tot_quant DESC
LIMIT(10);

--Top 10 customers by revenue
SELECT
	customer_id,
	country,
	ROUND(SUM(unit_price * quantity), 2) AS revenue
FROM online_retail
WHERE quantity >0
AND customer_id IS NOT NULL
GROUP BY customer_id, country
ORDER BY revenue DESC
LIMIT(10);

-- Customers Ranking by revenue
SELECT
	customer_id,
	ROUND(SUM(unit_price * quantity), 2) AS revenue,
	DENSE_RANK() OVER(ORDER BY SUM(unit_price * quantity) DESC) as ranking
FROM online_retail
WHERE quantity >0
AND customer_id IS NOT NULL
GROUP BY customer_id
ORDER BY revenue DESC
LIMIT(10);

-- ANALYSIS BY COUNTRY
SELECT
	country,
	SUM(quantity * unit_price) AS revenue
FROM online_retail
WHERE quantity >0
GROUP BY country
ORDER BY revenue DESC;

--cohort analysis. How many customers whose first bought was on 2010-12, buy on 2010-12, and so on.
--We group customers by their first purchase and analyze their behavior over time to measure retention and value.
WITH first_purchase AS (      --Identify first purchase (cohort)
    SELECT 
        customer_id,
        MIN(DATE_TRUNC('month', invoice_date)) AS cohort_month
    FROM online_retail
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id
),
orders AS (                   --Link every order to its cohort
    SELECT
        o.customer_id,
        DATE_TRUNC('month', o.invoice_date) AS order_month,
        f.cohort_month
    FROM online_retail AS o
    JOIN first_purchase AS f
        ON o.customer_id = f.customer_id
)
SELECT
    TO_CHAR(cohort_month, 'YYYY-MM') AS cohort,
    TO_CHAR(order_month, 'YYYY-MM') AS order_month,
    active_cust
FROM (                                  --Count active customers by cohort
    SELECT
        cohort_month,
        order_month,
        COUNT(DISTINCT customer_id) AS active_cust
    FROM orders
    GROUP BY cohort_month, order_month
) t
ORDER BY cohort_month, order_month;



-- Rolling 3-month average

WITH monthly_revenue AS (
    SELECT
		DATE_TRUNC('month', invoice_date) AS month,
		SUM(quantity* unit_price) as revn
	FROM online_retail
	WHERE quantity >0
	GROUP BY DATE_TRUNC('month', invoice_date))
SELECT 
	TO_CHAR(month, 'YYYY-MM'),
	revn,
	ROUND(AVG(revn) OVER (
	ORDER BY month
	ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS mov_avg
FROM monthly_revenue
ORDER BY month;

--How do customers behave over time based on the month of their first purchase?
--Cohorts were defined by the month of first purchase, then a monthly cohort index was calculated, 
--and retention was measured by comparing active customers against the initial size of each cohort

WITH first_purchase AS(					--defininig cohor, as first purchase
	SELECT
		customer_id,
		MIN(DATE_TRUNC('month', invoice_date)) AS cohort_month --first purchase
	FROM online_retail
	WHERE customer_id IS NOT NULL
	GROUP BY customer_id
),
orders AS(					--we link each purchase to its cohort
	SELECT
		o.customer_id,
        DATE_TRUNC('month', o.invoice_date) AS order_month,
        f.cohort_month
	FROM online_retail AS o
	JOIN first_purchase AS f
	ON o.customer_id = f.customer_id
),
cohort_index AS (		-- time since first purchase
    SELECT
        customer_id,
        cohort_month,
        order_month,
        (EXTRACT(YEAR FROM order_month) - EXTRACT(YEAR FROM cohort_month)
        ) * 12 + (EXTRACT(MONTH FROM order_month) - EXTRACT(MONTH FROM cohort_month)
        ) + 1 AS cohort_index	--number of months since first purchase
    FROM orders
),
cohort_counts AS (		--active customers through time
    SELECT
        cohort_month,
        cohort_index,
        COUNT(DISTINCT customer_id) AS active_customers
    FROM cohort_index
    GROUP BY cohort_month, cohort_index
),
cohort_size AS (		--initial cohort's size, to compute retention
    SELECT
        cohort_month,
        active_customers AS cohort_size
    FROM cohort_counts
    WHERE cohort_index = 1
)
SELECT
    TO_CHAR(c.cohort_month, 'YYYY-MM') AS cohort,
    c.cohort_index,
    c.active_customers,
    ROUND(
        100.0 * c.active_customers / s.cohort_size, --retention %
        2
    ) AS retention_percentage
FROM cohort_counts c
JOIN cohort_size s
    ON c.cohort_month = s.cohort_month
ORDER BY c.cohort_month, c.cohort_index;

 
   

--Calculé el revenue mensual y usé una ventana de 3 meses para crear una media móvil, lo que me permitió identificar la tendencia real eliminando la volatilidad mensual.
--rolling 3-month average	

WITH monthly_revenue AS (
    SELECT
		country,
		DATE_TRUNC('month', invoice_date) AS month,
		SUM(quantity * unit_price) AS rev
	FROM online_retail
	WHERE quantity >0
	GROUP BY DATE_TRUNC('month', invoice_date), country
)
SELECT
	country,
	TO_CHAR(month, 'YYYY-MM') AS month,
	rev,
	ROUND(AVG(rev) OVER (PARTITION BY country
					ORDER BY month
					ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS mov_avg
FROM monthly_revenue
ORDER BY country, month;


--I used multiple window functions: one with a moving frame for trend analysis and 
--another without a frame to calculate the historical average by country.
-- and deviation vs historic avg to analyse month performance

WITH monthly_revenue AS (
    SELECT
        country,
        DATE_TRUNC('month', invoice_date) AS month,
        SUM(quantity * unit_price) AS rev
    FROM online_retail
    WHERE quantity > 0
    GROUP BY country, DATE_TRUNC('month', invoice_date)
)
SELECT
    country,
    TO_CHAR(month, 'YYYY-MM') AS month,
    rev,
    -- Rolling 3-month average
    ROUND(AVG(rev) OVER (
            PARTITION BY country
            ORDER BY month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS mov_avg,
    -- Total average per country
    ROUND(AVG(rev) OVER (
            		PARTITION BY country), 2) AS total_avg_country,
	ROUND(rev - AVG(rev) OVER (PARTITION BY country), 2) AS diff_vs_avg
FROM monthly_revenue
ORDER BY country, month;

	

