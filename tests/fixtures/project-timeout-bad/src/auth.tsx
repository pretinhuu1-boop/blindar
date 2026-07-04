// FIXTURE VULNERAVEL — tem sessao/login mas sem timeout de inatividade.
export function useAuth() {
  const login = async () => {
    // cria session
  };
  return { login };
}
