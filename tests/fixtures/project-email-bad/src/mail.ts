// FIXTURE VULNERAVEL — comentarios neutros.
import { resend } from './client';
export function welcome(to: string) {
  return resend.emails.send({ to, subject: 'oi', html: '<p>oi</p>' });
}
