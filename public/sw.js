// Service worker: lets the dashboard be installed as a full-screen app, and keeps it loading
// from cache if the web server is briefly unavailable (e.g. while the pod restarts).
// Network-first, so a redeploy is picked up on the next load.
// Price data (api/) is never cached: replaying old prices offline would look like fresh data
// and hide the "can't reach Amber" warning.
const CACHE = "amber-dashboard-v2";
const APP_SHELL = [
    "./",
    "index.html",
    "app.js",
    "vue-2.7.16.min.js",
    "luxon-1.28.1.min.js",
    "lodash-4.17.23.min.js",
    "manifest.webmanifest",
    "icon-192.png",
    "icon-512.png",
];

self.addEventListener("install", event => {
    event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(APP_SHELL)));
    self.skipWaiting();
});

self.addEventListener("activate", event => {
    event.waitUntil(
        caches.keys()
            .then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key))))
            .then(() => self.clients.claim())
    );
});

self.addEventListener("fetch", event => {
    const request = event.request;
    const url = new URL(request.url);
    if (request.method !== "GET" || url.origin !== self.location.origin
        || url.pathname.startsWith(new URL("api/", self.registration.scope).pathname)) {
        return;
    }
    event.respondWith(
        fetch(request)
            .then(response => {
                if (response.ok) {
                    const copy = response.clone();
                    caches.open(CACHE).then(cache => cache.put(request, copy));
                }
                return response;
            })
            .catch(() => caches.match(request, {ignoreSearch: true}))
    );
});
