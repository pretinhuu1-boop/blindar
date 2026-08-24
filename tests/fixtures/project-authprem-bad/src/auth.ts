// FIXTURE VULNERAVEL — comentarios neutros.
export function save(jwt: string) {
  localStorage.setItem("token", jwt);
}
export function saveSession(jwt: string) {
  sessionStorage.setItem("access_token", jwt);
}
export function saveCookie(jwt: string) {
  document.cookie = "session=" + jwt;
}
