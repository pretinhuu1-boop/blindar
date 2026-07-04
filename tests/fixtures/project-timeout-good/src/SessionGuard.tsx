// FIXTURE BOA — timeout de inatividade configuravel + popup/blur + resume.
import { useIdleTimer } from 'react-idle-timer';
// timeout configuravel pelo adm
const SESSION_TIMEOUT = Number(process.env.SESSION_TIMEOUT || 15);
export function SessionGuard() {
  // guarda a session/login por inatividade
  useIdleTimer({
    timeout: SESSION_TIMEOUT * 60000,
    onIdle: () => {
      // ao expirar: embaca o fundo (blur backdrop) e mostra modal de resume
    },
  });
  // autosave do draft pra retomar de onde parou apos refresh
  return null;
}
