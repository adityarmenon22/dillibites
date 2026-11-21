-- =====================================================================
--  DilliBites : File 03 : QUERIES
--  Syllabus: joins (inner/outer/self), aggregation, subqueries (nested and
--            correlated), set operations, window functions, CTEs
-- =====================================================================
USE dillibites;

-- =====================================================================
-- A. JOINS
-- =====================================================================

-- Q1. INNER JOIN : live order tracking board (who ordered what, from where, who delivers)
SELECT o.order_id, u.full_name AS customer, r.name AS restaurant,
       o.status, o.total_amt, p.full_name AS delivery_partner
FROM orders o
JOIN customers c        ON c.customer_id = o.customer_id
JOIN users u            ON u.user_id     = c.customer_id
JOIN restaurants r      ON r.restaurant_id = o.restaurant_id
LEFT JOIN deliveries d  ON d.order_id    = o.order_id
LEFT JOIN users p       ON p.user_id     = d.partner_id
WHERE o.status IN ('PLACED','PREPARING','OUT_FOR_DELIVERY')
ORDER BY o.order_time;

-- Q2. LEFT OUTER JOIN : restaurants that have never received an order
SELECT r.restaurant_id, r.name, r.cuisine
FROM restaurants r
LEFT JOIN orders o ON o.restaurant_id = r.restaurant_id
WHERE o.order_id IS NULL;

-- Q3. LEFT OUTER JOIN + aggregate : every delivery partner, including idle ones
SELECT u.full_name AS partner, dp.is_available,
       COUNT(d.delivery_id) AS deliveries_done
FROM delivery_partners dp
JOIN users u ON u.user_id = dp.partner_id
LEFT JOIN deliveries d ON d.partner_id = dp.partner_id
GROUP BY dp.partner_id, u.full_name, dp.is_available
ORDER BY deliveries_done DESC;

-- Q4. SELF JOIN : "Order Twins" - different customers who ordered the same dish
SELECT DISTINCT u1.full_name AS customer_1, u2.full_name AS customer_2,
       mi.item_name, r.name AS restaurant
FROM orders o1
JOIN order_items i1 ON i1.order_id = o1.order_id
JOIN orders o2      ON o2.restaurant_id = o1.restaurant_id
                   AND o2.customer_id  > o1.customer_id
JOIN order_items i2 ON i2.order_id = o2.order_id AND i2.item_id = i1.item_id
JOIN menu_items mi  ON mi.item_id = i1.item_id
JOIN restaurants r  ON r.restaurant_id = o1.restaurant_id
JOIN users u1       ON u1.user_id = o1.customer_id
JOIN users u2       ON u2.user_id = o2.customer_id
ORDER BY restaurant, item_name
LIMIT 15;

-- Q5. Multi-table JOIN + GROUP BY + HAVING : revenue per restaurant (delivered orders only)
SELECT r.name, a.area_name, COUNT(o.order_id) AS orders,
       SUM(o.total_amt) AS revenue, ROUND(AVG(o.total_amt),2) AS avg_order_value
FROM restaurants r
JOIN areas a  ON a.area_id = r.area_id
JOIN orders o ON o.restaurant_id = r.restaurant_id
WHERE o.status = 'DELIVERED'
GROUP BY r.restaurant_id, r.name, a.area_name
HAVING COUNT(o.order_id) >= 3
ORDER BY revenue DESC;

-- =====================================================================
-- B. SUBQUERIES
-- =====================================================================

-- Q6. Non-correlated subquery (scalar) : customers who spend more than the average customer
SELECT u.full_name, t.total_spent
FROM (SELECT customer_id, SUM(total_amt) AS total_spent
      FROM orders WHERE status = 'DELIVERED' GROUP BY customer_id) t
JOIN users u ON u.user_id = t.customer_id
WHERE t.total_spent > (SELECT AVG(s) FROM
                         (SELECT SUM(total_amt) AS s FROM orders
                          WHERE status = 'DELIVERED' GROUP BY customer_id) x)
ORDER BY t.total_spent DESC;

-- Q7. CORRELATED subquery : coupon abuse - customers who used a coupon more times than allowed
SELECT DISTINCT u.full_name, cp.code, cp.max_uses_per_customer AS allowed,
       (SELECT COUNT(*) FROM orders o2
         WHERE o2.customer_id = o.customer_id AND o2.coupon_id = o.coupon_id) AS times_used
