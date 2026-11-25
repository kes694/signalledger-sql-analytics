"""Run from repository root: python -m unittest discover -s tests -v"""
import sqlite3, unittest
from collections import defaultdict
from datetime import datetime
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

class PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db=sqlite3.connect(ROOT/'signalledger.db')
        cls.db.row_factory=sqlite3.Row
    @classmethod
    def tearDownClass(cls): cls.db.close()
    def test_integrity(self):
        self.assertEqual(self.db.execute('PRAGMA integrity_check').fetchone()[0],'ok')
        self.assertEqual(self.db.execute('PRAGMA foreign_key_check').fetchall(),[])
    def test_no_invoice_fanout(self):
        n=self.db.execute('SELECT count(*),count(DISTINCT invoice_id) FROM v_reconciliation').fetchone()
        self.assertEqual(tuple(n),(10800,10800))
    def test_independent_minute_oracle_and_cause_allocation(self):
        events=defaultdict(list)
        for r in self.db.execute('SELECT * FROM incidents WHERE is_planned=0 AND service_impact=1'):
            events[r['site_id']].append((datetime.fromisoformat(r['start_ts']),datetime.fromisoformat(r['end_ts']),r['severity'],r['incident_id'],r['cause']))
        months={r['month_start']:datetime.fromisoformat(r['next_month']) for r in self.db.execute('SELECT * FROM months')}
        allocated={(r['site_id'],r['month_start'],r['cause']):r['attributed_min'] for r in self.db.execute('SELECT * FROM v_cause_minutes')}
        oracle={}
        for r in self.db.execute('SELECT * FROM v_site_month'):
            s=r['site_id']; m=r['month_start']; start=datetime.fromisoformat(m); end=months[m]; minute_owner={}
            for a,b,sev,i,cause in events[s]:
                a=max(a,start); b=min(b,end)
                if a>=b: continue
                for minute in range(int((a-start).total_seconds()/60),int((b-start).total_seconds()/60)):
                    key=(sev,i,cause)
                    if minute not in minute_owner or key<minute_owner[minute]: minute_owner[minute]=key
            self.assertEqual(r['downtime_min'],len(minute_owner),(s,m))
            for _,_,cause in minute_owner.values(): oracle[s,m,cause]=oracle.get((s,m,cause),0)+1
            self.assertLessEqual(r['downtime_min'],r['month_minutes'])
        self.assertEqual(allocated,oracle)
    def test_money_identity_and_entitlement(self):
        ledger=defaultdict(int)
        for r in self.db.execute("SELECT invoice_id,amount_paise FROM credits WHERE status='POSTED'"):
            ledger[r['invoice_id']]+=r['amount_paise']
        for r in self.db.execute('SELECT * FROM v_reconciliation'):
            # Independent Fraction arithmetic; no rounded percentage comparisons.
            from fractions import Fraction
            availability=Fraction(r['month_minutes']-r['downtime_min'],r['month_minutes'])*10000
            short=r['target_bps']-availability
            rate=0 if short<=0 else 5 if short<50 else 10 if short<150 else 20
            expected=(r['fee_paise']*rate+50)//100
            self.assertEqual(r['expected_paise'],expected)
            self.assertEqual(r['posted_paise'],ledger[r['invoice_id']])
            self.assertEqual(r['expected_paise']-r['posted_paise'],r['underpaid_paise']-r['overpaid_paise'])
    def test_isolated_overlap_and_boundary_case(self):
        db=sqlite3.connect(':memory:')
        db.executescript((ROOT/'sql/01_schema.sql').read_text())
        db.execute("INSERT INTO sites VALUES(1,'TEST','TEST','Edge')")
        db.executemany('INSERT INTO months VALUES(?,?,?)',[('2025-01-01','2025-02-01',44640),('2025-02-01','2025-03-01',40320)])
        rows=[(1,1,'2025-01-31 23:00:00','2025-02-01 03:00:00','A',2,0,1),(2,1,'2025-02-01 00:00:00','2025-02-01 00:30:00','B',1,0,1),(3,1,'2025-02-01 02:00:00','2025-02-01 04:00:00','C',2,0,1),(4,1,'2025-02-01 04:00:00','2025-02-01 04:30:00','D',3,0,1),(5,1,'2025-02-01 00:00:00','2025-02-01 10:00:00','E',1,1,1),(6,1,'2025-02-01 00:00:00','2025-02-01 15:00:00','F',1,0,0)]
        db.executemany('INSERT INTO incidents VALUES(?,?,?,?,?,?,?,?)',rows)
        db.executescript((ROOT/'sql/02_views.sql').read_text())
        self.assertEqual(db.execute('SELECT month_start,downtime_min,outage_blocks FROM v_site_month ORDER BY month_start').fetchall(),[('2025-01-01',60,1),('2025-02-01',270,1)])
        db.close()
    def test_index_used(self):
        plan=self.db.execute("EXPLAIN QUERY PLAN SELECT * FROM credits WHERE invoice_id=100 AND status='POSTED'").fetchall()
        self.assertTrue(any('idx_credit_invoice_status' in r[3] for r in plan))
if __name__=='__main__': unittest.main()
