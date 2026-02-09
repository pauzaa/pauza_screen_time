# Project Specifications: Pauza Screen Time Plugin

## Project Overview
This project is a dedicated plugin designed specifically for the **Pauza** digital wellbeing application. Its primary objective is to provide the necessary API capabilities to enable Pauza's core native functionalities on both Android and iOS platforms. The implementation is tailored to Pauza's specific requirements.

## Core Concepts

*   **Application Blocked**: A state where a "shield" is displayed over a specific application when a user attempts to open it, effectively preventing interaction with that application.
*   **Shield**: A native screen overlay that appears on top of a blocked application, making it inaccessible.
*   **Mode**: An object that defines the rules for blocking (what, when, and how).
*   **Schedule**: An optional component of a Mode (0 or 1 per Mode). A schedule defines the active times for a Mode, including:
    *   Days of the week
    *   Start time
    *   End time

## Core Features
The plugin must implement the following core features:

### 1. Reliable Manual Mode
*   **Start/End**: Users can manually start and end a mode.
*   **Behavior**: When a mode is active, selected applications must be blocked. The shield should appear upon entering an app and disappear when exiting.
*   **Persistence**: An active mode must remain active even if the Pauza app is closed or the device is rebooted.
*   **Termination**: A manually started mode can only be ended manually.

### 2. Reliable-Enforced Pause
*   **Functionality**: Users can temporarily "pause" an active mode for a fixed duration.
*   **Behavior**: During a pause, blocking is lifted. Once the pause duration expires, the mode and its blocking rules must be immediately re-enforced.
    *   *Example*: If Instagram is blocked and a user takes a 5-minute pause to use it, the shield must immediately reappear exactly when the 5 minutes are up, even if the user is still inside the app.
*   **Persistence**: Pauses must survive device reboots and Pauza app exits.

### 3. Reliable Schedules
*   **Functionality**: Schedules automatically enable and disable Modes without user intervention.
*   **Persistence**: Schedules must be enforced even if the Pauza app is not running and must persist across device reboots.

### 4. Shield Configuration
*   **Functionality**: Provide APIs to customize the appearance and content of the native shield screen.

### 5. App Usage Statistics
*   **Functionality**: Provide APIs to retrieve application usage statistics (screen time) for a specified date-time period.

### 6. Applications Enumeration
*   **Functionality**: Provide APIs to list all applications installed on the device.

### 7. Permissions
*   **Functionality**: Provide APIs to request and check all necessary user permissions required for the features listed above to function correctly.

### 8. Prioritization & Conflict Resolution
*   **Single Active Mode**: Only one mode can be active at any given time.
*   **Schedule Constraint**: Schedules for different modes cannot overlap.
*   **Manual Override**: A voluntarily manually started mode always takes precedence over scheduled modes.
    *   *Scenario 1*: If Mode A is scheduled to start (e.g., 8 AM - 8 PM), but Mode B is manually running at 8 AM, then Mode A is ignored. Mode B continues to run until manually stopped.
    *   *Scenario 2*: If Mode A is scheduled for 8 AM - 8 PM, but the user manually starts it at 7 AM, the manual state overrides the schedule. The mode will **not** automatically end at 8 PM; it continues until the user manually ends it.
