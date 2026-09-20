# Split Chat

> This README is the reference document for the project. It explains what the app is, how it is built, and how it functions in enough detail for another developer (human or AI) to understand, maintain, or extend the codebase.

---

## 1. Overview

**Split Chat** is a Flutter mobile application for **tracking shared expenses** with an optional **splitting** feature, plus a simple built-in **chat**. It is local-first: there is **no backend, no accounts, and no network** — all data is stored on the device and survives restarts.

The app's purpose:

- Be a group **expense tracker** where several people (the recorded members) maintain **one shared list** of expenses.
- Allow an expense to be either **tracked only** (who paid, how much, when) or **split** among people (equal or manual shares).
- Maintain a **history trail** — every add / edit / delete is logged **with the name of the person** who did it, both per-expense and in a global activity log.
- Compute **balances** and a minimal set of **settlements** ("who owes whom") but only from split expenses.
- Provide a trivial **local chat** tab.

---

## 2. Tech stack

| Layer        | Choice                                                        |
|--------------|---------------------------------------------------------------|
| Language     | Dart (SDK constraint `^3.13.2`)                                |
| Framework    | Flutter (verified with 3.47.x / Dart 3.13.x)                  |
| UI           | Material 3 (`ColorScheme.fromSeed`, teal seed)                |
| Persistence  | `shared_preferences ^2.5.3` (JSON string)                     |
| State        | `ChangeNotifier` (`AppStore`) + `ListenableBuilder`           |
| Linting      | `flutter_lints ^6.0.0`                                        |
| Tests        | `flutter_test` (unit tests, no widget tests)                  |

Run with `flutter run`. Static analysis: `flutter analyze`. Tests: `flutter test`.

---

## 3. Project structure

```
split_chat/
├── pubspec.yaml
├── lib/
│   ├── main.dart                        # App entry, tab shell
│   ├── models/
│   │   └── expense.dart                 # Expense, ExpenseChange data model
│   ├── utils/
│   │   └── money.dart                   # paise (integer) money math + formatting
│   ├── store/
│   │   └── app_store.dart               # AppStore (ChangeNotifier), Activity, Settlement
│   ├── screens/
│   │   ├── splits_screen.dart           # Splits tab: tracking, splits, history, dialogs
│   │   └── chat_screen.dart             # Chat tab: local message list
│   └── firebase_options.dart            # Unwired stub (see §10)
└── test/
    └── splits_test.dart                 # 11 unit tests for model + store logic
```

---

## 4. Data model

### 4.1 `Expense` (`lib/models/expense.dart`)

One record that is either a tracked expense or a split bill.

| Field          | Type                      | Meaning                                                    |
|----------------|---------------------------|------------------------------------------------------------|
| `id`           | `String`                  | Unique id. New: `DateTime.now().microsecondsSinceEpoch`.   |
| `title`        | `String`                  | What the expense is for.                                   |
| `amountPaise`  | `int`                     | Amount, stored in **paise** (₹1 = 100). See §5.            |
| `split`        | `bool`                    | `true` if split among people, `false` for tracking-only.   |
| `paidBy`       | `String?`                 | The member who paid (only meaningful when `split`).        |
| `sharesPaise`  | `Map<String,int>`         | Member → amount owed, **only for split** expenses.         |
| `date`         | `DateTime`                | Expense date (default today).                              |
| `addedBy`      | `String`                  | Name of the person who created the record.                 |
| `changes`      | `List<ExpenseChange>`     | Per-expense history of edits (oldest first).               |

Behaviors:

- `factory Expense.equalSplit(...)` — builds a split expense equally over `members`:
  `share = amountPaise ~/ n`; the remainder `amountPaise - share*n` is added to the **last** member, so shares always sum exactly to `amountPaise`.
- `bool get isEqualSplit` — heuristic for "equal" shares: true when `max - min <= amountPaise % n`. Any uneven split is then identified as manual.
- `toJson()` / `factory fromJson()` — full serialization; `fromJson` tolerates missing keys for backward compatibility (old saved data without `split`/`changes`/`addedBy` still loads; `split` defaults to `sharesPaise.isNotEmpty`).

### 4.2 `ExpenseChange` (same file)

```dart
ExpenseChange { String by; String change; DateTime at; }
```

A human-readable audit line, e.g. `by: 'Meera'`, `change: 'Amount: ₹100.00 → ₹150.00'`.

### 4.3 `Activity` (`lib/store/app_store.dart`)

Global event-log entry:

```dart
Activity { String by; String verb; String title; int? amountPaise; DateTime at; }
```

`verb` is one of `'added' | 'edited' | 'deleted'`. Kept **newest-first** in `AppStore.activity`.

### 4.4 `Settlement` (same file)

```dart
Settlement { String from; String to; int amountPaise; }
```

One transfer instruction, e.g. `B pays A ₹100.00`.

---

## 5. Money handling (important)

All money is represented as integer **paise** to avoid floating-point errors
(`0.1 + 0.2`-type problems). The UI converts user input to paise and formats paise back.

`lib/utils/money.dart`:

