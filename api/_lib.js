const SUPA_URL = 'https://dlsmpfxflpmatpzfssrk.supabase.co';
const SUPA_KEY = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRsc21wZnhmbHBtYXRwemZzc3JrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgxMTU5NDIsImV4cCI6MjA5MzY5MTk0Mn0.KZzPckubA-0lmmz6_Bcuo_CoHpbIAMSzv0r0w5ToKYI';
async function rpc(name, args) {
  const r = await fetch(SUPA_URL + '/rest/v1/rpc/' + name, {
    method: 'POST',
    headers: { apikey: SUPA_KEY, Authorization: 'Bearer ' + SUPA_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify(args)
  });
  if (!r.ok) return null;
  const d = await r.json();
  return Array.isArray(d) ? d[0] || null : d;
}
function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
function host(req) { return 'https://' + (req.headers['x-forwarded-host'] || req.headers.host); }
const UUID = /^[0-9a-f-]{36}$/i;
module.exports = { rpc, esc, host, UUID };
