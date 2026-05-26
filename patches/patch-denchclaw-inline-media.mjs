import fs from "node:fs";
import crypto from "node:crypto";
import path from "node:path";

const kPackageRoot =
  process.env.DENCHCLAW_PACKAGE_ROOT ?? "/app/node_modules/denchclaw";
const kNextRoot = path.join(kPackageRoot, "apps/web/.next");
const kAppChunkDir = path.join(
  kNextRoot,
  "static/chunks/app",
);
const kStandaloneChunkDir = path.join(
  kNextRoot,
  "standalone/apps/web/.next/static/chunks/app",
);

const kOriginal = String.raw`img:e=>{let{src:t,alt:r,...o}=e,l="string"!=typeof t||t.startsWith("http://")||t.startsWith("https://")||t.startsWith("data:")?t:"/api/workspace/raw-file?path=".concat(encodeURIComponent(t));return(0,n.jsx)(c0,{src:l,alt:null!=r?r:"",...o})}`;

const kReplacement = String.raw`img:e=>{let{src:t,alt:r,...o}=e,l="string"==typeof t?t:"",a=!!l&&!l.startsWith("http://")&&!l.startsWith("https://")&&!l.startsWith("data:"),s=a?"/api/workspace/raw-file?path=".concat(encodeURIComponent(l)):t,i=l.split(/[?#]/)[0].toLowerCase(),c=/\.(?:jpg|jpeg|png|gif|webp|svg|bmp|ico|heic|tiff?)$/.test(i);return a&&!c?(0,n.jsx)("a",{href:s,target:"_blank",rel:"noopener noreferrer",className:"dench-non-image-media-link",style:{color:"var(--color-accent)",textDecoration:"underline",wordBreak:"break-all"},children:null!=r&&"media"!==r?r:l.split("/").pop()||l}):(0,n.jsx)(c0,{src:s,alt:null!=r?r:"",...o})}`;

function findPageChunks(dir) {
  if (!fs.existsSync(dir)) {
    return [];
  }
  return fs
    .readdirSync(dir)
    .filter((name) => /^page-[a-f0-9]+\.js$/.test(name))
    .map((name) => path.join(dir, name));
}

function walkFiles(dir) {
  if (!fs.existsSync(dir)) {
    return [];
  }

  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walkFiles(fullPath));
    } else if (entry.isFile()) {
      files.push(fullPath);
    }
  }
  return files;
}

function replaceChunkReferences(replacements) {
  let touched = 0;

  for (const file of walkFiles(kNextRoot)) {
    let source = fs.readFileSync(file, "utf8");
    let updated = source;
    for (const [from, to] of replacements) {
      updated = updated.split(from).join(to);
    }
    if (updated !== source) {
      fs.writeFileSync(file, updated);
      touched += 1;
    }
  }

  return touched;
}

const chunks = [
  ...findPageChunks(kAppChunkDir),
  ...findPageChunks(kStandaloneChunkDir),
];

if (chunks.length === 0) {
  throw new Error("Could not find DenchClaw app page chunks to patch");
}

const patched = [];
const replacements = new Map();
for (const chunk of chunks) {
  const source = fs.readFileSync(chunk, "utf8");
  if (!source.includes(kOriginal)) {
    continue;
  }

  const updated = source.replace(kOriginal, kReplacement);
  const digest = crypto
    .createHash("sha256")
    .update(updated)
    .digest("hex")
    .slice(0, 16);
  const oldName = path.basename(chunk);
  const newName = `page-${digest}.js`;
  const newChunk = path.join(path.dirname(chunk), newName);

  fs.writeFileSync(newChunk, updated);
  if (newChunk !== chunk) {
    fs.unlinkSync(chunk);
    replacements.set(oldName, newName);
  }
  patched.push(newChunk);
}

if (patched.length === 0) {
  throw new Error(
    "DenchClaw inline media renderer patch did not match the installed bundle",
  );
}

const updatedReferences = replaceChunkReferences(replacements);

console.log(
  `Patched DenchClaw inline media renderer in ${patched.length} bundle(s); updated ${updatedReferences} manifest/reference file(s).`,
);