| Function                       | Behavior                                           |
|--------------------------------|----------------------------------------------------|
| `toPaise(double rupees)`       | `(rupees * 100).round()` — input → integer paise   |
| `fmtPaise(int paise)`          | Signed, formatted `-₹1234.50` / `₹0.05`            |
| `paiseToInput(int paise)`      | `(paise / 100).toStringAsFixed(2)` for pre-filling text fields |
| `fmtShares(Map<String,int>)`   | `"A: ₹50.00 · B: ₹50.00"` for share summaries/history |

---

## 6. Core logic (`lib/store/app_store.dart`)

### 6.1 `AppStore` (a `ChangeNotifier`)

Holds all state and is the single source of truth:

- `members: List<String>`
- `expenses: List<Expense>`
- `activity: List<Activity>` (newest first)
- `currentUser: String` — "who am I acting as" (used to stamp every history entry)

Every mutating method calls `_commit()` → `notifyListeners()` + async `save()`.

Public API:

| Method                          | Effect                                                    |
|---------------------------------|-----------------------------------------------------------|
| `load()`                        | Reads saved JSON; seeds `['Aarav','Meera']` if empty.     |
| `save()`                        | Writes JSON under key `split_chat_store`.                 |
| `setCurrentUser(name)`          | Switches acting identity.                                 |
| `addMember(name)`               | Adds member (no-op if duplicate/empty).                   |
| `removeMember(name)`            | Removes member **and strips their entry from all shares**. |
| `addExpense(e)`                 | Adds expense + logs `added` activity (by `e.addedBy`).    |
| `replaceExpense(e)`             | Diffs old vs new, appends `ExpenseChange` per diff (by `currentUser`), logs `edited` activity if anything changed. |
| `removeExpense(id)`             | Removes expense + logs `deleted` activity (by `currentUser`) with a snapshot of title/amount. |
| `clearActivity()`               | Empties the activity log (expenses untouched).            |
| `balances()`                    | Net balance per member (see below).                       |
| `settle()`                      | Minimal-transfer settlement list (see below).             |

### 6.2 Balances

`balances()` returns `Map<String,int>` (member → net paise), computed **only from split expenses**:

```
for each expense where split == true:
    balances[paidBy]        += amountPaise      # payer is credited the whole bill
    for (member, share) in sharesPaise:
        balances[member]    -= share            # each sharer is debited their share
```

Positive = is owed money. Negative = owes money. Tracking-only expenses never touch balances.

### 6.3 Settlement

`settle()` nets balances into the fewest practical transfers:

1. Debtors = members with negative balance, sorted most-negative first.
2. Creditors = members with positive balance, sorted most-positive first.
3. For each debtor, greedily transfer the minimum of (remaining debt, available credit) to the current creditor, moving to the next creditor once one is full.

Result is a `List<Settlement>`. Everyone settled ⇒ empty list.

---

## 7. Persistence format

Two `shared_preferences` keys:

**`split_chat_store`** (AppStore), a JSON object:

```json
{
  "members": ["Aarav", "Meera"],
  "expenses": [
    {
      "id": "...",
      "title": "Lunch",
      "amountPaise": 10000,
      "split": true,
      "paidBy": "Aarav",
      "sharesPaise": {"Aarav": 5000, "Meera": 5000},
      "date": "2026-09-20T00:00:00.000",
      "addedBy": "Aarav",
      "changes": [
        {"by": "Meera", "change": "Amount: ₹100.00 → ₹150.00", "at": "2026-09-21T10:00:00.000"}
      ]
    }
  ],
  "currentUser": "Aarav",
  "activity": [
    {"by": "Aarav", "verb": "added", "title": "Lunch", "amountPaise": 10000, "at": "2026-09-20T08:00:00.000"}
  ]
}
```

**`split_chat_messages`** (ChatScreen), a JSON list of `{"text": "...", "mine": true|false}`.

On `load()`, if no store data exists, the app seeds `members = ['Aarav','Meera']` and `currentUser = 'Aarav'`. `currentUser` is forced onto a member if it is absent from `members`.

---

## 8. Screens & user flows

### 8.1 Tab shell (`lib/main.dart`)

- `IndexedStack` keeps both tabs alive / state preserved.
- **Splits is the default (first) tab**; Chat is second.
- `AppStore` is created in `_HomeScreenState` and `load()`ed on startup; passed to `SplitsScreen`.

### 8.2 Splits tab (`lib/screens/splits_screen.dart`)

Renders via `ListenableBuilder` on the store. A `ListView` of sections, top to bottom:

1. **Expenses** header (+ add button), with "Total tracked" line.
2. **Expense cards** — one per expense:
   - Leading icon: `receipt_long` (primary color) when split, `receipt` (outlined) when tracking-only.
   - Subtitle: `"{paidBy} paid · {date}"` (split) or `"Tracking only · {date}"`.
   - Tap → detail bottom sheet (§8.4). Trailing `⋮` menu → **Edit** / **Delete**.
