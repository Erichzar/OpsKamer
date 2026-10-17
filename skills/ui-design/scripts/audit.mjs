#!/usr/bin/env node
/**
 * audit.mjs - run an axe-core accessibility pass over a running web app so the
 * visual review can focus on taste rather than mechanics.
 */
import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { AxeBuilder } from "@axe-core/playwright";
import { chromium } from "playwright";

const OPTION_SPEC = {
	url: { type: "string" },
	paths: { type: "string", default: "/" },
	widths: { type: "string", default: "390,1440" },
	tags: { type: "string", default: "wcag2a,wcag2aa,wcag21a,wcag21aa,wcag22aa" },
	json: { type: "string" },
	help: { type: "boolean", default: false },
};

const HELP = `audit.mjs - axe-core accessibility and contrast audit of a running web app.

Usage:
  node scripts/audit.mjs --url <url> [options]

Options:
  --url <url>     Base URL of the running app. Required.
  --paths <csv>   Route paths to audit, relative to --url. Write them without a
                  leading slash ("pricing,docs"). Default: / (the root route)
  --widths <csv>  Viewport widths in CSS px to audit at. Default: 390,1440
  --tags <csv>    axe rule tags to run.
                  Default: wcag2a,wcag2aa,wcag21a,wcag21aa,wcag22aa
  --json <file>   Also write the full unabridged results as JSON to this file.
                  Default: none (stdout report only).
  --help          Show this help.

Output:
  Violations grouped by impact (critical, serious, moderate, minor), each with
  its rule id, help text, where it was seen, and up to 3 offending elements.
  Console output is capped so it stays small; use --json for everything.

Notes:
  Route paths may be written with or without a leading slash: "pricing" and
  "/pricing" are the same route. The slashless form is the portable spelling and
  is recommended, because Git Bash rewrites a bare leading "/" argument into the
  Git install path (that rewrite is detected and undone, but only for Git Bash).

Exit codes:
  0  no critical or serious violations (verdict PASS)
  1  at least one critical or serious violation (verdict FAIL)
  2  bad arguments, or the app could not be reached

Example:
  node scripts/audit.mjs --url http://localhost:5173 --paths pricing,docs --json a11y.json
`;

const IMPACT_ORDER = ["critical", "serious", "moderate", "minor"];
const MAX_NODES_PER_RULE = 3;
const MAX_OUTPUT_LINES = 120;
const NAV_TIMEOUT_MS = 20000;
const IDLE_TIMEOUT_MS = 8000;
const VIEWPORT_HEIGHT = 900;

let args;
try {
	args = parseArgs({ options: OPTION_SPEC }).values;
} catch (error) {
	console.error(`${error.message}\nValid flags: ${Object.keys(OPTION_SPEC).map((f) => `--${f}`).join(", ")}`);
	process.exit(2);
}

if (args.help) {
	process.stdout.write(HELP);
	process.exit(0);
}

if (!args.url) {
	console.error("Missing required --url. Run with --help for usage.");
	process.exit(2);
}

const widths = args.widths
	.split(",")
	.map((value) => Number(value.trim()))
	.filter((value) => value > 0);
const routes = args.paths
	.split(",")
	.map((value) => value.trim())
	.filter((value) => value.length > 0)
	.map((value) => {
		// Git Bash rewrites a bare leading "/" into the Git install directory
		// ("/pricing" arrives as "C:/Program Files/Git/pricing"). Undo that, then
		// accept "pricing", "./pricing", and "/pricing" as the same route.
		const unmangled = value.replace(/^[A-Za-z]:[\\/](?:.*[\\/])?Git(?:[\\/]|$)/i, "/");
		const relative = unmangled.replace(/^\.\/+/, "/");
		return relative.startsWith("/") ? relative : `/${relative}`;
	});
const tags = args.tags
	.split(",")
	.map((value) => value.trim())
	.filter((value) => value.length > 0);

if (widths.length === 0 || routes.length === 0 || tags.length === 0) {
	console.error("Invalid --widths, --paths, or --tags: each must be a non-empty comma-separated list.");
	process.exit(2);
}

