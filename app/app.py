"""DilliBites : Food Delivery and Restaurant Analytics  (Flask front end for the DBMS project)

Every feature is a thin layer over the database objects from the SQL files:
  tables/constraints (01), sample data (02), the 26 queries (03), views + indexes (04),
  functions / triggers / procedures / roles (05), star-schema warehouse (06), scale test (07).
Business rules live IN the database (procedures + triggers); this app only calls them.
"""
import os
import re
from decimal import Decimal
from datetime import datetime, date, timedelta

import pymysql
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify

BASE = os.path.dirname(os.path.abspath(__file__))
SQL_DIR = os.path.join(os.path.dirname(BASE), "sql")

DB = dict(
    host=os.environ.get("DB_HOST", "127.0.0.1"),
    port=int(os.environ.get("DB_PORT", "3306")),
    user=os.environ.get("DB_USER", "root"),
    password=os.environ.get("DB_PASSWORD", "root"),
    charset="utf8mb4",
    autocommit=True,
    cursorclass=pymysql.cursors.DictCursor,
)

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "dillibites-dev-key")


# ----------------------------------------------------------------- helpers
def conn(db="dillibites"):
    return pymysql.connect(database=db, **DB)


def run(sql, args=None, db="dillibites", one=False):
    c = conn(db)
    try:
        with c.cursor() as cur:
            cur.execute(sql, args)
            rows = cur.fetchall()
            return (rows[0] if rows else None) if one else rows
    finally:
        c.close()


def db_error(e):
    """Pull the readable message out of a MySQL error (trigger SIGNAL text etc.)."""
    if isinstance(e, pymysql.MySQLError) and len(e.args) > 1:
        return str(e.args[1])
    return str(e)


def fmt(v):
    if isinstance(v, Decimal):
        return f"{v:,.2f}".rstrip("0").rstrip(".") if v % 1 else f"{int(v):,}"
    if isinstance(v, (datetime,)):
        return v.strftime("%d %b %Y, %H:%M")
    if isinstance(v, date):
        return v.strftime("%d %b %Y")
    if isinstance(v, timedelta):
        s = int(v.total_seconds())
        return f"{s // 3600:02d}:{(s % 3600) // 60:02d}"
    if v is None:
        return "-"
    return v


app.jinja_env.filters["fmt"] = fmt
app.jinja_env.filters["inr"] = lambda v: "Rs {:,.0f}".format(v or 0)


@app.errorhandler(pymysql.MySQLError)
def mysql_down(e):
    return render_template("error.html", msg=db_error(e)), 500


@app.context_processor
def inject():
    return {"nav": [
        ("dashboard", "Dashboard"), ("orders", "Orders"), ("new_order", "Place order"),
        ("restaurants", "Restaurants"), ("querylab", "Query lab"),
        ("warehouse", "Warehouse"), ("indexlab", "Index lab"), ("security", "Security"),
    ]}


