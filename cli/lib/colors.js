// Zero-deps ANSI colors. Substitui kleur.
const noColor = !process.stdout.isTTY || process.env.NO_COLOR;
const w = code => s => noColor ? String(s) : `\x1b[${code}m${s}\x1b[0m`;
export default {
  red: w('31'), green: w('32'), yellow: w('33'), blue: w('34'),
  cyan: w('36'), gray: w('90'), bold: w('1'), dim: w('2'),
};
