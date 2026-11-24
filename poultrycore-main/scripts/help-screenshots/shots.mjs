/**
 * The picture walkthroughs for the Help Center, keyed by HELP_ENTRIES id
 * (lib/help/poultry-help-content.ts). `npm run screenshots` walks each list in
 * order, in ONE browser tab per entry, so a shot continues from the screen the
 * previous shot left behind.
 *
 * EVERY WALKTHROUGH STARTS IN THE MENU BAR (menu(...) below): users must learn
 * where a page lives, not only what it looks like once they are there. The
 * menu picture boxes the orange-bar button (1) and the row to choose (2), and
 * the run then clicks through to the page the way a person would.
 *
 * A shot:
 *   path       open this page first (omit to stay on the current screen)
 *   menu       { bar, href }: open that top-bar menu and picture the row
 *              linking to href, then click it. Rows come from
 *              lib/nav/poultry-nav-config.ts (and the Reports menu in
 *              components/dashboard/top-nav.tsx).
 *   click      click this BEFORE the picture (a tab, a radio)
 *   fill       [{ ...target, value }]: example values typed into a form
 *   pick       [{ ...target, option | nth }]: choose in a dropdown
 *   scrollTo   bring this part of a long form or page into view
 *   highlight  the thing to box in orange: { button }, { tab }, { text },
 *              { label }, { placeholder }, { css }, or { card: "exact text" }
 *              for the whole card/panel holding that text. A list gets
 *              numbered boxes. Add within: "dialog" to look only in the open
 *              dialog, nth: n for the n-th match.
 *   then       click this AFTER the picture, ready for the next shot
 *   area       "page" (default) or "dialog" -- crop to the open dialog
 *   optional   true: if the highlight is missing, take the picture anyway
 *   focus      click this before typing
 *   press/type a key to press / text to type before the picture
 *   mask       extra targets to paint over (names etc.); emails and phone
 *              numbers are always painted over
 *   caption    one plain sentence; shown under the picture
 *
 * Button labels must match the screen (case-insensitive). When a screen
 * changes, the run fails on that shot and says which -- fix the label here and
 * the answer text in poultry-help-content.ts together.
 */

const BARS = {
  setup: "Setup",
  ops: "Operations",
  money: "Sales, Expenses & Money",
  reports: "Reports",
  tools: "Tools",
  quick: "Quick Links",
}

/** The first picture of a walkthrough: where to find the page. */
const menu = (bar, row, href) => ({
  path: "/dashboard",
  menu: { bar, href },
  caption: `In the orange menu bar at the top, click "${bar}" (1), then choose "${row}" (2).`,
})

/**
 * One Farm Setup tab: click it, box the tab (1) and its main button (2). With
 * `extra: { then: { button } }` and a following { area: "dialog" } shot, the
 * form that button opens is pictured too.
 */
const tab = (name, button, caption, extra = {}) => [{
  click: { tab: name },
  highlight: button ? [{ tab: name }, { button }] : { tab: name },
  optional: true,
  caption,
  ...extra,
}]

/** The owner's name on Company settings. */
const OWNER_NAME = { css: 'xpath=//*[normalize-space()="Owner name"]/following::input[1]' }
/** People's names in a setup list (customers, suppliers, staff, drivers). */
const LIST_ROWS = { css: "tbody td" }
/** The egg-size boxes of the sorting form (not its day tick-box, date or notes). */
const SORT_BOXES = 'input:not([type="checkbox"]):not([type="date"]):not([placeholder="Optional"])'