# --------------------------------------------------------------- dashboard
@app.route("/")
def dashboard():
    kpi = run("""
        SELECT COUNT(*) total_orders,
               COALESCE(SUM(CASE WHEN status='DELIVERED' THEN total_amt END),0) revenue,
               SUM(status IN ('PLACED','PREPARING','OUT_FOR_DELIVERY')) active,
               SUM(status='CANCELLED') cancelled,
               ROUND(AVG(CASE WHEN status='DELIVERED' THEN total_amt END),0) aov
        FROM orders""", one=True)
    rating = run("SELECT ROUND(AVG(restaurant_rating),2) r, COUNT(*) n FROM reviews", one=True)
    customers = run("SELECT COUNT(*) n FROM customers", one=True)["n"]
    rest = run("SELECT name, cuisine, total_orders, revenue, avg_rating, cancelled_orders "
               "FROM v_restaurant_performance ORDER BY revenue DESC")
    monthly = run("""
        WITH monthly AS (SELECT DATE_FORMAT(order_time,'%Y-%m') ym, SUM(total_amt) revenue
                         FROM orders WHERE status='DELIVERED' GROUP BY ym)
        SELECT ym, revenue, ROUND((revenue-LAG(revenue) OVER (ORDER BY ym))*100/
               LAG(revenue) OVER (ORDER BY ym),1) growth_pct FROM monthly""")
    hours = run("SELECT HOUR(order_time) h, COUNT(*) n FROM orders GROUP BY h ORDER BY h")
    hv = run("SELECT full_name, orders, total_spent FROM v_high_value_customers ORDER BY total_spent DESC")
    late = run("SELECT name, cuisine, area_name, opens_at, closes_at FROM v_late_night_restaurants")
    partners = run("""
        SELECT u.full_name partner, COUNT(*) trips,
               ROUND(AVG(TIMESTAMPDIFF(MINUTE, d.picked_at, d.delivered_at)),1) avg_min,
               RANK() OVER (ORDER BY AVG(TIMESTAMPDIFF(MINUTE, d.picked_at, d.delivered_at))) speed_rank
        FROM deliveries d JOIN users u ON u.user_id=d.partner_id
        WHERE d.delivered_at IS NOT NULL GROUP BY d.partner_id, u.full_name""")
    rest_bars = [(r["name"], r["revenue"], "Rs {:,.0f}".format(r["revenue"])) for r in rest]
    monthly_rows = [(m["ym"], "Rs {:,.0f}".format(m["revenue"]),
                     "-" if m["growth_pct"] is None else f"{m['growth_pct']:+}%") for m in monthly]
    return render_template("dashboard.html", kpi=kpi, rating=rating, customers=customers, rest=rest,
                           rest_bars=rest_bars, monthly_rows=monthly_rows, hours=hours, hv=hv,
                           late=late, partners=partners)


# ------------------------------------------------------------------ orders
NEXT = {"PLACED": "PREPARING", "PREPARING": "OUT_FOR_DELIVERY", "OUT_FOR_DELIVERY": "DELIVERED"}


@app.route("/orders")
def orders():
    status = request.args.get("status", "")
    sql = "SELECT * FROM v_order_details"
    args = []
    if status:
        sql += " WHERE status=%s"
        args.append(status)
    sql += " ORDER BY order_time DESC LIMIT 100"
    rows = run(sql, args)
    log = run("""SELECT l.log_id, l.order_id, l.old_status, l.new_status, l.changed_at
                 FROM order_status_log l ORDER BY l.log_id DESC LIMIT 10""")
    return render_template("orders.html", rows=rows, status=status, log=log, NEXT=NEXT)


@app.route("/orders/<int:oid>")
def order_detail(oid):
    o = run("SELECT * FROM v_order_details WHERE order_id=%s", (oid,), one=True)
    if not o:
        flash("Order not found", "err")
        return redirect(url_for("orders"))
    items = run("""SELECT m.item_name, m.is_veg, oi.quantity, oi.unit_price, oi.quantity*oi.unit_price line
                   FROM order_items oi JOIN menu_items m ON m.item_id=oi.item_id WHERE oi.order_id=%s""", (oid,))
    d = run("SELECT d.*, u.full_name partner FROM deliveries d JOIN users u ON u.user_id=d.partner_id "
            "WHERE d.order_id=%s", (oid,), one=True)
    rv = run("SELECT * FROM reviews WHERE order_id=%s", (oid,), one=True)
    log = run("SELECT * FROM order_status_log WHERE order_id=%s ORDER BY log_id", (oid,))
    return render_template("order_detail.html", o=o, items=items, d=d, rv=rv, log=log, NEXT=NEXT)


