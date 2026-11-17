/* Links from the info pages (About, Privacy, Features, guides…) back to the
   site: a plain "/" shows the "Who's it for?" chooser, so a visitor who already
   picked their field would land on it again. Send them back to their field's
   page instead (/physio, /fr/therapy…), in the language they're reading.
   Visitors who never picked a field keep going to "/". */
(function () {
  var PATH = { physio: 'physio', kinesiology: 'kinesiology', osteo: 'osteopathy', occupational: 'occupational-therapy',
    neuropsych: 'neuropsychology', nutrition: 'nutrition', sports: 'sports', fitness: 'fitness', recovery: 'addiction',
    schools: 'schools', therapy: 'therapy', individual: 'individual' };
  var field = null;
  try { field = localStorage.getItem('btw_field'); } catch (e) {}
  if (!field || !PATH[field]) return;
  var HOME = /^\/(fr\/?)?(#.*)?$/;  // "/", "/#book-demo", "/fr", "/fr/#…"
  function target(href) {
    var m = HOME.exec(href);
    if (!m) return null;
    var fr = !!m[1] || (document.documentElement.lang || '').toLowerCase().indexOf('fr') === 0;
    return (fr ? '/fr/' : '/') + PATH[field] + (m[2] || '');
  }
  function fix(a) {
    var orig = a.getAttribute('data-home-href') || a.getAttribute('href');
    var t = orig && target(orig);
    if (!t) return;
    a.setAttribute('data-home-href', orig);
    a.setAttribute('href', t);
  }
  function fixAll() { document.querySelectorAll('a[href]').forEach(fix); }
  // Re-evaluate at click time too, so a language switch on the page is respected.
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (a) fix(a);
  }, true);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fixAll); else fixAll();
})();
