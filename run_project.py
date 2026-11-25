"""Rebuild the SQLite database, run all analyses, and export results. Python 3.10+, SQLite 3.38+, stdlib only."""
import csv, re, sqlite3
from pathlib import Path
from src.generate_data import generate
ROOT=Path(__file__).resolve().parent

def build():
    db=sqlite3.connect(ROOT/'signalledger.db'); db.execute('PRAGMA foreign_keys=ON')
    db.executescript((ROOT/'sql/01_schema.sql').read_text())
    for table in ('sites','plans','contracts','months','incidents','invoices','credits'):
        with (ROOT/'data'/f'{table}.csv').open(newline='',encoding='utf-8') as f:
            reader=csv.reader(f); columns=next(reader)
            db.executemany(f"INSERT INTO {table} ({','.join(columns)}) VALUES ({','.join('?' for _ in columns)})",reader)
    db.commit(); db.executescript((ROOT/'sql/02_views.sql').read_text()); return db

def export(db):
    out=ROOT/'outputs'; out.mkdir(exist_ok=True)
    sql=(ROOT/'sql/03_analysis.sql').read_text()
    for name,query in re.findall(r'^-- name: (\w+)\n(.*?)(?=^-- name: |\Z)',sql,re.M|re.S):
        cur=db.execute(query.strip()); rows=cur.fetchall()
        with (out/f'{name}.csv').open('w',newline='',encoding='utf-8') as f:
            w=csv.writer(f); w.writerow([x[0] for x in cur.description]); w.writerows(rows)
        print(f'{name}: {len(rows)} rows')
    plan=db.execute("EXPLAIN QUERY PLAN SELECT * FROM credits WHERE invoice_id=100 AND status='POSTED'").fetchall()
    (out/'query_plan.txt').write_text('\n'.join(str(x) for x in plan)+'\n',encoding='utf-8')

if __name__=='__main__':
    generate(); (ROOT/'signalledger.db').unlink(missing_ok=True)
    with build() as db: export(db)