@app.post("/orders/<int:oid>/advance")
def advance(oid):
    """Move an order forward. The AFTER UPDATE trigger (T2) writes the audit log row."""
    c = conn()
    try:
        with c.cursor() as cur:
            cur.execute("SELECT status FROM orders WHERE order_id=%s", (oid,))
            r = cur.fetchone()
            if not r or r["status"] not in NEXT:
                flash("This order cannot be advanced.", "err")
                return redirect(request.referrer or url_for("orders"))
            nxt = NEXT[r["status"]]
            if nxt == "OUT_FOR_DELIVERY":
                cur.execute("""SELECT dp.partner_id FROM delivery_partners dp
                               LEFT JOIN deliveries d ON d.partner_id=dp.partner_id AND d.delivered_at IS NULL
                               WHERE dp.is_available=1 GROUP BY dp.partner_id
                               ORDER BY COUNT(d.delivery_id), dp.partner_id LIMIT 1""")
                p = cur.fetchone()
                if not p:
                    flash("No delivery partner is available right now.", "err")
                    return redirect(request.referrer or url_for("orders"))
                cur.execute("""INSERT INTO deliveries (order_id, partner_id, picked_at, distance_km)
                               VALUES (%s,%s,NOW(), ROUND(1+RAND()*10,1))
                               ON DUPLICATE KEY UPDATE partner_id=VALUES(partner_id)""", (oid, p["partner_id"]))
            if nxt == "DELIVERED":
                cur.execute("UPDATE deliveries SET delivered_at=GREATEST(NOW(), picked_at + INTERVAL 1 SECOND) "
                            "WHERE order_id=%s", (oid,))
            cur.execute("UPDATE orders SET status=%s WHERE order_id=%s", (nxt, oid))
        flash(f"Order #{oid} is now {nxt.replace('_', ' ')}.", "ok")
    except pymysql.MySQLError as e:
        flash(db_error(e), "err")
    finally:
        c.close()
    return redirect(request.referrer or url_for("orders"))


@app.post("/orders/<int:oid>/cancel")
def cancel(oid):
    try:
        n = run("SELECT status FROM orders WHERE order_id=%s", (oid,), one=True)
        if n and n["status"] in ("PLACED", "PREPARING"):
            run("UPDATE orders SET status='CANCELLED' WHERE order_id=%s", (oid,))
            flash(f"Order #{oid} cancelled.", "ok")
        else:
            flash("Only PLACED or PREPARING orders can be cancelled.", "err")
    except pymysql.MySQLError as e:
        flash(db_error(e), "err")
    return redirect(url_for("order_detail", oid=oid))


@app.post("/orders/<int:oid>/review")
def review(oid):
    """Trigger T4 rejects reviews on orders that are not DELIVERED."""
    try:
        d = request.form.get("delivery_rating") or None
        run("INSERT INTO reviews (order_id, restaurant_rating, delivery_rating, comment, reviewed_at) "
            "VALUES (%s,%s,%s,%s,NOW())",
            (oid, int(request.form["restaurant_rating"]), d, request.form.get("comment", "")[:200]))
        flash("Thanks for the review!", "ok")
    except pymysql.MySQLError as e:
        flash("Database says: " + db_error(e), "err")
    return redirect(url_for("order_detail", oid=oid))


# --------------------------------------------------------------- new order
@app.route("/order/new", methods=["GET", "POST"])
def new_order():
    if request.method == "POST":
        f = request.form
        cust, rest, addr = int(f["customer"]), int(f["restaurant"]), int(f["address"])
        method, code = f["method"], (f.get("coupon") or None)
        lines = [(int(k[4:]), int(v)) for k, v in f.items() if k.startswith("qty_") and v.isdigit() and int(v) > 0]
        if not lines:
            flash("Add at least one dish to the cart.", "err")
            return redirect(url_for("new_order"))
        c = conn()
        oid = None
        try:
            with c.cursor() as cur:
                cur.execute("CALL sp_place_order(%s,%s,%s,%s,@oid)", (cust, rest, addr, code))   # step 1
                cur.execute("SELECT @oid AS oid")
                oid = cur.fetchone()["oid"]
                for item, qty in lines:
                    cur.execute("CALL sp_add_item(%s,%s,%s)", (oid, item, qty))              # step 2 (row locks)
                cur.execute("CALL sp_checkout(%s,%s)", (oid, method))                        # step 3 (ACID txn)
            flash(f"Order #{oid} placed and paid via {method}.", "ok")
            return redirect(url_for("order_detail", oid=oid))
        except pymysql.MySQLError as e:
            msg = "Could not place order: " + db_error(e)
            if oid:
                msg += f"  (order #{oid} was left in PLACED state; checkout rolled back)"
            flash(msg, "err")
            return redirect(url_for("order_detail", oid=oid) if oid else url_for("new_order"))
        finally:
            c.close()
    customers = run("SELECT c.customer_id, u.full_name, c.wallet_balance FROM customers c "
                    "JOIN users u ON u.user_id=c.customer_id ORDER BY u.full_name")
    rests = run("SELECT restaurant_id, name, cuisine FROM restaurants WHERE is_active=1 ORDER BY name")
    coupons = run("SELECT code, discount_pct, max_discount, min_order_value, max_uses_per_customer FROM coupons")
    return render_template("new_order.html", customers=customers, rests=rests, coupons=coupons)