const byRule = new Map();
const rawRuns = [];
const browser = await chromium.launch();
try {
	for (const width of widths) {
		const context = await browser.newContext({ viewport: { width, height: VIEWPORT_HEIGHT } });
		const page = await context.newPage();

		for (const route of routes) {
			const target = new URL(route, args.url).href;
			try {
				await page.goto(target, { waitUntil: "load", timeout: NAV_TIMEOUT_MS });
			} catch (error) {
				const reason = /ERR_CONNECTION_REFUSED|ECONNREFUSED/.test(error.message)
					? "connection refused - is the dev server running?"
					: /ERR_NAME_NOT_RESOLVED/.test(error.message)
						? "host could not be resolved"
						: error.message.split("\n")[0];
				console.error(`Cannot load ${target}: ${reason}`);
				await browser.close();
				process.exit(2);
			}
			await page.waitForLoadState("networkidle", { timeout: IDLE_TIMEOUT_MS }).catch(() => {});

			const results = await new AxeBuilder({ page }).withTags(tags).analyze();
			rawRuns.push({ route, width, violations: results.violations });

			for (const violation of results.violations) {
				const entry = byRule.get(violation.id) ?? {
					id: violation.id,
					impact: violation.impact ?? "minor",
					help: violation.help,
					helpUrl: violation.helpUrl,
					locations: new Set(),
					nodes: new Map(),
				};
				entry.locations.add(`${route} @${width}w`);
				for (const node of violation.nodes) {
					const selector = node.target.flat(Number.POSITIVE_INFINITY).join(" >> ");
					if (!entry.nodes.has(selector)) {
						entry.nodes.set(selector, (node.failureSummary ?? "").replace(/\s*\n\s*/g, "; ").trim());
					}
				}
				byRule.set(violation.id, entry);
			}
		}

		await context.close();
	}
} finally {
	await browser.close();
}

if (args.json) {
	const jsonPath = resolve(process.cwd(), args.json);
	await writeFile(jsonPath, `${JSON.stringify(rawRuns, null, 2)}\n`, "utf8");
	console.log(`Full results written to ${jsonPath}`);
}

const lines = [
	"ACCESSIBILITY AUDIT",
	`url:    ${args.url}`,
	`paths:  ${routes.join(", ")}`,
	`widths: ${widths.join(", ")}`,
	`tags:   ${tags.join(", ")}`,
];

const counts = { critical: 0, serious: 0, moderate: 0, minor: 0 };
for (const entry of byRule.values()) {
	counts[entry.impact] = (counts[entry.impact] ?? 0) + 1;
}

let omittedNodes = 0;
for (const impact of IMPACT_ORDER) {
	const entries = [...byRule.values()].filter((entry) => entry.impact === impact);
	if (entries.length === 0) {
		continue;
	}
	const elementCount = entries.reduce((total, entry) => total + entry.nodes.size, 0);
	lines.push("", `${impact.toUpperCase()} (${entries.length} rule(s), ${elementCount} element(s))`);

	for (const entry of entries) {
		lines.push(`  ${entry.id} - ${entry.help}`);
		lines.push(`    seen at: ${[...entry.locations].join(", ")}`);
		lines.push(`    ${entry.helpUrl}`);
		let shown = 0;
		for (const [selector, summary] of entry.nodes) {
			const withinCap = shown < MAX_NODES_PER_RULE;
			const withinBudget = lines.length < MAX_OUTPUT_LINES - 4;
			if (!withinCap || !withinBudget) {
				omittedNodes += 1;
				continue;
			}
			shown += 1;
			lines.push(`    ${shown}. ${selector.slice(0, 110)}`);
			if (summary) {
				lines.push(`       ${summary.slice(0, 160)}`);
			}
		}
	}
}

if (byRule.size === 0) {
	lines.push("", "No violations found.");
}
if (omittedNodes > 0) {
	lines.push("", `(${omittedNodes} further offending element(s) omitted; use --json for the full report)`);
}

const failed = counts.critical + counts.serious > 0;
lines.push(
	"",
	`SUMMARY critical=${counts.critical} serious=${counts.serious} moderate=${counts.moderate} minor=${counts.minor} | VERDICT: ${failed ? "FAIL" : "PASS"}`,
);

console.log(lines.join("\n"));
process.exit(failed ? 1 : 0);
