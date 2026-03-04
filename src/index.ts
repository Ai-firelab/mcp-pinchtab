#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { spawn } from "child_process";
import { setTimeout as sleep } from "timers/promises";

const BASE_URL = process.env.PINCHTAB_URL || "http://localhost:9867";

let started = false;

async function ensureRunning(): Promise<void> {
  async function isHealthy(): Promise<boolean> {
    try {
      const res = await fetch(`${BASE_URL}/health`, {
        signal: AbortSignal.timeout(2000),
      });
      if (!res.ok) return false;
      const body = (await res.json()) as { status?: string };
      return body.status === "ok";
    } catch {
      return false;
    }
  }

  if (await isHealthy()) return;

  const bin = process.env.PINCHTAB_BIN || "pinchtab";
  const child = spawn(bin, [], { detached: true, stdio: "ignore" });
  child.unref();

  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    await sleep(500);
    if (await isHealthy()) {
      process.stderr.write("Pinchtab server auto-started (port 9867)\n");
      return;
    }
  }

  throw new Error(
    "Pinchtab server failed to start within 15s. Install it: npm i -g pinchtab"
  );
}

async function pinchtab(
  path: string,
  options: {
    method?: string;
    body?: Record<string, unknown>;
    query?: Record<string, string>;
  } = {}
): Promise<unknown> {
  if (!started) {
    started = true;
    await ensureRunning();
  }

  const url = new URL(path, BASE_URL);
  if (options.query) {
    for (const [key, value] of Object.entries(options.query)) {
      url.searchParams.set(key, value);
    }
  }

  const fetchOptions: RequestInit = {
    method: options.method || "GET",
    headers: { "Content-Type": "application/json" },
  };

  if (options.body) {
    fetchOptions.body = JSON.stringify(options.body);
  }

  const response = await fetch(url.toString(), fetchOptions);

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Pinchtab API error (${response.status}): ${text}`);
  }

  const contentType = response.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    return response.json();
  }
  return response.text();
}

function ok(text: string) {
  return { content: [{ type: "text" as const, text }] };
}

function fail(error: unknown) {
  const msg = error instanceof Error ? error.message : String(error);
  return { isError: true as const, content: [{ type: "text" as const, text: msg }] };
}

const server = new McpServer({ name: "pinchtab", version: "1.0.0" });

server.tool(
  "navigate",
  "Navigate the browser to a URL",
  {
    url: z.string().describe("The URL to navigate to"),
    newTab: z.boolean().optional().describe("Open in a new tab"),
  },
  async ({ url, newTab }) => {
    try {
      if (newTab) {
        await pinchtab("/tab", { method: "POST", body: { action: "new", url } });
      } else {
        await pinchtab("/navigate", { method: "POST", body: { url } });
      }
      return ok(`Navigated to ${url}`);
    } catch (e) {
      return fail(e);
    }
  }
);

server.tool(
  "snapshot",
  "Get accessibility tree snapshot of the page. Returns element refs (e0, e1, ...) for interaction.",
  {
    interactive: z.boolean().optional().describe("Only show interactive elements"),
    compact: z.boolean().optional().describe("Compact format to reduce tokens"),
  },
  async ({ interactive, compact }) => {
    try {
      const query: Record<string, string> = {};
      if (interactive) query.interactive = "true";
      if (compact) query.compact = "true";
      const result = await pinchtab("/snapshot", { query });
      return ok(typeof result === "string" ? result : JSON.stringify(result, null, 2));
    } catch (e) {
      return fail(e);
    }
  }
);

server.tool(
  "click",
  "Click an element by ref (e.g. 'e5'). Use snapshot to find refs.",
  {
    ref: z.string().describe("Element ref from snapshot (e.g. 'e5')"),
    human: z.boolean().optional().describe("Human-like click with random delays"),
  },
  async ({ ref, human }) => {
    try {
      await pinchtab("/action", {
        method: "POST",
        body: { kind: human ? "humanClick" : "click", ref },
      });
      return ok(`Clicked ${ref}`);
    } catch (e) {
      return fail(e);
    }
  }
);

server.tool(
  "type_text",
  "Type text character by character. Use 'fill' for instant input.",
  {
    ref: z.string().describe("Element ref (e.g. 'e5')"),
    text: z.string().describe("Text to type"),
    human: z.boolean().optional().describe("Human-like typing with random delays"),
  },
  async ({ ref, text, human }) => {
    try {
      await pinchtab("/action", {
        method: "POST",
        body: { kind: human ? "humanType" : "type", ref, text },
      });
      return ok(`Typed "${text}" into ${ref}`);
    } catch (e) {
      return fail(e);
    }
  }
);

server.tool(
  "fill",
  "Instantly fill a form field (clears existing value).",
  {
    ref: z.string().describe("Element ref (e.g. 'e5')"),
    value: z.string().describe("Value to fill"),
  },
  async ({ ref, value }) => {
    try {
      await pinchtab("/action", {
        method: "POST",
        body: { kind: "fill", ref, value },
      });
      return ok(`Filled ${ref} with "${value}"`);
    } catch (e) {
      return fail(e);
    }
  }
);

server.tool(
  "press",
  "Press a keyboard key (Enter, Tab, Escape, ArrowDown, etc.)",
  {
    key: z.string().describe("Key to press (e.g. 'Enter', 'Tab')"),
    ref: z.string().optional().describe("Element to focus before pressing"),
  },
  async ({ key, ref }) => {
    try {
      const body: Record<string, unknown> = { kind: "press", key };
      if (ref) body.ref = ref;
      await pinchtab("/action", { method: "POST", body });
      return ok(`Pressed ${key}`);
    } catch (e) {
      return fail(e);
    }
  }
);

server.tool(
  "select",
  "Select an option from a dropdown.",
  {
    ref: z.string().describe("Select element ref"),
    value: z.string().describe("Option value to select"),
  },
  async ({ ref, value }) => {
    try {
      await pinchtab("/action", {
        method: "POST",
        body: { kind: "select", ref, value },
      });
      return ok(`Selected "${value}" in ${ref}`);
    } catch (e) {
      return fail(e);
    }
  }
);

server.tool(
  "scroll",
  "Scroll the page or a specific element.",
  {
    direction: z.enum(["up", "down", "left", "right"]).describe("Scroll direction"),
    amount: z.number().optional().describe("Pixels to scroll (default: 500)"),
    ref: z.string().optional().describe("Element to scroll within"),
  },
  async ({ direction, amount, ref }) => {
    const px = amount || 500;
    const x = direction === "left" ? -px : direction === "right" ? px : 0;
    const y = direction === "up" ? -px : direction === "down" ? px : 0;
    try {
      const body: Record<string, unknown> = { kind: "scroll", x, y };
      if (ref) body.ref = ref;
      await pinchtab("/action", { method: "POST", body });
      return ok(`Scrolled ${direction} ${px}px`);
    } catch (e) {
      return fail(e);
    }
  }
);

server.tool(
  "hover",
  "Hover over an element.",
  {
    ref: z.string().describe("Element ref (e.g. 'e5')"),
  },
  async ({ ref }) => {
    try {
      await pinchtab("/action", {
        method: "POST",
        body: { kind: "hover", ref },
      });
      return ok(`Hovered over ${ref}`);
    } catch (e) {
      return fail(e);
    }
  }
);

server.tool(
  "get_text",
  "Extract text content of the current page.",
  {},
  async () => {
    try {
      const result = await pinchtab("/text");
      return ok(typeof result === "string" ? result : JSON.stringify(result));
    } catch (e) {
      return fail(e);
    }
  }
);

server.tool(
  "screenshot",
  "Take a screenshot (base64 JPEG). Prefer snapshot for lower token cost.",
  {},
  async () => {
    try {
      const result = (await pinchtab("/screenshot")) as { base64: string; format?: string };
      const mimeType = result.format === "png" ? "image/png" : "image/jpeg";
      return {
        content: [{ type: "image" as const, data: result.base64, mimeType }],
      };
    } catch (e) {
      return fail(e);
    }
  }
);

server.tool(
  "evaluate",
  "Execute JavaScript in the browser and return the result.",
  {
    expression: z.string().describe("JavaScript expression to evaluate"),
  },
  async ({ expression }) => {
    try {
      const result = await pinchtab("/evaluate", {
        method: "POST",
        body: { expression },
      });
      return ok(typeof result === "string" ? result : JSON.stringify(result, null, 2));
    } catch (e) {
      return fail(e);
    }
  }
);

server.tool("list_tabs", "List all open browser tabs.", {}, async () => {
  try {
    const result = await pinchtab("/tabs");
    return ok(JSON.stringify(result, null, 2));
  } catch (e) {
    return fail(e);
  }
});

server.tool(
  "close_tab",
  "Close the current or a specific tab.",
  {
    tabId: z.string().optional().describe("Tab ID to close (default: current)"),
  },
  async ({ tabId }) => {
    try {
      const body: Record<string, unknown> = { action: "close" };
      if (tabId) body.tabId = tabId;
      await pinchtab("/tab", { method: "POST", body });
      return ok("Tab closed");
    } catch (e) {
      return fail(e);
    }
  }
);

server.tool("get_cookies", "Get all cookies for the current page.", {}, async () => {
  try {
    const result = await pinchtab("/cookies");
    return ok(JSON.stringify(result, null, 2));
  } catch (e) {
    return fail(e);
  }
});

server.tool("health", "Check if Pinchtab server is running.", {}, async () => {
  try {
    const result = await pinchtab("/health");
    return ok(JSON.stringify(result));
  } catch (e) {
    return fail(e);
  }
});

const transport = new StdioServerTransport();
server.connect(transport).catch((e) => {
  console.error(e);
  process.exit(1);
});
