// Page de partage : donne aux réseaux sociaux (WhatsApp, Facebook...) un aperçu avec la photo
// de l'événement ou de l'article, puis renvoie les visiteurs vers l'application.
const { rpc, esc, host, UUID } = require('./_lib');
const BOTS = /(facebookexternalhit|facebot|whatsapp|twitterbot|linkedinbot|slackbot|telegrambot|discordbot|skypeuripreview|applebot|googlebot|bingbot|pinterest|embedly|vkshare|redditbot|signal|viber|line-poker)/i;

module.exports = async (req, res) => {
  const q = req.query || {};
  const base = host(req);
  let titre = 'Rézo la Kour', desc = 'Partage de fruits et légumes entre voisins, contre le gaspillage.', image = base + '/logo-512.png', dest = '/';
  if (q.e && UUID.test(q.e)) {
    dest = '/#biyetri';
    const e = await rpc('rlk_partage_evenement', { ev: q.e });
    if (e) {
      const d = new Date(e.date_debut);
      const quand = d.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Indian/Reunion' }) + ' à ' + d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit', timeZone: 'Indian/Reunion' });
      titre = e.titre;
      desc = [quand, e.quartier, e.objet].filter(Boolean).join(' · ') + ' — Rézo la Kour';
      if (e.photo) image = base + '/api/img?e=' + q.e;
    }
  } else if (q.p && UUID.test(q.p)) {
    dest = '/#boutik';
    const a = await rpc('rlk_partage_article', { pid: q.p });
    if (a) {
      titre = a.nom;
      desc = (a.description ? a.description + ' · ' : '') + 'À la Boutik de Rézo la Kour';
      if (a.photo) image = base + '/api/img?p=' + q.p;
    }
  }
  const ua = req.headers['user-agent'] || '';
  if (!BOTS.test(ua)) { res.statusCode = 302; res.setHeader('Location', dest); res.end(); return; }
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'public, s-maxage=300, stale-while-revalidate=600');
  res.end('<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>' + esc(titre) + '</title>'
    + '<meta property="og:type" content="website"><meta property="og:site_name" content="Rézo la Kour">'
    + '<meta property="og:title" content="' + esc(titre) + '"><meta property="og:description" content="' + esc(desc) + '">'
    + '<meta property="og:image" content="' + esc(image) + '"><meta property="og:url" content="' + esc(base + req.url) + '">'
    + '<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="' + esc(titre) + '">'
    + '<meta name="twitter:description" content="' + esc(desc) + '"><meta name="twitter:image" content="' + esc(image) + '">'
    + '<meta name="description" content="' + esc(desc) + '"></head><body><a href="' + esc(base + dest) + '">' + esc(titre) + '</a>'
    + '<script>location.replace(' + JSON.stringify(dest) + ')</script></body></html>');
};
