CEDI LEDGER: put it on your iPhone home screen
==============================================

This folder is a complete web app. It needs to be hosted on a web address that
starts with https:// so your iPhone can install it and use it offline.
Both options below are free.

OPTION A: Netlify Drop (easiest, about 2 minutes, from a computer)
1. Unzip this folder.
2. Go to https://app.netlify.com/drop and create a free account.
3. Drag the whole "cedi-app" folder onto the page.
4. Netlify gives you a link like https://something.netlify.app.
   You can rename it under Site settings.

OPTION B: GitHub Pages
1. Create a new public repository on github.com.
2. Upload every file in this folder to it (Add file > Upload files).
3. Go to Settings > Pages, set Source to "Deploy from a branch", pick main / root, and save.
4. After a minute your app is live at https://<your-username>.github.io/<repo-name>/

INSTALL ON IPHONE
1. Open your link in Safari. It has to be Safari, not Chrome.
2. Tap the Share button, then "Add to Home Screen", then Add.
3. Open it from the home screen. It runs full-screen and works offline.

YOUR DATA
- Everything is stored on the phone itself, inside the app.
- Use Business > Backup & restore > "Save backup" regularly, and save the
  file to iCloud Drive or Files. Use "Restore from backup" to move your data
  to a new phone or browser.
- Deleting the home-screen app also deletes its data, so back up first.

UPDATING THE APP LATER
Replace the files on Netlify or GitHub, then raise the version number in
sw.js (cedi-ledger-v1 -> cedi-ledger-v2) so phones pick up the new version.

FILES
index.html            the app
sw.js                 offline support
manifest.webmanifest  app name, colours, icons
jspdf.umd.min.js      PDF generator, bundled so PDFs also work offline
*.png                 home-screen icons
