-- name: monthly_executive
SELECT month_start,count(*) AS invoices,sum(credit_pct>0) AS breached_invoices,
 round(100.0*sum(credit_pct>0)/count(*),2) AS breach_pct,
 round(sum(fee_paise)/100.0,2) AS billed_inr,round(sum(expected_paise)/100.0,2) AS entitled_inr,
 round(sum(posted_paise)/100.0,2) AS posted_inr,round(sum(underpaid_paise)/100.0,2) AS underpaid_inr,
 round(sum(overpaid_paise)/100.0,2) AS overpaid_inr,sum(audit_status<>'MATCHED') AS exceptions
FROM v_reconciliation GROUP BY month_start ORDER BY month_start;

-- name: audit_queue
SELECT invoice_id,contract_id,month_start,site_id,region,plan_name,audit_status,posted_entries,
 round(expected_paise/100.0,2) AS expected_inr,round(posted_paise/100.0,2) AS posted_inr,
 round(pending_paise/100.0,2) AS pending_inr,round(underpaid_paise/100.0,2) AS underpaid_inr,
 round(overpaid_paise/100.0,2) AS overpaid_inr
FROM v_reconciliation WHERE audit_status<>'MATCHED'
ORDER BY max(underpaid_paise,overpaid_paise) DESC,invoice_id;

-- name: site_priority
WITH site_cost AS (
 SELECT site_id,region,sum(expected_paise) AS liability,sum(underpaid_paise) AS outstanding,
 sum(credit_pct>0) AS breaches FROM v_reconciliation GROUP BY site_id,region
), ranked AS (
 SELECT *,dense_rank() OVER(ORDER BY liability DESC) AS national_rank,
 row_number() OVER(PARTITION BY region ORDER BY liability DESC,site_id) AS region_rank,
 sum(liability) OVER(ORDER BY liability DESC,site_id ROWS UNBOUNDED PRECEDING) AS cumulative_liability,
 sum(liability) OVER() AS total_liability FROM site_cost
)
SELECT site_id,region,national_rank,region_rank,breaches,round(liability/100.0,2) AS entitled_inr,
 round(outstanding/100.0,2) AS underpaid_inr,round(100.0*cumulative_liability/nullif(total_liability,0),2) AS cumulative_pct
FROM ranked ORDER BY national_rank,site_id;

-- name: overlap_audit
SELECT site_id,region,month_start,incident_count,outage_blocks,raw_min,downtime_min,
 raw_min-downtime_min AS double_count_prevented_min
FROM v_site_month WHERE raw_min>downtime_min ORDER BY double_count_prevented_min DESC,site_id,month_start;

-- name: cause_pareto
WITH cause AS (SELECT cause,sum(attributed_min) AS minutes FROM v_cause_minutes GROUP BY cause)
SELECT cause,minutes,round(100.0*minutes/sum(minutes) OVER(),2) AS share_pct,
 round(100.0*sum(minutes) OVER(ORDER BY minutes DESC,cause ROWS UNBOUNDED PRECEDING)/sum(minutes) OVER(),2) AS cumulative_pct
FROM cause ORDER BY minutes DESC,cause;

-- name: recurring_breaches
-- Consecutive breached months per contract using a calendar month ordinal and row number.
WITH breached AS (
 SELECT contract_id,site_id,month_start,expected_paise,
 cast(strftime('%Y',month_start) AS INTEGER)*12+cast(strftime('%m',month_start) AS INTEGER)
 -row_number() OVER(PARTITION BY contract_id ORDER BY month_start) AS streak_key
 FROM v_entitlement WHERE credit_pct>0
), streaks AS (
 SELECT contract_id,site_id,min(month_start) AS start_month,max(month_start) AS end_month,
 count(*) AS consecutive_months,sum(expected_paise) AS entitled FROM breached GROUP BY contract_id,site_id,streak_key
)
SELECT contract_id,site_id,start_month,end_month,consecutive_months,round(entitled/100.0,2) AS entitled_inr
FROM streaks WHERE consecutive_months>=3 ORDER BY consecutive_months DESC,entitled DESC,contract_id,start_month;

-- name: region_rolling_trend
WITH monthly AS (
 SELECT region,month_start,sum(expected_paise) AS liability,sum(credit_pct>0) AS breached,count(*) AS invoices
 FROM v_reconciliation GROUP BY region,month_start
), trend AS (
 SELECT *,lag(liability) OVER(PARTITION BY region ORDER BY month_start) AS previous_liability,
 avg(liability) OVER(PARTITION BY region ORDER BY month_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_avg,
 count(*) OVER(PARTITION BY region ORDER BY month_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS window_months FROM monthly
)
SELECT region,month_start,round(100.0*breached/invoices,2) AS breach_pct,round(liability/100.0,2) AS entitled_inr,
 CASE WHEN window_months=3 THEN round(rolling_avg/100.0,2) END AS rolling_3m_inr,
 round(100.0*(liability-previous_liability)/nullif(previous_liability,0),2) AS mom_pct
FROM trend ORDER BY region,month_start;

-- name: plan_segment_matrix
SELECT plan_name,segment,count(*) AS invoices,sum(credit_pct>0) AS breached,
 round(100.0*sum(credit_pct>0)/count(*),2) AS breach_pct,
 round(sum(expected_paise)/100.0,2) AS entitled_inr,round(sum(underpaid_paise)/100.0,2) AS outstanding_inr
FROM v_reconciliation GROUP BY plan_name,segment ORDER BY outstanding_inr DESC;

-- name: audit_status_summary
SELECT audit_status,count(*) AS invoices,round(sum(underpaid_paise)/100.0,2) AS underpaid_inr,
 round(sum(overpaid_paise)/100.0,2) AS overpaid_inr,round(sum(pending_paise)/100.0,2) AS pending_inr
FROM v_reconciliation GROUP BY audit_status ORDER BY invoices DESC;

-- name: site_downtime_percentiles
-- Nearest-rank 95th percentile over monthly site downtime, calculated in SQL.
WITH ranked AS (
 SELECT region,site_id,month_start,downtime_min,
 row_number() OVER(PARTITION BY region ORDER BY downtime_min,site_id,month_start) AS rn,
 count(*) OVER(PARTITION BY region) AS n FROM v_site_month
)
SELECT region,count(*) AS site_months,round(avg(downtime_min),2) AS avg_min,
 max(CASE WHEN rn=(95*n+99)/100 THEN downtime_min END) AS p95_min,max(downtime_min) AS worst_min
FROM ranked GROUP BY region ORDER BY p95_min DESC,region;

-- name: portfolio_kpis
SELECT count(*) AS invoices,count(DISTINCT contract_id) AS contracts,count(DISTINCT site_id) AS sites,
 sum(credit_pct>0) AS breached_invoices,sum(audit_status<>'MATCHED') AS exceptions,
 round(sum(fee_paise)/100.0,2) AS billed_inr,round(sum(expected_paise)/100.0,2) AS expected_inr,
 round(sum(posted_paise)/100.0,2) AS posted_inr,round(sum(underpaid_paise)/100.0,2) AS underpaid_inr,
 round(sum(overpaid_paise)/100.0,2) AS overpaid_inr FROM v_reconciliation;
