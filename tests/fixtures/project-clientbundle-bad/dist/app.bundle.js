// FIXTURE VULNERAVEL — comentarios neutros. Chave secreta inlineada no bundle.
// Valor deliberadamente curto/FAKE: dispara o regex do blindar (sk_live_{16,})
// sem casar o secret-scanning do GitHub (que exige {24,}). Nao e chave real.
var C={stripe:"sk_live_FAKEexamplekey00"};export default C;
