// Serves the browser build (export/web) from the Worker's static assets.
//
// Static assets are limited to 25 MiB a file, and the game's pack and engine
// are larger. `scripts/build.py --deploy-web` stores every file gzipped, and
// splits the ones still too big into parts; _manifest.json lists the parts.
// This joins them back into one gzip stream, which the browser unpacks.

let manifest = null;

const TYPES = {
  html: "text/html; charset=utf-8",
  js: "application/javascript",
  wasm: "application/wasm",
  pck: "application/octet-stream",
  png: "image/png",
  json: "application/manifest+json",
  ico: "image/x-icon",
};

export default {
  async fetch(request, env) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405 });
    }
    if (manifest === null) {
      const r = await env.ASSETS.fetch(new Request(new URL("/_manifest.json", request.url)));
      manifest = await r.json();
    }
    let path = new URL(request.url).pathname;
    if (path === "/") path = "/index.html";
    const entry = manifest.files[path.slice(1)];
    if (!entry) return new Response("Not found", { status: 404 });

    const etag = `"${manifest.build}"`;
    const headers = {
      "Content-Type": TYPES[path.split(".").pop()] || "application/octet-stream",
      "Content-Encoding": "gzip",
      "Content-Length": String(entry.size),
      // Same URLs on every release: browsers ask again each time and get a
      // 304 while the build is unchanged.
      "Cache-Control": "no-cache",
      ETag: etag,
    };
    if (request.headers.get("If-None-Match") === etag) {
      return new Response(null, { status: 304, headers: { ETag: etag, "Cache-Control": "no-cache" } });
    }
    if (request.method === "HEAD") {
      return new Response(null, { headers, encodeBody: "manual" });
    }

    const { readable, writable } = new FixedLengthStream(entry.size);
    (async () => {
      for (const part of entry.parts) {
        const r = await env.ASSETS.fetch(new Request(new URL("/" + part, request.url)));
        await r.body.pipeTo(writable, { preventClose: true });
      }
      await writable.close();
    })();
    return new Response(readable, { headers, encodeBody: "manual" });
  },
};
