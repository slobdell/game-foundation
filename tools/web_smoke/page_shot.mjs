// Look at a choices page before publishing it: `make choices-shot NAME=<name>`.
//
// Usage: node page_shot.mjs <page.html> <out-dir> [--tap]
//
// Writes <out-dir>/phone.png (400 px wide, light) and <out-dir>/desktop.png (1280 px wide, dark), full page.
// The page runs against a pretend Artifact database (window.claude.use("db")), so the screenshots show it the way
// the director will see it: "Your picks save as you tap". With --tap it also taps the first option of every
// question (and types a note), checks each tap reached the pretend database as choices/<question id>, and saves
// <out-dir>/tapped.png. Fails on console errors.
import puppeteer from "puppeteer-core";
import { pathToFileURL } from "node:url";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";

const [pagePath, outDir, ...flags] = process.argv.slice(2);
if (!pagePath || !outDir) { console.error("usage: node page_shot.mjs <page.html> <out-dir> [--tap]"); process.exit(2); }
const tapMode = flags.includes("--tap");
mkdirSync(outDir, { recursive: true });
const url = pathToFileURL(resolve(pagePath)).href;

// A tiny stand-in for the Artifact runtime's db capability (the shape in _agents/choices_pages.md).
function fakeRuntime() {
  const store = (window.__store = {});
  const listeners = [];
  const snapshot = () => ({ docs: Object.entries(store).map(([p, d]) => ({ id: p.split("/").pop(), exists: true, data: () => d })) });
  const db = {
    doc: path => ({ set: async data => { store[path] = JSON.parse(JSON.stringify(data)); listeners.forEach(l => l(snapshot())); } }),
    collection: () => ({ onSnapshot: next => { listeners.push(next); setTimeout(() => next(snapshot()), 0); return () => {}; } }),
  };
  window.claude = { use: name => Promise.resolve(name === "db" ? db : null) };
}

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME ?? (process.platform === "darwin" ? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" : "/usr/bin/google-chrome"),
  headless: true,
  args: ["--hide-scrollbars"],
});
const problems = [];
try {
  for (const [name, width, scheme] of [["phone", 400, "light"], ["desktop", 1280, "dark"]]) {
    const page = await browser.newPage();
    page.on("console", m => { if (m.type() === "error" && !/fonts\.(googleapis|gstatic)/.test(m.text())) problems.push(`${name}: console error: ${m.text()}`); });
    page.on("pageerror", e => problems.push(`${name}: uncaught exception: ${e.message}`));
    await page.evaluateOnNewDocument(fakeRuntime);
    await page.emulateMediaFeatures([{ name: "prefers-color-scheme", value: scheme }]);
    await page.setViewport({ width, height: 900, deviceScaleFactor: 1 });
    await page.goto(url, { waitUntil: "networkidle0", timeout: 30000 }).catch(() => page.goto(url, { waitUntil: "load" }));
    await new Promise(r => setTimeout(r, 300));
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    if (overflow > 0) problems.push(`${name}: the page scrolls sideways by ${overflow}px`);
    await page.screenshot({ path: `${outDir}/${name}.png`, fullPage: true });
    console.log(`screenshot: ${outDir}/${name}.png`);

    if (tapMode && name === "phone") {
      const questions = await page.evaluate(() => JSON.parse(document.getElementById("page-data").textContent).questions);
      for (const q of questions) {
        const sel = q.kind === "keep_redo" ? `#q-${q.id} .verdict button` : `#q-${q.id} .pickbtn`;
        await page.click(sel);
        await page.type(`#why-${q.id}`, "because it is cool");
        await page.click("h1"); // blur: the note saves
      }
      await new Promise(r => setTimeout(r, 500));
      const store = await page.evaluate(() => window.__store);
      for (const q of questions) {
        const d = store[`choices/${q.id}`];
        const want = q.kind === "keep_redo" ? "keep" : q.options[0].id;
        const got = d && (Array.isArray(d.pick) ? d.pick[0] : d.pick);
        if (got !== want || d.note !== "because it is cool" || !d.at) problems.push(`tap: choices/${q.id} saved ${JSON.stringify(d)}, wanted pick ${want} + the note`);
        else console.log(`tap saved: choices/${q.id} = ${JSON.stringify(d)}`);
      }
      const saved = await page.$$eval(".saved", els => els.map(e => e.textContent));
      if (saved.some(t => t !== "Saved ✓")) problems.push(`tap: badges read ${JSON.stringify(saved)}`);
      await page.screenshot({ path: `${outDir}/tapped.png`, fullPage: true });
      console.log(`screenshot: ${outDir}/tapped.png`);
    }
    await page.close();
  }
} catch (e) {
  problems.push(`page shot failed: ${e.message}`);
} finally {
  await browser.close();
}
if (problems.length) { console.error("\nPAGE SHOT FAILED:\n  " + problems.join("\n  ")); process.exit(1); }
console.log("\nPAGE SHOT PASSED");
