# Split Chat

> This README is the reference document for the project. It explains what the app is, how it is built, and how it functions in enough detail for another developer (human or AI) to understand, maintain, or extend the codebase.

---

## 1. Overview

**Split Chat** is a Flutter mobile application for **tracking shared expenses** with an optional **splitting** feature, plus a simple built-in **chat**.

It is **cloud-backed with accounts**: users sign up with email + password, data lives in **Firebase Firestore**, and changes sync across devices in real time. There are two roles:

- **Admin** — the first registered user. Can edit/delete *any* expense, clear the activity log, and manage users & roles.
- **Member** — every later signup. Can add expenses and edit/delete **only their own** (an expense's `ownerId` == their uid).

The app's purpose:

- Be a group **expense tracker** where signed-in people maintain **one shared list** of expenses, synced to Firestore.
- Allow an expense to be either **tracked only** (who paid, how much, when) or **split** among people (equal or manual shares).
- Maintain a **history trail** — every add / edit / delete is logged **with the name of the person** who did it, both per-expense and in a global activity log.
- Compute **balances** and a minimal set of **settlements** ("who owes whom") but only from split expenses.
- Provide a real-time **chat** tab.

---

## 2. Tech stack

| Layer        | Choice                                                                 |
|--------------|------------------------------------------------------------------------|
| Language     | Dart (SDK constraint `^3.13.2`)                                         |
| Framework    | Flutter (verified with 3.47.x / Dart 3.13.x)                            |
| UI           | Material 3 (`ColorScheme.fromSeed`, teal seed)                         |
| Backend      | Firebase (Firebase Auth + Cloud Firestore)                             |
| State        | `ChangeNotifier` (`AppStore`) + `ListenableBuilder` / `StreamBuilder`  |
| Linting      | `flutter_lints ^6.0.0`                                                 |
| Tests        | `flutter_test` (pure-logic unit tests, no widgets)                     |

Packages: `firebase_core 4.15.0`, `firebase_auth 6.7.0`, `cloud_firestore 6.10.0`

Run with `flutter run`. Static analysis: `flutter analyze`. Tests: `flutter test` (currently **16/16 pass**).

---

## 3. Project structure

```
split_chat/
├── pubspec.yaml
├── firebase.json                       # Firestore rules deploy config
├── firestore.rules                     # Firestore security rules
├── lib/
│   ├── main.dart                       # Entry: Firebase init, auth gate, tab shell
│   ├── firebase_options.dart           # Auto-generated Firebase config (project split-chat-007)
│   ├── auth/
│   │   └── auth_service.dart           # Sign-up (first user becomes admin)
│   ├── models/
│   │   ├── expense.dart                # Expense, ExpenseChange data model
│   │   └── models.dart                 # UserProfile, Activity, ChatMessage
│   ├── logic/
│   │   └── split_logic.dart            # Pure functions: balances, settlements, diffs
│   ├── utils/
│   │   └── money.dart                  # paise (integer) money math + formatting
│   ├── store/
│   │   └── app_store.dart              # AppStore (ChangeNotifier) with Firestore streams
│   └── screens/
│       ├── auth_screen.dart            # Login / sign-up screen
│       ├── splits_screen.dart          # Splits tab: tracking, splits, history, dialogs
│       ├── admin_panel_screen.dart     # Manage users & roles (admin only)
│       └── chat_screen.dart            # Chat tab: Firestore message list
└── test/
    └── splits_test.dart                # 16 unit tests for model + pure logic
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
| `ownerId`      | `String`                  | Firebase Auth uid of the creator; used for permissions.    |
| `changes`      | `List<ExpenseChange>`     | Per-expense history of edits (oldest first).               |

Behaviors:

- `factory Expense.equalSplit(...)` — builds a split expense equally over `members`:
  `share = amountPaise ~/ n`; the remainder `amountPaise - share*n` is added to the **last** member, so shares always sum exactly to `amountPaise`.
- `bool get isEqualSplit` — heuristic for "equal" shares: true when `max - min <= amountPaise % n`. Any uneven split is then identified as manual.
- `toMap()` / `factory fromMap()` — Firestore-friendly serialization. Dates are stored as `DateTime` (the store layer converts to/from Firestore `Timestamp`); `fromMap` tolerates missing keys.

### 4.2 `ExpenseChange` (same file)

```dart
ExpenseChange { String by; String change; DateTime at; }
```

A human-readable audit line, e.g. `by: 'Meera'`, `change: 'Amount: ₹100.00 → ₹150.00'`.

### 4.3 Shared models (`lib/models/models.dart`)

```dart
UserProfile { String uid; String email; String name; String role; bool get isAdmin; }
Activity   { String by; String byUid; String verb; String title; int? amountPaise; DateTime at; }
ChatMessage{ String id; String text; String by; String byUid; DateTime at; }
```

- `Activity.verb` is one of `'added' | 'edited' | 'deleted'`, kept **newest-first**.
- `UserProfile.role` is `'admin'` or `'member'` (any other value reads as member).

### 4.4 `Settlement` (`lib/logic/split_logic.dart`)

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

## 6. Core logic (`lib/logic/split_logic.dart`)

Pure, side-effect-free functions (kept out of the store so they stay unit-testable):

- `computeBalances(List<String> members, List<Expense> expenses) → Map<String,int>`
- `computeSettlements(...) → List<Settlement>`

### 6.1 Balances

Computes net paise **only from split expenses**:

```
for each expense where split == true:
    balances[paidBy]        += amountPaise      # payer is credited the whole bill
    for (member, share) in sharesPaise:
        balances[member]    -= share            # each sharer is debited their share
```

Positive = is owed money. Negative = owes money. Tracking-only expenses never touch balances.

### 6.2 Settlement

Nets balances into a minimal practical set of transfers:

1. Debtors = members with negative balance, sorted most-negative first.
2. Creditors = members with positive balance, sorted most-positive first.
3. For each debtor, greedily transfer the minimum of (remaining debt, available credit) to the current creditor, moving to the next creditor once one is full.

Result is a `List<Settlement>`. Everyone settled ⇒ empty list.

### 6.3 `diffExpenses(before, after) → List<String>`

Human-readable list of what changed between two versions of the same expense
(title, amount, paidBy, shares, date, split flag). Used to build per-expense
`ExpenseChange` audit lines on edit.

---

## 7. Persistence & real-time sync (Firestore)

Firestore collections in project **split-chat-007**:

| Collection  | Doc / doc-id      | Fields                                            | Ordering        |
|-------------|-------------------|---------------------------------------------------|-----------------|
| `users`     | `{uid}`           | `name`, `email`, `role`                          | —               |
| `expenses`  | `{expense.id}`    | same as `Expense.toMap()`, `date`/`changes.at` as `Timestamp` | `date` desc |
| `activity`  | auto              | `by`, `byUid`, `verb`, `title`, `amountPaise`, `at` (`serverTimestamp`) | `at` desc, limit 50 |
| `messages`  | auto              | `text`, `by`, `byUid`, `at` (`serverTimestamp`)  | `at` asc        |

### 7.1 `AppStore` (`lib/store/app_store.dart`, a `ChangeNotifier`)

The store holds the synced lists and exposes the signed-in identity:

- **State**: `users`, `expenses`, `activity`, `messages` (all `List`), plus `_profile` (the signed-in user's `UserProfile`).
- **Identity getters**: `myUid`, `myName`, `isAdmin`, `loaded`.
- **Derived**: `members` = `[u.name for u in users]`, `canEdit(e)` / `canDelete(e)` = `isAdmin || e.ownerId == myUid`.

Data flow: `init()` attaches a Firestore `.snapshots()` stream per collection; each stream rebuilds its list and calls `notifyListeners()`. Writes go straight to Firestore and the UI updates live via the streams.

Public API:

| Method            | Effect                                                     |
|-------------------|------------------------------------------------------------|
| `init()`          | Subscribes to the four collection streams.                  |
| `addExpense(e)`   | Writes `expenses/{id}` (stamps `addedBy = myName`, `ownerId = myUid`), logs `added` activity. |
| `replaceExpense(e)`| Diffs the saved doc vs new, appends an `ExpenseChange` per diff (by `myName`), logs `edited`. |
| `removeExpense(id)`| Deletes the doc if `canEdit`, logs `deleted`.               |
| `clearActivity()` | Empties the `activity` collection.                          |
| `sendMessage(t)`  | Adds a message doc (stamped `by`/`byUid`).                  |
| `setRole(uid, role)` | Updates a user's `role` (`'admin'`/`'member'`).          |
| `removeUser(uid)` | Deletes a `users/{uid}` doc (keeps their expenses' history).|

### 7.2 Auth (`lib/auth/auth_service.dart`)

- Sign-in: plain `FirebaseAuth.instance.signInWithEmailAndPassword` from the login form.
- Sign-up (`AuthService.signUp(name, email, password)`): creates the Auth user, sets `displayName`, then reads the `users` collection — **if it is empty the new user becomes `admin`, otherwise `member`** — and writes `users/{uid}` with `{name, email, role}`.
- `lib/main.dart` uses `FirebaseAuth.instance.authStateChanges()` in a `StreamBuilder` (`AuthGate`) to swap between `AuthScreen` and `HomeScreen`. `HomeScreen` creates the `AppStore`, calls `init()` and disposes it.

Reverse-auth note: there is no "admin creates the other users" flow. Clients can only create their own account (using FirebaseAuth's client API would hijack the session). An admin instead *assigns roles* to people after they sign up.

---

## 8. Screens & user flows

### 8.1 Auth gate (`lib/main.dart`)

- `main()` initializes Firebase with `DefaultFirebaseOptions.currentPlatform`, then runs the app.
- `AuthGate` → `StreamBuilder` on `authStateChanges()`: `waiting` = spinner; `null` = `AuthScreen`; signed in = `HomeScreen`.
- `HomeScreen` owns the `AppStore` and an `IndexedStack` with **Splits (default tab)** and **Chat**, plus a `NavigationBar`.

### 8.2 Auth screen (`lib/screens/auth_screen.dart`)

Toggle between **Sign in** and **Create account**:

- Sign-in: email + password.
- Sign-up: name + email + password. Notes that the first user becomes the admin.
- Maps `FirebaseAuthException` codes to friendly messages (wrong password, email in use, weak password, invalid email, …).
- On success the auth stream flips the UI automatically (SharedPreferences-free).

### 8.3 Splits tab (`lib/screens/splits_screen.dart`)

Renders via `ListenableBuilder` on the store. A `ListView` of sections, top to bottom:

1. **Expenses** header (+ add button), with "Total tracked" line.
2. **Expense cards** — one per expense:
   - Leading icon: `receipt_long` (primary color) when split, `receipt` (outlined) when tracking-only.
   - Subtitle: `"{paidBy} paid · {date}"` (split) or `"Tracking only · {date}"`.
   - Tap → detail bottom sheet (§8.5). Trailing `⋮` menu → **Edit** / **Delete**, shown **only when `store.canEdit(e)`** (member's own or admin). Others get no menu.
3. **History** — an `ExpansionTile`, collapsed by default, showing the event count. When expanded: a **Clear history** button (admin only, with confirmation) and the activity feed (newest 50), each line color-coded (green add, amber edit, red delete) as `"{by} {verb} “{title}” · ₹amount · date"`.
4. **People** — chips with initial avatars from `store.users`, role marked as `"(admin)"`. Admin-only delete (`onDeleted`) on anyone except yourself; no generic "add person" (users come from sign-up).
5. **Balances (from split expenses)** — per-member net, green when owed, red when owing, grey at zero.
6. **Who owes whom** — settlements computed via `computeSettlements(store.members, store.expenses)`, or "All settled up!".

**AppBar**: title "Shared expenses" and an account menu showing `"Name · Admin|Member"` with **Manage users & roles** (admin only → `AdminPanelScreen`) and **Sign out**.

### 8.4 Admin panel (`lib/screens/admin_panel_screen.dart`)

- Lists every signed-up user with their role.
- For any user other than yourself: toggle role (member ↔ admin) and remove them (confirmation dialog). You cannot demote/remove yourself.
- Shows a note about keeping at least one admin when multiple exist.

### 8.5 Expense add/edit dialog (`showExpenseDialog`)

A single dialog is used for both add and edit (edit pre-fills everything and preserves `addedBy`, `ownerId` and existing `changes`). Guarded against opening when there are no users.

Fields:

- **What for?** (title, required)
- **Amount** (₹; `toPaise` conversion; must be > 0)
- **Date** — tappable field opening a `DatePicker` (2020 → today + 1 yr)
- **Split this expense** — a `SwitchListTile`. Default **on** for new expenses.
  - **Off**: expense is tracking-only → no paidBy / no shares; note text "Just tracking this expense — no money split."
  - **On**: shows **Paid by** dropdown (a member) and a **Split equally / Manual** `SegmentedButton`.
    - *Equal*: built via `Expense.equalSplit` (all members).
    - *Manual*: one text field per member pre-filled with equal amounts; live validation that shares sum to the bill — with an inline red error, otherwise Save is disabled.

Save is enabled only when: amount > 0, title non-empty, shares sum correctly (manual), and members exist.

On create: `id = microsecondsSinceEpoch`, `addedBy = myName`. On edit: id/addedBy/ownerId/changes are preserved from the existing expense.

### 8.6 Expense detail sheet

Bottom sheet (scrollable, drag handle) when tapping an expense:

- Title + big amount.
- **Meta chips**: split status (`Split · paid by X` or `Tracking only`), date, `Added by X`.
- If split: card listing each sharer's owed amount. If not: note that nothing was split.
- **Edit** and **Delete** buttons (delete asks for confirmation) — shown only when `canEdit`.
- **History** `ExpansionTile` (collapsed) with the "Added expense" line plus each recorded `ExpenseChange` (`{by}` + `{change}` + date).

### 8.7 Chat tab (`lib/screens/chat_screen.dart`)

- Renders `store.messages` (Firestore stream, oldest first) as alignment bubbles: right = mine (`byUid == store.myUid`), left = others (with the sender's name label).
- Sending calls `store.sendMessage(text)` → new doc appears live from the stream.
- Sticky input bar with a send button (`IconButton.filled`); empty input is ignored.

---

## 9. Testing (`test/splits_test.dart`)

Pure-logic unit tests (no widgets, no Firebase — the store's side effects are deliberately routed through `split_logic.dart` so they stay testable):

1. `Expense.equalSplit` — remainder handling (101 paise / 3 → 33,33,35; sums exact).
2. `Expense.equalSplit` — single member gets the full amount.
3. `Expense` — `toMap`/`fromMap` round-trip.
4. `Expense.split` flag — tracking-only has no `paidBy` nor shares.
5. `computeBalances` — equal split credits payer / debits others.
6. `computeBalances` — manual split honours custom shares.
7. `computeBalances` — tracking-only expense does not affect balances.
8. `computeSettlements` — nets debts into minimal transfers.
9. `computeSettlements` — no transfers when everyone is settled.
10. `computeSettlements` — partial payments chain across debtors.
11. `diffExpenses` — catches title + amount changes.
12. `diffExpenses` — catches paidBy changes.
13. `diffExpenses` — no changes for identical expenses.
14. `toPaise` — rounding (incl. `0.1 + 0.2`).
15. `fmtPaise` — sign + formatting.
16. `paiseToInput` — two-decimal input string.

Run: `flutter test` → currently **16/16 pass**.

---

## 10. Setup for a fresh Firebase project

1. In the Firebase console, create a project and register your app(s).
2. Replace `lib/firebase_options.dart` with the generated config (or `flutterfire configure`).
3. **Enable the Email/Password provider**: Firebase console → Authentication → Sign-in method.
4. Deploy the Firestore rules: `flutterfire deploy`-style tooling or `firebase deploy --only firestore:rules` (uses `firebase.json` → `firestore.rules`).
5. The very first sign-up becomes `admin`; promote/demote others from the admin panel.

---

## 11. Known state / notes for future work

- **Firestore rules are enforced on Firestore, not the client.** UI permission checks (`canEdit`) are cosmetic; the document-level rules in `firestore.rules` are the real guard (admin or owner expensed-write; signed-in reads/writes; admin-only role/activity/delete).
- **Deleting a member keeps their expense history** (expenses are stamped with `ownerId`, and removing a `users/{uid}` doc only removes them from the People list; they also lose access on their device).
- **First user wins admin.** There is no admin-invite flow; if someone else signs up before the intended admin, promotion covers it (once an admin exists).
- **Settlement** is a greedy approximation (pairs biggest debtor with biggest creditor). It is optimal in practice for small groups but is not a mathematically guaranteed minimum.
- Activity feed shows the most recent 50 events; per-expense history is unbounded.
- **Linux desktop** build requires system packages (`clang cmake ninja-build g++ pkg-config libgtk-3-dev`); `flutter analyze` and `flutter test` work without them.

---

## 12. Quick reference: how the flow ties together

```
AuthGate ─ authStateChanges() ─► signed out → AuthScreen (login/sign-up)
                                   signed in → HomeScreen (AppStore.init streams)
                                                        │
Tap + (Expense dialog) ──► Expense{ title, amountPaise, split?,
    equal/manual, date, paidBy, addedBy, ownerId=myUid }
                                                        │
AppStore.addExpense ──► expenses/{id} + activity["added by myName"]
                                                        │
Tap expense (detail sheet) ──► shows shares + history
     │  "Edit" ──► replaceExpense ──► diffExpenses → per-expense changes[]
     │              (stamped "edited by myName") + activity["edited"]
     │  "Delete"──► removeExpense (admin or owner) ──► activity["deleted"]
                                                        │
computeBalances ←─ split expenses only ──► computeSettlements ──► "who owes whom"
                                                        │
Chat: store.sendMessage ──► messages/{auto} ──► stream → bubble "mine?"
                                                        │
Admin panel: setRole / removeUser (admin only)          │
    role changes flow back through the users stream ──► canEdit/canDelete
```