@app.get("/api/menu/<int:rid>")
def api_menu(rid):
    rows = run("""SELECT m.item_id, m.item_name, m.description, m.price, m.is_veg, m.is_available, m.stock_qty,
                  c.category_name FROM menu_items m JOIN menu_categories c ON c.category_id=m.category_id
                  WHERE m.restaurant_id=%s ORDER BY c.category_id, m.item_name""", (rid,))
    return jsonify([{**r, "price": float(r["price"]), "is_veg": bool(r["is_veg"]),
                     "is_available": bool(r["is_available"])} for r in rows])


@app.get("/api/addresses/<int:cid>")
def api_addr(cid):
    return jsonify(run("SELECT a.address_id, a.label, a.address_line, ar.area_name FROM addresses a "
                       "JOIN areas ar ON ar.area_id=a.area_id WHERE a.customer_id=%s", (cid,)))


# ------------------------------------------------------------- restaurants
@app.route("/restaurants")
def restaurants():
    q = request.args.get("q", "").strip()
    rows = run("""SELECT r.restaurant_id, r.name, r.cuisine, a.area_name, a.city, r.opens_at, r.closes_at,
                  r.serves_after_midnight late, p.total_orders, p.revenue, p.avg_rating
                  FROM restaurants r JOIN areas a ON a.area_id=r.area_id
                  JOIN v_restaurant_performance p ON p.restaurant_id=r.restaurant_id ORDER BY r.name""")
    hits = []
    if q:   # uses the FULLTEXT index ft_item_search
        hits = run("""SELECT r.name restaurant, m.item_name, m.price, m.is_veg,
                      MATCH(m.item_name, m.description) AGAINST(%s IN NATURAL LANGUAGE MODE) score
                      FROM menu_items m JOIN restaurants r ON r.restaurant_id=m.restaurant_id
                      WHERE MATCH(m.item_name, m.description) AGAINST(%s IN NATURAL LANGUAGE MODE)
                      ORDER BY score DESC""", (q, q))
    return render_template("restaurants.html", rows=rows, q=q, hits=hits)


@app.route("/restaurants/<int:rid>")
def restaurant(rid):
    r = run("""SELECT r.*, a.area_name, a.city, p.total_orders, p.revenue, p.avg_rating
               FROM restaurants r JOIN areas a ON a.area_id=r.area_id
               JOIN v_restaurant_performance p ON p.restaurant_id=r.restaurant_id WHERE r.restaurant_id=%s""",
            (rid,), one=True)
    if not r:
        return redirect(url_for("restaurants"))
    menu = run("""SELECT m.item_name, m.description, m.price, m.is_veg, m.stock_qty, c.category_name
                  FROM menu_items m JOIN menu_categories c ON c.category_id=m.category_id
                  WHERE m.restaurant_id=%s ORDER BY c.category_id, m.item_name""", (rid,))
    top = run("""SELECT m.item_name, SUM(oi.quantity) qty FROM order_items oi
                 JOIN orders o ON o.order_id=oi.order_id AND o.status<>'CANCELLED'
                 JOIN menu_items m ON m.item_id=oi.item_id WHERE m.restaurant_id=%s
                 GROUP BY m.item_id, m.item_name ORDER BY qty DESC LIMIT 3""", (rid,))
    return render_template("restaurant.html", r=r, menu=menu, top=top)


