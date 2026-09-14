# Dive demo app

The working Dive desktop demo as a real desktop application (Electron).

```bash
cd app
npm install        # once, downloads Electron
npm start          # opens Dive in its own window
npm run build      # makes out/Dive-darwin-arm64/Dive.app (macOS, Apple Silicon)
```

For a Windows build run `npm run build:win` on a Windows PC (needs `icon.ico`).
The app loads `prototype/dive.html`; edit that file and restart to see changes.
