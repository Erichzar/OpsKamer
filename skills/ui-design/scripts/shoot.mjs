#!/usr/bin/env node
/**
 * shoot.mjs - capture screenshots of a running web app at several viewport
 * widths, so the rendered result can be reviewed visually.
 */
import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { chromium } from "playwright";

const OPTION_SPEC = {
	url: { type: "string" },
	paths: { type: "string", default: "/" },
	out: { type: "string", default: "./shots" },
	widths: { type: "string", default: "390,768,1440" },
	dark: { type: "boolean", default: false },
	full: { type: "boolean", default: false },
	wait: { type: "string", default: "400" },
	selector: { type: "string" },
	motion: { type: "boolean", default: false },
	help: { type: "boolean", default: false },
};

const HELP = `shoot.mjs - screenshot a running web app at several viewport widths.

Usage:
  node scripts/shoot.mjs --url <url> [options]

Options:
  --url <url>       Base URL of the running app. Required.
  --paths <csv>     Route paths to capture, relative to --url. Write them without
                    a leading slash ("pricing,docs"). Default: / (the root route)
  --out <dir>       Directory to write PNGs into. Created if missing. Default: ./shots
  --widths <csv>    Viewport widths in CSS px. Default: 390,768,1440
  --dark            Also capture every shot again with prefers-color-scheme: dark.
                    Default: light only.
  --full            Capture the full scrollable page instead of one viewport height.
                    Default: viewport only.
  --wait <ms>       Extra settle delay after the page goes idle. Default: 400
  --selector <css>  Screenshot only the first element matching this CSS selector,
                    instead of the page. Default: none (whole page/viewport).
  --motion          Leave animations and transitions running. Default: they are
                    frozen so repeated runs produce identical pixels.
  --help            Show this help.

Notes:
  Viewport height is fixed at 900px. Use --full for whole-page captures.
  Files are named <route>__<width>w__<light|dark>.png and overwritten on re-run.
  The root path "/" is named "home".
  Route paths may be written with or without a leading slash: "pricing" and
  "/pricing" are the same route. The slashless form is the portable spelling and
  is recommended, because Git Bash rewrites a bare leading "/" argument into the
  Git install path (that rewrite is detected and undone, but only for Git Bash).
  The final block of output lists the absolute path of every file written.

Example:
  node scripts/shoot.mjs --url http://localhost:5173 --paths pricing,docs --widths 390,1440 --dark
`;

const VIEWPORT_HEIGHT = 900;
const NAV_TIMEOUT_MS = 20000;
const IDLE_TIMEOUT_MS = 8000;

const FREEZE_MOTION_CSS = `*, *::before, *::after {
	animation-delay: 0.01ms !important;
	animation-duration: 0.01ms !important;
	animation-iteration-count: 1 !important;
	transition-delay: 0.01ms !important;
	transition-duration: 0.01ms !important;
	scroll-behavior: auto !important;
	caret-color: transparent !important;
}`;

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
if (widths.length === 0) {
	console.error(`Invalid --widths "${args.widths}". Expected a comma-separated list of positive numbers.`);
	process.exit(2);
}

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
if (routes.length === 0) {
	console.error(`Invalid --paths "${args.paths}". Expected a comma-separated list of route paths.`);
	process.exit(2);
}

const settleMs = Number(args.wait);
if (!Number.isFinite(settleMs) || settleMs < 0) {
	console.error(`Invalid --wait "${args.wait}". Expected a non-negative number of milliseconds.`);
	process.exit(2);
}

const schemes = args.dark ? ["light", "dark"] : ["light"];
const outDir = resolve(process.cwd(), args.out);
await mkdir(outDir, { recursive: true });

const written = [];
const browser = await chromium.launch();
try {
	for (const scheme of schemes) {
		for (const width of widths) {
			const context = await browser.newContext({
				viewport: { width, height: VIEWPORT_HEIGHT },
				colorScheme: scheme,
				deviceScaleFactor: 1,
			});
			const page = await context.newPage();
			page.setDefaultTimeout(NAV_TIMEOUT_MS);

			for (const route of routes) {
				const target = new URL(route, args.url).href;
				try {
					await page.goto(target, { waitUntil: "load", timeout: NAV_TIMEOUT_MS });
				} catch (error) {
					const reason = /ERR_CONNECTION_REFUSED|ERR_CONNECTION_RESET|ECONNREFUSED/.test(error.message)
						? "connection refused - is the dev server running?"
						: /ERR_NAME_NOT_RESOLVED|ERR_ADDRESS_UNREACHABLE/.test(error.message)
							? "host could not be resolved"
							: /Timeout/i.test(error.message)
								? `no response within ${NAV_TIMEOUT_MS}ms`
								: error.message.split("\n")[0];
					console.error(`Cannot load ${target}: ${reason}`);
					await browser.close();
					process.exit(1);
				}

				// Network idle is best-effort: dev servers hold HMR sockets open forever.
				await page.waitForLoadState("networkidle", { timeout: IDLE_TIMEOUT_MS }).catch(() => {});
				if (!args.motion) {
					await page.addStyleTag({ content: FREEZE_MOTION_CSS });
				}
				await page.waitForTimeout(settleMs);

				const slug =
					route
						.replace(/[?#].*$/, "")
						.replace(/^\/+|\/+$/g, "")
						.replace(/[^a-zA-Z0-9]+/g, "-") || "home";
				const file = resolve(outDir, `${slug}__${width}w__${scheme}.png`);

				if (args.selector) {
					const locator = page.locator(args.selector).first();
					if ((await locator.count()) === 0) {
						console.error(`Selector "${args.selector}" matched no element on ${target}.`);
						await browser.close();
						process.exit(1);
					}
					await locator.screenshot({ path: file });
				} else {
					await page.screenshot({ path: file, fullPage: args.full });
				}
				written.push(file);
			}

			await context.close();
		}
	}
} finally {
	await browser.close();
}

console.log(`Captured ${written.length} screenshot(s) at ${widths.join(", ")}px (${schemes.join(" + ")}).`);
console.log("SCREENSHOTS:");
for (const file of written) {
	console.log(file);
}
