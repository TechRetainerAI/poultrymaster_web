# Projects & Contracts — Step-by-Step Testing Guide

This guide tells you **exactly what to click and type**, one step at a time. You do not need to know how the system works inside. Follow the steps in order and compare what you see with the **✅ Check** lines.

---

## What you are testing

A business, for example a government supplier, can run many **contracts** at the same time. With **Projects & Contracts** switched on, one company can see, for each contract:
- how much it has earned and spent;
- how much profit it made;
- how much money came in and went out;
- what the customer still owes, and what is still owed to suppliers.

Everything is still recorded **once**, in the company's normal Sales, Purchases and Expenses. The project pages only *sort* those records by contract.

> **Use a test company.** You will be recording real sales and purchases.

---

## Contents

- [Part A — Get ready (once)](#part-a--get-ready-once)
- [Part B — Create the test company](#part-b--create-the-test-company)
- [Part C — Add the basics (product, customer, supplier, cash account)](#part-c--add-the-basics)
- [Part D — The main test: one contract, start to finish](#part-d--the-main-test-one-contract-start-to-finish)
- [Part E — Check the final numbers](#part-e--check-the-final-numbers)
- [Part F — Check nothing was counted twice](#part-f--check-nothing-was-counted-twice)
- [Part G — Sharing one bill between two contracts](#part-g--sharing-one-bill-between-two-contracts)
- [Part H — Keeping stock aside for a contract](#part-h--keeping-stock-aside-for-a-contract)
- [Part I — Budget and milestones](#part-i--budget-and-milestones)
- [Part J — Adding old transactions to a contract](#part-j--adding-old-transactions-to-a-contract)
- [Part K — Filters, archiving, switching off](#part-k--filters-archiving-switching-off)
- [Part L — If something goes wrong](#part-l--if-something-goes-wrong)

---

## Part A — Get ready (once)

Someone who runs the system on the computer does this part.

1. **Start the database changes.** Migrations 482 to 486 are already applied on dev. Nothing to do.
2. **Restart the back office server (Farm API).** Stop it if it is running, then start it again from the folder `poultrycore_Backend/PoultryFarmAPI` with:
   ```
   dotnet run
   ```
3. **Restart the website.** In the folder `poultrycore-main`, stop it, then run:
   ```
   npm run dev:reset
   ```
   If pages show "404" or you cannot log in, stop it and run `npm run dev:webpack` instead.
4. **Open the website** in Chrome at `http://localhost:3000` and press **Ctrl + Shift + R** once, to load the newest version.
5. **Log in** as the organisation owner/admin, the same login you normally use.

---

## Part B — Create the test company

### B1. Open the "Create new company" window

1. After logging in you are on **Business Office** (the page with your list of companies on the left).
2. Look for the **QUICK ACTIONS** box and click **+ Create**.
3. A window titled **Create new company** opens.

### B2. Fill in the window

1. Click the **Business type** box. A long list opens.
2. Scroll **down past "Restaurant"** and click **Wholesaler / distributor**.
3. Just **under** the Business type box, a grey sentence appears, and under it a box with a tick-box:
   **☐ Enable Projects & Contracts**
   → **Click the tick-box** so it shows ☑.
   > Don't see it? Check that Water/Poultry/Livestock/Hotel/Restaurant is **not** selected. If it still doesn't show, see [Part L](#part-l--if-something-goes-wrong).
4. In **Company name** type: `Contracts Test Co`
5. Leave Contact email and Phone empty (optional).
6. Click the black **Create** button.

### B3. ✅ Check

- The screen changes and you are now **inside** "Contracts Test Co". The company name shows at the top.
- At the top menu, click **Operations**. You should see a column called **Projects & Contracts** with 4 links:
  - Projects & Contracts
  - New project / contract
  - Compare projects
  - Link older transactions

> If you don't see the Operations menu at the top, open the menu on the left side of the screen instead. It has the same items.

---

## Part C — Add the basics

You need one product, one customer, one supplier and a cash account. Do these once.

### C1. Add the product "Computer"

1. Top menu **Operations** → click **Products**.
2. Click the **+ New item** button (top right).
3. A big window **New item** opens. Fill it in from top to bottom:

   **Section "What will this item be used for?"**
   - Make sure **☑ Sell to Customers** is ticked. Leave the other two unticked.

   **Section "Basic Details"**
   - **Item name**: `Computer`
   - Leave SKU, Barcode, Description, Category as they are.
   - **Base stock unit**: `pcs`

   **Section "Sale Settings"**
   - **Selling price**: `10000`
   - **Sales unit**: `pcs` (or leave empty)

   **Section "Cost & Inventory"** — important:
   - **Cost price**: `5000`

     > The system uses this cost price to work out the "cost of goods sold" when you sell. That is why it must be **5000** for the numbers in this guide to match.
   - **Opening stock**: `0` (leave it at 0; the computers will come in through a purchase)
   - **Low-stock alert at**: leave as it is.

   **Section "Status & Tracking"**
   - Make sure **☑ Track inventory** is ticked.
   - Make sure **☑ Active** is ticked.
4. Scroll to the bottom and click **Create item**.

✅ **Check:** "Computer" appears in the Products list with stock **0**.

### C2. Add the customer "Ministry of Education"

1. Top menu **Sales** → click **Customers**.
2. Click **+ New Customer** (top right).
3. The window has a few sections. Fill them in like this:

   **First section (name and contact)**
   - **Customer name**: `Ministry of Education`
   - **Type**: choose **Government**
   - **Phone**, **Email**, **Location**, **Address**: optional. Leave them empty or fill in anything.

   **Section "Credit & balance"**

   | Field | What it means | Type this for the test |
   |---|---|---|
   | **Credit limit** | The most this customer should owe you. The system does **not** stop a sale above it. It only marks the customer *over limit* on the balances screens. **0 = no limit.** | `0` |
   | **Payment terms (days)** | How many days the customer has to pay a credit sale. A sale becomes *overdue* on **Customer Balances** after this many days. A government contract often has 30 to 90 days. | `30` |
   | **Opening balance owed** | Money this customer **already** owed you before you started using the system. It goes straight onto their balance. | `0` ⚠️ |

   > ⚠️ **Keep Opening balance owed at 0 for this test.** If you put an amount here, the customer will owe more than the contract sale. In Step 6 the **Oldest first** button would then pay off that old amount first, and the contract numbers would not match this guide.

   **Section "Notes"** (if shown): optional.
4. Click **Create**.

✅ **Check:** "Ministry of Education" is in the customer list.

### C3. Add a supplier

1. Top menu **Setup** → under **Finance** click **Suppliers**.
2. Click **+ New supplier**.
3. Fill in:
   - **Supplier name**: `Computer Supplier`
   - **Type**: any (e.g. *Business*)
   - **Phone**, **Email**, **Location**, **Address**: optional.

   | Field | What it means | Type this for the test |
   |---|---|---|
   | **Payment terms (days)** | How many days you have to pay this supplier. | `30` |
   | **Opening balance (you owe)** | Money you **already** owed this supplier before you started using the system. | `0` ⚠️ |

   > ⚠️ **Keep Opening balance (you owe) at 0 for this test.** Otherwise, in Step 4, **Oldest first** would pay that old debt before the computer purchase, and *Owed to suppliers* on the contract would not drop to 120,000.

   - **Notes**: optional.
4. Click **Create**.

✅ **Check:** "Computer Supplier" is in the supplier list.

### C4. Make sure you have a cash account

1. Top menu **Money** → click **Cash & Accounts**.
2. If you see an account in the list (e.g. "Cash" or "Bank"), you are fine. Remember its name.
3. If the list is empty:
   - click **New account**;
   - **Name**: `Bank`; **Type**: *Bank*; **Opening balance**: `0`;
   - click **Save**.

### C5. Check there is an expense category

1. Top menu **Expenses** → click **Expenses** → click **New expense**.
2. Click the **Category** box. If you see categories (for example *Delivery & Distribution*), you are fine. Press **Cancel**.
3. If the list is empty, ask your admin to add a category called `Transport` (Setup → expense categories), then continue.

---

## Part D — The main test: one contract, start to finish

You will do **7 steps**. After each step, look at the project's **Overview** tab and compare the numbers with the ✅ Check box.

> **How to open the project's Overview at any time:** top menu **Operations** → **Projects & Contracts** → click the project in the list. The **Overview** tab is the first tab.

---

### Step 1 — Create the contract

1. Top menu **Operations** → **New project / contract**.
2. A form opens with **four boxes**. Only the name is required, but for this test fill in **everything** so you can see what each field does.

#### Box 1 — "Basic information"

| Field | What it means | Type / choose this |
|---|---|---|
| **Project / contract name** \* | A short name you will recognise in lists. | `Supply of Computers` |
| **Type** | *Contract* = work given to you under a signed contract (e.g. a government tender). *Project* = any other job you want to track separately. Both work the same way. | **Contract** |
| **Customer / client** | Who the work is for. | **Ministry of Education** |
| **Status** | Where the job is: Draft, Planned, Active, On hold, Completed, Cancelled. Only affects how it is listed; it does not block anything. | leave **Active** |
| **Project manager / responsible person** | The staff member in charge. The list comes from your Staff. | choose anyone, or leave **None** |
| **Start date** | When work started. | today's date |
| **Expected completion** | When the work should be finished. Must be after the start date. | a date 3 months from today |
| **Description** | A sentence about the job. | `Supply of 30 computers to schools` |

#### Box 2 — "Contract information"

| Field | What it means | Type this |
|---|---|---|
| **Government / client contract number** | The number written on the customer's contract. It is **separate** from the project number (PRJ-0001) the system gives automatically. Two projects cannot share the same contract number. | `GOV-2026-001` |
| **Contract reference** | Any other reference on the paperwork (tender number, LPO, file number). | `MOE/ICT/2026/14` |
| **Contracting organisation** | The office that awarded the contract. | `Ministry of Education` |
| **Award date** | The date you were given the contract. | today's date |
| **Contract award value** | The **total** amount the customer will pay you for the whole contract. It is **not** money earned yet: revenue only comes when you record sales. | `500000` |

#### Box 3 — "Financial planning"

These are **plans only**. Nothing here is recorded in your books; they are targets the project is measured against.

| Field | What it means | Type this |
|---|---|---|
| **Approved budget (costs)** | The most you plan to **spend** to deliver the contract. | `350000` |
| **Working capital needed to start** | Cash you expect to need up front before the customer starts paying (for buying goods, transport…). | `100000` |
| **Estimated direct cost** | What you expect the contract itself to cost: the goods you buy, delivery, labour. | `320000` |
| **Estimated overhead** | Your share of general company costs (office, admin) you expect to put against this contract. | `30000` |

Under these fields a grey line works it out for you:

✅ **Check:** it shows **Expected profit: 150,000 · expected margin 30.0%**
(500,000 award − 320,000 direct − 30,000 overhead = 150,000; 150,000 ÷ 500,000 = 30%).

> **Approved budget vs estimates:** the *approved budget* is the spending limit you will compare actual costs against (on the **Budget** tab you can break it into Materials, Labour, Transport…). The *estimates* are only used to show the expected profit.

#### Box 4 — "Organisation (optional)"

| Field | What it means | Type this |
|---|---|---|
| **Contract category** | Your own grouping, e.g. Supply, Construction, Service. Helps when searching. | `Supply` |
| **Location / site** | Where the work is done or delivered. | `Accra` |
| **Notes** | Anything else. | leave empty |

3. Click **Create** (bottom right).

✅ **Check** — you are now on the contract's own page:
- The title shows something like **PRJ-0001 — Supply of Computers**, with a green **Active** label.
- Under the title: *Contract · Ministry of Education · Contract GOV-2026-001 · Award 500,000 · Due (the expected completion date)*.
- A bar **"Work inside this project:"** with buttons: *Record purchase, Add expense, Record sale, Owner contribution, View inventory, View P&L, View cash flow, Add milestone*.
- On the **Overview** tab:

| Box | Line | Should show |
|---|---|---|
| Contract | Contract award value | **500,000** |
| Contract | Award not yet earned | **500,000** |
| Contract | Approved budget (costs) | **350,000** |
| Contract | Budget used (committed) | **0.0%** |
| Profit (recognised) | Revenue earned | **0** |
| Profit (recognised) | Net project profit | **0** |

> The award value and the budget are **not** money earned or spent. Revenue only appears when you record a sale, and costs only when you record purchases and expenses.

✅ **Check the register:** top menu **Operations → Projects & Contracts**.
- Your contract is in the list with its number, *GOV-2026-001* under it, the customer, **Active**, award **500,000**, budget **350,000** and the expected completion date.
- In the search box, type `GOV-2026` or `Ministry` or `Supply`. It is found each time.

> **Changing it later:** open the contract and click **Edit** (top right) to change any of these fields. The project number (PRJ-0001) never changes.

---

### Step 2 — The owner puts in 100,000 for this contract

1. On the contract's page, click **Owner contribution** (in the "Work inside this project" bar).
2. The **Owner money** page opens with a window already open for a **contribution**. Fill in:
   - **Amount**: `100000`
   - **Cash account**: choose your account (e.g. *Bank*)
   - **Date**: leave today
   - **Owner**: your name (optional)
   - **Project / contract**: it already shows **PRJ-0001 — Supply of Computers**. Leave it.
3. Click **Record Contribution**.
4. You are taken back to the contract page (on the cash tab). Click the **Overview** tab.

✅ **Check (Overview):**

| Box | Line | Should show |
|---|---|---|
| Funding & balances | Owner money put in | **100,000** |
| Profit (recognised) | Revenue earned | **0** |
| Profit (recognised) | Net project profit | **0** |

> Owner money is **funding**, not income. It does not change profit.

---

### Step 3 — Buy 40 computers on credit (200,000)

1. On the contract's page, click **Record purchase**.
2. The **Record Purchase** page opens. At the top:
   - **Purchase date**: leave today
   - **Supplier**: choose **Computer Supplier**
   - **Invoice number**: leave what is there
   - **Related project / contract**: already shows **PRJ-0001 — Supply of Computers**. Leave it.
3. In the **Items** box, first row:
   - **Product**: choose **Computer**
   - **Qty**: `40`
   - **Unit**: leave as it is
   - **Cost per unit**: `5000`
   - The **Line total** shows **200,000**.
   - Under the product you see a small grey link **Project: PRJ-0001 (as above)**. Leave it.
4. In the **Payment** box (right side), important:
   - **Amount paid now**: it fills in 200,000 by itself. **Change it to `0`**, because we are buying on credit.
   - Under the box it now says *Your own figure*.
5. In the **Totals** box, check **Balance owed to supplier** = **200,000**.
6. Click the green **Save & Approve** button.
7. You are taken back to the contract page, on the **Purchases & Inventory** tab.

✅ **Check (Overview tab):**

| Box | Line | Should show |
|---|---|---|
| Funding & balances | Purchases made (value) | **200,000** |
| Funding & balances | Owed to suppliers | **200,000** |
| Profit (recognised) | Cost of goods sold | **0** |
| Cash (actual money) | Paid for purchases | **0** |

> Buying stock is **not** a cost yet. It only becomes a cost when the computers are sold.

✅ **Check (Purchases & Inventory tab):** Computer — *Bought for project* **40**.

---

### Step 4 — Pay the supplier 80,000

1. Top menu **Expenses** → click **Supplier Payments**.
2. Click the orange **Record supplier payment** button.
3. A small window asks which supplier: choose **Computer Supplier** and click **Next**.
4. The payment window opens. Fill in:
   - **Payment amount**: `80000`
   - **Payment date**: leave today
   - **Payment method**: *Bank* (or Cash)
   - **Cash account**: your account
5. In the section **Apply to open purchases**, find the purchase of **200,000** and type `80000` in its box. Or click **Oldest first** and it fills in by itself.
6. Click the button **Record 80,000** (bottom right).

> You do **not** choose a project here. The system knows the payment is for the purchase, and the purchase belongs to the contract.

✅ **Check (contract → Overview):**

| Box | Line | Should show |
|---|---|---|
| Cash (actual money) | Paid for purchases | **80,000** |
| Funding & balances | Owed to suppliers | **120,000** |

---

### Step 5 — Sell 30 computers to the Ministry on credit (300,000)

1. Go back to the contract page and click **Record sale**.
2. The **New Sale** page opens. At the top:
   - **Sale date**: leave today
   - **Sales type**: choose **CreditSale**
   - **Customer (optional)**: choose **Ministry of Education**
   - **Related project / contract**: already shows **PRJ-0001**. Leave it.
3. In the **Items** box, first row:
   - **Type**: *Product*
   - **Product**: **Computer**
   - **Unit**: leave **pcs**
   - **Factor**: leave **1**. *Factor = how many stock units are in one sale unit. Stock goes down by Qty × Factor. A computer is kept and sold in pcs, so it is 1. If it showed something else, the stock and the cost of goods sold would be wrong.*
   - **Qty**: `30`
   - **Unit price**: shows **10000** by itself (from the product). If not, type `10000`.
   - **Line total**: **300,000**.
4. In the **Payment** box (right side):
   - **Amount paid**: it may fill in 300,000 by itself. **Change it to `0`** (credit sale).
5. Click **Create as Draft**.
6. The sale's own page opens with status **Draft**. Click the green **Approve** button (top right).
   > A sale only counts once it is **Approved**.
7. Scroll down on that sale page. In the **Project / Contract** box you see the line "Computer — PRJ-0001 — Supply of Computers".

✅ **Check (contract → Overview):**

| Box | Line | Should show |
|---|---|---|
| Profit (recognised) | Revenue earned | **300,000** |
| Profit (recognised) | Cost of goods sold | **150,000** (30 × 5,000) |
| Profit (recognised) | Gross profit | **150,000** |
| Funding & balances | Customer still owes | **300,000** |

---

### Step 6 — The Ministry pays 200,000

1. Top menu **Sales** → click **Customer Balances**.
2. Find **Ministry of Education** in the list and click **Receive payment** on that row.
3. The payment window opens. Fill in:
   - **Payment amount**: `200000`
   - **Payment method**: *Bank*
   - **Cash account**: your account
4. Under **Apply to open sales**, put `200000` on the sale of 300,000 (or click **Oldest first**).
5. Click **Receive 200,000**.

> Again you don't choose a project. The payment follows the sale.

✅ **Check (contract → Overview):**

| Box | Line | Should show |
|---|---|---|
| Cash (actual money) | Received from customers | **200,000** |
| Funding & balances | Customer still owes | **100,000** |
| Profit (recognised) | Revenue earned | **still 300,000** |

> The payment is **not** new income. The income was counted when the sale was approved.

---

### Step 7 — Pay 10,000 for transport

1. Go back to the contract page and click **Add expense**.
2. The **New expense** page opens. Fill in:
   - **Date**: leave today
   - **Category**: choose a transport-type category (e.g. *Delivery & Distribution*)
   - **Description**: `Transport of computers`
   - **Amount**: `10000`
   - **Paid to**: `Haulier`
   - **Payment method**: *Cash* or *Bank* (not *Credit*)
   - **Cash account**: your account
   - **Related project / contract**: already shows **PRJ-0001**. Leave it.
   - Under it, **Kind of cost**: leave **Direct project cost**.
3. Click **Create as Draft**. You are taken back to the contract page.
4. The expense must now be **approved**:
   - top menu **Expenses** → **Expenses**;
   - find *Transport of computers* (status **Draft**);
   - click the **✓** (Approve) icon on its row. It is approved straight away.

✅ **Check (contract → Overview):**

| Box | Line | Should show |
|---|---|---|
| Profit (recognised) | Operating expenses | **10,000** |
| Profit (recognised) | Net project profit | **140,000** |
| Cash (actual money) | Paid for expenses & wages | **10,000** |

---

## Part E — Check the final numbers

Open the contract → **Overview** tab. Tick each line:

| ☐ | Line | Should show |
|---|---|---|
| ☐ | Contract award value | 500,000 |
| ☐ | Award not yet earned | 200,000 |
| ☐ | Revenue earned | 300,000 |
| ☐ | Cost of goods sold | 150,000 |
| ☐ | Gross profit | 150,000 |
| ☐ | Operating expenses | 10,000 |
| ☐ | **Net project profit** | **140,000** |
| ☐ | Profit margin | 46.7% |
| ☐ | Received from customers | 200,000 |
| ☐ | Customer still owes | 100,000 |
| ☐ | Paid for purchases | 80,000 |
| ☐ | Owed to suppliers | 120,000 |
| ☐ | Paid for expenses & wages | 10,000 |
| ☐ | Owner money put in | 100,000 |
| ☐ | **Net attributable cash** | **210,000** |

> **Why is cash 210,000 but profit 140,000?** Cash counts money that actually moved: +100,000 owner, +200,000 customer, −80,000 supplier, −10,000 transport. Profit counts what was earned minus what it cost. They are different things, and the page shows both.

Now click through the other tabs:

| Tab | What to look for |
|---|---|
| **Transactions** | A list of everything: the sale, the cost of the computers sold, the transport, the owner money and the purchase. Click a blue reference to open the real record. |
| **Purchases & Inventory** | Computer: *Bought for project* **40**, *Delivered / sold* **30**. |
| **Sales & Receivables** | The 300,000 sale. *Still owed* **100,000**. |
| **Expenses & Costs** | Cost of goods sold **150,000** and Transport **10,000**. *Owed to suppliers* **120,000**. |
| **Cash Flow & Funding** | *Money in* **300,000**. *Money out* **90,000**. *Operating* **110,000**. *Financing* **100,000**. |
| **Profit & Loss** | Revenue 300,000 → Gross profit 150,000 → **Net project profit 140,000**. Owner money is shown separately under *Not in profit*. |

On the **Profit & Loss** tab, click **Open in the full P&L** (top right). The company's normal Profit & Loss page opens, already filtered to this contract. ✅ It shows the **same** numbers.

---

## Part F — Check nothing was counted twice

1. Top menu **Money** → **Profit & Loss**.
2. Next to the dates there is a box with a briefcase icon that says **All projects (entire company)**.
   - ✅ With *All projects*, this is the company's normal P&L, exactly as it would be without the module.
3. Click that box → choose **General company activity**. This shows everything **not** linked to any contract.
4. Click it again → choose **PRJ-0001 — Supply of Computers**.
   - ✅ The contract's figures + the General figures = the *All projects* figures.
5. Top menu **Money** → **Cash Flow**. Try the same box there.
6. Top menu **Operations** → **Compare projects**.
   - ✅ At the bottom there is a **green** box saying projects plus General company activity add up exactly.
   - ❌ If it is **red**, stop and report it (take a screenshot).

---

## Part G — Sharing one bill between two contracts

### G1. Create a second contract

1. **Operations** → **New project / contract**.
2. **Project / contract name**: `Contract B`, **Type**: *Contract*. Click **Create**.

### G2. One purchase of 100 chairs: 60 for one contract, 40 for the other

1. Add a product **Office chair** (Part C1 again): cost price `100`, selling price `250`, ☑ Sell to Customers, ☑ Track inventory.
2. **Operations** → **Record Purchase**.
   - **Supplier**: Computer Supplier.
   - Leave **Related project / contract** as *General company activity*.
   - Items: **Office chair**, Qty `100`, Cost per unit `100` (line total 10,000).
3. Under the product, click the small link **Project: General**. A window **Projects for: Office chair** opens.
   - **Split by**: *Quantity* (whole = 100 pcs).
   - Row 1: choose **Supply of Computers**, type `60`.
   - Row 2: choose **Contract B**, type `40`.
   - The grey box says *Given to projects: 100 · stays General: 0*.
   - Click **Use this split**.
4. Leave **Amount paid now** as the full total (paid now). Click **Save & Approve**.

✅ **Check:**
- **Operations → Purchases**: only **one** purchase of 10,000 (with "PRJ-0001, PRJ-0002" under its number).
- **Operations → Products**: Office chair stock is **100** (not 200).
- Contract → Overview: *Purchases made* is **6,000** on Supply of Computers and **4,000** on Contract B.

### G3. One expense shared between two contracts

1. **Expenses → Expenses → New expense**: Description `Truck rental`, Amount `10000`, paid now.
2. Next to **Related project / contract** there is a small **split** button (⑂). Click it.
   - Split by *Amount*: Supply of Computers `6000`, Contract B `4000`.
   - **Kind of cost**: *Shared project cost*.
   - Click **Use this split**.
3. **Create as Draft**, then approve it in the Expenses list (✓).

✅ **Check:**
- The Expenses list shows **one** Truck rental of **10,000**.
- Supply of Computers' operating expenses go **up by 6,000**; Contract B's by **4,000**.

### G4. A split that adds up to too much is refused

1. Open any split window and type 70% for one contract and 40% for the other.
2. ✅ A red message appears: *The parts add up to more than the whole…*, and **Use this split** is greyed out.

### G5. Moving a purchase to the other contract

1. **Operations → Purchases** → click the **#number** of the chairs purchase. Its page opens.
2. On the right, in the **Project / Contract** box, click **Change**.
3. Choose **Contract B**. In **Why**, type `recorded against the wrong contract`. Click **Save**.

✅ **Check:**
- Supply of Computers: *Purchases made* goes **down by 6,000**.
- Contract B: *Purchases made* is now **10,000**.
- There is still only **one** purchase, and the chair stock is still **100**.
- Click **History** in the same box: the old split shows as *Replaced*, with your name, the time and your reason.

---

## Part H — Keeping stock aside for a contract

Open **Supply of Computers** → tab **Purchases & Inventory**. You have 10 computers left on the shelf (40 bought − 30 sold).

| # | Do this | ✅ Check |
|---|---|---|
| 1 | Click **Reserve stock**. Product **Computer**, Quantity `5`, click **Save**. | *Still reserved* **5**. *Company on hand* still **10**. *Free for the company* **5**. |
| 2 | Click **Reserve** on the Computer row, Quantity `20`, **Save**. | Refused: *Only 10 Computer in stock…* |
| 3 | Click the **⇄** (move) button on the Computer row. Quantity `2`, **To project**: Contract B, **Save**. | Supply of Computers still reserved **3**. |
| 4 | In **Reservation history**, click **↶** (undo) on the move. **Why**: `test`. Click **Undo**. | The move is crossed out. Still reserved **5** again. |
| 5 | Top menu **Operations → Inventory & Purchases** | Under Computer's stock: *5 reserved for PRJ-0001*. |

> Reserving stock never sells, moves or uses anything. It only says "these items on the shelf are for this contract".

---

## Part I — Budget and milestones

### I1. Budget

1. Open **Supply of Computers** → tab **Budget** → click **Set budget**.
2. Type amounts in the **Budget** column:
   - *Materials / inventory*: `250000`
   - *Other direct costs*: `5000`
3. Click **Save budget**.

✅ **Check:**
- A yellow warning at the top: *Other direct costs spending has exceeded its approved budget by…* (the transport alone was 10,000). It is only a warning; nothing is blocked.
- The box at the top right says **Committed (approved purchases & expenses)**. Change it to each option and look at the **Materials / inventory** row:

| Measure | Materials "Actual" |
|---|---|
| Committed | 200,000 (the 40 computers bought) |
| Cash actually paid | 80,000 (paid to the supplier) |
| Recognised cost in the P&L | 150,000 (the 30 computers sold) |

> Expenses count under **Other direct costs** for now. There is no screen yet to tell the system "this expense category is Transport". Purchases always count as Materials.

4. Click **Change budget**, change Other direct costs to `20000`, and save.
   - ✅ The warning disappears and the page shows **version 2**.

### I2. Milestones

1. Tab **Milestones** → **Add milestone**.
2. **Name**: `Goods delivered`, **Planned date**: yesterday, **Status**: *Planned*. Click **Save**.
   - ✅ The planned date shows in **red** with *(late)*.
3. Click the ✏️ pencil on that row. Change **Status** to **Completed**. Click **Save**.
   - ✅ A green ✔ with today's date appears.
   - ✅ Go to **Sales**: **no** new sale was created. A milestone is only a progress note.

---

## Part J — Adding old transactions to a contract

1. **Expenses → Expenses → New expense**: Description `Old site visit`, Amount `700`, paid now. Leave **Related project / contract** as *General company activity*. **Create as Draft**, then approve it (✓).
2. Write down the **Net profit** on **Money → Profit & Loss** (All projects).
3. Top menu **Operations** → **Link older transactions**.
4. **Link to project**: choose **Supply of Computers**. **Kind**: *Expenses*.
5. Tick the box next to **Old site visit**. Click **Preview & link**.
   - ✅ A window shows the contract's costs *Now* and *After linking* (+700), and says company totals do not change.
6. Click **Link**.

✅ **Check:**
- The contract's operating expenses went **up by 700**.
- **Money → Profit & Loss** (All projects): the company net profit is **the same** as you wrote down.

---

## Part K — Filters, archiving, switching off

### K1. Filters on the lists

Open **Sales**, **Purchases**, **Expenses** and **Owner money** one by one. Each has a box with a briefcase icon (**All projects**).
- Choose **Supply of Computers**. ✅ Only that contract's items show.
- Choose **General company activity**. ✅ Only items not linked to any contract show.

### K2. Archive and restore

1. Open **Contract B** → click **Archive** (top right) → confirm.
   - ✅ Contract B disappears from the **Related project / contract** boxes on forms.
2. **Operations → Projects & Contracts** → in the status box choose **Archived** → open Contract B → click **Restore**.
   - ✅ It's back.

### K3. Change status

1. Open a contract → **Status** → choose **On hold**, note `waiting for payment`, **Save**.
2. ✅ On the **Overview** tab, **Status history** shows the change with your name.

### K4. Switch the module off and on

1. Top menu **Setup → Business Features**.
2. Find the **Projects & Contracts** box and click its switch to turn it **off**.
   - ✅ A message warns you that projects and their history are kept.
3. Click **OK**, then **Save Changes**.

✅ **Check:**
- **Operations** no longer has the Projects & Contracts column.
- New sales, purchases and expenses have **no** project box.
- **Money → Profit & Loss** shows the same company figures as before.

Turn it back **on** the same way and click **Save Changes**. ✅ Everything comes back as it was.

### K5. A company without the module (optional)

Create another company (Part B) but **don't** tick *Enable Projects & Contracts*.
✅ There is no Projects menu and no project boxes anywhere. The company works exactly as before.

---

## Part L — If something goes wrong

| What you see | What to do |
|---|---|
| No *Enable Projects & Contracts* tick-box | Pick a business **below Restaurant** in the list. Then restart the website (Part A, step 3) and press **Ctrl + Shift + R**. |
| No *Projects & Contracts* in the Operations menu | **Setup → Business Features** → turn **Projects & Contracts** on → **Save Changes**. |
| A project page says "Request failed" or "404" | The back office server (Farm API) was not restarted with the new version. Do Part A, step 2. |
| *Cost of goods sold* is not 150,000 in Step 5 | The Computer's **Cost price** is not 5,000. **Operations → Products** → edit Computer → Cost price `5000`. |
| *Owed to suppliers* did not go down in Step 4 | The 80,000 was not put against the purchase. Record it again and type the amount in the purchase's box under *Apply to open purchases*. |
| Revenue is 0 after Step 5 | The sale is still **Draft**. Open it and click **Approve**. |
| The expense doesn't show on the contract | It is still **Draft**. Approve it in the Expenses list (✓). |
| *Customer still owes* is 0 after Step 5 | **Amount paid** was left at 300,000 on the sale. That's a cash sale, not credit. |
| Compare projects shows a **red** box | Stop and report it with a screenshot. |

**When you report a problem, send:**
- the Part and step (e.g. *Part D, Step 5*);
- what this guide says you should see;
- what you actually see (a screenshot is best).
