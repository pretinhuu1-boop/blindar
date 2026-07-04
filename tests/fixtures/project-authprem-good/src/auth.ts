// FIXTURE SEGURA — comentarios neutros.
export function save(res: any, token: string) {
  res.cookie("session", token, { httpOnly: true, secure: true, sameSite: "strict" });
}
