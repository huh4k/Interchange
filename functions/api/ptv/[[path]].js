// Cloudflare Pages Function: signs PTV Timetable API requests server-side so
// the web app never holds the API key.
//
//   GET /api/ptv/v3/departures/...?max_results=20  ->  timetableapi.ptv.vic.gov.au
//
// Used by the web app (same origin) and by mobile/desktop builds (PTV_PROXY_URL).
// Set PTV_USER_ID and PTV_API_KEY as (encrypted) variables on the Pages project.

const PTV_ORIGIN = 'https://timetableapi.ptv.vic.gov.au';
const PREFIX = '/api/ptv';

async function sign(key, message) {
  const k = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(key),
    { name: 'HMAC', hash: 'SHA-1' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(message));
  return [...new Uint8Array(mac)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
    .toUpperCase();
}

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const path = url.pathname.slice(PREFIX.length);
  if (!path.startsWith('/v3/') || path.includes('..')) {
    return new Response('Not found', { status: 404 });
  }
  if (!env.PTV_USER_ID || !env.PTV_API_KEY) {
    return new Response('PTV credentials are not configured', { status: 500 });
  }

  // Drop any client-supplied credentials, then sign exactly what we forward.
  const query = url.search
    .slice(1)
    .split('&')
    .filter((p) => p && !/^(devid|signature)=/i.test(p));
  query.push(`devid=${env.PTV_USER_ID}`);
  const toSign = `${path}?${query.join('&')}`;
  const signature = await sign(env.PTV_API_KEY, toSign);

  const upstream = await fetch(`${PTV_ORIGIN}${toSign}&signature=${signature}`, {
    headers: { Accept: 'application/json' },
    // Identical requests share one upstream call for a few seconds, which keeps
    // a busy app from burning through the API key's rate limit.
    cf: { cacheEverything: true, cacheTtl: 10 },
  });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json',
      'Cache-Control': 'no-store',
    },
  });
}
