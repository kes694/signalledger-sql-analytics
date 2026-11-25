-- Half-open intervals [start,end); clip eligible events to reporting months.
CREATE VIEW v_clipped AS
SELECT i.incident_id,i.site_id,m.month_start,i.cause,i.severity,
 max(unixepoch(i.start_ts),unixepoch(m.month_start)) AS start_s,
 min(unixepoch(i.end_ts),unixepoch(m.next_month)) AS end_s
FROM incidents i JOIN months m ON i.start_ts < m.next_month||' 00:00:00'
 AND i.end_ts > m.month_start||' 00:00:00'
WHERE i.is_planned=0 AND i.service_impact=1;

-- Gaps and islands: running MAX (not LAG) correctly handles nested outages.
CREATE VIEW v_outage_islands AS
WITH ordered AS (
 SELECT *,max(end_s) OVER(PARTITION BY site_id,month_start ORDER BY start_s,end_s,incident_id
 ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prior_max_end
 FROM v_clipped
), marked AS (
 SELECT *,CASE WHEN prior_max_end IS NULL OR start_s>prior_max_end THEN 1 ELSE 0 END AS new_island FROM ordered
), grouped AS (
 SELECT *,sum(new_island) OVER(PARTITION BY site_id,month_start ORDER BY start_s,end_s,incident_id ROWS UNBOUNDED PRECEDING) AS island_id FROM marked
)
SELECT site_id,month_start,island_id,min(start_s) AS start_s,max(end_s) AS end_s,
 (max(end_s)-min(start_s))/60 AS downtime_min
FROM grouped GROUP BY site_id,month_start,island_id;

CREATE VIEW v_site_month AS
WITH outages AS (
 SELECT site_id,month_start,sum(downtime_min) AS downtime_min,count(*) AS outage_blocks FROM v_outage_islands GROUP BY site_id,month_start
), raw AS (
 SELECT site_id,month_start,sum((end_s-start_s)/60) AS raw_min,count(*) AS incident_count FROM v_clipped GROUP BY site_id,month_start
)
SELECT s.site_id,s.region,m.month_start,m.month_minutes,coalesce(o.downtime_min,0) AS downtime_min,
 coalesce(o.outage_blocks,0) AS outage_blocks,coalesce(r.raw_min,0) AS raw_min,coalesce(r.incident_count,0) AS incident_count
FROM sites s CROSS JOIN months m LEFT JOIN outages o ON o.site_id=s.site_id AND o.month_start=m.month_start
LEFT JOIN raw r ON r.site_id=s.site_id AND r.month_start=m.month_start;

-- Assign each atomic segment to one cause by severity (1 highest), then incident ID.
-- This is deterministic operational allocation, not proof of causal responsibility.
CREATE VIEW v_cause_minutes AS
WITH boundaries AS (
 SELECT site_id,month_start,start_s AS boundary FROM v_clipped
 UNION SELECT site_id,month_start,end_s FROM v_clipped
), segments AS (
 SELECT *,lead(boundary) OVER(PARTITION BY site_id,month_start ORDER BY boundary) AS next_boundary FROM boundaries
), candidates AS (
 SELECT s.site_id,s.month_start,s.boundary,s.next_boundary,c.cause,
 row_number() OVER(PARTITION BY s.site_id,s.month_start,s.boundary ORDER BY c.severity,c.incident_id) AS priority
 FROM segments s JOIN v_clipped c ON c.site_id=s.site_id AND c.month_start=s.month_start
 AND c.start_s<=s.boundary AND c.end_s>=s.next_boundary WHERE s.next_boundary>s.boundary
)
SELECT site_id,month_start,cause,sum((next_boundary-boundary)/60) AS attributed_min
FROM candidates WHERE priority=1 GROUP BY site_id,month_start,cause;

-- Monetary calculations use integer paise. Targets and shortfalls use exact integer arithmetic.
-- SLA tiers: any shortfall <50 bps => 5%; 50 to <150 bps => 10%; >=150 bps => 20%.
CREATE VIEW v_entitlement AS
WITH base AS (
 SELECT i.invoice_id,i.contract_id,i.month_start,c.site_id,c.segment,p.plan_name,p.target_bps,i.fee_paise,
 s.region,s.downtime_min,s.month_minutes,
 s.downtime_min*10000-(10000-p.target_bps)*s.month_minutes AS shortfall_numerator
 FROM invoices i JOIN contracts c USING(contract_id) JOIN plans p USING(plan_id)
 JOIN v_site_month s ON s.site_id=c.site_id AND s.month_start=i.month_start
), tiers AS (
 SELECT *,CASE WHEN shortfall_numerator<=0 THEN 0 WHEN shortfall_numerator<50*month_minutes THEN 5
 WHEN shortfall_numerator<150*month_minutes THEN 10 ELSE 20 END AS credit_pct FROM base
)
SELECT *,round(100.0*(month_minutes-downtime_min)/month_minutes,4) AS availability_pct,
 (fee_paise*credit_pct+50)/100 AS expected_paise FROM tiers;

-- Aggregate ledger before joining to avoid invoice fanout. Pending entries do not settle liability.
CREATE VIEW v_reconciliation AS
WITH ledger AS (
 SELECT invoice_id,sum(CASE WHEN status='POSTED' THEN amount_paise ELSE 0 END) AS posted_paise,
 sum(CASE WHEN status='PENDING' THEN amount_paise ELSE 0 END) AS pending_paise,
 sum(CASE WHEN status='POSTED' THEN 1 ELSE 0 END) AS posted_entries
 FROM credits GROUP BY invoice_id
), joined AS (
 SELECT e.*,coalesce(l.posted_paise,0) AS posted_paise,coalesce(l.pending_paise,0) AS pending_paise,
 coalesce(l.posted_entries,0) AS posted_entries FROM v_entitlement e LEFT JOIN ledger l USING(invoice_id)
)
SELECT *,max(expected_paise-posted_paise,0) AS underpaid_paise,max(posted_paise-expected_paise,0) AS overpaid_paise,
 CASE WHEN expected_paise=posted_paise THEN 'MATCHED' WHEN expected_paise=0 AND posted_paise>0 THEN 'UNENTITLED_CREDIT'
 WHEN posted_paise=0 AND expected_paise>0 THEN 'MISSING_CREDIT' WHEN posted_paise<expected_paise THEN 'UNDERPAID'
 ELSE 'OVERPAID' END AS audit_status FROM joined;
