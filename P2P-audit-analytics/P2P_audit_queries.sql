-- ============================================================
-- PROCURE-TO-PAY AUDIT ANALYTICS  |  MySQL 8 / PostgreSQL style
-- Tables: vendors, purchase_orders, invoices, payments
-- ============================================================

CREATE DATABASE P2p_audit_project;
USE P2p_audit_project;  

-- 0. SCHEMA (MySQL)
CREATE TABLE vendors (vendor_id VARCHAR(10) PRIMARY KEY, vendor_name VARCHAR(100), category VARCHAR(50),
  city VARCHAR(50), payment_terms_days INT, bank_account VARCHAR(20), onboarded_date DATE);
CREATE TABLE purchase_orders (po_id VARCHAR(10) PRIMARY KEY, vendor_id VARCHAR(10), po_date DATE,
  po_amount DECIMAL(14,2), department VARCHAR(30), approved_by VARCHAR(20));
CREATE TABLE invoices (invoice_id VARCHAR(12) PRIMARY KEY, invoice_number VARCHAR(30), po_id VARCHAR(10),
  vendor_id VARCHAR(10), invoice_date DATE, invoice_amount DECIMAL(14,2), gst_amount DECIMAL(14,2), posted_by VARCHAR(20));
CREATE TABLE payments (payment_id VARCHAR(12) PRIMARY KEY, invoice_id VARCHAR(12), vendor_id VARCHAR(10),
  payment_date DATE, payment_amount DECIMAL(14,2), payment_mode VARCHAR(10));
  
  -- 1. DATA QUALITY CHECKS
SELECT 'invoices' t, COUNT(*) FROM invoices UNION ALL SELECT 'payments', COUNT(*) FROM payments;
SELECT COUNT(*) AS invoices_without_po FROM invoices WHERE po_id IS NULL OR po_id = '';

-- 2. DUPLICATE INVOICES (same vendor + invoice number)
SELECT vendor_id, invoice_number, COUNT(*) AS cnt, SUM(invoice_amount) AS total_amt
FROM invoices GROUP BY vendor_id, invoice_number HAVING COUNT(*) > 1
ORDER BY total_amt DESC;

-- 2b. Duplicates via window function (keep first, flag the rest)
WITH ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY vendor_id, invoice_number ORDER BY invoice_date) rn
  FROM invoices)
SELECT * FROM ranked WHERE rn > 1;

-- 3. INVOICES WITHOUT PURCHASE ORDER (3-way match failure)
SELECT i.invoice_id, i.vendor_id, i.invoice_amount, i.invoice_date
FROM invoices i LEFT JOIN purchase_orders p ON i.po_id = p.po_id
WHERE p.po_id IS NULL ORDER BY i.invoice_amount DESC;

-- 4. THRESHOLD AVOIDANCE (just under Rs 5,00,000 approval limit)
SELECT invoice_id, vendor_id, invoice_amount, posted_by
FROM invoices WHERE invoice_amount BETWEEN 475000 AND 499999.99
ORDER BY invoice_amount DESC;

-- 5. OVERPAYMENTS & DUPLICATE PAYMENTS
SELECT i.invoice_id, i.invoice_amount, SUM(p.payment_amount) AS total_paid,
       SUM(p.payment_amount) - i.invoice_amount AS excess, COUNT(p.payment_id) AS pay_count
FROM invoices i JOIN payments p ON i.invoice_id = p.invoice_id
GROUP BY i.invoice_id, i.invoice_amount
HAVING SUM(p.payment_amount) > i.invoice_amount + 1
ORDER BY excess DESC;
-- 5b. SEPRATING DUPLICATE PAYMENTS & OVERPAYMENRTS 
SELECT
  CASE WHEN pay_count > 1 THEN 'Duplicate payment' ELSE 'Overpayment' END AS issue_type,
  COUNT(*) AS invoices,
  ROUND(SUM(excess), 0) AS excess_paid
FROM (
  SELECT i.invoice_id, i.invoice_amount,
         SUM(p.payment_amount) - i.invoice_amount AS excess,
         COUNT(p.payment_id) AS pay_count
  FROM invoices i JOIN payments p ON i.invoice_id = p.invoice_id
  GROUP BY i.invoice_id, i.invoice_amount
  HAVING SUM(p.payment_amount) > i.invoice_amount + 1
) x
GROUP BY issue_type;

-- 6. PAYMENTS AGAINST NON-EXISTENT / UNMATCHED INVOICES
SELECT p.* FROM payments p LEFT JOIN invoices i ON p.invoice_id = i.invoice_id WHERE i.invoice_id IS NULL;

