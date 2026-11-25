# Portfolio walkthrough

## Publish on GitHub

1. Extract the ZIP. Open the SignalLedger folder in VS Code or a terminal and run the commands in README. Review the CSV output and understand the business rules.
2. Create a new public repository named `signalledger-sql-revenue-assurance` at https://github.com/new. Do not initialize it with a README if using the terminal instructions below.
3. From inside the extracted folder run:

```bash
git init
git add .
git commit -m "Build telecom SLA reconciliation and analytics pipeline"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/signalledger-sql-revenue-assurance.git
git push -u origin main
```

Replace `YOUR-USERNAME` with your GitHub username. GitHub may prompt for authentication. Alternatively, use Add file → Upload files on a new repository and upload the extracted source tree, not the ZIP. The CLI is better for retaining hidden CI and .gitignore files. Do not upload the regenerated database or Python cache directories. No actual account or repository was created by this project package.

4. Open the Actions tab and confirm the CI workflow passes. Pin the repo to your profile. Link the repository next to the resume project title.
5. Make it your own by completing one extension: implement a breach streak alert threshold, add a regional incident drill-down query, or port the SQL to PostgreSQL and validate results. Document the change and commit it. Do not fabricate development history, real-company data, or personal authorship; explain which work you personally performed and what you learned from the assisted starter project.

## Resume example (use after you can reproduce and explain the work)

**SignalLedger — Telecom Revenue Assurance Analytics | SQL, SQLite, Python | GitHub**
- Implemented an SLA and billing reconciliation pipeline across 10,800 simulated invoices and 72 network sites using CTEs, window functions and interval-merging logic.
- Identified 1,649 simulated credit discrepancies, including ₹6.48L outstanding and ₹1.98L excess credits; eliminated 12,387 minutes of duplicate outage counting.
- Developed 11 business analyses and validated financial and time-interval calculations with 6 automated tests.

Use only statements you can substantiate in an interview; these figures are outputs from the synthetic case study.

## Interview questions and answers

**Why use running MAX rather than LAG to merge outages?** A nested interval can have an earlier end than a previous enclosing interval. Running MAX preserves the furthest prior endpoint and correctly detects a new island only when the next start exceeds that endpoint.

**How do you prevent one-to-many join inflation?** Aggregate credits to invoice grain before joining entitlements. Enforce one invoice per contract-month and test invoice counts and uniqueness after the join.

**How are incidents spanning two months handled?** Join intervals to intersecting months, clip to the month bounds, then merge separately for each site-month. Half-open intervals avoid duplication at midnight.

**How do you calculate SLA availability?** Subtract deduplicated service-impact minutes from the actual calendar-month length and divide by month length. Exclude planned and non-impacting events by policy.

**Why integer paise and basis points?** Avoid binary floating-point errors when deciding eligibility and reconciling monetary values. Round only for display or at the final credit rounding boundary.

**How do you calculate P95 without a percentile built-in?** Rank downtime within each region, count rows, and select the observation at ceiling(0.95 × n). This is nearest-rank P95, not an interpolated percentile.

**What happens to credits awaiting approval?** Pending transactions are not settled liabilities. Show them separately and review them before triggering duplicate compensation.

**What did you test?** Compare SQL union and attribution against an independent Python minute-level oracle, check monetary results with Fraction arithmetic, test isolated overlapping/excluded events, check foreign keys and fanout, and verify a composite-index query plan.

**What would you improve in production?** Incremental ingestion, effective-dated contracts, multi-site routing and redundancy, late-event handling, idempotent ledger posting, access controls, and performance benchmarks in PostgreSQL or a warehouse. Validate with real contract rules before use.

**45-second explanation:** This is a synthetic telecom revenue assurance case study. It merges overlapping outages, calculates contract SLA credit entitlement, and compares that amount with posted billing credits. I can demonstrate how running window functions avoid double counting and how pre-aggregating ledger rows prevents fanout. The output identifies 1,649 exceptions in 10,800 invoices, then ranks sites and audit cases for review. The included tests check the calculations independently. The numbers are simulated, not real company financial results.
