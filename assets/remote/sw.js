// Service worker minimo: rende il telecomando installabile dove il browser
// lo consente. I dati arrivano sempre dal player, niente cache.
self.addEventListener('install', (e) => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});
