// FIXTURE SEGURA — redirect validado por allowlist / caminho relativo.
const ALLOW = ['app.example.com', 'account.example.com'];

function safeRedirect(raw) {
  if (raw && raw.startsWith('/') && !raw.startsWith('//')) return raw;
  try {
    const u = new URL(raw, location.origin);
    if (ALLOW.includes(u.host)) return u.href;
  } catch (e) { /* invalido */ }
  return '/';
}

function handleReturn() {
  const params = new URLSearchParams(location.search);
  location.href = safeRedirect(params.get('url'));
}

handleReturn();
