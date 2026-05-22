#!/usr/bin/env node

const path = require("path");
const fs = require("fs");

/**
 * @param {number} tokens
 * @returns {string}
 */
const formatTokenCount = (tokens) =>
  tokens >= 1000000
    ? `${(tokens / 1000000).toFixed(1)}M`
    : tokens >= 1000
      ? `${(tokens / 1000).toFixed(1)}K`
      : tokens.toString();

/**
 * @param {number} ms
 * @returns {string}
 */
const formatDuration = (ms) => {
  const totalSec = Math.floor(ms / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  if (h > 0) return `${h}h${m}m`;
  if (m > 0) return `${m}m${s}s`;
  return `${s}s`;
};

/**
 * Walk up from startDir to find a .git directory and return the current branch
 * (or short SHA if detached). Returns null when not in a git repo.
 * @param {string} startDir
 * @returns {string | null}
 */
const findGitBranch = (startDir) => {
  let dir = path.resolve(startDir);
  while (dir && dir !== path.dirname(dir)) {
    const headPath = path.join(dir, ".git", "HEAD");
    try {
      const contents = fs.readFileSync(headPath, "utf8").trim();
      if (contents.startsWith("ref: refs/heads/")) {
        return contents.slice("ref: refs/heads/".length);
      }
      return contents.slice(0, 7);
    } catch {
      // not a git dir at this level — keep walking up
    }
    dir = path.dirname(dir);
  }
  return null;
};

/**
 * @param {number} percent 0–100
 * @param {number} width
 * @returns {string}
 */
const buildBar = (percent, width = 10) => {
  const filled = Math.max(0, Math.min(width, Math.round((percent / 100) * width)));
  return "█".repeat(filled) + "░".repeat(width - filled);
};

/**
 * Read the last main-thread assistant `usage` from a transcript jsonl file.
 * Skips sidechain (sub-agent) messages and synthetic compaction summaries so
 * the statusline reflects the same accounting as `/context`.
 * @param {string} transcriptPath
 * @returns {{ input: number, cacheCreate: number, cacheRead: number } | null}
 */
const readLatestUsage = (transcriptPath) => {
  if (!transcriptPath) return null;
  let raw;
  try {
    raw = fs.readFileSync(transcriptPath, "utf8");
  } catch {
    return null;
  }
  const lines = raw.split("\n");
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i];
    if (!line) continue;
    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      continue;
    }
    if (entry.isSidechain) continue;
    if (entry.type !== "assistant") continue;
    const usage = entry.message?.usage;
    if (!usage) continue;
    const input = usage.input_tokens || 0;
    const cacheCreate = usage.cache_creation_input_tokens || 0;
    const cacheRead = usage.cache_read_input_tokens || 0;
    if (input + cacheCreate + cacheRead === 0) continue;
    return { input, cacheCreate, cacheRead };
  }
  return null;
};

const ANSI = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
  cyan: "\x1b[36m",
};

/**
 * @param {string} input
 * @returns {string}
 */
const buildStatusLine = (input) => {
  const data = JSON.parse(input);
  const model = data.model?.display_name || "Unknown";
  const cwd = data.workspace?.current_dir || data.cwd || ".";
  const currentDir = path.basename(cwd);
  const branch = findGitBranch(cwd);

  const modelId = data.model?.id || "";
  const isLongContext =
    /\[1m\]$/.test(modelId) || data.exceeds_200k_tokens === true;
  const contextWindowSize = isLongContext ? 1_000_000 : 200_000;

  const usage = readLatestUsage(data.transcript_path);
  const currentTokens = usage
    ? usage.input + usage.cacheCreate + usage.cacheRead
    : 0;

  const percentage =
    contextWindowSize > 0
      ? Math.min(100, Math.round((currentTokens / contextWindowSize) * 100))
      : 0;
  const tokenDisplay = formatTokenCount(currentTokens);

  const percentageColor =
    percentage >= 90
      ? ANSI.red
      : percentage >= 70
        ? ANSI.yellow
        : ANSI.green;

  const cost = data.cost || {};
  const durMs = cost.total_duration_ms;
  const added = cost.total_lines_added;
  const removed = cost.total_lines_removed;

  const parts = [];
  parts.push(`${ANSI.bold}${ANSI.cyan}[${model}]${ANSI.reset}`);
  if (branch) parts.push(`${ANSI.magenta}⎇ ${branch}${ANSI.reset}`);
  parts.push(`${ANSI.blue}📁 ${currentDir}${ANSI.reset}`);
  parts.push(
    `🪙 ${tokenDisplay} ${percentageColor}${buildBar(percentage)} ${percentage}%${ANSI.reset}`,
  );
  if (typeof durMs === "number") {
    parts.push(`${ANSI.dim}⏱ ${formatDuration(durMs)}${ANSI.reset}`);
  }
  if (typeof added === "number" || typeof removed === "number") {
    parts.push(
      `${ANSI.dim}${ANSI.green}+${added || 0}${ANSI.reset}${ANSI.dim}/${ANSI.red}-${removed || 0}${ANSI.reset}`,
    );
  }

  return parts.join(` ${ANSI.dim}│${ANSI.reset} `);
};

const chunks = [];
process.stdin.on("data", (chunk) => chunks.push(chunk));
process.stdin.on("end", () => console.log(buildStatusLine(chunks.join(""))));
