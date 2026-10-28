# Jujutsu (jj) Version Control Workflow Guide

A complete, step-by-step practical reference for managing code repositories with **Jujutsu (`jj`)**—from initializing an empty directory to linking a remote Git server, managing changes, and pushing bookmarks.

---

## 1. Quick Command Cheat Sheet

| Task                  | Jujutsu (`jj`) Command                                    | Notes                                           |
|:--------------------- |:--------------------------------------------------------- |:----------------------------------------------- |
| **Initialize Repo**   | `jj git init`                                             | Initialized in existing directory               |
| **Check Status**      | `jj status`                                               | Views changed/untracked files                   |
| **View Log Graph**    | `jj log`                                                  | Shows commit tree and `@` working copy          |
| **Review Changes**    | `jj diff`                                                 | Inspects line-by-line diffs                     |
| **Describe Change**   | `jj describe -m "msg"`                                    | Attaches commit message to current change       |
| **New Clean Slate**   | `jj new`                                                  | Closes active change, starts fresh working copy |
| **Set Remote URL**    | `jj git remote add origin <URL>`                          | Connects new remote endpoint                    |
| **Update Remote URL** | `jj git remote set-url origin <URL>`                      | Updates existing remote address                 |
| **Set Bookmark**      | `jj bookmark set main -r @-`                              | Moves bookmark pointer to described commit      |
| **Push Bookmark**     | `jj git push --remote origin --bookmark main`             | Pushes local bookmark to remote                 |
| **Push New Bookmark** | `jj git push --remote origin --bookmark main --allow-new` | First push of a brand-new remote bookmark       |
| **Fetch Remote**      | `jj git fetch --remote origin`                            | Synchronizes remote tracking pointers           |

---

## 2. Fundamental Concepts & Terminology

Before running commands, it helps to understand how Jujutsu differs from traditional Git:

1. **No `git add` is Ever Needed:**
   `jj` automatically tracks all untracked files and modifications in real time within your current working change (`@`). You never need to stage files using `git add`.

2. **`jj describe` vs. `git commit`:**
   * **In Git:** Running `git commit` creates a permanent snapshot, closes the current commit, and moves your branch pointer forward. To add a message, you must commit.
   * **In `jj`:** Running `jj describe` does **not** close a commit or create a new revision in history. It simply updates or renames the text message on your *current active change* (`@`). You can run `jj describe` multiple times on the same change to refine its message without creating extra commits.

3. **Multiple `jj describe`s Before `jj new` (Example):**
   If you make edits and run `jj describe` multiple times *without* running `jj new`, you are just overwriting the commit message on that single change:
   
   ```bash
   # 1. Edit code
   jj describe -m "WIP: working on bashrc"    # Message set to "WIP: working on bashrc"
   
   # 2. Make more edits to the SAME change
   jj describe -m "feat: complete bashrc script" # Overwrites previous message
   ```
   
   **What `jj log` looks like:**
   
   ```text
   @  pkkzsutv user@domain 2026-08-05 16:00:00 20bb42f8
   │  feat: complete bashrc script
   ◆  zzzzzzzz root() 00000000
   ```
   
   *Result:* Only **one** commit exists in history. The second `jj describe` simply replaced the text of the first.

4. **`jj new` is What Creates Separate Commits:**
   To turn your work into multiple distinct commits in history, you must use `jj new` to finalize the current change and open a new one:
   
   ```bash
   # First Commit
   vim .bashrc
   jj describe -m "feat: configure bashrc"
   jj new                                      # Closes change 1, opens change 2 (@)
   
   # Second Commit
   vim .bash_profile
   jj describe -m "feat: configure bash_profile"
   ```
   
   **What `jj log` looks like now:**
   
   ```text
   @  a1b2c3d4 user@domain 2026-08-05 16:05:00 99xx88yy
   │  (empty) feat: configure bash_profile
   ○  pkkzsutv user@domain 2026-08-05 16:00:00 20bb42f8
   │  feat: configure bashrc
   ◆  zzzzzzzz root() 00000000
   ```

5. **Bookmarks Replace Branches:**
   In `jj` version 0.31+, branch markers (like `main` or `master`) are explicitly called **bookmarks**.

