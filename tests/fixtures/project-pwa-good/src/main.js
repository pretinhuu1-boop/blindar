// FIXTURE LIMPA — registra o service worker.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js');
}
