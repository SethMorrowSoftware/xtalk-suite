// A deliberately minimal service worker. Its only job here is to prove that a service
// worker CAN register - which the browser allows ONLY in a secure context. Over Tor a
// .onion origin is treated as secure, so this registers and activates; over a plain
// http:// web link it will not register at all (and the About page says so).
//
// It intentionally has NO 'fetch' handler and does NO caching of its own. That used to
// be the whole freshness story ("the live demo can never serve a stale file"); since the
// host grew conditional GET it is only half of it: the server tags every file response
// with a weak ETag (W/"size-seed-generation" - qsHttpWeakETag in the stack) plus
// Cache-Control: no-cache, so the BROWSER's own cache revalidates on every load. An edit
// through the built-in LAN editor bumps the generation and shows up immediately; but an
// out-of-band disk edit that keeps the byte size unchanged leaves the ETag intact and
// revalidates 304-stale until the app is relaunched (a fresh per-launch seed). The
// worker just takes control of open pages so the status shows up immediately.
self.addEventListener('install', function () {
  self.skipWaiting();
});
self.addEventListener('activate', function (event) {
  event.waitUntil(self.clients.claim());
});