FROM orders o
JOIN coupons cp ON cp.coupon_id = o.coupon_id
JOIN users u    ON u.user_id = o.customer_id
WHERE (SELECT COUNT(*) FROM orders o2
        WHERE o2.customer_id = o.customer_id AND o2.coupon_id = o.coupon_id)
      > cp.max_uses_per_customer;

-- Q8. CORRELATED subquery : menu items priced above their own restaurant's average
SELECT r.name AS restaurant, m.item_name, m.price
FROM menu_items m
JOIN restaurants r ON r.restaurant_id = m.restaurant_id
WHERE m.price > (SELECT AVG(m2.price) FROM menu_items m2
                 WHERE m2.restaurant_id = m.restaurant_id)
ORDER BY r.name, m.price DESC;

-- Q9. NESTED subquery : the highest-grossing restaurant
SELECT name FROM restaurants
WHERE restaurant_id = (
    SELECT restaurant_id FROM orders WHERE status = 'DELIVERED'
    GROUP BY restaurant_id
    ORDER BY SUM(total_amt) DESC LIMIT 1);

-- Q10. EXISTS : customers who have never left a review
SELECT u.full_name
FROM customers c JOIN users u ON u.user_id = c.customer_id
WHERE NOT EXISTS (SELECT 1 FROM orders o JOIN reviews rv ON rv.order_id = o.order_id
                  WHERE o.customer_id = c.customer_id);

-- Q11. IN with subquery : orders containing at least one non-veg item
SELECT order_id, customer_id, total_amt FROM orders
WHERE order_id IN (SELECT oi.order_id FROM order_items oi
                   JOIN menu_items m ON m.item_id = oi.item_id WHERE m.is_veg = 0)
ORDER BY total_amt DESC LIMIT 10;

-- =====================================================================
-- C. SET OPERATIONS
-- =====================================================================

-- Q12. UNION : one contact directory for everyone who delivers or orders
SELECT full_name, 'Customer' AS role FROM users WHERE user_type = 'CUSTOMER'
UNION
SELECT full_name, 'Partner'  FROM users WHERE user_type = 'PARTNER'
ORDER BY role, full_name;

-- Q13. UNION vs UNION ALL : distinct city names
SELECT city FROM areas UNION SELECT city FROM areas;

-- Q14. INTERSECT : customers who ordered from BOTH Dilli Darbar and Biryani Blues
SELECT DISTINCT customer_id FROM orders
WHERE restaurant_id = 1
  AND customer_id IN (SELECT customer_id FROM orders WHERE restaurant_id = 7);

-- Q15. EXCEPT : customers who ordered in September but never in November (churn list)
SELECT DISTINCT customer_id FROM orders
WHERE MONTH(order_time) = 9
  AND customer_id NOT IN (SELECT customer_id FROM orders WHERE MONTH(order_time) = 11);

-- =====================================================================
-- D. WINDOW FUNCTIONS
-- =====================================================================

-- Q16. RANK / DENSE_RANK / ROW_NUMBER : restaurant leaderboard by revenue
SELECT r.name,
       SUM(o.total_amt) AS revenue,
       RANK()       OVER (ORDER BY SUM(o.total_amt) DESC) AS rnk,
       DENSE_RANK() OVER (ORDER BY SUM(o.total_amt) DESC) AS dense_rnk,
       ROW_NUMBER() OVER (ORDER BY SUM(o.total_amt) DESC) AS row_no
FROM restaurants r JOIN orders o ON o.restaurant_id = r.restaurant_id
WHERE o.status = 'DELIVERED'
GROUP BY r.restaurant_id, r.name;

-- Q17. PARTITION BY : top 2 best-selling dishes inside each restaurant
SELECT * FROM (
    SELECT r.name AS restaurant, m.item_name, SUM(oi.quantity) AS qty_sold,
           DENSE_RANK() OVER (PARTITION BY r.restaurant_id ORDER BY SUM(oi.quantity) DESC) AS rnk
    FROM order_items oi
    JOIN orders o      ON o.order_id = oi.order_id AND o.status <> 'CANCELLED'
    JOIN menu_items m  ON m.item_id = oi.item_id
    JOIN restaurants r ON r.restaurant_id = m.restaurant_id
    GROUP BY r.restaurant_id, r.name, m.item_id, m.item_name
) t WHERE rnk <= 2
ORDER BY restaurant, rnk;

-- Q18. Running total (SUM OVER) : daily revenue and cumulative revenue
SELECT DATE(order_time) AS day, SUM(total_amt) AS daily_revenue,
       SUM(SUM(total_amt)) OVER (ORDER BY DATE(order_time)) AS cumulative_revenue
