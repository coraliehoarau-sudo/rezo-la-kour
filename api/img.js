// Sert la photo d'un événement ou d'un article (stockée en base64) comme vraie image pour les aperçus.
const { rpc, UUID } = require('./_lib');
module.exports = async (req, res) => {
  const q = req.query || {};
  let photo = null;
  if (q.e && UUID.test(q.e)) { const e = await rpc('rlk_partage_evenement', { ev: q.e }); photo = e && e.photo; }
  else if (q.p && UUID.test(q.p)) { const a = await rpc('rlk_partage_article', { pid: q.p }); photo = a && a.photo; }
  const m = /^data:(image\/[a-z+.-]+);base64,(.+)$/i.exec(photo || '');
  if (!m) { res.statusCode = 302; res.setHeader('Location', '/logo-512.png'); res.end(); return; }
  res.setHeader('Content-Type', m[1]);
  res.setHeader('Cache-Control', 'public, s-maxage=3600, stale-while-revalidate=86400');
  res.end(Buffer.from(m[2], 'base64'));
};
