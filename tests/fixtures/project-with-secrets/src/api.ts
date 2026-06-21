// FIXTURE — strings que disparam regex blindar mas não são secrets reais.
// Mascaradas pra evitar GitHub Push Protection. Padrão suficiente pros checks.
// Pra ver detecção real, troque "REDACTED" pelo padrão completo localmente.

export const config = {
  stripeKey:    'sk_' + 'live_' + 'REDACTED_NOT_A_REAL_KEY_FIXTURE',
  openaiKey:    'sk-' + 'REDACTED_NOT_A_REAL_KEY_FIXTURE_xyz789',
  awsAccessKey: 'AKIA' + 'REDACTED_FIXTURE_X',
  githubToken:  'ghp_' + 'REDACTED_NOT_A_REAL_TOKEN_FIXTURE',
  password:     "Hardcoded" + "Pass" + "Word123!",
  apiUrl:       'https://api.production.example.com/v1',
};
