# Livestock Farm Management — Step-by-Step Guide

This guide walks you through a Livestock company from the very first login to
the monthly reports, in the order you should do things. Each step says
**where to go**, **what to do**, and **what the feature is for**.

A Livestock company is for every animal except chickens: ducks, guinea fowl,
turkeys, quail, geese, rabbits, grasscutters, goats, sheep, pigs and cattle.
Its screens use a brown/amber colour so you can always tell it apart from a
Poultry company.

> **How to read the "Where" lines.** The menu has these sections: **Setup**,
> **Operations**, **Sales**, **Expenses**, **Money**, **Trackers** (reports),
> **Quick Links** and **System**. "Operations → Animals → Animal groups" means open Operations,
> then the Animals group, then Animal groups. The web address is shown too,
> e.g. `/livestock-groups`, in case you prefer to type it.

---

## Contents

- [Part A — Before you start: three ideas that run through everything](#part-a)
- [Part B — Create the company](#part-b)
- [Part C — Set up the farm (do once, in this order)](#part-c)
- [Part D — Get your animals onto the system](#part-d)
- [Part E — Every day](#part-e)
- [Part F — Breeding, growth and health](#part-f)
- [Part G — Feed](#part-g)
- [Part H — Buying](#part-h)
- [Part I — Selling and getting paid](#part-i)
- [Part J — Delivery](#part-j)
- [Part K — Money](#part-k)
- [Part L — Staff and payroll](#part-l)
- [Part M — Checking the animals and stock](#part-m)
- [Part N — Reports](#part-n)
- [Part O — Fixing mistakes](#part-o)
- [Quick reference — daily, weekly, monthly](#quick-reference)

---

<a id="part-a"></a>
## Part A — Three ideas that run through everything

1. **Groups hold your animals.** Every animal belongs to a group (a herd, a
   litter group, a flock of ducks). The group's count is what the farm has.
   You can also **tag** individual animals (cows, breeding does, boars) to
   follow them one by one — tagging is optional.

2. **Counts, stock and money only change through records.** You never type
   "we now have 37 goats". The count goes down because you recorded deaths or
   a sale, and up because you recorded a purchase or a birth. That is why
   every number can always be explained — open the group, item or account and
   you see every change that made it.

3. **Nothing is deleted.** A wrong entry is **reversed**: the animals, stock
   and money go back to how they were, and both the entry and the reversal
   stay on record. Then you enter it again correctly.

---

<a id="part-b"></a>
## Part B — Create the company

**Step 1. Register or add the company**
- **New account:** on the Register page choose the **Livestock** card (🐐).
- **Existing account:** go to **Companies → Add company** and pick type
  **Livestock**.

You land on the **Livestock dashboard** (`/livestock-dashboard`). It shows the
animals on the farm by kind and what needs doing (alerts).

---

<a id="part-c"></a>
## Part C — Set up the farm (do once, in this order)

Setup pages can only be changed by the owner/admin.

### Step 2. Company settings
**Where:** Setup → Company → **Company settings** (`/livestock-company-settings`)

Enter the farm/brand name, owner, phone, email, town and site address, total
capacity and operating hours; pick the **currency** (and its symbol) and the
**business time zone**.

**What it does:** the name and contacts appear on receipts and documents;
the currency is how every amount is shown; the time zone decides when a
business day starts and ends (daily records, closing, reports).

### Step 2b. Choose the animals you keep
**Where:** Setup → Company → **Animals kept** (`/livestock-animals-kept`)

Tick every kind of animal on the farm (e.g. Ducks, Goats, Rabbits).

**What it does:** this switches the right pages on and off for you:
- **Eggs** pages and columns only appear if you keep egg layers (ducks, guinea
  fowl, turkeys, quail, geese).
- **Milk** only appears for goats, sheep and cattle.
- **Breeding & births** only appears for animals you breed on the farm
  (rabbits, grasscutters, goats, sheep, pigs, cattle).
- Words change per animal: a rabbit birth is a *kindling*, young are *kits*;
  goats *kid*; pigs *farrow*; cows *calve*.

### Step 3. Add your pens
**Where:** Setup → Company → **Pens** (`/livestock-pens`)

Add each house, hutch, sty, paddock or kraal, with how many animals it holds
and (optionally) which animal it is for.

**What it does:** groups are placed in pens. The pen's capacity warns you
when you put in more animals than it holds.

### Step 4. Add your cash accounts
**Where:** Money → **Cash accounts** (`/livestock-cash-accounts`)

Add one account for every place money is kept: Cash box, Bank, Mobile Money.
Enter how much is in each today (the opening balance) and mark one as the
**default**.

**What it does:** every sale, payment, expense and pay run goes in or out of
one of these accounts, so each account's balance is always exactly what
happened to it. Open an account to see every movement.

### Step 5. Add your feed, medicine and supplies
**Where:** Operations → Feed & Stock → **Feed & stock** (`/livestock-items`)

Add each item — feed (e.g. "Layer mash", in kg), ingredients for mixing
(maize, soya), medicine, vaccines, and supplies. Enter what you have now and
what it cost (the opening stock).

**What it does:** this is your store. Stock goes out automatically when you
record feed or medicine on a daily record, and comes in when you buy. Each
item is valued at its **average cost**. Eggs and milk you collect also appear
here automatically as produce, ready to sell.

### Step 6. Add customers and suppliers (optional now)
**Where:** Sales → **Customers** (`/livestock-customers`) and
Expenses → **Suppliers** (`/livestock-suppliers`)

You can also add them on the fly when you record a sale or purchase.

### Step 7. Delivery setup (only if you deliver)
**Where:** Setup → Delivery → **Drivers, vehicles & routes**
(`/livestock-delivery-setup`)

Add drivers, vehicles and routes. The same registration number cannot be
entered twice, even written differently ("gr 123-24" and "GR-123 24").

### Step 8. Staff (if you pay workers)
**Where:** Expenses → **Staff** (`/livestock-staff`)

Add each worker and their pay rate. See [Part L](#part-l).

---

<a id="part-d"></a>
## Part D — Get your animals onto the system

There are two ways animals arrive. Use whichever fits.

### Step 9a. Animals already on the farm → create groups directly
**Where:** Operations → Animals → **Animal groups** (`/livestock-groups`) →
**Add group**

Fill in:
- **Animal** — the kind of animal.
- **Name** — e.g. "Goats A", "Rabbit breeders".
- **Pen** — where they live.
- **How many** — the animals in the group today (the opening count).
- **Breed** — pick from the list (each animal has its own breeds; choose
  *Local / indigenous*, *Cross / mixed*, or *Other (type it)* if needed).
- **Purpose** — meat, eggs, milk, breeding.
- **Age on the start date** — type a number and choose **days, weeks, months
  or years**, whichever you know.

**What it does:** the group is where everything else hangs — daily records,
weights, health, sales. Its **age** drives the vaccination schedule.

### Step 9b. New animals bought or brought in → record an intake batch
**Where:** Operations → Animals → **Intake batches** (`/livestock-batches`)

- **Buy animals** — opens a purchase (see [Part H](#part-h)). The animals
  become an intake batch automatically.
- **Record intake** — for animals that came another way (gift, from another
  farm of yours, hatched elsewhere). Enter the animal, how many, the date, the
  breed, and the age when they came (number + days/weeks/months/years).

Then press **Divide** on the batch to split it into groups (e.g. 60 rabbits →
"Rabbits A" 30 and "Rabbits B" 30).
No pens yet, or need more? Inside the Divide window press **Quickly add
hutches/pens** (owner/admin): give a name, how many and how many each holds,
and they are created on the spot ("Hutch 1", "Hutch 2"…). The new pens are
put on the groups that have no pen yet, and a group is added for any extra
pen.

**What it does:** a batch is "animals that arrived together". It shows how
many are **not yet in a group**, so none get lost between arrival and
housing. Its cost carries through to the groups for profit by group.

### Step 10. Tag animals you want to follow one by one (optional)
**Where:** Operations → Animals → **Animal register** (`/livestock-animals`),
or on a group's page → **⋯ → Tag an animal**

Enter the tag number, sex, birth date, breed, and (if known) its mother and
father.

**What it does:** a tagged animal has its own page — its parents and
offspring, every group it has been in, its breeding record, and whether it was
sold, died or culled. Use it for breeding stock and valuable animals.

---

<a id="part-e"></a>
## Part E — Every day

### Step 11. Fill the daily record for each group
**Where:** Operations → Production → **Daily records**
(`/livestock-production-records`) → **New**  (also a Quick Link)

One record per group per day. Enter what applies:
- **Deaths** and **culls**, with the **cause** (e.g. "Heat", "Diarrhoea").
- **Eggs collected** (and broken) — egg layers only.
- **Milk (litres)** — dairy animals only.
- **Feed given** — pick the feed and quantity; add more lines for more feeds.
- **Medicine given** — same, one line per medicine.

**What it does when you save:**
- The group's count goes down by the deaths and culls.
- The feed and medicine come out of stock, and their cost is charged to the
  group (used for profit by group and feed per animal).
- Eggs and milk go into stock as produce, ready to sell.
- A second record for the same group and day is refused — edit the first
  instead.

### Step 12. Feed many groups at once (shortcut)
**Where:** Operations → Feed & Stock → **Feed many groups**
(`/livestock-feed-distribution`)

Pick one feed and one date, then enter a quantity for each group.

**What it does:** adds a feed line to each group's daily record for that day
(creating the record if there isn't one). Saves filling the same feed into
ten records.

### Step 13. Check for missed days
**Where:** Operations → Production → **Missing records**
(`/livestock-missing-records`)

**What it does:** lists every day a group with animals has no daily record.
Click a day to open a ready-filled record for it.

### Step 14. Close the day
**Where:** Money → **Daily closing** (`/livestock-daily-closing`)  (also a
Quick Link)

Pick the day (the strip at the top shows the last two weeks as Open, Closed
or Reopened). The page shows:
- **Animals:** each group's start, born, died, culled, sold, end, produce and
  feed — with an **Add** link where the daily record is missing.
- **Money:** each account's start of day, money in, money out and end of day.
  Count the cash box against "End of day" (see Step 33).
- **Before closing:** anything wrong — a missing record, an account below
  zero, a delivery still out.

Press **Close**. If there are problems, fix them or write why you are closing
anyway.

**What it does:** a **closed day is locked**. Nothing dated on it — deaths,
births, stock, money, daily records, health records — can be added, edited or
reversed. This protects your books. If something truly has to change, press
**Reopen** and give a reason; both the reopen and the next close are kept.

---

<a id="part-f"></a>
## Part F — Breeding, growth and health

### Step 15. Breeding and births
**Where:** Operations → Production → **Breeding & births**
(`/livestock-breeding`)  (only shows if you breed animals)

Record, in order as they happen:
1. **Mating** — the mother (doe/ewe/sow/cow) and father.
2. **Pregnancy check** — positive or negative.
3. **Birth** — born alive and born dead, and which group the young go into.
4. **Weaning** — how many were weaned.
5. **Loss** — if a pregnancy was lost.

**What it does:**
- Shows who is **due to give birth**, worked out from how long each kind of
  animal carries its young.
- A **birth adds the young born alive** to the group you chose.
- Builds each mother's record (litters, litter size) — see the *Births &
  litters* report.

### Step 16. Weigh-ins and growth
**Where:** Operations → Production → **Weigh-ins & growth**
(`/livestock-weigh-ins`)

Pick a group and record a weigh-in: how many you weighed and their average
weight.

**What it does:** shows the group's weight over time, **daily gain**, and
**feed per kg gained** (how well feed turns into meat). Also on the group's
page under *Growth*.

### Step 17. Health records
**Where:** Operations → Health → **Health records** (`/livestock-health`)

Record illness, treatment, vaccination, deworming or a vet visit for a group
(or a tagged animal): what was seen, the diagnosis, how many were affected,
and any medicine used.

**What it does:** keeps the health history; medicine used comes out of stock.
Groups still sick are listed on top. If the medicine has a **withdrawal
period**, the group shows a warning banner until it ends (see Step 26).

### Step 18. Vaccinations & deworming
**Where:** Operations → Health → **Vaccinations & deworming**
(`/livestock-vaccinations`)

- **Due list:** what each group is due for and when, based on its age.
- **Plans:** each kind of animal follows a plan of steps (e.g. "deworm at 8
  weeks, repeat every 3 months"). Suggested plans come built in for every
  animal — copy one and adjust it to your vet's advice.
- Press **Given** on a due step to record it.

**What it does:** you never have to remember schedules. Marking a step
given saves a health record for the group.

### Step 19. Treatment campaigns
**Where:** Operations → Health → **Treatment campaigns**
(`/livestock-treatments`)

Use this when **one medicine is given to several groups over several days**
(e.g. a 5-day antibiotic course for three pens). Create the campaign, then
**record each day** — the quantity per group is suggested from its head
count. Complete or cancel it at the end.

**What it does:** takes the medicine out of stock each day, charges it to the
groups, and tracks the **withdrawal period** — the groups that must not be
sold for meat/milk yet.

### Step 20. Farm alerts
**Where:** Operations → Health → **Farm alerts** (`/livestock-alerts`), also
on the dashboard

**What it does:** warns you about things that need attention — unusual
deaths, a drop in eggs or milk, stock low or about to run out, missing daily
records, vaccinations due, births due, and animals under withdrawal. Alerts are worked out fresh from your records; an
alert goes away by itself when the problem is dealt with.

---

<a id="part-g"></a>
## Part G — Feed

### Step 21. Feed formulas (if you mix your own feed)
**Where:** Operations → Feed & Stock → **Feed formulas**
(`/livestock-feed-formulas`)

Write the recipe for one batch: which ingredients and how much of each, and
which feed it makes.

**What it does:** shows what one batch costs at today's stock prices and how
many batches your stock allows.

### Step 22. Feed mixing
**Where:** Operations → Feed & Stock → **Feed mixing**
(`/livestock-feed-production`)

Pick a formula and how many batches you mixed (add milling or labour cost if
any).

**What it does:** takes the ingredients out of stock and puts the finished
feed in, valued at what the ingredients cost plus the extra costs.

### Step 23. Days of supply
**Where:** Operations → Feed & Stock → **Days of supply**
(`/livestock-feed-supply`)

**What it does:** for each feed and ingredient, how many days it will last at
the rate you have been using it, and the date it runs out — so you buy
before you run out.

---

<a id="part-h"></a>
## Part H — Buying

### Step 24. Record a purchase
**Where:** Expenses → **Purchases** (`/livestock-purchases`) →
**New**

Pick the supplier and date, then add lines:
- **Item** — feed, medicine, supplies (quantity and price).
- **Animals** — the animal, breed, age when bought, how many, price each.
- **Expense** — a bill bought on credit (vet, transport…).

Enter how much you **paid now** and from which account. The rest is owed.

**What it does:**
- Items go into stock at the price paid.
- Animals become an **intake batch** ready to divide into groups (Step 9b).
- What you did not pay shows on **Supplier balances**.

### Step 25. Pay suppliers
**Where:** Expenses → **Supplier balances**
(`/livestock-supplier-balances`)

See what you owe each supplier, open their **statement** (every purchase and
payment with a running balance), and **pay** them.

**What it does:** a payment is matched to the **oldest unpaid purchase
first**, and the money leaves the account you choose.

---

<a id="part-i"></a>
## Part I — Selling and getting paid

### Step 26. Record a sale
**Where:** Sales → **Sales** (`/livestock-sales`) → **New**
(also a Quick Link)

Pick the customer (or leave as walk-in) and add lines:
- **Animals from a group** — how many and the price each.
- **Tagged animals** — pick them one by one.
- **Produce or stock** — eggs, milk, meat, or any stock item.

Enter how much was **received now** and into which account; the rest is on
credit to the customer.

**What it does:**
- Animals come off the group count; tagged animals are marked sold.
- Eggs, milk and stock come out of stock.
- What was not paid shows on **Customer balances**.
- **Withdrawal protection:** if a group or animal has had a medicine and its
  withdrawal period has not ended, you are warned. You can only go ahead by
  giving a reason (e.g. "sold as breeding stock, not for meat").

### Step 27. Receive customer payments
**Where:** Sales → **Customer balances**
(`/livestock-customer-balances`)  (also a Quick Link)

See what each customer owes, open their **statement**, and **receive
payment**.

**What it does:** the payment pays off the **oldest unpaid sale first** and
goes into the account you choose.

---

<a id="part-j"></a>
## Part J — Delivery (only if you deliver)

### Step 28. Send out a delivery
**Where:** Operations → Delivery → **Deliveries** (`/livestock-deliveries`) →
**Send out**

Pick the driver (and vehicle/route), the date, and tick the customer sales
going out.

**What it does:** shows how much the driver should bring back. A sale can
only be out with one driver at a time.

### Step 29. Driver comes back
On the delivery, press **Driver back** and enter what was collected from each
customer, and which account the money went into. If the driver brings back
less than expected, a note explaining why is required.

**What it does:** each amount collected is recorded as that customer's
payment. The **Driver report** tab shows, per driver, deliveries, what was
expected, collected and **short**.

---

<a id="part-k"></a>
## Part K — Money

### Step 30. Expenses
**Where:** Expenses → **Expenses** (`/livestock-expenses`)

Record running costs paid now: labour, vet, transport, fuel, electricity,
water, repairs — pick the category and the account it was paid from.

**What it does:** money leaves the account and the cost appears in **Profit &
loss**. Bills bought on credit are entered as a purchase (Step 24, Expense
line) and are listed here too.

### Step 31. Move money between accounts
**Where:** Money → **Move money** (`/livestock-cash-transfers`)

E.g. banking the cash box, or bank → mobile money. Enter any bank fee.

**What it does:** one account goes down, the other up — it is not income or a
cost. A fee is recorded as a Fees expense.

### Step 32. Owner money
**Where:** Money → **Owner money** (`/livestock-owner-money`)

Money the owner puts into the farm or takes out for personal use.

**What it does:** moves cash but is kept apart from income and costs, so your
profit stays honest.

### Step 33. Count the money
**Where:** Money → **Count the money** (`/livestock-cash-reconciliation`)

Count the cash box (or read the bank statement) and enter what is really
there.

**What it does:** compares it with what the records say. Any difference is
recorded as a **cash difference** (with a note) so the books match reality —
and it shows in Profit & loss. Do this before closing the day.

### Step 34. Loans
**Where:** Money → **Loans** (`/livestock-loans`)

Record money borrowed (bank, microfinance, family), then each repayment split
into the loan itself and the interest.

**What it does:** shows what is left to repay. **Interest is a cost** of the
farm; repaying the loan itself is not.

### Step 35. Assets
**Where:** Money → **Assets** (`/livestock-assets`)

Record buildings, equipment and vehicles: what they cost and how many months
they will last. Record selling or scrapping one.

**What it does:** spreads the cost evenly over its useful life
(depreciation, "wear and tear") so Profit & loss is fair month to month, and
shows what each asset is worth now.

---

<a id="part-l"></a>
## Part L — Staff and payroll

### Step 36. Staff and advances
**Where:** Expenses → **Staff** (`/livestock-staff`)

Add workers with their pay rate. Give an **advance** (a loan to a worker)
from a cash account; it is repaid in cash or taken off their pay.

### Step 37. Pay run
**Where:** Expenses → **Payroll** (`/livestock-payroll`)

Create a pay run for a period: each person's pay, other deductions, and what
comes off their advance.

**What it does:** the **net pay** leaves the account you choose; the **gross
pay** is the farm's labour cost in Profit & loss; advances go down by what was
deducted.

---

<a id="part-m"></a>
## Part M — Checking the animals and stock

### Step 38. Head count (physical count)
**Where:** Operations → Animals → **Head count** (`/livestock-head-count`)

Walk the pens, count the animals, and enter the real count for each group on
a date.

**What it does:** every difference from the records becomes a **count
correction** dated that day, so the system matches the pens. Everything
recorded after that date stays as it was.

### Step 39. Losses
**Where:** Operations → Feed & Stock → **Losses** (`/livestock-losses`)

Record stock that was spoiled, expired, spilled, stolen or damaged.

**What it does:** takes it out of stock at its value and shows the loss.
Also lists the animals that died or were culled, by group.

### Step 40. Animal stock
**Where:** Operations → Animals → **Animal stock** (`/livestock-animal-stock`)

**What it does:** for each group over a period: what it started with, every
way animals came and went (bought, born, died, culled, sold, moved,
corrected) and what it ended with. Start + in − out = end on every row.

### Step 41. A group's page
**Where:** Operations → Animals → Animal groups → click a group

Tabs: **Count history** (every change to the count and where it came from),
**Tagged animals**, **Daily records**, **Growth**, **Breeding**.
Jobs under **⋯**: change the count, tag an animal, record breeding, edit,
**Whole-life summary**, close the group (when it is empty), reopen.

---

<a id="part-n"></a>
## Part N — Reports

**Where:** Trackers → **All reports** (`/livestock/reports`)

All reports in one place. Pick the dates at the top of each report.

| Report | What it tells you |
|---|---|
| **Production** | Per group: start and end count, deaths and death %, eggs and **lay rate**, milk per animal a day, feed per animal a day. Filter by kind of animal. |
| **Monthly trackers** (`/livestock-trackers`) | A month as a grid — days down, groups across — for deaths, eggs, milk, feed (kg) or animal count. |
| **Deaths & culls** | Deaths and culls by group, death %, and the **causes**. |
| **Births & litters** | Matings, births, average litter, % born alive, weaned; each mother's record. |
| **Herd make-up** | Animals of each kind now; tagged animals by sex and age band. |
| **Group summary** | One group's whole life: animals in and out, produce, feed, latest weight, and its **profit**. |
| **Growth** | Weights, daily gain, feed per kg gained (Weigh-ins page). |
| **Feed used** | Feed used by item and by group, kg and cost, cost per animal. |
| **Medicine used** | Medicine and vaccines used, by item and group, and illnesses seen. |
| **Sales** | What sold, average price, by customer (with what each owes), day by day. |
| **Profit & loss** (`/livestock-profit-loss`) | Income and costs for the whole farm or **one group**, and every group side by side. |
| **Cash flow** (`/livestock-cash-flow`) | Money at the start, where money came from and went, and what is left, per account. |
| **Customer / Supplier balances** | Who owes you, and who you owe. |
| **Driver report** | What each driver collected and what is short. |
| **Days of supply**, **Losses**, **Animal stock**, **Missing records** | See Steps 23, 39, 40, 13. |

> **Lay rate** = eggs ÷ the birds alive at the **start** of each day (the
> standard "hen-day" rate), so deaths or sales during the day do not inflate
> it.

---

<a id="part-o"></a>
## Part O — Fixing mistakes

| Mistake | How to fix it |
|---|---|
| Wrong daily record | Open it and **Edit** (re-posts the whole record) or **Delete** (puts its animals and stock back). |
| Wrong sale | Open the sale → **Reverse**. Animals, stock and money go back. Enter it again. |
| Wrong purchase | Open the purchase → **Reverse** (only while its stock is unused and its animals are not yet in groups). |
| Wrong payment | Reverse it from the balances page; the sale/purchase is owed again. |
| Wrong count change | On the group's Count history, **reverse** that change. |
| Wrong stock movement | On the item's page, reverse the manual movement. Usage is changed on the daily record that made it. |
| The day is closed | Daily closing → **Reopen** (with a reason), fix it, close it again. |
| Count in the pens is different | Do a **Head count** (Step 38). |

---

<a id="quick-reference"></a>
## Quick reference

**Every day**
1. Daily record for each group (deaths, eggs/milk, feed, medicine).
2. Sales and payments received.
3. Expenses paid.
4. Count the money.
5. Close the day.

**Every week**
- Missing records — fill any gaps.
- Vaccinations & deworming — give what is due.
- Weigh a sample from growing groups.
- Days of supply — buy feed before it runs out.
- Customer balances — chase what is owed.

**Every month**
- Head count in every pen.
- Pay run.
- Pay suppliers.
- Reports: Production, Deaths & culls, Profit & loss, Cash flow.

**Once, at setup**
Company settings → Animals kept → Pens → Cash accounts → Feed & stock → (Customers, Suppliers,
Drivers, Staff) → Groups or Intake batches → Tag key animals.
