PRAGMA foreign_keys = ON;
CREATE TABLE sites (
 site_id INTEGER PRIMARY KEY, site_name TEXT NOT NULL UNIQUE,
 region TEXT NOT NULL, site_type TEXT NOT NULL
);
CREATE TABLE plans (
 plan_id INTEGER PRIMARY KEY, plan_name TEXT NOT NULL UNIQUE,
 target_bps INTEGER NOT NULL CHECK(target_bps BETWEEN 0 AND 10000),
 monthly_fee_paise INTEGER NOT NULL CHECK(monthly_fee_paise > 0)
);
CREATE TABLE contracts (
 contract_id INTEGER PRIMARY KEY, account_name TEXT NOT NULL,
 site_id INTEGER NOT NULL REFERENCES sites, plan_id INTEGER NOT NULL REFERENCES plans,
 segment TEXT NOT NULL
);
CREATE TABLE months (
 month_start TEXT PRIMARY KEY, next_month TEXT NOT NULL,
 month_minutes INTEGER NOT NULL CHECK(month_minutes > 0)
);
CREATE TABLE incidents (
 incident_id INTEGER PRIMARY KEY, site_id INTEGER NOT NULL REFERENCES sites,
 start_ts TEXT NOT NULL, end_ts TEXT NOT NULL CHECK(end_ts > start_ts),
 cause TEXT NOT NULL, severity INTEGER NOT NULL CHECK(severity BETWEEN 1 AND 3),
 is_planned INTEGER NOT NULL CHECK(is_planned IN (0,1)),
 service_impact INTEGER NOT NULL CHECK(service_impact IN (0,1))
);
CREATE TABLE invoices (
 invoice_id INTEGER PRIMARY KEY, contract_id INTEGER NOT NULL REFERENCES contracts,
 month_start TEXT NOT NULL REFERENCES months, fee_paise INTEGER NOT NULL CHECK(fee_paise > 0),
 UNIQUE(contract_id, month_start)
);
CREATE TABLE credits (
 credit_id INTEGER PRIMARY KEY, invoice_id INTEGER NOT NULL REFERENCES invoices,
 amount_paise INTEGER NOT NULL CHECK(amount_paise <> 0),
 status TEXT NOT NULL CHECK(status IN ('POSTED','PENDING')),
 entry_type TEXT NOT NULL CHECK(entry_type IN ('CREDIT','REVERSAL')),
 CHECK((entry_type='CREDIT' AND amount_paise>0) OR (entry_type='REVERSAL' AND amount_paise<0))
);
CREATE INDEX idx_incident_site_time ON incidents(site_id,start_ts,end_ts) WHERE is_planned=0 AND service_impact=1;
CREATE INDEX idx_contract_site ON contracts(site_id);
CREATE INDEX idx_invoice_month ON invoices(month_start);
CREATE INDEX idx_credit_invoice_status ON credits(invoice_id,status);
