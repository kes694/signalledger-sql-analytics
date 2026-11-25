# Business rules and data dictionary

## Contract SLA policy (fictional)

| Plan | Target availability | Base monthly fee |
|---|---:|---:|
| Standard | 99.00% | ₹1,800 |
| Business | 99.50% | ₹4,200 |
| Mission Critical | 99.90% | ₹8,500 |

Invoices include simulated recurring fee adjustments. The actual invoice fee is the credit base. All values in `*_paise` columns are integer paise (100 paise = ₹1); `target_bps` is availability × 100, e.g. 99.90% = 9,990 basis points. Severity 1 is highest priority.

1. Clip unplanned, service-impacting outages to each calendar month; merge overlapping and adjacent intervals before summing downtime. A zero-event site-month has zero downtime. Example: [00:00, 03:00), [00:00, 00:30), [02:00, 04:00) overlap; union is 240 minutes, not 330.
2. Availability = 100 × (month minutes − eligible downtime minutes) / month minutes.
3. SLA shortfall in basis points = target_bps − 10,000 × (month minutes − downtime) / month minutes. Compare exactly, without rounding availability first.
4. Credit is 0% when there is no shortfall; 5% when shortfall is greater than 0 and less than 50 bps; 10% from 50 to less than 150 bps; 20% at 150 bps or above. Multiply by invoice fee and round half-up to paise.
5. Actual settled credit is the sum of POSTED entries including negative reversals. PENDING entries are reported separately. Expected minus posted is the net discrepancy; report positive and negative sides separately.
6. Audit status: MATCHED (equal), UNENTITLED_CREDIT (expected zero, posted positive), MISSING_CREDIT (expected positive, posted zero), UNDERPAID (remaining posted below expected), OVERPAID (remaining posted above expected). Negative net posted totals, if present, fall into UNDERPAID.
7. Cause allocation: split at every unique eligible event boundary; each segment is assigned to the active incident with highest severity (lowest integer), then lowest incident ID. This produces exclusive minute totals; it is not causal inference.

## Columns

- `sites`: `site_id`, unique `site_name` (POP label), `region`, `site_type` (Metro/Edge/Enterprise).
- `plans`: `plan_id`, `plan_name`, `target_bps`, `monthly_fee_paise`.
- `contracts`: `contract_id`, fictional `account_name`, `site_id`, `plan_id`, customer `segment`.
- `months`: `month_start` inclusive, `next_month` exclusive, `month_minutes`.
- `incidents`: `incident_id`, `site_id`, `start_ts`, `end_ts`, `cause`, `severity`, `is_planned`, `service_impact`; flags are 0/1.
- `invoices`: `invoice_id`, `contract_id`, `month_start`, `fee_paise`; one per contract-month.
- `credits`: `credit_id`, `invoice_id`, signed `amount_paise`, `status` (POSTED/PENDING), `entry_type` (CREDIT/REVERSAL).

The generator deliberately includes partial, missing, pending, duplicate and reversed credits, unentitled credits, overlapping/nested outages, and month-boundary incidents. Random seed: 73129.
