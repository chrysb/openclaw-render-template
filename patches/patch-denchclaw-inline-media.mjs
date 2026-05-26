import fs from "node:fs";
import path from "node:path";

const kPackageRoot =
  process.env.DENCHCLAW_PACKAGE_ROOT ?? "/app/node_modules/denchclaw";
const kAppChunkDir = path.join(
  kPackageRoot,
  "apps/web/.next/static/chunks/app",
);
const kStandaloneChunkDir = path.join(
  kPackageRoot,
  "apps/web/.next/standalone/apps/web/.next/static/chunks/app",
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

const chunks = [
  ...findPageChunks(kAppChunkDir),
  ...findPageChunks(kStandaloneChunkDir),
];

if (chunks.length === 0) {
  throw new Error("Could not find DenchClaw app page chunks to patch");
}

const patched = [];
for (const chunk of chunks) {
  const source = fs.readFileSync(chunk, "utf8");
  if (!source.includes(kOriginal)) {
    continue;
  }
  fs.writeFileSync(chunk, source.replace(kOriginal, kReplacement));
  patched.push(chunk);
}

if (patched.length === 0) {
  throw new Error(
    "DenchClaw inline media renderer patch did not match the installed bundle",
  );
}

console.log(
  `Patched DenchClaw inline media renderer in ${patched.length} bundle(s).`,
);
