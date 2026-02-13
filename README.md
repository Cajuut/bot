# Discord Bot Controller

This is a Windows application built with Flutter that controls a local Node.js Discord bot.

## Project Structure

- `flutter_ui/`: The Flutter application (Frontend).
- `node_bot/`: The Node.js application (Backend/Bot).

## Getting Started

### Prerequisites

1.  **Node.js**: Ensure Node.js is installed on your machine.
2.  **Flutter**: Ensure Flutter SDK is installed.

### Setup

1.  Navigate to `node_bot` and install dependencies:
    ```bash
    cd node_bot
    npm install
    ```

2.  Navigate to `flutter_ui` and run the app:
    ```bash
    cd flutter_ui
    flutter run -d windows
    ```

## Usage

1.  Enter your **Discord Bot Token** in the input field.
2.  Click **Start Bot**.
3.  The bot logs will appear in the black console window.
4.  The bot also starts a local web server at `http://localhost:3000`.

## Modes of Operation

### 1. Windows Host Mode
Checks if running on Desktop.
*   **Action**: Starts the local Node.js bot process (spawn).
*   **Display**: Shows stdout/stderr logs from the local process.
*   **Server**: Automatically hosts the Socket.io server on port 3000.

### 2. iPhone / Remote Mode
Checks if running on Mobile (or if you manually connect).
*   **Action**: Connects to the Windows Host via Wi-Fi (IP Address).
*   **Display**: Streams logs via Socket.io.
*   **Control**: Can send "Stop" command to the host.

## How to use on iPhone (Sideloading/ESign)

Since you are installing via ESign (IPA):

1.  **Build the IPA**: You need a Mac to build the specific `Runner.app` or `.ipa`.
    *   *If you don't have a Mac, you might be looking for a pre-built IPA. I cannot generate one here on Windows.*
    *   However, the source code is fully compatible. If you have a way to build it (e.g. GitHub Actions, Codemagic, or a friend with a Mac), use this source.
2.  **Configuration**:
    *   Ensure your iPhone is on the **same Wi-Fi network** as your PC.
    *   Open the app on iPhone.
    *   Enter your PC's Local IP Address (e.g., `192.168.1.15`) in the "IP Address" field.
    *   Tap **Connect**.
3.  **Troubleshooting**:
    *   **Firewall**: Ensure Windows Firewall allows traffic on port 3000 (Node.js). You might need to allow "Node.js JavaScript Runtime" in firewall settings.

## Developer Notes

*   **Node.js Dependency**: The Windows app expects `node` to be in your System PATH.
*   **Dependencies**: Run `npm install` in `node_bot` before starting.


## Bot Features

-   Responds to `ping` with `pong`.
-   Serves a simple HTML status page.
