[README.md](https://github.com/user-attachments/files/35456688/README.md)
# Procure-to-Pay (P2P) Audit Analytics | MySQL + Power BI

A risk-based audit analytics project that tests a procure-to-pay dataset for duplicate invoices, missing purchase orders, threshold avoidance, overpayments and high-risk vendors, then presents the findings in a 4-page Power BI dashboard.

> **Note on data:** The dataset is **synthetic**. I generated it with Python and deliberately planted audit red flags so the detection logic could be tested. Counts below reflect what my SQL tests flagged, not real company data.

## Business problem
Audit and risk teams review thousands of invoices and payments. Checking everything by hand is impossible, so analytics is used to flag the transactions most likely to be errors or fraud. This project builds that workflow end to end.

## Data
| Table | Rows | Purpose |
|---|---|---|
| vendors | 120 | Vendor master (category, payment terms, bank account, onboarding date) |
| purchase_orders | 3,000 | Approved purchase orders |
| invoices | 3,030 | Vendor invoices |
| payments | 2,691 | Payments made against invoices |

Data generator: `gen.py`. Amounts are in INR.

## Approach
1. **Validate the data:** row counts, key uniqueness, nulls, orphan records, data types. Anomalous records were preserved as findings, not cleaned away.
2. **Run audit tests in SQL** (`p2p_audit_queries.sql`), using CTEs, window functions and joins:
   - Duplicate invoices (`ROW_NUMBER()` over vendor and invoice number)
   - Invoices with no valid PO (`LEFT JOIN` to the PO master)
   - Threshold avoidance (invoices just under the Rs 5,00,000 approval limit)
   - Overpayments and duplicate payments
   - Invoices dated before vendor onboarding
   - Weekend invoices combined with other risk signals
   - Vendors sharing bank accounts
   - AP ageing buckets
3. **Combine tests into views:** `invoice_flags` (flags per invoice) and `vendor_risk` (weighted vendor risk score).
4. **Build the dashboard in Power BI** with DAX measures on top of the views.

## Vendor risk score
Duplicates x 3 + no-PO x 2 + threshold x 2 + pre-onboard x 3 + weekend x 1, plus 5 if the vendor shares a bank account with another vendor. Weights are judgement-based and can be tuned.

## Dashboard
| Page | What it shows |
|---|---|
| Executive Summary | Flagged %, flagged invoices, flagged value, exceptions by test, monthly invoice value |
| Exceptions | Flagged invoices with amounts, dates and flag counts |
| AP Ageing | Outstanding payables by age bucket, top 10 vendors by outstanding |
| Vendor Risk | Top risky vendors and full vendor ranking |

![Executive Summary](screenshots/01_executive_summary.png)
![Exceptions](screenshots/02_exceptions.png)
![AP Ageing](screenshots/03_ap_ageing.png)
![Vendor Risk](screenshots/04_vendor_risk.png)

## Key findings
- **232 invoices (7.66%)** carry at least one red flag, but they represent **Rs 59.1M of Rs 265.6M** total invoice value, about **22%**.
- Exceptions by test: weekend + risk signal (95), no PO (85), duplicate invoices (60), threshold avoidance (45), pre-onboarding (20).
- **55 payments** were flagged: overpayments and duplicate payments.
- **364 invoices worth Rs 33.5M** are unpaid, with about **Rs 29M older than 90 days**.
- Vendors that share bank accounts rank among the highest-risk suppliers.

## Limitations and next steps
- Synthetic data, so findings demonstrate the method rather than real-world rates.
- Risk weights are subjective; with real data they could be calibrated against confirmed issues.
- Next steps: approver-level analysis, Benford's law test on invoice amounts, and a Python/pandas version of the tests.

## Tools
MySQL 8, SQL (CTEs, window functions), Power BI, DAX, Python (data generation)

## Repository contents
- `data/`: vendors.csv, purchase_orders.csv, invoices.csv, payments.csv
- `p2p_audit_queries.sql`: schema and audit tests
- `gen.py`: synthetic data generator
- `P2P_Audit_Dashboard.pbix` and `P2P_Audit_Dashboard.pdf`
- `screenshots/`: dashboard page images
