// Service worker minimal : page toujours chargée depuis le réseau d'abord (jamais de version périmée),
// copie en cache seulement si le téléphone est hors ligne.
const CACHE = 'rlk-v23';
self.addEventListener('install', e => { self.skipWaiting(); });
self.addEventListener('activate', e => { e.waitUntil(self.clients.claim()); });
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET' || new URL(e.request.url).origin !== location.origin) return;
  e.respondWith(
    fetch(e.request).then(r => { const c = r.clone(); caches.open(CACHE).then(k => k.put(e.request, c)); return r; })
      .catch(() => caches.match(e.request).then(m => m || caches.match('/')))
  );
});