6. **Why `jj new` BEFORE `jj bookmark set main -r @-` is the Recommended Workflow:**
   * **Seals Your Work First:** Running `jj new` closes off your current working copy (`@`) and seals it into history as a parent commit (`@-`).
   * **Prevents Accidental Empty/Undescribed Commits:** If you set the bookmark to `@` and push *before* running `jj new`, your working copy remains active. If you get interrupted or edit further, your next edits will bleed into the commit you already pushed—or leave an undescribed empty commit in the history chain.
   * **Bulletproof Pushes:** Pointing `main` to the sealed parent (`@-`) ensures you only push finished, fully described commits to the remote.

---

## 3. Workflow Flowchart

```text
===================================================================
  PASS 1: One-Time Repository Setup & Initial Push
===================================================================

[ Empty Project Directory ]
           │
           ▼
     jj git init                  <── Initialize Jujutsu repo with Git backend
           │
           ▼
jj git remote add origin <URL>    <── Link remote Git repository
           │
           ▼
[ Add initial project files ]
           │
           ▼
  jj describe -m "initial commit" <── Describe initial commit (@)
           │
           ▼
        jj new                    <── Seal commit (@-) and open clean working copy (@)
           │
           ▼
  jj bookmark set main -r @-      <── Point 'main' bookmark to described parent (@-)
           │
           ▼
jj git push --remote origin \
   --bookmark main --allow-new    <── Initial push (creates bookmark on remote)


===================================================================
  PASS 2: Ongoing Daily Iteration Loop
===================================================================

[ Edit files / make updates ]
           │
           ▼
     jj status & jj diff          <── Inspect untracked / modified changes
           │
           ▼
  jj describe -m "description"   <── Describe active change (@)
           │
           ▼
        jj new                    <── Seal change into history (@-) and open clean working copy (@)
           │
           ▼
  jj bookmark set main -r @-      <── Advance 'main' bookmark to described parent (@-)
           │
           ▼
jj git push --remote origin \
   --bookmark main                <── Push updated bookmark & commits to remote
           │
           └──────────────────────► (Repeat for next task)
```

---

## 4. End-to-End Walkthrough

### Step 1: Initialize a New Jujutsu Repository

Navigate to your target directory (or create a new one) and initialize Jujutsu with a Git storage backend:

```bash
mkdir -p ~/Projects/my-app
cd ~/Projects/my-app

# Initialize Jujutsu with Git backend capability
jj git init
```

---

### Step 2: Make Changes & Manage the Working Copy

Create your project files as normal. `jj` automatically tracks file additions and updates in the working change (`@`).

```bash
# Create files
echo "# My App" > README.md
echo "echo 'Hello World'" > app.sh
chmod +x app.sh

# Check tracked changes
jj status

# Review exact line diffs
jj diff
```

---

### Step 3: Describe and Complete the Change

Assign a commit message to your change, then open a clean slate for subsequent work:

```bash
# 1. Label/describe the current working change (@)
jj describe -m "feat: initial project structure and entry script"

# 2. Complete the change and open a new empty working copy (@)
jj new
```

To view your newly committed change in the revision graph:

```bash
jj log
```

**Example Log Output:**

```text
@  pkkzsutv user@domain 2026-08-05 16:00:00 20bb42f8
│  (empty) (no description set)
○  ousyuzlm user@domain 2026-08-05 15:58:00 ef4d4523
│  feat: initial project structure and entry script
◆  zzzzzzzz root() 00000000
```

---

### Step 4: Link to a Remote Git Repository

Add your remote repository endpoint. Choose SSH (preferred) or HTTPS depending on your infrastructure setup.

#### Option A: Adding a New Remote (`jj git remote add`)

Use `add` when configuring a remote for the first time in this local repository:

```bash
# SSH Remote (using host alias or explicit address)
jj git remote add origin giteaserver:username/my-app.git

# Or standard SSH URL:
# jj git remote add origin git@github.com:username/my-app.git
```

#### Option B: Modifying an Existing Remote (`jj git remote set-url`)

