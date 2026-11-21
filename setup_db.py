"""Create (or reset) the DilliBites databases by running sql/setup_app.sql with the mysql client.

Usage:   python setup_db.py
Env:     DB_HOST (127.0.0.1)  DB_PORT (3306)  DB_USER (root)  DB_PASSWORD (root)

Needs the `mysql` command-line client on PATH (it understands the DELIMITER lines in the scripts).
WARNING: this DROPS and recreates the `dillibites` and `dillibites_dw` databases.
"""
import os
import shutil
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
sql = os.path.join(here, "sql", "setup_app.sql")

mysql = shutil.which("mysql")
if not mysql:
    sys.exit("The `mysql` client was not found on PATH. Install MySQL 8 (or add its bin folder to PATH), "
             "or run the SQL by hand: mysql -u root -p < sql/setup_app.sql")

env = dict(os.environ, MYSQL_PWD=os.environ.get("DB_PASSWORD", "root"))
cmd = [mysql, f"-h{os.environ.get('DB_HOST', '127.0.0.1')}", f"-P{os.environ.get('DB_PORT', '3306')}",
       f"-u{os.environ.get('DB_USER', 'root')}", "--default-character-set=utf8mb4"]
print("Building databases from", sql)
with open(sql, "rb") as f:
    r = subprocess.run(cmd, stdin=f, env=env, capture_output=True, text=True)
if r.returncode != 0:
    sys.exit("Setup failed:\n" + r.stderr)
print("Done. Databases `dillibites` and `dillibites_dw` are ready.\nNext: cd app && python app.py")
