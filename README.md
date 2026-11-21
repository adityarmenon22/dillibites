# DilliBites: Food Delivery and Restaurant Analytics (DBMS project)

A Flask web app on top of a MySQL 8 database. All business rules (coupon limits, stock locking,
wallet payments, audit log, review rules) are enforced **inside the database** by the stored
procedures, triggers and constraints from your SQL files. The app only calls them.

## Run it

1. Install **MySQL 8.0.31+** (needed for INTERSECT/EXCEPT) and **Python 3.9+**.
2. Install the Python packages:
   ```
   pip install -r requirements.txt
   ```
3. Build the databases (drops and recreates `dillibites` and `dillibites_dw`):
   ```
   python setup_db.py
   ```
   Defaults to user `root`, password `root`, host `127.0.0.1`. Override with environment variables:
   `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`
   (Windows PowerShell: `$env:DB_PASSWORD="yourpassword"`; Mac/Linux: `export DB_PASSWORD=yourpassword`).
   The `mysql` command-line client must be on your PATH.
4. Start the app and open http://127.0.0.1:5000
   ```
   cd app
   python app.py
   ```

## Pages and the syllabus topic each one shows

| Page | What it does | Topic |
|---|---|---|
| Dashboard | KPIs, revenue, hourly demand, month-on-month growth, partner leaderboard | Views, window functions, CTEs |
| Orders / order detail | Move orders through PLACED > PREPARING > OUT FOR DELIVERY > DELIVERED, cancel, review. The audit log fills by itself | Triggers (T2, T4), constraints |
| Place order | Pick customer, restaurant, dishes, coupon, payment. Try Rohan + WELCOME50, Aarav + WALLET, or buying more Choco Lava Cake than the 20 in stock | Stored procedures, transactions (ACID), row locks, trigger T1/T3 |
| Restaurants | Browse, menus, full-text dish search | FULLTEXT index, generated column |
| Query lab | All 26 queries from `03_queries.sql`, read from the file, with a Run button | Joins, subqueries, set operations, window functions, CTEs |
| Warehouse | Star schema diagram and the slice / dice / roll-up / snowflake queries on `dillibites_dw` | Data warehouse, ETL, OLAP |
| Index lab | Builds 200,000 rows, times a query with and without a B-tree index (about 40 ms to under 1 ms) | Indexing, EXPLAIN ANALYZE |
| Security | SQL injection attack vs prepared statement, and the 5 roles with their grants | RBAC (DCL), SQL injection |

## Files

```
sql/dillibites_all.sql   all 7 scripts (01 to 07) joined in order. Run with: mysql -u root -p --force < dillibites_all.sql
                         (--force because part 5 section J raises 5 errors on purpose)
sql/setup_app.sql        clean version used by the app: schema, data, views, indexes, functions,
                         triggers, procedures, roles, warehouse. No demo rows added
sql/03_queries.sql       read by the Query lab page
setup_db.py              runs setup_app.sql
app/app.py               Flask routes (every SQL statement is in this one file)
app/templates, static    pages and styling
```

## Notes for the viva

- Scenario data is dated Sep to 18 Nov 2026, with three live orders on 18 Nov so the tracking board is not empty.
- The planted cases are still there: Rohan and Riya broke coupon limits (Q7), Sweet Tooth has no orders (Q2),
  Faiz Ahmed has no deliveries (Q3).
- A failed checkout (for example empty wallet) leaves the order in PLACED with no payment row. That is the
  Atomicity demo from section J2.
- The Security page's "vulnerable" mode is deliberately insecure for teaching. Do not copy that pattern.
- Passwords in the sample data are placeholder strings, not real hashes. In a real app, hash with bcrypt.