# --------------------------------------------------------------- query lab
def load_queries():
    """Parse 03_queries.sql into runnable, read-only entries (id, title, notes, sql)."""
    text = open(os.path.join(SQL_DIR, "03_queries.sql"), encoding="utf-8").read()
    groups = [(1, 5, "Joins"), (6, 11, "Subqueries"), (12, 15, "Set operations"),
              (16, 21, "Window functions"), (22, 26, "CTEs")]
    parts = re.split(r"(?m)^-- (Q\d+)\. ", text)
    out = []
    for i in range(1, len(parts), 2):
        qid = int(parts[i][1:])
        chunk = parts[i + 1].split("\n-- ====")[0]
        lines = chunk.split("\n")
        title = lines[0].strip()
        notes, sql = [], []
        for ln in lines[1:]:
            if ln.startswith("--"):
                notes.append(ln.lstrip("- ").strip())
            else:
                sql.append(ln)
        body = "\n".join(sql).strip()
        grp = next(g for a, b, g in groups if a <= qid <= b)
        out.append(dict(id=qid, title=title, notes=" ".join(n for n in notes if n), sql=body, group=grp))
    return out


@app.route("/query-lab")
def querylab():
    return render_template("querylab.html", queries=load_queries())


@app.post("/api/query/<int:qid>")
def api_query(qid):
    q = next((x for x in load_queries() if x["id"] == qid), None)
    if not q:
        return jsonify(error="unknown query"), 404
    results = []
    try:
        for stmt in [s.strip() for s in q["sql"].split(";") if s.strip()]:
            if all(ln.strip().startswith("--") or not ln.strip() for ln in stmt.split("\n")):
                continue   # a fragment that is only a trailing comment
            rows = run(stmt)
            cols = list(rows[0].keys()) if rows else []
            results.append(dict(cols=cols, rows=[[str(fmt(r[c])) for c in cols] for r in rows]))
    except pymysql.MySQLError as e:
        return jsonify(error=db_error(e)), 200
    return jsonify(results=results)


# --------------------------------------------------------------- warehouse
DW_QUERIES = [
    ("Slice: revenue by cuisine",
     "SELECT r.cuisine, COUNT(*) AS orders, SUM(f.total_amt) AS revenue\n"
     "FROM fact_orders f JOIN dim_restaurant r ON r.restaurant_key = f.restaurant_key\n"
     "GROUP BY r.cuisine ORDER BY revenue DESC"),
    ("Dice: weekend vs weekday by payment method",
     "SELECT d.is_weekend, p.method, COUNT(*) AS orders, ROUND(AVG(f.total_amt),0) AS avg_order\n"
     "FROM fact_orders f JOIN dim_date d ON d.date_key = f.date_key\n"
     "JOIN dim_payment p ON p.payment_key = f.payment_key\n"
     "GROUP BY d.is_weekend, p.method ORDER BY d.is_weekend, orders DESC"),
    ("Roll-up: month > city > grand total",
     "SELECT d.month_name, r.city, SUM(f.total_amt) AS revenue\n"
     "FROM fact_orders f JOIN dim_date d ON d.date_key = f.date_key\n"
     "JOIN dim_restaurant r ON r.restaurant_key = f.restaurant_key\n"
     "GROUP BY d.month_name, r.city WITH ROLLUP"),
    ("Peak hours: when does Delhi order?",
     "SELECT hour_of_day, COUNT(*) AS orders FROM fact_orders\n"
     "GROUP BY hour_of_day ORDER BY orders DESC LIMIT 5"),
    ("Snowflake: same city revenue needs one extra join",
     "SELECT a.city, SUM(f.total_amt) AS revenue\n"
     "FROM fact_orders f JOIN dim_restaurant_sf r ON r.restaurant_key = f.restaurant_key\n"
     "JOIN dim_area a ON a.area_key = r.area_key GROUP BY a.city"),
]


@app.route("/warehouse")
def warehouse():
    out = []
    for title, sql in DW_QUERIES:
        rows = run(sql, db="dillibites_dw")
        cols = list(rows[0].keys()) if rows else []
        out.append(dict(title=title, sql=sql, cols=cols,
                        rows=[["TOTAL" if r[c] is None and c in ("month_name", "city") else fmt(r[c])
                               for c in cols] for r in rows]))
    counts = {t: run(f"SELECT COUNT(*) n FROM {t}", db="dillibites_dw", one=True)["n"]
              for t in ("fact_orders", "dim_date", "dim_customer", "dim_restaurant", "dim_partner",
                        "dim_payment", "dim_area")}
    return render_template("warehouse.html", out=out, counts=counts)


