// Takes the place of the engine's service worker (index.service.worker.js,
// written over it by scripts/build.py). That one served the page itself from
// its cache, so a new release reached a player only a visit later, and it kept
// a second copy of the 90 MB game; the page now keeps the game in its own
// cache (shell.html). Browsers that still have the old worker fetch this one
// on their next visit: it removes the old cache and itself, and loads the
// page again from the network.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
	event.waitUntil((async () => {
		for (const key of await caches.keys()) {
			if (key.indexOf('-sw-cache-') >= 0) await caches.delete(key);
		}
		await self.registration.unregister();
		for (const client of await self.clients.matchAll({ type: 'window' })) client.navigate(client.url);
	})());
});