3. **History** — an `ExpansionTile`, collapsed by default, showing event count. When expanded: a **Clear history** button (with confirmation) and the activity feed (newest ~30), each line color-coded (green add, amber edit, red delete) as `"{by} {verb} “{title}” · ₹amount · date"`.
4. **People** — chips with initial avatars; `+` adds; deleting a chip removes the member from the group and strips them from all expense shares.
5. **Balances (from split expenses)** — per-member net, green when owed, red when owing, grey at zero.
6. **Who owes whom** — settlement transfers, or "All settled up!".

**AppBar**: title "Shared expenses", and a person-icon menu labeled **"Managing as"** where the acting user is picked (check-mark on the active member). This name stamps all history entries.

**Add-person dialog** — single text prompt.

### 8.3 Expense add/edit dialog (`showExpenseDialog`)

A single dialog is used for both add and edit (edit pre-fills everything and preserves `addedBy` and existing `changes`). Guarded against opening when there are no members.

Fields:

- **What for?** (title, required)
- **Amount** (₹; `toPaise` conversion; must be > 0)
- **Date** — tappable field opening a `DatePicker` (2020 → today+1yr)
- **Split this expense** — a `SwitchListTile`. Default **on** for new expenses.
  - **Off**: expense is tracking-only → no paidBy / no shares; note text "Just tracking this expense — no money split."
  - **On**: shows **Paid by** dropdown (member) and a **Split equally / Manual** `SegmentedButton`.
    - *Equal*: built via `Expense.equalSplit` (all members).
    - *Manual*: one text field per member pre-filled with equal amounts; live validation that shares sum to the bill — with an inline red error, otherwise Save is disabled.

Save is enabled only when: amount > 0, title non-empty, shares sum correctly (manual), and members exist.

On create: `id = microsecondsSinceEpoch`, `addedBy = currentUser`. On edit: id/addedBy/changes are preserved from the existing expense.

### 8.4 Expense detail sheet

Bottom sheet (scrollable, drag handle) when tapping an expense:

- Title + big amount.
- **Meta chips**: split status (`Split · paid by X` or `Tracking only`), date, `Added by X`.
- If split: card listing each sharer's owed amount. If not: note that nothing was split.
- **Edit** and **Delete** buttons (delete asks for confirmation).
- **History** `ExpansionTile` (collapsed) with the "Added expense" line plus each recorded `ExpenseChange` (`{by}` + `{change}` + date), one row per event.

### 8.5 Chat tab (`lib/screens/chat_screen.dart`)

- Local message list; persisted under `split_chat_messages`.
- Renders as alignment bubbles (right = mine, left = others), Material 3 colors.
- Sticky input bar with send button (`IconButton.filled`); send persists.
- Seeds three demo messages on first ever run.

---

## 9. Testing (`test/splits_test.dart`)

Pure-logic unit tests (no widgets; `SharedPreferences.setMockInitialValues`):

1. `Expense.equalSplit` — remainder handling (101 paise / 3 → 33,33,35; sums exact).
2. `Expense.equalSplit` — single member gets the full amount.
3. `Expense.split` flag — tracking-only has no `paidBy` nor shares.
4. `balances` — equal split credits payer / debits others.
5. `balances` — manual split honours custom shares.
6. `balances` — tracking-only expense does not affect balances nor settlements.
7. `settle` — nets debts into minimal transfers.
8. `settle` — no transfers when everyone is settled.
9. History — `addExpense` logs who added it.
10. History — `replaceExpense` appends diffs stamped with who edited.
11. History — `removeExpense` leaves a delete activity record.

Run: `flutter test` → currently **11/11 pass**.

---

## 10. Known state / notes for future work

- **`lib/firebase_options.dart` exists but is NOT wired in.** It imports `package:firebase_core` and fails `flutter analyze` (firebase_core is not in `pubspec.yaml`). It is leftover work-in-progress for a possible future backend and is not referenced by app code. Either remove it or add Firebase to make analysis green.
- **Single-device only.** "Shared" currently means multiple members collaborate on one device; changes are not synchronized across devices. True multi-user editing requires a backend (e.g., Firestore/Firebase) and is the natural next step given the existing activity/history model.
- **Delete is destructive.** Deleting a member strips them from shares; deleting an expense removes the expense but leaves its activity record in the history log.
- **Settlement** is a greedy approximation (pairs biggest debtor with biggest creditor). It is optimal in practice for small groups but is not a mathematically guaranteed minimum.
- Activity feed shows the most recent 30 events; per-expense history is unbounded.

---

## 11. Quick reference: how the flow ties together

```
User picks "Managing as" name ───────────────► AppStore.currentUser
                                                       │
Tap + (Expense dialog) ──► Expense{ title, amountPaise,
    split? (equal/manual), date, paidBy, addedBy }
                                                       │
AppStore.addExpense ──► expenses[] + activity["added" by addedBy]
                                                       │
Tap expense (detail sheet) ──► shows shares + history
    │  "Edit" ──► replaceExpense ──► diffs → per-expense changes[]
    │              (stamped "edited by currentUser") + activity["edited"]
    │  "Delete"──► removeExpense ──► activity["deleted"]
                                                       │
balances() ←─ split expenses only ──► settle() ──► "who owes whom"
                                                       │
Everything persists via _commit() → save() → shared_preferences
```