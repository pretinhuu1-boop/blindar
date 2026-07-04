// FIXTURE SEGURA — portal gov.br com acessibilidade eMAG.
// Menu Acessibilidade, atalhos accesskey, alto-contraste, mapa do site, VLibras.
export default function App() {
  return (
    <div>
      <a href="https://www.gov.br">Portal</a>
      <button accessKey="1">Acessibilidade</button>
      <a href="/mapa-do-site">Mapa do site</a>
      <button className="alto-contraste">Alto contraste</button>
      {/* VLibras.Widget embedado */}
    </div>
  );
}
