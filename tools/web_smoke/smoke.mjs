// Does the web export boot in a real browser? `make web-smoke`.
//
// Usage: node smoke.mjs <url> <screenshot.png> [seconds-to-play]
//
// Loads the page in headless Chrome (SwiftShader gives WebGL 2 without a GPU), waits for the Godot engine to start,
// lets the game run a few seconds, then saves a screenshot and checks three things:
//   1. no console errors and no uncaught exceptions (the game's push_error() shows up as a console error),
//   2. no file failed to load (a 404 for the .pck or .wasm),
//   3. the game drew something: the canvas is not one flat colour.
// Always writes the screenshot, so a person (or Claude) can look at what the browser really showed.
// Optional: WEB_SMOKE_MARKER=<text> also waits for the game to print that text.
import puppeteer from "puppeteer-core";

const [url, screenshotPath, playArg] = process.argv.slice(2);
if (!url || !screenshotPath) { console.error("usage: node smoke.mjs <url> <screenshot.png> [seconds]"); process.exit(2); }
const playMs = Number(playArg ?? 6) * 1000;
const BOOT_TIMEOUT_MS = Number(process.env.SMOKE_TIMEOUT_MS ?? 90_000);
const MARKER = process.env.WEB_SMOKE_MARKER || "";

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME ?? "/usr/bin/google-chrome",
  headless: true,
  args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--window-size=1280,720", "--autoplay-policy=no-user-gesture-required"],
});

const problems = [];
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 720 });

  let engineStarted, markerSeen;
  const started = new Promise((r) => (engineStarted = r));
  const marked = new Promise((r) => (markerSeen = r));
  page.on("console", (msg) => {
    const text = msg.text();
    console.log(`[browser:${msg.type()}] ${text}`);
    if (msg.type() === "error" && !/favicon/.test(msg.location()?.url ?? "")) problems.push(`console error: ${text}`);
    if (/Godot Engine v\d/.test(text)) engineStarted();
    if (MARKER && text.includes(MARKER)) markerSeen();
  });
  page.on("pageerror", (err) => problems.push(`uncaught exception: ${err.message}`));
  page.on("requestfailed", (req) => problems.push(`failed to load: ${req.url()} (${req.failure()?.errorText})`));
  page.on("response", (res) => { if (res.status() >= 400 && !res.url().endsWith("/favicon.ico")) problems.push(`HTTP ${res.status()}: ${res.url()}`); });

  // make starts the static server just before us; retry until it answers.
  for (let attempt = 0; ; attempt++) {
    try { await page.goto(url, { waitUntil: "load" }); break; }
    catch (err) { if (attempt >= 40) throw err; await new Promise((r) => setTimeout(r, 250)); }
  }
  const t0 = Date.now();
  const timeout = (ms) => new Promise((r) => setTimeout(() => r("timeout"), ms));
  if (await Promise.race([started.then(() => "ok"), timeout(BOOT_TIMEOUT_MS)]) === "timeout") {
    problems.push(`the Godot engine never started within ${BOOT_TIMEOUT_MS / 1000}s`);
  } else {
    console.log(`engine started after ${((Date.now() - t0) / 1000).toFixed(1)}s`);
    if (MARKER && await Promise.race([marked.then(() => "ok"), timeout(BOOT_TIMEOUT_MS)]) === "timeout") {
      problems.push(`the game never printed ${MARKER}`);
    }
    await new Promise((r) => setTimeout(r, playMs));
  }

  const shot = await page.screenshot({ path: screenshotPath });
  console.log(`screenshot saved: ${screenshotPath}`);

  // Is the picture more than one flat colour? Decode the screenshot in the page and count distinct colours.
  const stats = await page.evaluate(async (b64) => {
    const img = new Image();
    img.src = "data:image/png;base64," + b64;
    await img.decode();
    const c = new OffscreenCanvas(img.width, img.height);
    const g = c.getContext("2d");
    g.drawImage(img, 0, 0);
    const px = g.getImageData(0, 0, img.width, img.height).data;
    const colours = new Set();
    for (let i = 0; i < px.length; i += 4 * 97) colours.add((px[i] >> 3) << 10 | (px[i + 1] >> 3) << 5 | (px[i + 2] >> 3));
    return { colours: colours.size, canvas: !!document.querySelector("canvas") };
  }, Buffer.from(shot).toString("base64"));
  console.log(`canvas: ${stats.canvas ? "present" : "MISSING"}, ${stats.colours} distinct colours in the screenshot`);
  if (!stats.canvas) problems.push("no <canvas> on the page");
  if (stats.colours < 8) problems.push(`the screen is blank (${stats.colours} colours): the game drew nothing`);
} catch (err) {
  problems.push(`smoke harness failed: ${err.message}`);
} finally {
  await browser.close();
}

if (problems.length) {
  console.error("\nWEB SMOKE FAILED:\n  " + [...new Set(problems)].join("\n  "));
  process.exit(1);
}
console.log("\nWEB SMOKE PASSED");
