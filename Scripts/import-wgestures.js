#!/usr/bin/env node

const fs = require("fs");
const os = require("os");
const path = require("path");

const oldPath = path.join(
  os.homedir(),
  "Library/Application Support/com.yingdev.wgestures/2.3.3/gestures.json",
);
const newDir = path.join(os.homedir(), "Library/Application Support/WeGestureARM");
const newPath = path.join(newDir, "gestures.json");

const keyCodes = {
  ANSI_A: 0,
  ANSI_S: 1,
  ANSI_D: 2,
  ANSI_F: 3,
  ANSI_H: 4,
  ANSI_G: 5,
  ANSI_Z: 6,
  ANSI_X: 7,
  ANSI_C: 8,
  ANSI_V: 9,
  ANSI_B: 11,
  ANSI_Q: 12,
  ANSI_W: 13,
  ANSI_E: 14,
  ANSI_R: 15,
  ANSI_Y: 16,
  ANSI_T: 17,
  ANSI_1: 18,
  ANSI_2: 19,
  ANSI_3: 20,
  ANSI_4: 21,
  ANSI_6: 22,
  ANSI_5: 23,
  ANSI_Equal: 24,
  ANSI_9: 25,
  ANSI_7: 26,
  ANSI_Minus: 27,
  ANSI_8: 28,
  ANSI_0: 29,
  ANSI_RightBracket: 30,
  ANSI_O: 31,
  ANSI_U: 32,
  ANSI_LeftBracket: 33,
  ANSI_I: 34,
  ANSI_P: 35,
  ANSI_L: 37,
  ANSI_J: 38,
  ANSI_Quote: 39,
  ANSI_K: 40,
  ANSI_Semicolon: 41,
  ANSI_Backslash: 42,
  ANSI_Comma: 43,
  ANSI_Slash: 44,
  ANSI_N: 45,
  ANSI_M: 46,
  ANSI_Period: 47,
  Return: 36,
  Tab: 48,
  Space: 49,
  Delete: 51,
  Escape: 53,
  LeftArrow: 123,
  RightArrow: 124,
  DownArrow: 125,
  UpArrow: 126,
};

const modifierMap = {
  Command: "command",
  Shift: "shift",
  Option: "option",
  Control: "control",
};

function actionFor(command, fallbackName) {
  if (!command || command.$type !== "KeySeqCommand") {
    throw new Error(`Unsupported command type: ${command && command.$type}`);
  }

  const modifiers = [];
  let keyCode = null;
  for (const key of command.Keys || []) {
    if (modifierMap[key]) {
      modifiers.push(modifierMap[key]);
    } else if (keyCodes[key] !== undefined) {
      keyCode = keyCodes[key];
    } else {
      throw new Error(`Unsupported key: ${key}`);
    }
  }

  if (keyCode === null) {
    throw new Error(`Missing non-modifier key for ${fallbackName}`);
  }
  return { name: fallbackName, keys: [{ keyCode, modifiers }] };
}

function simpleCode(points) {
  const dirs = [];
  const threshold = 24;
  let last = { x: points[0], y: points[1] };

  for (let i = 2; i < points.length; i += 2) {
    const current = { x: points[i], y: points[i + 1] };
    const dx = current.x - last.x;
    const dy = current.y - last.y;
    if (Math.hypot(dx, dy) < threshold) continue;
    const dir = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? "R" : "L") : (dy > 0 ? "U" : "D");
    if (dirs[dirs.length - 1] !== dir) dirs.push(dir);
    last = current;
  }

  return dirs.join("");
}

function importConfig() {
  if (!fs.existsSync(oldPath)) {
    throw new Error(`WGestures config not found: ${oldPath}`);
  }

  fs.mkdirSync(newDir, { recursive: true });
  if (fs.existsSync(newPath)) {
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    fs.copyFileSync(newPath, path.join(newDir, `gestures.backup-${stamp}.json`));
  }

  const oldConfig = JSON.parse(fs.readFileSync(oldPath, "utf8"));
  const gestures = {};
  const mouseButtons = {};
  const templates = [];

  for (const intent of oldConfig.General.Intents || []) {
    const gesture = intent.Gesture || [];
    const keys = (intent.Command.Keys || []).join("+");
    const stroke = gesture.find((step) => step.$type === "StrokeStep");

    if (stroke) {
      const action = actionFor(intent.Command, keys);
      const code = simpleCode(stroke.P);
      if (code && !gestures[code]) gestures[code] = action;
      templates.push({ name: keys, points: stroke.P.map(Number), action });
      continue;
    }

    const chord = gesture.map((step) => step.Key).join("+");
    if (chord === "MOUSE:1+MOUSE:0") {
      mouseButtons["R+Left"] = actionFor(intent.Command, keys);
    }
  }

  fs.writeFileSync(newPath, JSON.stringify({ gestures, mouseButtons, templates }, null, 2) + "\n");
  console.log(`Imported ${templates.length} gesture templates to ${newPath}`);
}

try {
  importConfig();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
