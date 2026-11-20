import numpy as np, pandas as pd
from datetime import timedelta
rng=np.random.default_rng(42)
# ---------- VENDORS ----------
n_v=120
cities=["Mumbai","Delhi","Bengaluru","Chennai","Pune","Hyderabad","Kolkata","Ahmedabad"]
cats=["IT Services","Office Supplies","Logistics","Consulting","Facilities","Raw Material","Marketing","Legal"]
v=pd.DataFrame({"vendor_id":[f"V{str(i).zfill(4)}" for i in range(1,n_v+1)],
 "vendor_name":[f"Vendor {i} Pvt Ltd" for i in range(1,n_v+1)],
 "category":rng.choice(cats,n_v),"city":rng.choice(cities,n_v),
 "payment_terms_days":rng.choice([15,30,45,60],n_v,p=[.1,.5,.25,.15]),
 "bank_account":[f"{rng.integers(10**11,10**12)}" for _ in range(n_v)],
 "onboarded_date":pd.to_datetime("2019-01-01")+pd.to_timedelta(rng.integers(0,1500,n_v),unit="D")})
# anomaly: 4 vendors share bank accounts (shell/ghost vendor risk)
for a,b in [(5,60),(18,77),(33,101),(40,41)]:
    v.loc[b,"bank_account"]=v.loc[a,"bank_account"]
# ---------- PURCHASE ORDERS ----------
n_po=3000
po=pd.DataFrame({"po_id":[f"PO{str(i).zfill(5)}" for i in range(1,n_po+1)],
 "vendor_id":rng.choice(v.vendor_id,n_po),
 "po_date":pd.to_datetime("2024-04-01")+pd.to_timedelta(rng.integers(0,540,n_po),unit="D"),
 "po_amount":np.round(rng.lognormal(10.8,1.0,n_po),2),
 "department":rng.choice(["Finance","IT","Operations","HR","Sales","Admin"],n_po),
 "approved_by":rng.choice(["Mgr_A","Mgr_B","Mgr_C","Dir_X","Dir_Y"],n_po)})
po["po_amount"]=po.po_amount.clip(5000,2500000)
# ---------- INVOICES ----------
inv=po.sample(2850,random_state=1).copy()
inv["invoice_id"]=[f"INV{str(i).zfill(6)}" for i in range(1,len(inv)+1)]
inv["invoice_number"]=[f"{vid}/{rng.integers(1000,99999)}" for vid in inv.vendor_id]
inv["invoice_date"]=inv.po_date+pd.to_timedelta(rng.integers(5,60,len(inv)),unit="D")
inv["invoice_amount"]=np.round(inv.po_amount*rng.choice([1,1,1,1,.98,1.02],len(inv)),2)
inv["gst_amount"]=np.round(inv.invoice_amount*.18,2)
inv["posted_by"]=rng.choice(["user_riya","user_amit","user_neha","user_karan","user_sana"],len(inv))
inv=inv[["invoice_id","invoice_number","po_id","vendor_id","invoice_date","invoice_amount","gst_amount","posted_by"]].reset_index(drop=True)
# anomaly 1: duplicate invoices (same vendor+number, new id, slightly later)
dups=inv.sample(60,random_state=2).copy()
dups["invoice_id"]=[f"INV{str(i).zfill(6)}" for i in range(900001,900061)]
dups["invoice_date"]=dups.invoice_date+pd.to_timedelta(rng.integers(1,10,60),unit="D")
# anomaly 2: invoices with no PO
nopo=inv.sample(45,random_state=3).copy()
nopo["invoice_id"]=[f"INV{str(i).zfill(6)}" for i in range(910001,910046)]
nopo["invoice_number"]=[f"{x}/NP{rng.integers(100,999)}" for x in nopo.vendor_id]
nopo["po_id"]=None
# anomaly 3: amounts just below 5,00,000 approval limit (split / threshold avoidance)
thr=inv.sample(40,random_state=4).copy()
thr["invoice_id"]=[f"INV{str(i).zfill(6)}" for i in range(920001,920041)]
thr["invoice_number"]=[f"{x}/T{rng.integers(100,999)}" for x in thr.vendor_id]
thr["invoice_amount"]=np.round(rng.uniform(480000,499900,40),2)
thr["gst_amount"]=np.round(thr.invoice_amount*.18,2)
thr["po_id"]=None
# anomaly 4: weekend / late-night style postings -> invoice_date on Sat/Sun
wk=inv.sample(35,random_state=5).copy()
wk["invoice_id"]=[f"INV{str(i).zfill(6)}" for i in range(930001,930036)]
wk["invoice_number"]=[f"{x}/W{rng.integers(100,999)}" for x in wk.vendor_id]
wk["invoice_date"]=wk.invoice_date.apply(lambda d:d+timedelta(days=(5-d.weekday())%7))
inv=pd.concat([inv,dups,nopo,thr,wk],ignore_index=True)
# anomaly 5: invoices dated before the vendor was onboarded (ghost vendor)
inv=inv.merge(v[["vendor_id","onboarded_date"]],on="vendor_id")
idx=inv.sample(20,random_state=6).index
inv.loc[idx,"invoice_date"]=inv.loc[idx,"onboarded_date"]-pd.to_timedelta(rng.integers(5,120,20),unit="D")
inv=inv.drop(columns="onboarded_date").sort_values("invoice_date").reset_index(drop=True)
# ---------- PAYMENTS ----------
terms=v.set_index("vendor_id").payment_terms_days
pay=inv.sample(frac=.88,random_state=7).copy()
pay["payment_id"]=[f"PAY{str(i).zfill(6)}" for i in range(1,len(pay)+1)]
pay["due_date"]=pay.invoice_date+pd.to_timedelta(pay.vendor_id.map(terms),unit="D")
pay["payment_date"]=pay.due_date+pd.to_timedelta(rng.choice([-5,0,0,3,7,15,30,50],len(pay),p=[.1,.3,.2,.15,.1,.08,.05,.02]),unit="D")
pay["payment_amount"]=pay.invoice_amount
pay["payment_mode"]=rng.choice(["NEFT","RTGS","Cheque","UPI"],len(pay),p=[.5,.3,.15,.05])
# anomaly 6: overpayments
op=pay.sample(30,random_state=8).index
pay.loc[op,"payment_amount"]=np.round(pay.loc[op,"invoice_amount"]*rng.uniform(1.05,1.5,30),2)
# anomaly 7: duplicate payments (same invoice paid twice)
dp=pay.sample(25,random_state=9).copy()
dp["payment_id"]=[f"PAY{str(i).zfill(6)}" for i in range(800001,800026)]
dp["payment_date"]=dp.payment_date+pd.to_timedelta(rng.integers(1,15,25),unit="D")
pay=pd.concat([pay,dp],ignore_index=True)
pay=pay[["payment_id","invoice_id","vendor_id","payment_date","payment_amount","payment_mode"]].sort_values("payment_date")
# dates -> str
for d,c in [(v,"onboarded_date"),(po,"po_date"),(inv,"invoice_date"),(pay,"payment_date")]: d[c]=pd.to_datetime(d[c]).dt.strftime("%Y-%m-%d")
v.to_csv("vendors.csv",index=False);po.to_csv("purchase_orders.csv",index=False)
inv.to_csv("invoices.csv",index=False);pay.to_csv("payments.csv",index=False)
print(len(v),len(po),len(inv),len(pay))
