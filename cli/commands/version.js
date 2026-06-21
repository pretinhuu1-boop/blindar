// blindar version
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

export default function version({ cliRoot, skillRoot }) {
  const cliPkg = JSON.parse(readFileSync(join(cliRoot, 'package.json'), 'utf8'));
  let skillVersion = 'unknown';
  try {
    skillVersion = readFileSync(join(skillRoot, 'VERSION'), 'utf8').trim();
  } catch {}
  console.log(`blindar CLI : v${cliPkg.version}`);
  console.log(`blindar skill: v${skillVersion}`);
  return 0;
}