export const SHOTS = {
  // ---------------------------------------------------------- Getting Started
  // A tour of every Farm Setup tab, left to right, in the order a new farm
  // fills them in. Each picture boxes the tab (1) and its main button (2).
  "set-up-farm": [
    menu(BARS.setup, "Production Setup", "/poultry-setup?section=production"),
    { highlight: [{ tab: "Company settings" }, { button: "Save company settings" }], optional: true, mask: [OWNER_NAME], caption: "Farm Setup opens on Production Setup; work through its tabs from left to right. Company settings (1): your business name and contacts, farm type, capacity, currency and business time zone. Click \"Save company settings\" (2) when you are done." },
    ...tab("Houses & pens", "Add House", "Houses & pens (1): add every house or pen your birds live in with \"Add House\" (2). Several at once? Use \"Add Multiple Houses/Pens\".", { then: { button: "Add House" } }),
    { area: "dialog", caption: "Give the house a name and capacity, then save it." },
    ...tab("Flock purchases", "Add Flock Batch", "Flock purchases (1): record each batch of birds you bought with \"Add Flock Batch\" (2): supplier, number of birds and cost per bird."),
    ...tab("Flock groups", "Add Flock", "Flock groups (1): split a batch into the groups you manage, each in its house, with \"Add Flock\" (2)."),
    ...tab("Products", "New product", "Products (1): your products (eggs, egg sizes, birds, broken eggs and so on) are already set up for you, so you can skip this tab. Only use \"New product\" (2) for something you sell that is not in the list.", { then: { button: "New product" } }),
    { area: "dialog", caption: "Adding a missing product: name it, choose its type and unit, and set its price." },
    ...tab("Feed formulas", "New Formula", "Feed formulas (1): if you mix your own feed, list the ingredients of each mix with \"New Formula\" (2)."),
    ...tab("Egg settings", null, "Egg settings (1): your pick times, eggs per crate, packaging and egg sizes. They shape how you record production."),
    ...tab("Supply items", "New Item", "Supply items (1): feed, medicine, packaging and other supplies you keep in stock. Add one with \"New Item\" (2)."),
    { highlight: { css: 'label:has(input[name="setup-section"][value="business"])' }, then: { css: 'input[name="setup-section"][value="business"]' }, caption: "Then switch to \"Business Setup\" at the top of the page for the money side of the farm." },
    ...tab("Customers", "Add Customer", "Customers (1): everyone you sell to. Add one with \"Add Customer\" (2); you pick them when you record a sale.", { mask: [LIST_ROWS], then: { button: "Add Customer" } }),
    { area: "dialog", caption: "Enter the customer's name and contacts, then save." },
    ...tab("Suppliers", "Add supplier", "Suppliers (1): everyone you buy birds, feed and supplies from. Add one with \"Add supplier\" (2).", { mask: [LIST_ROWS] }),
    ...tab("Financial settings", null, "Financial settings (1): choose whether feed and medicine count as a cost when you buy them or when you use them."),
    ...tab("Cash accounts", "New account", "Cash accounts (1): your cash box, bank and mobile money accounts. Money you receive or pay goes into one of these. Add one with \"New account\" (2)."),
    ...tab("Delivery Drivers", "New employee & driver", "Delivery Drivers (1): the people who deliver your eggs. \"Delivery Vehicles\" and \"Delivery Routes\" sit next to it.", { mask: [LIST_ROWS] }),
    ...tab("Staff", "New staff", "Staff (1): your workers, their role and pay, used for payroll. Add one with \"New staff\" (2).", { mask: [LIST_ROWS] }),
  ],
  // The working day, in the order it happens, all from "Quick Links".
  "daily-routine": [
    { path: "/dashboard", menu: { bar: BARS.quick, href: "/production-records" }, caption: "Everything you do each day is under \"Quick Links\" (1), in the order the day happens. Step 1: \"Production Records\" (2)." },
    { highlight: { button: "Log Production" }, optional: true, caption: "Step 1, after each egg pick: log every flock's eggs, deaths and feed with \"Log Production\"." },
    { path: "/dashboard", menu: { bar: BARS.ops, href: "/poultry-egg-sorting" }, caption: "Step 2: \"Operations\" (1), then \"Egg Sorting\" (2). (You can add it to Quick Links with \"Customize\" at the bottom of that menu.)" },
    { highlight: { button: "Sort all available eggs" }, optional: true, caption: "Sort the day's eggs into sizes, so they can be sold by size." },
    { path: "/dashboard", menu: { bar: BARS.quick, href: "/sales" }, caption: "Step 3: \"Quick Links\" (1), then \"Sales\" (2)." },
    { highlight: { button: "Add Sale" }, optional: true, caption: "Record every sale as it happens with \"Add Sale\"." },
    { path: "/dashboard", menu: { bar: BARS.quick, href: "/poultry-payments" }, caption: "Step 4: \"Quick Links\" (1), then \"Customer Payments\" (2)." },
    { highlight: { button: "Record customer payment" }, optional: true, caption: "When a customer pays for an earlier sale, record it here." },
    { path: "/dashboard", menu: { bar: BARS.quick, href: "/expenses" }, caption: "Step 5: \"Quick Links\" (1), then \"Expenses\" (2)." },
    { highlight: { button: "Add Expense" }, optional: true, caption: "Record what the farm spent today with \"Add Expense\"." },
    { path: "/dashboard", menu: { bar: BARS.quick, href: "/poultry-daily-closing" }, caption: "Step 6, at the end of the day: \"Quick Links\" (1), then \"Daily Closing\" (2)." },
    { highlight: [{ text: "Must fix" }, { button: "Close Business Day" }], optional: true, caption: "Fix everything under Must fix (1), then close the day (2)." },
  ],
  "find-anything": [
    // Not /dashboard: it can open an alert dialog over the header.
    { path: "/sales", focus: { css: 'input[placeholder^="Search pages"]' }, highlight: { css: 'input[placeholder^="Search pages"]' }, caption: "Click the search bar at the top of any page, or press Ctrl+K." },
    { type: "expense", highlight: { css: 'input[placeholder^="Search pages"]' }, caption: "Type what you are looking for: a page (\"expense\"), a task, a customer or a flock. Matching pages and records appear as you type." },
    { press: "Control+a", type: "new sale", highlight: { css: 'input[placeholder^="Search pages"]' }, caption: "Type a task, like \"new sale\", and press Enter to go straight to it. Use the arrow keys to pick another result." },
  ],

  // ---------------------------------------------------------- Flocks & Birds
  "add-flock": [
    menu(BARS.ops, "Flock Purchases (Batches)", "/flock-batch"),
    { highlight: [{ card: "Total Purchase Price" }, { card: "Birds Left" }, { card: "Active Batches" }], optional: true, caption: "Flock Purchases lists every batch of birds you bought. The cards show what you spent (1), how many birds are left (2) and how many batches are active (3)." },
    { highlight: { button: "Add Flock Batch" }, then: { button: "Add Flock Batch" }, caption: "Click \"Add Flock Batch\" for the birds you bought." },
    { area: "dialog", highlight: { within: "dialog", text: "New batch purchase" }, optional: true,
      fill: [
        { within: "dialog", placeholder: "e.g., Batch A - Rhode Island Reds", value: "Batch A - Isa Brown" },
        { within: "dialog", placeholder: "e.g., B-001", value: "B-001" },
        { within: "dialog", placeholder: "e.g., 100", value: "500" },
      ],
      caption: "Choose \"New batch purchase\" for birds you just bought (\"Existing batch\" is for birds you already had). Enter the batch name, code, breed, start date and number of birds." },
    { area: "dialog", scrollTo: { within: "dialog", text: "Purchase Details" }, caption: "Under Purchase Details, enter the cost per chick: the total is worked out for you. Enter how much you paid now; anything unpaid is owed to the supplier." },
    menu(BARS.setup, "Flock Groups", "/flocks"),
    { highlight: [{ card: "Overall Total Birds" }, { card: "Total Deaths" }, { card: "Total Birds Left" }], optional: true, caption: "Flock Groups: the groups of birds in your houses. The cards show all birds bought (1), deaths (2) and birds alive in flocks now (3)." },
    { highlight: { button: "Add Flock" }, then: { button: "Add Flock" }, caption: "To put birds from a batch into a house, click \"Add Flock\"." },
    { area: "dialog", pick: [{ within: "dialog", css: "select", nth: 0 }],
      fill: [{ within: "dialog", placeholder: "e.g., Flock A - Rhode Island Reds", value: "Flock A - House 1" }],
      caption: "Pick the batch the birds come from, name the flock and choose Layers or Broilers. Then set the start date, the number of birds and the house." },
    { area: "dialog", scrollTo: { within: "dialog", button: "Create Flock" }, highlight: { within: "dialog", button: "Create Flock" }, optional: true, caption: "Turn on \"Flock Has Arrived\" once the birds are in the house, add any notes, then click \"Create Flock\"." },
  ],

  "close-flock": [
    menu(BARS.tools, "Flock Closeout", "/flock-closeout"),
    { highlight: [{ tab: "Ready to close" }, { tab: "Closed" }, { tab: "Compare" }], optional: true, caption: "Flock Closeout lists the flocks still running under \"Ready to close\" (1) and the ones already ended under \"Closed\" (2). \"Compare\" (3) puts finished flocks side by side." },
    { highlight: { button: "Close" }, then: { button: "Close" }, caption: "When a flock's birds are sold, culled or moved off the farm, click \"Close\" on its row." },
    { area: "dialog", highlight: { within: "dialog", text: "Reconcile", exact: true }, optional: true, then: { within: "dialog", button: "Next" }, caption: "Step 1, Reconcile: check the birds the farm still has in this flock. If the count is wrong, correct it first. Then click \"Next\"." },
    { area: "dialog", highlight: { within: "dialog", text: "Where the birds went" }, optional: true, caption: "Step 2, Dispose: say where every bird went: Sold (with the buyer and price), Culled, or Transferred off the farm. Step 3 shows the totals, and \"Close flock & record sales\" ends the flock and records the sales for you." },
    { press: "Escape", click: { tab: "Closed" }, highlight: { tab: "Closed" }, optional: true, caption: "A closed flock moves to \"Closed\" with its lifetime results. Closed one by mistake? Open its lifetime summary and reopen it." },
  ],
  "correct-bird-count": [
    menu(BARS.ops, "Stock movements", "/poultry-stock"),
    { highlight: { button: "New movement" }, optional: true, then: { button: "New movement" }, caption: "Stock movements lists every stock change, with the batch and flock it belongs to. To correct a bird count, click \"New movement\"." },
    { area: "dialog", pick: [{ within: "dialog", css: 'button[role="combobox"]', nth: 0, option: "Birds" }], caption: "Under Item, choose \"Birds\". Then choose whether birds are added or taken away, and the reason." },
    { area: "dialog", pick: [{ within: "dialog", css: 'button[role="combobox"]', nth: 3 }, { within: "dialog", css: 'button[role="combobox"]', nth: 4 }], fill: [{ within: "dialog", css: 'input[type="number"]', nth: 0, value: "3" }],
      caption: "Pick the batch, then the flock (or \"Not placed in a flock\" for birds still in the batch). Enter the change in whole birds and the date it applies from. The count now and after the change is shown before you save." },
  ],

  // ---------------------------------------------------------- Production & Eggs
  "log-production": [
    menu(BARS.ops, "Production Records", "/production-records"),
    { highlight: [{ card: "Total Eggs" }, { card: "Feed (kg)" }, { card: "Recorded Mortality" }, { card: "Total Birds Left" }], optional: true, caption: "Production Records shows every day's records. The cards add up eggs (1), feed (2), deaths (3) and birds left (4) for the filters you choose." },
    { highlight: { button: "Log Production" }, then: { button: "Log Production" }, caption: "Click \"Log Production\" after each pick, or once at the end of the day." },
    { area: "dialog", pick: [{ within: "dialog", css: 'button[role="combobox"]', nth: 1 }],
      fill: [
        { within: "dialog", css: 'input[type="number"]', nth: 1, value: "2" },
        { within: "dialog", css: 'input[type="number"]', nth: 2, value: "5" },
      ],
      caption: "Pick the flock and the date. The list shows how many birds are alive in each batch and flock right now. For each pick, enter the crates and loose pieces collected; the total eggs are worked out for you." },
    { area: "dialog", scrollTo: { within: "dialog", text: "Egg Losses / Quality" }, caption: "Further down, enter broken eggs, birds that died and the feed used." },
    { area: "dialog", highlight: { within: "dialog", button: "Save Production Record" }, optional: true, caption: "The bar at the bottom sums it up: total eggs, crates, net sellable eggs, deaths and feed cost. Check it, then click \"Save Production Record\"." },
  ],
  "eggs-per-crate": [
    menu(BARS.setup, "Egg Settings", "/business-office/egg-pick-settings"),
    { highlight: [{ tab: "Pick times" }, { tab: "Egg sorting" }, { tab: "Packaging & units" }, { tab: "Egg sizes" }], optional: true, caption: "Egg Settings has four tabs: when you pick eggs (1), egg sorting and eggs per crate (2), boxes and crates (3), and your egg sizes (4). Only an owner or admin can change them." },
    { click: { tab: "Egg sorting" }, highlight: { tab: "Egg sorting" }, optional: true, caption: "\"Egg sorting\" holds eggs per crate (30 unless you change it). Total eggs = crates x eggs per crate + loose eggs." },
    { click: { tab: "Pick times" }, highlight: { tab: "Pick times" }, optional: true, caption: "\"Pick times\" sets the picks you record each day. A 4th pick shows on the production form only when it is turned on here." },
  ],
  "sort-eggs": [
    menu(BARS.ops, "Egg Sorting", "/poultry-egg-sorting"),
    { highlight: [{ css: 'button:has-text("Workspace")' }, { css: 'button:has-text("Sortings")' }, { css: 'button:has-text("Size reports")' }, { css: 'button:has-text("Sizes & settings")' }], optional: true, caption: "Egg Sorting has four parts: the Workspace to sort (1), past Sortings (2), Size reports (3) and Sizes & settings (4)." },
    { highlight: { button: "Sort all available eggs" }, then: { button: "Sort all available eggs" }, caption: "Each day with unsorted eggs is listed with its picks. Click \"Sort all available eggs\" (or \"Sort pick\" for one pick)." },
    { area: "dialog",
      fill: [
        { within: "dialog", css: SORT_BOXES, nth: 0, value: "900" },
        { within: "dialog", css: SORT_BOXES, nth: 1, value: "1000" },
        { within: "dialog", css: SORT_BOXES, nth: 2, value: "300" },
      ],
      caption: "Enter how many eggs went into each size. Put eggs you rejected or broke while sorting under Reject or Breakage." },
    { area: "dialog", highlight: [{ within: "dialog", text: "Left unsorted after" }, { within: "dialog", button: "Post sorting" }], optional: true, caption: "Check what is left unsorted (1), then click \"Post sorting\" (2). The sized eggs are now in stock to sell. \"Save draft\" keeps it for later." },
  ],

  // ---------------------------------------------------------- Sales & Customers
  "record-sale": [
    menu(BARS.money, "Sales", "/sales"),
    { highlight: [{ card: "Total Sales" }, { card: "Total Quantity" }, { card: "Average Sale" }], optional: true, caption: "Sales lists every sale. The cards show the money (1), the eggs sold (2) and the average sale (3) for the dates and customer you filter on." },
    { highlight: { button: "Add Sale" }, then: { button: "Add Sale" }, caption: "Click \"Add Sale\"." },
    { area: "dialog", pick: [{ within: "dialog", css: 'button[role="combobox"]', nth: 0 }],
      fill: [{ within: "dialog", css: 'input[type="number"]', nth: 1, value: "10" }, { within: "dialog", css: 'input[type="number"]', nth: 3, value: "50" }],
      highlight: { card: "Sale total" }, optional: true,
      caption: "Pick the customer and the date. For each product, choose the egg size and enter the boxes, crates or pieces. The price per crate fills in, and the sale total updates as you type." },
    { area: "dialog", highlight: { within: "dialog", text: "Add line" }, optional: true, caption: "Selling more than one size or product? Click \"Add line\" for each one; they are saved as one sale." },
    { area: "dialog", scrollTo: { within: "dialog", text: "Payment status" }, highlight: [{ within: "dialog", text: "Paid now", exact: true }, { within: "dialog", text: "Part payment", exact: true }, { within: "dialog", text: "Pay later", exact: true }], optional: true, caption: "How did they pay? Paid now (1) puts the money in a cash account. Part payment (2) records what they paid; the rest is owed. Pay later (3) adds it all to their balance. Then click \"Record sale\"." },
    menu(BARS.money, "Customer Balances", "/customer-balances"),
    { highlight: [{ card: "Total customer balance" }, { card: "Overdue balance" }], optional: true, caption: "Unpaid sales show up in Customer Balances: what all customers owe (1) and how much of it is overdue (2)." },
  ],
  "reverse-sale": [
    menu(BARS.money, "Sales", "/sales"),
    { highlight: [{ css: 'button[aria-label="View sale"]' }, { css: 'button[aria-label="Reverse sale"]' }], optional: true, caption: "A saved sale can't be edited or deleted. On its row, open it (1) to correct or reverse it, or reverse it straight away (2)." },
    { click: { css: 'button[aria-label="View sale"]' }, area: "dialog", highlight: [{ within: "dialog", button: "Correct sale" }, { within: "dialog", button: "Reverse sale" }], optional: true, then: { within: "dialog", button: "Reverse sale" }, caption: "\"Correct sale\" (1) reverses it and opens a new sale already filled in, for you to fix and save. \"Reverse sale\" (2) undoes it completely." },
    { area: "dialog", caption: "Pick the reason (Other needs a note). The dialog shows what will be undone: the eggs go back into stock, the debt is cleared, and money already paid is paid back from cash or kept as the customer's credit. The sale stays in the list, struck through." },
  ],
  "customer-payment": [
    menu(BARS.money, "Customer Payments", "/poultry-payments"),
    { highlight: [{ card: "Payments" }, { card: "Total received" }, { card: "Sales settled" }], optional: true, caption: "Customer Payments lists every payment received: how many (1), how much (2) and how many sales they settled (3)." },
    { highlight: { button: "Record customer payment" }, then: { button: "Record customer payment" }, caption: "Click \"Record customer payment\"." },
    { area: "dialog", pick: [{ within: "dialog", css: 'button[role="combobox"]', nth: 0, option: "man" }], highlight: { within: "dialog", button: "Next" }, optional: true, then: { within: "dialog", button: "Next" }, caption: "Choose the customer who paid, then click \"Next\"." },
    { area: "dialog", caption: "Enter the amount, how they paid and into which cash account. Then apply it to their open sales, oldest first. Anything you don't apply is kept as their credit." },
  ],
  "old-debt": [
    menu(BARS.money, "Customer Balances", "/customer-balances"),
    { highlight: [{ card: "Total customer balance" }, { card: "Customers owing" }, { card: "Overdue balance" }], optional: true, caption: "Customer Balances shows who owes you: the total (1), how many customers (2) and what is overdue (3)." },
    { highlight: { button: "Receive payment" }, optional: true, caption: "Each customer is one row. When they pay, click \"Receive payment\" on their row." },
    { highlight: { button: "Record customer debt" }, then: { button: "Record customer debt" }, caption: "For money they owed before you started using the app, an owner or admin clicks \"Record customer debt\"." },
    { area: "dialog", pick: [{ within: "dialog", css: 'button[role="combobox"]', nth: 0 }],
      fill: [{ within: "dialog", placeholder: "e.g. Eggs supplied before we started using the system", value: "Eggs supplied in October, before we used the app" }],
      caption: "Pick the customer and the date the debt started. Enter the amount, why it is owed (opening balance, for example) and a description. It is added to their balance like an unpaid sale." },
  ],

  // ---------------------------------------------------------- Expenses & Purchases
  "add-expense": [
    menu(BARS.money, "Expenses", "/expenses"),
    { highlight: [{ card: "This Month" }, { card: "Total (Filtered)" }], optional: true, caption: "Expenses lists everything the farm spent: this month (1) and the total for your filters (2). Filter by date, category, flock or cash account above." },
    { highlight: [{ button: "Add Expense" }, { button: "Repeat previous" }], optional: true, then: { button: "Add Expense" }, caption: "Click \"Add Expense\" (1). \"Repeat previous\" (2) copies an expense you record often." },
    { area: "dialog", highlight: { card: "Flock & Date" }, optional: true, caption: "Flock & Date (1): choose a flock if the cost is for one flock (or leave it farm-wide), and the date it was spent." },
    { area: "dialog", fill: [{ within: "dialog", placeholder: "0.00", value: "250" }], highlight: { card: "Category & Payment" }, optional: true, caption: "Category & Payment: choose the category, enter the amount and how it was paid. Pick the cash account it came out of, so your cash balance stays right." },
    { area: "dialog", highlight: [{ card: "Supplier & Payment Status" }, { within: "dialog", button: "Create Expense" }], optional: true, caption: "Choose who it was paid to and whether it is paid (1). An unpaid expense gets a due date and is owed to that supplier. Then click \"Create Expense\" (2)." },
  ],
  "recurring-expense": [
    menu(BARS.tools, "Recurring Expenses", "/recurring-expenses"),
    { highlight: [{ css: 'button:has-text("To review")' }, { css: 'button:has-text("Upcoming")' }, { css: 'button:has-text("Templates")' }], optional: true, caption: "Recurring Expenses keeps costs that repeat, like rent, security and internet. \"To review\" (1) holds the ones due now, \"Upcoming\" (2) the next ones, \"Templates\" (3) the list you set up." },
    { highlight: [{ button: "Review" }, { button: "Post" }, { button: "Skip" }], optional: true, caption: "For each one due: \"Review\" (1) to check or change the amount, \"Post\" (2) to record it as an expense, or \"Skip\" (3) this time." },
    { highlight: { button: "New recurring expense" }, then: { button: "New recurring expense" }, caption: "To add one, click \"New recurring expense\"." },
    { area: "dialog", fill: [{ within: "dialog", placeholder: "e.g. Office rent", value: "Security guard" }, { within: "dialog", css: 'input[type="number"]', nth: 0, value: "500" }], caption: "Name it, choose the category and payee, and enter the amount. Turn on \"Amount varies\" for bills like electricity." },
    { area: "dialog", scrollTo: { within: "dialog", text: "When it falls due" }, highlight: { within: "dialog", text: "Draft for review (recommended)" }, optional: true, caption: "Set how often it repeats and the first due date. Keep \"Draft for review\" so nothing is recorded without you checking it." },
  ],
  "which-purchase": [
    menu(BARS.ops, "Inventory & Supply Purchases", "/poultry-supply-purchases"),
    { highlight: [{ card: "Stock value" }, { card: "Low stock" }, { card: "Outstanding" }], optional: true, caption: "Supply Purchases: what you hold in stock (1), what is running low (2) and what you still owe suppliers (3)." },
    { highlight: { css: 'button[aria-label="Reverse purchase"]' }, optional: true, caption: "Entered a purchase wrongly? It is reversed, not deleted: click the reverse arrow on its row, pick a reason and check what will be undone. A purchase whose stock is already used can't be reversed." },
    { highlight: { button: "Record Purchase" }, then: { button: "Record Purchase" }, caption: "For one item from one supplier, click \"Record Purchase\"." },
    { area: "dialog", caption: "Pick the item and supplier, enter the quantity and price, and how much you paid now." },
    menu(BARS.tools, "Receive Purchase", "/poultry-purchase-receipts"),
    { highlight: { button: "Receive purchase" }, then: { button: "Receive purchase" }, caption: "For one supplier invoice with several items, click \"Receive purchase\"." },
    { area: "dialog", caption: "Add a line for each item on the invoice, plus extra costs like transport. The extra costs are shared across the items." },
    menu(BARS.money, "Supplier Payments", "/supplier-payments"),
    { highlight: [{ card: "Total paid" }, { button: "Record supplier payment" }], optional: true, then: { button: "Record supplier payment" }, caption: "Supplier Payments lists what you have paid suppliers (1). To pay money you already owe, click \"Record supplier payment\" (2)." },
    { area: "dialog", caption: "Choose the supplier you paid and click \"Next\". Then enter the amount and the cash account, and apply it to what you owe them. Anything not applied is kept as supplier credit." },
  ],
  "internal-use": [
    menu(BARS.money, "Internal Use", "/poultry-internal-use"),
    { highlight: [{ card: "Records" }, { card: "Posted cost" }], optional: true, caption: "Internal Use lists eggs, birds or supplies the farm used instead of selling: how many records (1) and what they cost (2)." },
    { highlight: { button: "Record internal use" }, then: { button: "Record internal use" }, caption: "Click \"Record internal use\"." },
    { area: "dialog", caption: "Set the date and the reason (staff allowance, farm use, donation, sample) and, if you like, who received it." },
    { area: "dialog", scrollTo: { within: "dialog", text: "Number of staff" }, fill: [{ within: "dialog", css: 'input[type="number"]', nth: 0, value: "6" }, { within: "dialog", css: 'input[type="number"]', nth: 1, value: "1" }], caption: "Pick the product and how it was given out (eggs or crates). For a staff allowance, enter the number of staff and how much each got." },
    { area: "dialog", scrollTo: { within: "dialog", text: "Cancel" }, caption: "The cost is shown before you save. Stock goes down and the cost is booked as an expense. It is not a sale and no cash moves." },
  ],

  // ---------------------------------------------------------- Money & Reports
  "egg-cost": [
    menu(BARS.tools, "Egg Cost & Profit Analyzer", "/egg-cost-analyzer"),
    { highlight: [{ text: "Period", exact: true }, { text: "Analyse", exact: true }, { text: "Cost definition", exact: true }], optional: true, caption: "Choose the period (1), what to analyse: the whole farm, one batch or one flock (2), and full or direct cost (3)." },
    { highlight: [{ card: "Cost per saleable egg" }, { card: "Avg selling price / crate" }, { card: "Estimated margin / crate" }], optional: true, caption: "The top cards show what one saleable egg cost you (1), what you sold a crate for (2) and the margin left on each crate (3)." },
    { scrollTo: { text: "Data completeness" }, highlight: { card: "Data completeness" }, optional: true, caption: "\"Data completeness\" says what was missing for the period, such as days with no feed recorded. A missing cost makes eggs look cheaper than they are." },
    { click: { tab: "What-If scenario" }, highlight: { tab: "What-If scenario" }, optional: true, caption: "\"What-If scenario\" lets you change feed price, laying rate or selling price and see the new cost and margin per crate. Nothing on the farm changes." },
  ],
  "daily-closing": [
    menu(BARS.tools, "Daily Closing", "/poultry-daily-closing"),
    { highlight: [{ css: 'input[type="date"]' }, { card: "Production" }, { card: "Sales" }], optional: true, caption: "Daily Closing checks one business day (1). It adds up production (2), and sales and money (3), for that day." },
    { highlight: [{ text: "Must fix" }, { text: "Warnings" }], optional: true, caption: "The checklist says what is missing. Must fix (1) blocks the closing; Warnings (2) don't. Click \"Resolve\" next to an item to go to the page that fixes it." },
    { highlight: { button: "Close Business Day" }, optional: true, caption: "When nothing is left under Must fix, an approver clicks \"Close Business Day\". Anyone else submits the day for approval." },
    { click: { text: "Previous closings" }, highlight: { text: "Previous closings" }, optional: true, caption: "\"Previous closings\" lists the days already closed and who closed them." },
  ],
  "reports-exports": [
    menu(BARS.reports, "View all reports", "/poultry/reports"),
    { highlight: [{ text: "Sales, Money & Profit" }, { text: "Production & Eggs" }, { text: "Feed, Birds & Health" }], optional: true, caption: "Every report in one place, grouped into money (1), production (2), and feed, birds and health (3). Click any report to open it." },
    menu(BARS.money, "Profit & Loss", "/poultry-profit-loss"),
    { highlight: [{ text: "Period", exact: true }, { button: "CSV" }, { button: "Email" }, { button: "PDF" }], optional: true, caption: "Profit & Loss: choose the period (1). Export to CSV for Excel (2), email it (3) or download a PDF (4)." },
    { scrollTo: { text: "Revenue" }, highlight: { card: "Revenue" }, optional: true, caption: "Below the totals, each part is broken down: revenue, production costs, operating expenses and depreciation. Click a line to see the records behind it." },
  ],
  // ---------------------------------------------------------- Account & Access
  "switch-company": [
    { path: "/sales", highlight: { css: 'button[aria-label="Switch company"]' }, then: { css: 'button[aria-label="Switch company"]' }, caption: "The company you are working in is shown at the top of every page. Click it to switch." },
    { caption: "Pick the company you want; you land on its dashboard. Only the account owner can create a new company." },
  ],
  "add-user": [
    menu(BARS.setup, "Users & Permissions", "/employees"),
    { highlight: { button: "Add Employee" }, then: { button: "Add Employee" }, mask: [LIST_ROWS], caption: "Users & Permissions lists everyone who can log in. To give a worker their own login, click \"Add Employee\"." },
    { area: "dialog", mask: [{ css: 'input[name="password"]' }, { css: 'input[name="confirmPassword"]' }],
      fill: [
        { within: "dialog", css: 'input[name="firstName"]', value: "Ama" },
        { within: "dialog", css: 'input[name="lastName"]', value: "Mensah" },
        { within: "dialog", css: 'input[name="userName"]', value: "ama_mensah" },
      ],
      caption: "Pick the company, then fill in their name, phone, username and email. A password is made for you; give it to them." },
    { area: "dialog", scrollTo: { within: "dialog", text: "Create as administrator" }, highlight: { within: "dialog", text: "Create as administrator" }, optional: true, caption: "Switch on \"Create as administrator\" only for someone who should manage setup and money. Admins can do everything." },
    { area: "dialog", scrollTo: { within: "dialog", text: "Staff Page Access" }, highlight: { within: "dialog", text: "Staff Page Access" }, optional: true, caption: "Everyone else is staff and starts with access to nothing. Under \"Staff Page Access\", switch on only the pages they need, then save." },
  ],
}
