import React from 'react';

export function Dashboard() {
  console.log('rendering dashboard');  // ← deve ser detectado
  console.debug('debug info');          // ← idem

  const mockData = { user: 'fake' };    // ← mock fora de teste

  // TODO: implementar real auth                  ← TODO sem issue
  // FIXME: race condition

  return (
    <div>
      <button onClick={() => {}}>Salvar</button>   {/* ← onClick vazio CRIT */}
    </div>
  );
}
