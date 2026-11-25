"""Generate fictional telecom operations data; no real customer information."""
import csv, random, calendar
from pathlib import Path
from datetime import datetime, timedelta
ROOT=Path(__file__).resolve().parents[1]
SEED=73129
MONTHS=[datetime(2025,m,1) for m in range(1,8)]
FMT='%Y-%m-%d %H:%M:%S'

def write(name,header,rows):
    with (ROOT/'data'/f'{name}.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.writer(f); w.writerow(header); w.writerows(rows)

def generate():
    r=random.Random(SEED); (ROOT/'data').mkdir(exist_ok=True)
    regions=['Delhi NCR','Mumbai','Bengaluru','Hyderabad','Pune','Chennai']
    sites=[(s,f'POP-{s:03}',regions[(s-1)%6],r.choice(['Metro','Edge','Enterprise'])) for s in range(1,73)]
    plans=[(1,'Standard',9900,180000),(2,'Business',9950,420000),(3,'Mission Critical',9990,850000)]
    contracts=[(c,f'Fictional Account {c:04}',r.randint(1,72),r.choices([1,2,3],[30,45,25])[0],r.choice(['SME','Enterprise','Public Sector'])) for c in range(1,1801)]
    months=[(a.date().isoformat(),b.date().isoformat(),int((b-a).total_seconds()/60)) for a,b in zip(MONTHS,MONTHS[1:])]
    incidents=[]; events={s:[] for s,*_ in sites}
    def add(s,a,b,cause,severity,planned=0,impact=1):
        incidents.append((len(incidents)+1,s,a.strftime(FMT),b.strftime(FMT),cause,severity,planned,impact))
        if not planned and impact: events[s].append((a,b))
    causes=['Power failure','Fiber cut','Router failure','Backhaul congestion','Cooling failure','Configuration error']
    for s,*_ in sites:
        # A small set of recurring problem sites creates a realistic concentration of downtime.
        for a,b in zip(MONTHS,MONTHS[1:]):
            for _ in range(r.randint(1,5)+(3 if s%9==0 else 0)):
                start=a+timedelta(minutes=r.randrange(int((b-a).total_seconds()/60)))
                duration=r.choices([r.randint(8,70),r.randint(75,240),r.randint(300,1100)], [65,25,10 if s%9 else 35])[0]
                planned=int(r.random()<.16); impact=int(r.random()>.10)
                add(s,start,start+timedelta(minutes=duration),r.choice(causes),r.randint(1,3),planned,impact)
                if duration>80 and r.random()<.24:
                    offset=r.randint(5,duration-1)
                    add(s,start+timedelta(minutes=offset),start+timedelta(minutes=offset+r.randint(15,duration)),r.choice(causes),r.randint(1,3),planned,impact)
    # Explicit edge cases: overlapping, nested, touching, cross-month, excluded.
    a=datetime(2025,2,1)
    for start,end,cause,sev,planned,impact in [(-60,180,'Fiber cut',2,0,1),(0,30,'Power failure',1,0,1),(120,240,'Router failure',2,0,1),(240,270,'Cooling failure',3,0,1),(0,600,'Configuration error',1,1,1),(0,900,'Backhaul congestion',1,0,0)]:
        add(1,a+timedelta(minutes=start),a+timedelta(minutes=end),cause,sev,planned,impact)
    # Independent minute-set oracle (SQL uses interval islands instead).
    downtime={}
    for s,intervals in events.items():
        for a,b in zip(MONTHS,MONTHS[1:]):
            covered=set()
            for x,y in intervals:
                lo=max(x,a); hi=min(y,b)
                if lo<hi: covered.update(range(int((lo-a).total_seconds()/60),int((hi-a).total_seconds()/60)))
            downtime[s,a.date().isoformat()]=len(covered)
    invoices=[]; credits=[]
    def entry(inv,amount,status='POSTED'):
        if amount: credits.append((len(credits)+1,inv,amount,status,'CREDIT' if amount>0 else 'REVERSAL'))
    for c,_,s,p,_ in contracts:
        _,_,target,base=plans[p-1]
        for m,_,minutes in months:
            inv=len(invoices)+1; fee=base+r.choice([0,0,0,25000,50000]); invoices.append((inv,c,m,fee))
            short=downtime[s,m]*10000-(10000-target)*minutes
            rate=0 if short<=0 else 5 if short<50*minutes else 10 if short<150*minutes else 20
            expected=(fee*rate+50)//100; roll=r.random()
            if expected:
                if roll<.70: entry(inv,expected)
                elif roll<.80: entry(inv,expected,'PENDING')
                elif roll<.86: pass
                elif roll<.92: entry(inv,expected//2)
                elif roll<.97: entry(inv,expected); entry(inv,expected)
                else: entry(inv,expected); entry(inv,expected//2); entry(inv,-(expected//2))
            elif roll<.018: entry(inv,fee//20)
    write('sites',['site_id','site_name','region','site_type'],sites)
    write('plans',['plan_id','plan_name','target_bps','monthly_fee_paise'],plans)
    write('contracts',['contract_id','account_name','site_id','plan_id','segment'],contracts)
    write('months',['month_start','next_month','month_minutes'],months)
    write('incidents',['incident_id','site_id','start_ts','end_ts','cause','severity','is_planned','service_impact'],incidents)
    write('invoices',['invoice_id','contract_id','month_start','fee_paise'],invoices)
    write('credits',['credit_id','invoice_id','amount_paise','status','entry_type'],credits)
if __name__=='__main__': generate()
