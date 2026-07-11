// FIXTURE VULNERAVEL — open redirect client-side.
// Pega ?url= da query e redireciona sem validar destino.
function handleReturn() {
  const params = new URLSearchParams(location.search);
  const returnUrl = params.get('url');
  location.href = returnUrl; // vai pra qualquer lugar — phishing
}

handleReturn();