-- 7. WEEKEND INVOICES (MySQL: DAYOFWEEK 1=Sun, 7=Sat; Postgres: EXTRACT(DOW ...) IN (0,6))
SELECT invoice_id, vendor_id, invoice_date, invoice_amount, po_id
FROM invoices
WHERE DAYOFWEEK(invoice_date) IN (1,7)
  AND (po_id IS NULL OR po_id = '' OR invoice_amount > 200000);

-- 8. SHARED BANK ACCOUNTS (ghost / related vendor risk)
SELECT bank_account, COUNT(*) AS vendors, GROUP_CONCAT(vendor_id) AS vendor_ids
FROM vendors GROUP BY bank_account HAVING COUNT(*) > 1;

-- 9. INVOICE DATED BEFORE VENDOR ONBOARDING
SELECT i.invoice_id, i.vendor_id, i.invoice_date, v.onboarded_date, i.invoice_amount
FROM invoices i JOIN vendors v ON i.vendor_id = v.vendor_id
WHERE i.invoice_date < v.onboarded_date;

-- 10. STATISTICAL OUTLIERS (z-score per vendor category)
WITH x AS (
  SELECT i.invoice_id, i.vendor_id, v.category, i.invoice_amount,
         AVG(i.invoice_amount) OVER (PARTITION BY v.category) mu,
         STDDEV(i.invoice_amount) OVER (PARTITION BY v.category) sd
  FROM invoices i JOIN vendors v ON i.vendor_id = v.vendor_id)
SELECT *, ROUND((invoice_amount - mu)/sd, 2) AS z_score FROM x
WHERE (invoice_amount - mu)/sd > 3 ORDER BY z_score DESC;

-- 11. LATE PAYMENTS vs PAYMENT TERMS
SELECT v.vendor_id, COUNT(*) AS payments,
       SUM(CASE WHEN DATEDIFF(p.payment_date, DATE_ADD(i.invoice_date, INTERVAL v.payment_terms_days DAY)) > 0 THEN 1 ELSE 0 END) AS late_cnt,
       ROUND(AVG(DATEDIFF(p.payment_date, i.invoice_date)),1) AS avg_days_to_pay
FROM payments p JOIN invoices i ON p.invoice_id = i.invoice_id JOIN vendors v ON i.vendor_id = v.vendor_id
GROUP BY v.vendor_id ORDER BY late_cnt DESC;

-- 12. AP AGEING AS OF A DATE (unpaid invoices)
WITH unpaid AS (
  SELECT i.invoice_id, i.vendor_id, i.invoice_amount, i.invoice_date,
         DATEDIFF('2026-01-31', i.invoice_date) AS age_days
  FROM invoices i LEFT JOIN payments p ON i.invoice_id = p.invoice_id
  WHERE p.invoice_id IS NULL)
SELECT CASE WHEN age_days<=30 THEN '0-30' WHEN age_days<=60 THEN '31-60'
            WHEN age_days<=90 THEN '61-90' ELSE '90+' END AS bucket,
       COUNT(*) AS invoices, ROUND(SUM(invoice_amount),0) AS outstanding
FROM unpaid GROUP BY bucket ORDER BY MIN(age_days);

-- 13. MoM SPEND TREND with LAG
WITH m AS (SELECT DATE_FORMAT(invoice_date,'%Y-%m') ym, SUM(invoice_amount) spend FROM invoices GROUP BY ym)
SELECT ym, spend, LAG(spend) OVER (ORDER BY ym) prev,
       ROUND((spend - LAG(spend) OVER (ORDER BY ym)) / LAG(spend) OVER (ORDER BY ym) * 100, 1) AS mom_pct
FROM m;

-- 14. VENDOR RISK SCORE (build as a VIEW, feed Power BI)
CREATE VIEW vendor_risk AS
SELECT v.vendor_id, v.category,
  (SELECT COUNT(*) FROM (SELECT 1 FROM invoices i WHERE i.vendor_id=v.vendor_id GROUP BY invoice_number HAVING COUNT(*)>1) d) * 3
 + (SELECT COUNT(*) FROM invoices i WHERE i.vendor_id=v.vendor_id AND (po_id IS NULL OR po_id='')) * 2
 + (SELECT COUNT(*) FROM invoices i WHERE i.vendor_id=v.vendor_id AND invoice_amount BETWEEN 475000 AND 499999.99) * 2
 + (SELECT COUNT(*) FROM vendors v2 WHERE v2.bank_account=v.bank_account AND v2.vendor_id<>v.vendor_id) * 5 AS risk_score
FROM vendors v;



