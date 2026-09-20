# Split Chat

> Reference document for the project. Intended to be read by other developers (human or AI) to understand, maintain or extend the codebase.

## How it works in simple words

- Several phones share **groups** of expenses. Everything a group does (expenses, edits, history, chat) is stored in the cloud (Firestore) and stays in sync on every phone in real time.
- There are **no passwords**. The app signs in to Firebase anonymously; your "account" is just the name you pick on the login screen (`users/{uid}.displayName`).
- After login you land on **Home** (My groups). If you have no groups yet it shows **Create group** / **Join group** buttons; once you have groups they are **listed on Home** and the create action becomes a **floating + button in the bottom-right corner**.
- The **group code is the Firestore document id** — shown inside a group with a copy button. Send it to friends on other phones and they join the same group (from Home → floating + → Join group).
- Joining a group records a **membership** for your account (`users/{uid}/groups/{groupId}`) and you pick which **member name to act as** ("Managing as") — an existing member, or your own new name. That name is stamped on the expenses, history and chat messages you create.
- The **only thing kept on your phone** is your display name (is it a new device?) plus the currently open group, via `shared_preferences`. Everything else is the cloud source of truth, so your groups appear after any reinstall with the same display name.
- Expenses, edits and deletions are each **one atomic write** together with their history entry, so the expense and its activity record always stay consistent even when people edit on different phones at the same time.
- Each phone shows "Managing as" next to messages it sent and its own member chip marked **(you)**, but every phone sees the same, live, up-to-date data.

## Quick reference

| Layer        | Choice                                                        |
|--------------|---------------------------------------------------------------|
| Language     | Dart (`^3.13.2`), Flutter 3.47.x                              |
| UI           | Material 3 (`ColorScheme.fromSeed`, teal)                    |
| Auth         | Firebase **Anonymous Auth**                                   |
| Backend      | Firebase Cloud Firestore (real-time)                         |
| On-device    | `shared_preferences` (display name + currently-open group)  |
| State        | `AppStore` (`ChangeNotifier`) + `ListenableBuilder`          |
| Data access  | `GroupRepository` interface (Firestore impl + test fake)     |
| Linting      | `flutter_lints ^6.0.0`                                       |
| Tests        | `flutter_test` — pure logic + store-vs-fake-repository        |

Commands: `flutter run` / `flutter analyze` / `flutter test` (currently 30/30 pass).

## Structure

```
lib/
├── main.dart                     # Firebase init, anonymous auth, login/home gate (AppBootstrap)
├── firebase_options.dart         # Auto-generated config (project split-chat-007)
├── models/
│   ├── expense.dart              # Expense, ExpenseChange (integer paise)
│   └── models.dart               # GroupInfo, Activity, ChatMessage
├── logic/
│   └── split_logic.dart          # computeBalances, computeSettlements, diffExpenses, stripMemberFromShares
├── utils/money.dart              # paise math + formatting
├── services/
│   ├── group_repository.dart     # abstract repository (streams + mutations)
│   ├── firestore_repository.dart # Firestore implementation (batched writes, arrayUnion, memberships)
│   └── local_session.dart        # shared_preferences: display name + current group
├── store/app_store.dart          # subscribes to repo streams, notifyListeners (per group)
└── screens/
    ├── login_screen.dart         # pick your identity name (no password)
    ├── home_page.dart            # My groups list + empty create/join + floating + (create/join)
    ├── group_detail_screen.dart  # one group: Splits+Chat tabs, back + leave group
    ├── group_screen.dart         # JoinSetupScreen: pick "Managing as" member
    ├── splits_screen.dart        # expenses, splits, history, people, balances, settlements
    └── chat_screen.dart          # chat bubbles ("mine" = own managing name)
test/
├── fake_group_repository.dart    # in-memory repository for tests
└── splits_test.dart              # pure-logic + AppStore + membership tests (30 tests)
```

## Firestore layout

- `groups/{groupId}` → `{name, members: [names], createdAt}` — `groupId` is the group code.
- `groups/{groupId}/expenses/{id}` → `{title, amountPaise, split, paidBy, sharesPaise, date: Timestamp, addedBy, changes: [{by, change, at: Timestamp}]}`.
- `groups/{groupId}/activity/{id}` → `{by, verb, title, amountPaise, at}` (`verb` ∈ `added|edited|deleted`).
- `groups/{groupId}/messages/{id}` → `{senderName, text, createdAt}`.
- `users/{uid}` → `{displayName, createdAt}` — the account's identity name.
- `users/{uid}/groups/{groupId}` → `{name, joinedAt}` — a membership; Home lists these live.

## Architecture notes

- **Repository** (`GroupRepository`) is the single Firestore access layer. `FirestoreGroupRepository` implements it; `InMemoryGroupRepository` in `test/` stands in for unit tests. `AppStore` calls only the interface.
- **Real-time sync**: the store subscribes to four snapshots — group doc, expenses (**`orderBy(date, descending)`**), latest 30 activity (**`orderBy(at, descending).limit(30)`**), latest 50 messages (**`orderBy(createdAt, descending).limit(50)`**, reversed in the store so chat renders oldest→newest).
- **Atomic writes** (Firestore `WriteBatch`):
  - `addExpense` / `replaceExpense` / `removeExpense` = expense doc op + activity entry in one batch.
  - `removeMember` / `leaveGroup` = `members` `arrayRemove`/`arrayUnion` + strip that member from every expense's `sharesPaise` (+ membership deletion for leave) in one batch (uses `stripMemberFromShares`).
  - `createGroup` / `joinGroup` = group write + the account's membership row in one batch (`arrayUnion` keeps "Managing as" names unique).
  - `replaceExpense` appends edit history with `FieldValue.arrayUnion` so concurrent edits on different phones don't overwrite `changes`.
- **Money** is integer paise end-to-end (`toPaise`/`fmtPaise`/`paiseToInput`); no floats.
- **Permissions UI-free**: anyone in the group edits/deletes anything; identity is only the chosen name for history/chat. Real validation lives in `firestore.rules` (signed-in only; `amountPaise` int > 0; `text` non-empty).

## Setup

1. Firebase project + `lib/firebase_options.dart` (this repo uses `split-chat-007`; regenerate with `flutterfire configure` for a new project).
2. Enable **Anonymous** provider in Firebase console → Authentication.
3. Deploy rules: `firebase deploy --only firestore:rules` (`firebase.json` → `firestore.rules`).

## Testing

Pure-logic groups (`Expense.equalSplit`, `computeBalances`, `computeSettlements`, `diffExpenses`, `stripMemberFromShares`, money helpers) plus `AppStore`-against-`InMemoryGroupRepository` groups (stream load, add/replace/remove expense with stamped history + activity, removeMember batch, chat senderName/ordering) and membership tests (`myGroups`, `joinGroup` dedupe, `leaveGroup` strips shares, unknown-code throws). `flutter analyze` clean, `flutter test` 30/30.