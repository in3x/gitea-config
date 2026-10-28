# `dtach-auto` — Interactive SSH Session Management

A modular Bash framework embedded within `~/.bashrc` that automatically prompts, creates, cleans, and attaches `dtach` persistent terminal sessions upon SSH login.

---

## Features

* **Default to New Session:** Defaults to creating a fresh session on login while keeping all existing sessions browsable.
* **Smart Friendly Names:** Automatically assigns human-readable session names (e.g., `swift-falcon`) sourced from system dictionaries or built-in word lists.
* **Accurate Attachment Detection:** Uses kernel-level socket queries (`ss -xla`) to count active UNIX domain socket connections, reliably distinguishing between attached and detached sessions without `/proc` scanning overhead.
* **Process Replacement (`exec`):** Replaces the parent login shell with `dtach`, ensuring that detaching (`Ctrl+\`) cleanly terminates the SSH connection rather than leaving an orphaned idle shell.
* **Dead Socket Cleanup:** Auto-detects and removes stale socket files from previous system reboots or crashed daemons.
* **Custom Prompt (PS1) Integration:** Dynamically prepends the active `dtach` session name to your `PS1` prompt.
* **Scoped Debugging (`DTACH_DEBUG`):** Toggle detailed execution tracing globally or within specific helper functions without polluting standard login output.

---

## Architecture Overview

The `.bashrc` implementation is structured into five distinct execution layers:

| Layer | Component | Responsibility |
| --- | --- | --- |
| **1** | **Guard Clause** | Immediately returns if the shell is non-interactive (`$- != *i*`). |
| **2** | **Environment & Config** | Sets `DTACH_DEBUG`, `PATH`, and tool completions (e.g., `jj`). |
| **3** | **Helper Functions** | Self-contained utilities for logging, socket inspection, dead socket purging, and name generation. |
| **4** | **Core Logic** | High-level orchestrator (`dtach_auto`), menu renderer, input validator, and branch dispatchers. |
| **5** | **Entry Point & Prompt** | Modifies `PS1` inside active sessions and triggers `dtach_auto` on SSH login (`SSH_CONNECTION` / `SSH_CLIENT`). |

---

## Prerequisites

* **`dtach`**: Minimalist terminal session emulator (`sudo apt install dtach` or `sudo dnf install dtach`).
* **`iproute2` (`ss`)**: Used for UNIX domain socket inspection.
* **System Dictionary (Optional)**: `/usr/share/dict/words` or `/usr/share/dict/american-english` for friendly session naming.

---

## Installation

Append the contents of the `dtach-auto` script to the end of your local or remote `~/.bashrc` file:

```bash
cat dtach_auto.sh >> ~/.bashrc
source ~/.bashrc

```

---

## Configuration & Usage

### 1. Daily Usage

When connecting to the server via SSH:

1. The session menu displays all active host sessions alongside their creation times and status (`[detached]` vs `* [ATTACHED]`).
2. Press **Enter** to accept default **Option 1** (Create a new session), or select a number corresponding to an existing session.
3. If creating a new session, press **Enter** to accept the auto-generated friendly name or input a custom identifier.

```text
=== dtach Sessions [Host: lake] ===
  1) [+] Create a new session
  2) swift-falcon (14:20 Aug 12)   [detached]
  3) quiet-forest (11:05 Aug 12) * [ATTACHED]

Select session [1-3] (default 1): 

```

### 2. Detaching

To detach from a running session without terminating your terminal programs:

* Press **`Ctrl+\`** (the default `dtach` detach character).
* Because `dtach` replaces the parent shell via `exec`, detaching immediately drops the SSH connection.

### 3. Debugging

Enable execution logging by setting `export DTACH_DEBUG=1` in Layer 2 of `~/.bashrc`:

```bash
export DTACH_DEBUG=1

```

To debug a single function during maintenance without turning on global logging, declare a localized variable within that function:

```bash
dtach_cleanup_dead_sockets() {
    local DTACH_DEBUG=1
    # ...
}

```