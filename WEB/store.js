// store.js
//
// Minimal file-backed store, standing in for get_config()/save_config() from
// the Python dashboard (contend_BRIDGE_main.py). Swap readConfig/writeConfig
// for real DB calls when you outgrow a single JSON file.

const fs = require("fs");
const path = require("path");

const DATA_FILE = process.env.DATA_FILE || "./data/config.json";

const DEFAULT_CONFIG = {
  api_keys: [],       // [{ name, key, rpm, created }]
  auth_tokens: [],     // [arena-auth-prod-v1... strings]
  cf_clearance: null,
  models: [],          // [{ publicName, rank, organization, capabilities }]
  usage: {},           // { [modelName]: requestCount }
};

function ensureDataFile() {
  const dir = path.dirname(DATA_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  if (!fs.existsSync(DATA_FILE)) {
    fs.writeFileSync(DATA_FILE, JSON.stringify(DEFAULT_CONFIG, null, 2));
  }
}

function readConfig() {
  ensureDataFile();
  try {
    const raw = fs.readFileSync(DATA_FILE, "utf8");
    return { ...DEFAULT_CONFIG, ...JSON.parse(raw) };
  } catch {
    return { ...DEFAULT_CONFIG };
  }
}

function writeConfig(config) {
  ensureDataFile();
  fs.writeFileSync(DATA_FILE, JSON.stringify(config, null, 2));
  return config;
}

module.exports = { readConfig, writeConfig };
