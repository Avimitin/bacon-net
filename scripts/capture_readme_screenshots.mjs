import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const serverPort = process.env.BACON_SCREENSHOT_PORT || "8000";
const origin = process.env.BACON_SCREENSHOT_ORIGIN ||
  `http://127.0.0.1:${serverPort}`;
const chromiumBin = process.env.CHROMIUM_BIN || "chromium";
const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));
const userDataDir = await mkdtemp(
  path.join(tmpdir(), "bacon-net-readme-chromium-"),
);
let chromium;
let socket;

try {
  chromium = spawn(
    chromiumBin,
    [
      "--headless=new",
      "--disable-gpu",
      "--disable-dev-shm-usage",
      "--disable-background-networking",
      "--disable-component-update",
      "--hide-scrollbars",
      "--no-default-browser-check",
      "--no-first-run",
      "--remote-debugging-address=127.0.0.1",
      "--remote-debugging-port=0",
      `--user-data-dir=${userDataDir}`,
      "about:blank",
    ],
    { stdio: ["ignore", "ignore", "pipe"] },
  );

  const devtoolsUrl = await waitForDevTools(chromium);
  const debuggingPort = new URL(devtoolsUrl).port;
  const targets = await fetch(`http://127.0.0.1:${debuggingPort}/json/list`)
    .then((response) => response.json());
  const target = targets.find((candidate) => candidate.type === "page");

  if (!target) throw new Error("No Chromium page target found");

  socket = new WebSocket(target.webSocketDebuggerUrl);
  const pending = new Map();
  let commandId = 0;

  socket.addEventListener("message", ({ data }) => {
    const message = JSON.parse(data);
    if (!message.id || !pending.has(message.id)) return;
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) {
      reject(
        new Error(
          `${message.error.message}: ${JSON.stringify(message.error.data)}`,
        ),
      );
    } else resolve(message.result);
  });

  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });

  function send(method, params = {}) {
    const id = ++commandId;
    socket.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) =>
      pending.set(id, { resolve, reject })
    );
  }

  async function evaluate(expression, awaitPromise = false) {
    const result = await send("Runtime.evaluate", {
      expression,
      awaitPromise,
      returnByValue: true,
    });
    if (result.exceptionDetails) {
      throw new Error(
        result.exceptionDetails.exception?.description ||
          result.exceptionDetails.text,
      );
    }
    return result.result.value;
  }

  async function waitFor(expression, label) {
    for (let attempt = 0; attempt < 100; attempt += 1) {
      try {
        if (await evaluate(`Boolean(${expression})`)) return;
      } catch {
        // A navigation can briefly invalidate the execution context.
      }
      await delay(200);
    }
    const body = await evaluate(
      "document.body?.innerText?.slice(0, 1200) || ''",
    );
    throw new Error(`Timed out waiting for ${label}. Page text:\n${body}`);
  }

  async function setViewport(width, height, mobile = false) {
    await send("Emulation.setDeviceMetricsOverride", {
      width,
      height,
      screenWidth: width,
      screenHeight: height,
      deviceScaleFactor: 1,
      mobile,
    });
  }

  async function navigate(route, marker) {
    await send("Page.navigate", { url: `${origin}/webui/#${route}` });
    await waitFor(
      `document.readyState === 'complete' && document.body?.innerText?.includes(${
        JSON.stringify(marker)
      })`,
      marker,
    );
    await evaluate(
      `new Promise(async (resolve) => {
      await document.fonts.ready;
      const style = document.createElement('style');
      style.textContent = '* { animation: none !important; transition: none !important; caret-color: transparent !important; }';
      document.head.appendChild(style);
      window.scrollTo(0, 0);
      setTimeout(resolve, 700);
    })`,
      true,
    );
  }

  async function screenshot(relativePath, cropToApp = true) {
    const clip = cropToApp
      ? await evaluate(`(() => {
        const app = document.querySelector('#main-content');
        const contentBottom = app
          ? app.getBoundingClientRect().top + app.scrollHeight
          : document.documentElement.scrollHeight;
        return {
          x: 0,
          y: 0,
          width: document.documentElement.clientWidth,
          height: Math.ceil(Math.max(contentBottom, window.innerHeight)),
          scale: 1
        };
      })()`)
      : undefined;
    const { data } = await send("Page.captureScreenshot", {
      format: "png",
      fromSurface: true,
      captureBeyondViewport: Boolean(clip),
      ...(clip ? { clip } : {}),
    });
    const destination = path.isAbsolute(relativePath)
      ? relativePath
      : path.resolve(repoRoot, relativePath);
    await writeFile(destination, Buffer.from(data, "base64"));
    console.log(`captured ${relativePath}`);
  }

  async function assertPageLayout(label) {
    const result = await evaluate(`(() => ({
      h1Count: document.querySelectorAll('main h1').length,
      hasMain: Boolean(document.querySelector('main#main-content')),
      hasSkipLink: Boolean(document.querySelector('a[href="#main-content"]')),
      viewportWidth: document.documentElement.clientWidth,
      pageWidth: document.documentElement.scrollWidth,
      overflowers: [...document.querySelectorAll('body *')]
        .map((element) => {
          const rect = element.getBoundingClientRect();
          return {
            tag: element.tagName.toLowerCase(),
            id: element.id,
            className: typeof element.className === 'string' ? element.className.slice(0, 120) : '',
            left: Math.round(rect.left),
            right: Math.round(rect.right),
            width: Math.round(rect.width)
          };
        })
        .filter((rect) => rect.left < -1 || rect.right > window.innerWidth + 1)
        .slice(0, 8),
      internalOverflow: [document.documentElement, document.body, ...document.querySelectorAll('body *')]
        .filter((element) => element.scrollWidth > element.clientWidth + 1)
        .map((element) => ({
          tag: element.tagName.toLowerCase(),
          id: element.id,
          className: typeof element.className === 'string' ? element.className.slice(0, 120) : '',
          clientWidth: element.clientWidth,
          scrollWidth: element.scrollWidth,
          overflowX: getComputedStyle(element).overflowX
        }))
        .sort((left, right) => (left.overflowX === 'visible' ? -1 : 1) - (right.overflowX === 'visible' ? -1 : 1))
        .slice(0, 12)
    }))()`);

    if (!result.hasMain || !result.hasSkipLink || result.h1Count !== 1) {
      throw new Error(`${label} has an invalid landmark or heading structure: ${JSON.stringify(result)}`);
    }

    if (result.pageWidth > result.viewportWidth + 1) {
      throw new Error(`${label} overflows horizontally: ${JSON.stringify(result)}`);
    }
  }

  async function assertOpenDialogFits(label) {
    const result = await evaluate(`(() => {
      const dialog = document.querySelector('.cds--modal.is-visible .cds--modal-container');
      if (!dialog) return null;
      const rect = dialog.getBoundingClientRect();
      return {
        left: Math.round(rect.left),
        right: Math.round(rect.right),
        width: Math.round(rect.width),
        viewportWidth: document.documentElement.clientWidth
      };
    })()`);
    if (!result || result.left < -1 || result.right > result.viewportWidth + 1) {
      throw new Error(`${label} does not fit the viewport: ${JSON.stringify(result)}`);
    }
  }

  await send("Page.enable");
  await send("Runtime.enable");
  await send("Network.enable");
  await send("Emulation.setTimezoneOverride", { timezoneId: "Asia/Shanghai" });
  await send("Emulation.setLocaleOverride", { locale: "en-US" });
  await setViewport(1440, 900);

  await navigate("/login", "Return to");
  await assertPageLayout("desktop login");
  await screenshot("docs/webui-login.png", false);

  await navigate("/register", "Make your");
  await assertPageLayout("desktop register");
  await screenshot("docs/webui-register.png", false);

  await setViewport(800, 900);
  await navigate("/login", "Return to");
  await assertPageLayout("medium login");
  await navigate("/register", "Make your");
  await assertPageLayout("medium register");

  await setViewport(390, 844, true);
  await navigate("/login", "Return to");
  await assertPageLayout("narrow login");
  await navigate("/register", "Make your");
  await assertPageLayout("narrow register");

  await setViewport(1440, 900);
  await navigate("/login", "Return to");

  const login = await evaluate(
    `fetch('/account/api/login', {
    method: 'POST',
    credentials: 'same-origin',
    headers: {'Content-Type': 'application/json', 'X-CSRF-Requested-With': 'fetch'},
    body: JSON.stringify({username: 'neonkite', password: 'readme-demo-only'})
  }).then(async (response) => ({status: response.status, body: await response.json()}))`,
    true,
  );

  if (login.status !== 200) {
    throw new Error(`Login failed: ${JSON.stringify(login)}`);
  }

  await evaluate(`
  localStorage.setItem('bn.admin', 'readme-demo-admin');
  localStorage.setItem('bn.konami', JSON.stringify({
    E0040123456789AB: '1234-5678-9012-3456',
    E0040FEDCBA98765: '9876-5432-1098-7654'
  }));
`);

  const me = await evaluate(
    "fetch('/account/api/me', {credentials: 'same-origin'}).then(async (response) => ({status: response.status, body: await response.json()}))",
    true,
  );

  if (me.status !== 200 || !me.body.admin) {
    throw new Error(`Admin session check failed: ${JSON.stringify(me)}`);
  }

  // The manual login changed the cookie outside React's session state. Reload
  // once so SessionProvider discovers it before switching hash routes.
  await send("Page.reload", { ignoreCache: true });
  await waitFor(
    "document.body?.innerText?.includes('Welcome back, neonkite')",
    "authenticated app shell",
  );

  await setViewport(1440, 1200);
  await navigate("/", "Welcome back, neonkite");
  await waitFor(
    "document.body.innerText.includes('GITADORA')",
    "all dashboard profiles",
  );
  await assertPageLayout("desktop dashboard");
  await screenshot("docs/webui-dashboard.png", false);

  await setViewport(1440, 900);
  await navigate("/cards", "Cards are your");
  await waitFor(
    "document.body.innerText.includes('E0040123456789AB')",
    "bound cards",
  );
  await assertPageLayout("desktop cards");
  await screenshot("docs/webui-cards.png", false);

  await navigate("/scores?game=iidx&pageSize=25", "Every play leaves");
  await waitFor(
    "document.body.innerText.includes('2,148') || document.body.innerText.includes('2148')",
    "score rows",
  );
  await assertPageLayout("desktop scores");
  await screenshot("docs/webui-scores.png");

  await navigate("/rankings?game=iidx&song=1207&chart=3&limit=10", "Find your place");
  await waitFor(
    "document.body.innerText.includes('BYTEBLOOM') && document.body.innerText.includes('you')",
    "ranking rows",
  );
  await assertPageLayout("desktop rankings");
  await screenshot("docs/webui-rankings.png");

  await navigate("/settings/iidx_profile/1", "Tune your");
  await waitFor(
    "document.body.innerText.includes('Advanced profile JSON (version 33)')",
    "profile settings",
  );
  await assertPageLayout("desktop settings");
  await screenshot("docs/webui-settings.png", false);

  await navigate("/admin", "Control the");
  await waitFor(
    "document.body.innerText.includes('PCBNEON001') && document.body.innerText.includes('PCBNEW0001')",
    "shop rows",
  );
  await assertPageLayout("desktop admin");
  await screenshot("docs/webui-admin-shops.png");

  await setViewport(800, 900);
  const responsiveRoutes = [
    ["/", "Welcome back, neonkite", "dashboard"],
    ["/cards", "Cards are your", "cards"],
    ["/scores?game=iidx&pageSize=25", "Every play leaves", "scores"],
    ["/rankings?game=iidx&song=1207&chart=3&limit=10", "Find your place", "rankings"],
    ["/settings/iidx_profile/1", "Tune your", "settings"],
    ["/admin", "Control the", "admin"],
  ];
  for (const [route, marker, label] of responsiveRoutes) {
    await navigate(route, marker);
    await assertPageLayout(`medium ${label}`);
  }
  await navigate("/", "Welcome back, neonkite");
  await screenshot(
    path.join(tmpdir(), "bacon-net-readme-medium-check.png"),
    true,
  );

  await setViewport(390, 844, true);
  for (const [route, marker, label] of responsiveRoutes) {
    await navigate(route, marker);
    await assertPageLayout(`narrow ${label}`);
    if (label === "admin") {
      await evaluate(`([...document.querySelectorAll('button')]
        .find((button) => button.textContent.trim() === 'Add shop'))?.click()`);
      await waitFor(
        "document.querySelector('.cds--modal.is-visible .cds--modal-container')",
        "open narrow admin dialog",
      );
      await assertOpenDialogFits("narrow admin dialog");
      await send("Input.dispatchKeyEvent", {
        type: "keyDown",
        key: "Escape",
        code: "Escape",
        windowsVirtualKeyCode: 27,
        nativeVirtualKeyCode: 27,
      });
      await send("Input.dispatchKeyEvent", {
        type: "keyUp",
        key: "Escape",
        code: "Escape",
        windowsVirtualKeyCode: 27,
        nativeVirtualKeyCode: 27,
      });
      await waitFor(
        "!document.querySelector('.cds--modal.is-visible')",
        "closed narrow admin dialog",
      );
    }
  }
  await navigate("/", "Welcome back, neonkite");

  const menuButtonFound = await evaluate(`(() => {
    const button = document.querySelector('button[aria-label="Open navigation"]');
    if (!button) return false;
    button.click();
    return true;
  })()`);
  if (!menuButtonFound) throw new Error("Narrow dashboard has no navigation disclosure");
  await waitFor(
    `document.querySelector('button[aria-label="Close navigation"]')?.getAttribute('aria-expanded') === 'true'`,
    "open narrow navigation",
  );
  await send("Input.dispatchKeyEvent", {
    type: "keyDown",
    key: "Escape",
    code: "Escape",
    windowsVirtualKeyCode: 27,
    nativeVirtualKeyCode: 27,
  });
  await send("Input.dispatchKeyEvent", {
    type: "keyUp",
    key: "Escape",
    code: "Escape",
    windowsVirtualKeyCode: 27,
    nativeVirtualKeyCode: 27,
  });
  await waitFor(
    `document.querySelector('button[aria-label="Open navigation"]')?.getAttribute('aria-expanded') === 'false'`,
    "closed narrow navigation",
  );
  await screenshot(
    path.join(tmpdir(), "bacon-net-readme-mobile-check.png"),
    true,
  );
} finally {
  socket?.close();

  if (
    chromium?.pid && chromium.exitCode === null && chromium.signalCode === null
  ) {
    chromium.kill("SIGTERM");
    await Promise.race([once(chromium, "exit"), delay(3_000)]);
  }

  if (
    chromium?.pid && chromium.exitCode === null && chromium.signalCode === null
  ) {
    chromium.kill("SIGKILL");
    await once(chromium, "exit");
  }

  await rm(userDataDir, { recursive: true, force: true });
}

function waitForDevTools(browser) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let output = "";

    const timeout = setTimeout(() => {
      fail(
        new Error(
          `Chromium did not expose DevTools within 15 seconds.\n${output}`,
        ),
      );
    }, 15_000);

    const finish = (url) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      resolve(url);
    };

    const fail = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    };

    browser.stderr.on("data", (chunk) => {
      output = `${output}${chunk}`.slice(-8_000);
      const match = output.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (match) finish(match[1]);
    });
    browser.once("error", fail);
    browser.once("exit", (code, signal) => {
      fail(
        new Error(
          `Chromium exited before DevTools was ready (${
            code ?? signal
          }).\n${output}`,
        ),
      );
    });
  });
}