If `origin` already exists (e.g., previously set to an HTTPS URL or expired certificate domain) and needs updating:

```bash
jj git remote set-url origin giteaserver:username/my-app.git
```

---

### Step 5: Assign the Bookmark Pointer

Set your local bookmark marker (`main`) to point at your completed parent revision (`@-`):

```bash
jj bookmark set main -r @-
```

> **Syntax Tip:**
> * `@` refers to your current empty working copy.
> * `@-` refers to the parent commit directly beneath your current working copy (the change described in Step 3).

---

### Step 6: Push to the Remote Repository

#### First Push (Creating Remote Bookmark)

Because the `main` bookmark does not exist on the remote server yet, include `--allow-new`:

```bash
jj git push --remote origin --bookmark main --allow-new
```

#### Subsequent Pushes

For ongoing updates after the remote bookmark has been initialized:

```bash
jj git push --remote origin --bookmark main
```

---

### Step 7: Verification

Verify that your local bookmark and remote tracking bookmark match:

```bash
jj log -r "main | main@origin"
```

**Expected Output:** Both `main` and `main@origin` sit on the exact same commit hash:

```text
○  ousyuzlm user@domain 2026-08-05 15:58:00 main main@origin | feat: initial project structure...
```

---

## 5. Daily Iteration & Context-Switching Loop

In `jj`, your working directory (`@`) is automatically recorded as an active revision in real time. You do not need to push to a remote server just to save your place when switching repositories or tasks.

---

### Loop A: Context Switching & Local Breadcrumbs (Work-in-Progress)

Use this loop whenever you reach a milestone, get interrupted, or need to switch context to another repository or task.

```bash
# 1. Label your active change with where you left off
jj describe -m "WIP: refactoring auth, token refresh left to fix"

# 2. Seal the WIP change into local history and open a clean slate
jj new

# 3. Safely switch repositories or tasks (no push required)
```

> **Context Recovery Tip:**
> When you return to the repository later, run `jj log`. The description on `@-` acts as your external memory and tells you exactly where you stopped.

---

### Loop B: Publishing Completed Work (Final Push)

Use this loop only when a feature or fix is complete and ready to be published upstream to `main`.

```bash
# 1. Inspect status and final diffs
jj status
jj diff

# 2. Assign the final, clean commit message
jj describe -m "feat: complete token refresh logic in auth module"

# 3. Seal the change into history and open a clean working copy
jj new

# 4. Advance the local bookmark pointer to the completed parent commit (@-)
jj bookmark set main -r @-

# 5. Push the bookmark to remote
jj git push --remote origin --bookmark main
```

---

## 6. Common Errors & Troubleshooting

### Error: "Won't push commit ... since it has no description"

#### Cause:
`jj` prevents pushing commits to a remote if any commit in the push chain is empty and lacks a description (e.g., an abandoned empty working copy left in history).

#### Example Error Output:
```text
Error: Won't push commit b882ced106f1 since it has no description
Hint: Rejected commit: pkkzsutv b882ced1 (empty) (no description set)
```

#### Solution Options:
* **Option A: Abandon the Empty Commit (Recommended)**
  If the empty commit was created accidentally or is no longer needed, abandon it:
  ```bash
  jj abandon <commit-id-or-change-id>
  ```

* **Option B: Describe the Commit**
  If you want to keep the commit, give it a description before pushing:
  ```bash
  jj describe -r <commit-id-or-change-id> -m "chore: commit description"
  ```

---

### Issue: "Bookmark main@origin already matches main" / "Nothing changed"

#### Cause:
Your `main` bookmark is already pointing at the parent commit (`@-`), but your latest edits are sitting uncommitted inside your active working copy (`@`). Running `jj bookmark set main -r @-` does nothing because `main` is already sitting on `@-`.

#### Fix:
Seal your active working copy into history first, advance `main` to that newly created parent commit, and push:

```bash
# 1. Seal your active working copy into history
jj new

# 2. Advance main to the newly completed parent commit (@-)
jj bookmark set main -r @-

# 3. Push to remote
jj git push --remote origin --bookmark main
```

---

### Error: "Refusing to move bookmark backwards or sideways: main"