FROM orders WHERE status = 'DELIVERED'
GROUP BY DATE(order_time)
ORDER BY day LIMIT 10;

-- Q19. LAG : days between consecutive orders of each customer
SELECT u.full_name, o.order_time,
       DATEDIFF(o.order_time, LAG(o.order_time) OVER (PARTITION BY o.customer_id ORDER BY o.order_time)) AS days_since_prev
FROM orders o JOIN users u ON u.user_id = o.customer_id
WHERE o.customer_id = 1
ORDER BY o.order_time;

-- Q20. Delivery partner leaderboard : average delivery minutes, ranked fastest first
SELECT u.full_name AS partner, COUNT(*) AS trips,
       ROUND(AVG(TIMESTAMPDIFF(MINUTE, d.picked_at, d.delivered_at)),1) AS avg_minutes,
       RANK() OVER (ORDER BY AVG(TIMESTAMPDIFF(MINUTE, d.picked_at, d.delivered_at))) AS speed_rank
FROM deliveries d JOIN users u ON u.user_id = d.partner_id
WHERE d.delivered_at IS NOT NULL
GROUP BY d.partner_id, u.full_name;

-- Q21. AVG OVER PARTITION : each review next to its restaurant's average rating
SELECT r.name, rv.order_id, rv.restaurant_rating,
       ROUND(AVG(rv.restaurant_rating) OVER (PARTITION BY r.restaurant_id),2) AS restaurant_avg
FROM reviews rv JOIN orders o ON o.order_id = rv.order_id
JOIN restaurants r ON r.restaurant_id = o.restaurant_id
ORDER BY r.name, rv.order_id LIMIT 12;

-- =====================================================================
-- E. COMMON TABLE EXPRESSIONS (CTE)
-- =====================================================================

-- Q22. CTE : Repeat-Craving Detector - same dish ordered 2+ times by the same customer
WITH craving AS (
    SELECT o.customer_id, oi.item_id, COUNT(*) AS times_ordered
    FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.status <> 'CANCELLED'
    GROUP BY o.customer_id, oi.item_id
    HAVING COUNT(*) >= 2
)
SELECT u.full_name, m.item_name, r.name AS restaurant, cr.times_ordered
FROM craving cr
JOIN users u       ON u.user_id = cr.customer_id
JOIN menu_items m  ON m.item_id = cr.item_id
JOIN restaurants r ON r.restaurant_id = m.restaurant_id
ORDER BY cr.times_ordered DESC, u.full_name;

-- Q23. Multiple CTEs + LAG : month-on-month revenue growth
WITH monthly AS (
    SELECT DATE_FORMAT(order_time,'%Y-%m') AS ym, SUM(total_amt) AS revenue
    FROM orders WHERE status = 'DELIVERED' GROUP BY ym
)
SELECT ym, revenue,
       LAG(revenue) OVER (ORDER BY ym) AS prev_month,
       ROUND((revenue - LAG(revenue) OVER (ORDER BY ym)) * 100 / LAG(revenue) OVER (ORDER BY ym),1) AS growth_pct
FROM monthly;

-- Q24. CTE customer segmentation : Gold / Silver / Bronze by lifetime spend
WITH spend AS (
    SELECT customer_id, COUNT(*) AS orders, SUM(total_amt) AS total_spent
    FROM orders WHERE status = 'DELIVERED' GROUP BY customer_id
)
SELECT u.full_name, s.orders, s.total_spent,
       CASE WHEN s.total_spent >= 6000 THEN 'Gold'
            WHEN s.total_spent >= 3000 THEN 'Silver'
            ELSE 'Bronze' END AS tier
FROM spend s JOIN users u ON u.user_id = s.customer_id
ORDER BY s.total_spent DESC;

-- Q25. RECURSIVE CTE : build a calendar of the last 7 days and show orders per day
WITH RECURSIVE cal AS (
    SELECT DATE('2026-11-12') AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM cal WHERE d < '2026-11-18'
)
SELECT cal.d AS day, COUNT(o.order_id) AS orders
FROM cal LEFT JOIN orders o ON DATE(o.order_time) = cal.d
GROUP BY cal.d ORDER BY cal.d;

-- Q26. Late-night insight : what do people order after 11 PM and before 4 AM?
SELECT m.item_name, SUM(oi.quantity) AS qty
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN menu_items m   ON m.item_id = oi.item_id
WHERE HOUR(o.order_time) >= 23 OR HOUR(o.order_time) < 4
GROUP BY m.item_id, m.item_name
ORDER BY qty DESC LIMIT 5;