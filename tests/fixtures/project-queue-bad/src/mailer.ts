// FIXTURE VULNERAVEL — trabalho pesado inline, sem fila.
import nodemailer from 'nodemailer';
export async function onSignup(to: string) {
  const t = nodemailer.createTransport({});
  await t.sendMail({ to, subject: 'welcome' });
}
