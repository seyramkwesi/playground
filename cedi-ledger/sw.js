// Cedi Ledger service worker: keeps the app working offline.
const VERSION = "cedi-ledger-v7";
const SHELL = ["./", "./index.html", "./manifest.webmanifest", "./jspdf.umd.min.js",
  "./icon-192.png", "./icon-512.png", "./apple-touch-icon.png", "./config.js", "./supabase.min.js"];
// Files that change when the app is updated or reconfigured: always try the network first.
const FRESH = ["index.html", "config.js", "manifest.webmanifest"];

self.addEventListener("install", e => {
  // cache: "reload" skips the browser's own HTTP cache, so a new version never
  // stores a stale copy of a file it was installed alongside.
  e.waitUntil(caches.open(VERSION)
    .then(c => c.addAll(SHELL.map(u => new Request(u, {cache: "reload"}))))
    .then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

function networkFirst(req, cacheKey) {
  return fetch(req, {cache: "no-cache"}).then(r => {
    if (r.ok) { const copy = r.clone(); caches.open(VERSION).then(c => c.put(cacheKey || req, copy)); }
    return r;
  }).catch(() => caches.match(cacheKey || req, {ignoreSearch: true}));
}

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);

  // Google Fonts: serve from cache, refresh in the background.
  if (url.hostname.endsWith("fonts.googleapis.com") || url.hostname.endsWith("fonts.gstatic.com")) {
    e.respondWith(caches.open(VERSION).then(async c => {
      const hit = await c.match(req);
      const net = fetch(req).then(r => { c.put(req, r.clone()); return r; }).catch(() => hit);
      return hit || net;
    }));
    return;
  }

  if (url.origin !== location.origin) return;

  // Pages and settings: network first so updates arrive, cached copy when offline.
  if (req.mode === "navigate") { e.respondWith(networkFirst(req, "./index.html")); return; }
  if (FRESH.some(f => url.pathname.endsWith("/" + f))) { e.respondWith(networkFirst(req)); return; }

  // Everything else (libraries, icons): cache first.
  e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(r => {
    const copy = r.clone(); caches.open(VERSION).then(c => c.put(req, copy)); return r;
  })));
});
