#!/usr/bin/env node
/**
 * blindar SARIF 2.1.0 converter
 * ============================================================
 *
 * Standalone Node.js (20+) script that converts blindar's
 * proprietary JSON findings (`.blindar/results/check-*.json` +
 * `.blindar/run-report.json`) into SARIF 2.1.0 — the format
 * consumed by GitHub Code Scanning, Azure DevOps and SonarQube.
 *
 * Spec: https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
 *
 * Zero runtime dependencies. Uses only Node 20 stdlib
 * (fs, path, url, util.parseArgs).
 *
 * --------------------------------------------------------------
 * USAGE
 * --------------------------------------------------------------
 *   node sarif-converter.js [--input DIR] [--output FILE] [--help]
 *
 *   --input DIR    Directory with `check-*.json` files.
 *                  Default: ".blindar/results"
 *   --output FILE  Write SARIF JSON to FILE.
 *                  Omit to print to stdout.
 *   --help         Show usage and exit.
 *
 * Exit codes:
 *   0 — success (SARIF written, even if zero findings)
 *   1 — input dir missing / unreadable
 *   2 — invalid CLI args
 *
 * --------------------------------------------------------------
 * FUTURE INTEGRATION (blindar-run.sh)
 * --------------------------------------------------------------
 * When/if `blindar-run.sh` grows a `--sarif PATH` flag, after the
 * pipeline finishes it should invoke:
 *
 *   node "$SKILL_DIR/scripts/sarif-converter.js" \
 *        --input  ".blindar/results" \
 *        --output "$SARIF_PATH"
 *
 * Then upload `$SARIF_PATH` in CI, e.g.:
 *
 *   - uses: github/codeql-action/upload-sarif@v3
 *     with: { sarif_file: blindar.sarif.json }
 *
 * This script does NOT modify blindar-run.sh — it's a standalone
 * post-processor so a separate agent can wire the flag.
 *
 * --------------------------------------------------------------
 * INPUT SCHEMA (blindar/check-result@v1)
 * --------------------------------------------------------------
 *   {
 *     "schema": "blindar/check-result@v1",
 *     "agent":  "check-mock-killer",
 *     "status": "passed|failed|skipped|deferred",
 *     "git_sha": "abc123",
 *     "findings_count": N,
 *     "findings": [
 *       { "severity": "crit|high|med|low",
 *         "message":  "...",
 *         "file":     "src/foo.ts",
 *         "line":     42 }
 *     ]
 *   }
 *
 * --------------------------------------------------------------
 * SEVERITY MAPPING
 * --------------------------------------------------------------
 *   crit, high -> "error"
 *   med        -> "warning"
 *   low        -> "note"
 *   (unknown)  -> "none"
 */

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { parseArgs } = require('node:util');

const SCRIPT_NAME = 'sarif-converter.js';
const SARIF_VERSION = '2.1.0';
const SARIF_SCHEMA =
  'https://docs.oasis-open.org/sarif/sarif/v2.1.0/schemas/sarif-schema-2.1.0.json';
const TOOL_VERSION = '1.0.0';
const TOOL_INFO_URI = 'https://github.com/maykonlong/blindar';

function printHelp() {
  const help = `${SCRIPT_NAME} — blindar -> SARIF 2.1.0 converter

USAGE:
  node ${SCRIPT_NAME} [--input DIR] [--output FILE]
  node ${SCRIPT_NAME} --help

OPTIONS:
  --input  DIR     Directory containing check-*.json files
                   (default: .blindar/results)
  --output FILE    Write SARIF to FILE (default: stdout)
  --help           Show this help and exit

EXIT CODES:
  0   success
  1   input directory missing / unreadable
  2   invalid CLI arguments

EXAMPLE:
  node ${SCRIPT_NAME} --input .blindar/results --output blindar.sarif.json
`;
  process.stdout.write(help);
}

/** Map blindar severity -> SARIF level. */
function severityToLevel(sev) {
  switch (String(sev || '').toLowerCase()) {
    case 'crit':
    case 'critical':
    case 'high':
      return 'error';
    case 'med':
    case 'medium':
      return 'warning';
    case 'low':
    case 'info':
      return 'note';
    default:
      return 'none';
  }
}

/** Normalize file path for SARIF (relative, forward slashes, no leading "./"). */
function normalizeUri(file) {
  if (!file) return null;
  let uri = String(file).replace(/\\/g, '/');
  if (uri.startsWith('./')) uri = uri.slice(2);
  return uri;
}

/**
 * Coerce a finding.line value into a positive integer.
 * blindar findings occasionally store a snippet string in "line"
 * (the matched source line, not a number). In that case we omit
 * `region` rather than emit garbage, since SARIF startLine must be
 * a positive integer.
 */
function coerceLine(line) {
  if (line == null) return null;
  if (typeof line === 'number' && Number.isFinite(line) && line >= 1) {
    return Math.floor(line);
  }
  if (typeof line === 'string') {
    const n = Number.parseInt(line, 10);
    if (Number.isFinite(n) && n >= 1) return n;
  }
  return null;
}

/** Stable rule id derived from agent + severity, e.g. "blindar.mock-killer.med". */
function buildRuleId(agent, severity) {
  const cleanAgent = String(agent || 'unknown').replace(/^check-/, '');
  const sev = String(severity || 'none').toLowerCase();
  return `blindar.${cleanAgent}.${sev}`;
}