# --------------------------------------------------------------- index lab
@app.route("/index-lab")
def indexlab():
    idx = run("SHOW INDEX FROM orders")
    return render_template("indexlab.html", idx=idx, result=None)


@app.post("/index-lab/run")
def indexlab_run():
    """File 07 : build 200,000 rows, EXPLAIN ANALYZE before and after adding a B-tree index."""
    probe = ("SELECT order_id, total_amt FROM orders_big "
             "WHERE customer_id = 777 AND order_time >= '2026-06-01'")
    c = conn()
    res = {}
    try:
        with c.cursor() as cur:
            cur.execute("SET SESSION cte_max_recursion_depth = 300000")
            cur.execute("DROP TABLE IF EXISTS orders_big")
            cur.execute("""CREATE TABLE orders_big (order_id INT PRIMARY KEY, customer_id INT NOT NULL,
                           restaurant_id INT NOT NULL, order_time DATETIME NOT NULL,
                           total_amt DECIMAL(10,2) NOT NULL)""")
            cur.execute("""INSERT INTO orders_big
                WITH RECURSIVE n AS (SELECT 1 AS i UNION ALL SELECT i+1 FROM n WHERE i < 200000)
                SELECT i, 1+(i*7919)%20000, 1+(i*31)%10,
                       '2026-01-01' + INTERVAL ((i*104729)%31536000) SECOND, 50+(i*13)%1500 FROM n""")
            cur.execute("EXPLAIN ANALYZE " + probe)
            res["before"] = list(cur.fetchone().values())[0]
            cur.execute("CREATE INDEX idx_big_cust_time ON orders_big (customer_id, order_time)")
            cur.execute("EXPLAIN ANALYZE " + probe)
            res["after"] = list(cur.fetchone().values())[0]
            cur.execute("ANALYZE TABLE orders_big")
            cur.fetchall()
            cur.execute("""SELECT ROUND(data_length/1024/1024,1) data_mb, ROUND(index_length/1024/1024,1) index_mb
                           FROM information_schema.tables WHERE table_schema='dillibites' AND table_name='orders_big'""")
            res["size"] = cur.fetchone()
            cur.execute("DROP TABLE orders_big")
    finally:
        c.close()

    def ms(t):
        m = re.search(r"actual time=[\d.]+\.\.([\d.]+)", t)
        return float(m.group(1)) if m else None
    res["before_ms"], res["after_ms"] = ms(res["before"]), ms(res["after"])
    res["probe"] = probe
    return render_template("indexlab.html", idx=run("SHOW INDEX FROM orders"), result=res)


# ---------------------------------------------------------------- security
@app.route("/security", methods=["GET", "POST"])
def security():
    demo = None
    if request.method == "POST":
        email, pwd, mode = request.form["email"], request.form["pwd"], request.form["mode"]
        demo = dict(email=email, pwd=pwd, mode=mode, rows=[], error=None)
        try:
            if mode == "vulnerable":   # DELIBERATELY unsafe: input glued into SQL (classroom demo)
                sql = ("SELECT user_id, full_name, user_type FROM users WHERE email = '" + email +
                       "' AND password_hash = '" + pwd + "'")
                demo["sql"] = sql
                demo["rows"] = run(sql.replace("%", "%%"))
            else:                      # parameterised: input is data, never SQL
                demo["sql"] = ("SELECT user_id, full_name, user_type FROM users "
                               "WHERE email = ? AND password_hash = ?")
                demo["rows"] = run("SELECT user_id, full_name, user_type FROM users "
                                   "WHERE email = %s AND password_hash = %s", (email, pwd))
        except pymysql.MySQLError as e:
            demo["error"] = db_error(e)
    grants = {}
    for role in ("role_customer", "role_partner", "role_owner", "role_analyst", "role_admin"):
        try:
            grants[role] = [list(r.values())[0] for r in run(f"SHOW GRANTS FOR {role}")]
        except pymysql.MySQLError:
            grants[role] = ["(role not found, run setup)"]
    return render_template("security.html", demo=demo, grants=grants)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=int(os.environ.get("PORT", "5000")), debug=False, threaded=True)