#### Cause:
Occurs when your active change (`@`) or target commit was created off an older parent revision instead of being based directly on top of `main`. Moving `main` to a parallel commit is treated as a "sideways" move by `jj`.

#### Fix:
Rebase the target commit on top of `main` first to make it a direct linear descendant, then update the bookmark and push:

```bash
# 1. Rebase your target commit onto the current main bookmark
jj rebase -r <commit_id> -d main

# 2. Advance the main bookmark to the rebased commit
jj bookmark set main -r <commit_id>

# 3. Push to remote
jj git push --remote origin --bookmark main
```

---

### Issue: Stale Remote / Diverged Bookmarks (`main` vs. `main@origin`)

#### Cause:
`main` was modified or pushed from another host/machine, leaving your local `main` pointer behind or diverged from `main@origin`.

#### Fix Option A: Stack local work on top of latest remote `main`
```bash
# 1. Fetch latest remote commits and bookmark positions
jj git fetch

# 2. Rebase your working change (@) onto origin/main
jj rebase -r @ -d main@origin

# 3. Advance local main bookmark to your rebased change
jj bookmark set main -r @

# 4. Push updated bookmark to origin
jj git push --remote origin --bookmark main
```

#### Fix Option B: Reset local main pointer back to match origin
```bash
# 1. Fetch latest remote state
jj git fetch

# 2. Snap local bookmark back to match origin/main
jj bookmark set main -r main@origin
```

---

### Issue: Flattening Accidental Branches / Parallel History

#### Cause:
Editing or running commands from a parent commit (`@-`) instead of `main` creates an unwanted parallel branch in `jj log`.

#### Fix:
Linearize your history by moving `main` to the specific commit and rebasing your working copy directly on top of it:

```bash
# 1. Identify your target commit ID or message in history
jj log -r 'main | ::@'

# 2. Point main directly to the desired commit
jj bookmark set main -r 'description("your target commit message")'

# 3. Rebase active working copy (@) onto main to clean up graph
jj rebase -d main

# 4. Push clean linear main to remote
jj git push --remote origin --bookmark main
```

---

### Issue: Pulling Changes Made on Remote / Web Interface

#### Cause:
Changes were committed directly on a remote server (e.g., via Gitea or GitHub web interface) and need to be synced down into your local working copy.

#### Fix:
```bash
# 1. Fetch latest commits and remote bookmarks
jj git fetch

# 2. Rebase your active working copy (@) onto the updated remote main
jj rebase -r @ -d main@origin

# 3. Fast-forward your local main bookmark to match remote main
jj bookmark set main -r main@origin
```

#### Verification:
Check `jj log` to confirm both `main` and `main@origin` sit on the latest commit with your working copy (`@`) directly on top:

```bash
jj log -r 'main | main@origin | @'
```

---

### Issue: Multiple Empty Commits Stacked Above `main` After Scripted Pushes

#### Cause:
When an automated script or command sequence runs `jj new` multiple times (or pushes while the working copy becomes immutable), it can leave behind multiple empty, undescribed commits (`@` and `@-`) sitting on top of `main`.

#### Example `jj log` Output:
```text
@  xzkxqltr user@domain 2026-08-10 17:25:52 3d4336e0
│  (empty) (no description set)
○  xyytrppv user@domain 2026-08-10 17:25:52 e499bf97
│  (empty) (no description set)
◆  sxnttvzv user@domain 2026-08-10 17:25:51 main a1b5acf6
│  more markdown cleanup and more troubleshooting bits.
```

#### Fix:
Abandon the empty parent commit (`@-`). `jj` will automatically collapse the chain and place your active working copy (`@`) directly on top of `main`:

```bash
jj abandon @-
```

#### Verification:
Check `jj log` to confirm you have a single clean working copy on top of `main`:

```bash
jj log
```

```text
@  a1b2c3d4 user@domain 2026-08-10 17:26:00 88xx99yy
│  (empty) (no description set)
◆  sxnttvzv user@domain 2026-08-10 17:25:51 main a1b5acf6
│  more markdown cleanup and more troubleshooting bits.
```