/** Convert one finding -> SARIF result object. */
function findingToResult(finding, agent) {
  const level = severityToLevel(finding.severity);
  const ruleId = buildRuleId(agent, finding.severity);
  const message = String(finding.message || '(no message)');

  const result = {
    ruleId,
    level,
    message: { text: message },
  };

  const uri = normalizeUri(finding.file);
  if (uri) {
    const physicalLocation = {
      artifactLocation: { uri },
    };
    const startLine = coerceLine(finding.line);
    if (startLine != null) {
      physicalLocation.region = { startLine };
    }
    result.locations = [{ physicalLocation }];
  }

  return { result, ruleId, level, severity: finding.severity };
}

/**
 * Convert one parsed check-*.json -> SARIF `run` object.
 * Each agent becomes its own run with its own tool.driver.
 */
function checkToRun(check, sourceFile) {
  const agent = check.agent || path.basename(sourceFile, '.json');
  const findings = Array.isArray(check.findings) ? check.findings : [];

  const rulesMap = new Map();
  const results = [];

  for (const f of findings) {
    const { result, ruleId, level, severity } = findingToResult(f, agent);
    results.push(result);
    if (!rulesMap.has(ruleId)) {
      rulesMap.set(ruleId, {
        id: ruleId,
        name: ruleId.replace(/\./g, '_'),
        shortDescription: {
          text: `${agent} (${severity || 'unknown'})`,
        },
        fullDescription: {
          text: `Finding produced by blindar agent "${agent}" at severity "${severity || 'unknown'}".`,
        },
        defaultConfiguration: { level },
        helpUri: TOOL_INFO_URI,
      });
    }
  }

  return {
    tool: {
      driver: {
        name: agent,
        version: TOOL_VERSION,
        informationUri: TOOL_INFO_URI,
        semanticVersion: TOOL_VERSION,
        rules: [...rulesMap.values()],
      },
    },
    invocations: [
      {
        executionSuccessful: check.status !== 'errored',
        exitCode: typeof check.exit_code === 'number' ? check.exit_code : 0,
        endTimeUtc: check.ran_at || undefined,
      },
    ],
    versionControlProvenance: check.git_sha
      ? [{ revisionId: check.git_sha, repositoryUri: TOOL_INFO_URI }]
      : undefined,
    results,
    properties: {
      'blindar.agent': agent,
      'blindar.status': check.status || 'unknown',
      'blindar.findings_count':
        typeof check.findings_count === 'number'
          ? check.findings_count
          : findings.length,
    },
  };
}

/** Read every check-*.json from `dir`, parse, return list of {check, file}. */
function loadChecks(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir);
  } catch (err) {
    throw new Error(`cannot read input dir "${dir}": ${err.message}`);
  }
  const checks = [];
  for (const name of entries.sort()) {
    if (!name.startsWith('check-') || !name.endsWith('.json')) continue;
    const full = path.join(dir, name);
    let parsed;
    try {
      const raw = fs.readFileSync(full, 'utf8');
      parsed = JSON.parse(raw);
    } catch (err) {
      process.stderr.write(
        `[${SCRIPT_NAME}] WARN: skipping ${name}: ${err.message}\n`,
      );
      continue;
    }
    if (parsed && parsed.schema && !parsed.schema.startsWith('blindar/check-result')) {
      process.stderr.write(
        `[${SCRIPT_NAME}] WARN: ${name} schema "${parsed.schema}" is not blindar/check-result — including anyway\n`,
      );
    }
    checks.push({ check: parsed, file: full });
  }
  return checks;
}

/** Build the full SARIF document. */
function buildSarif(checks) {
  const runs = checks.map(({ check, file }) => checkToRun(check, file));
  return {
    $schema: SARIF_SCHEMA,
    version: SARIF_VERSION,
    runs,
  };
}

function main(argv) {
  let parsed;
  try {
    parsed = parseArgs({
      args: argv,
      options: {
        input: { type: 'string', short: 'i' },
        output: { type: 'string', short: 'o' },
        help: { type: 'boolean', short: 'h', default: false },
      },
      allowPositionals: false,
      strict: true,
    });
  } catch (err) {
    process.stderr.write(`[${SCRIPT_NAME}] ${err.message}\n`);
    printHelp();
    process.exit(2);
  }

  if (parsed.values.help) {
    printHelp();
    process.exit(0);
  }

  const inputDir = parsed.values.input || '.blindar/results';
  const outputFile = parsed.values.output || null;

  if (!fs.existsSync(inputDir)) {
    process.stderr.write(
      `[${SCRIPT_NAME}] ERROR: input dir not found: ${inputDir}\n`,
    );
    process.exit(1);
  }

  let checks;
  try {
    checks = loadChecks(inputDir);
  } catch (err) {
    process.stderr.write(`[${SCRIPT_NAME}] ERROR: ${err.message}\n`);
    process.exit(1);
  }

  const sarif = buildSarif(checks);
  const out = JSON.stringify(sarif, null, 2);

  if (outputFile) {
    fs.mkdirSync(path.dirname(path.resolve(outputFile)), { recursive: true });
    fs.writeFileSync(outputFile, out + '\n', 'utf8');
    const totalResults = sarif.runs.reduce((n, r) => n + r.results.length, 0);
    process.stderr.write(
      `[${SCRIPT_NAME}] wrote ${sarif.runs.length} run(s), ${totalResults} result(s) -> ${outputFile}\n`,
    );
  } else {
    process.stdout.write(out + '\n');
  }
  process.exit(0);
}

if (require.main === module) {
  main(process.argv.slice(2));
}

module.exports = {
  severityToLevel,
  normalizeUri,
  coerceLine,
  buildRuleId,
  findingToResult,
  checkToRun,
  buildSarif,
  loadChecks,
};
