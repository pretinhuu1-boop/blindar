// FIXTURE SEGURA — checa lista de supressao antes de enviar.
import { resend } from './client';
import { isSuppressed } from './suppression';
export async function welcome(to: string) {
  if (await isSuppressed(to)) return;
  return resend.emails.send({ to, subject: 'oi', html: '<p>oi</p>' });
}
