#!/usr/bin/env node
/**
 * Renovate post-upgrade helper: fetch OCI image config for old/new digests,
 * extract common source labels (revision, source repo, created time),
 * and write a markdown note under renovate/image-diff/.
 *
 * Usage:
 *   node scripts/renovate-image-diff.mjs <depName> <currentDigest> <newDigest> <sourceUrl?>
 *
 * Notes:
 * - Works best when images include OCI labels like:
 *   - org.opencontainers.image.revision
 *   - org.opencontainers.image.source
 *   - org.opencontainers.image.url
 */

import fs from 'node:fs';
import path from 'node:path';

const [depName, currentDigest, newDigest, sourceUrlArg] = process.argv.slice(2);
if (!depName || !currentDigest || !newDigest) {
  console.error('Usage: renovate-image-diff.mjs <depName> <currentDigest> <newDigest> <sourceUrl?>');
  process.exit(2);
}

function sanitize(name) {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/(^-|-$)/g, '');
}

function splitImage(dep) {
  // depName examples:
  // - nginx
  // - docker.io/library/nginx
  // - ghcr.io/music-assistant/server
  // Normalize to registry/repo
  let registry = 'docker.io';
  let repo = dep;

  // If dep includes registry host
  if (dep.includes('/')) {
    const first = dep.split('/')[0];
    if (first.includes('.') || first.includes(':') || first === 'localhost') {
      registry = first;
      repo = dep.split('/').slice(1).join('/');
    }
  }

  // docker.io shorthand handling
  if (registry === 'docker.io') {
    if (!repo.includes('/')) repo = `library/${repo}`;
  }

  return { registry, repo };
}

async function getDockerHubToken(repo) {
  const url = `https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`DockerHub token failed: ${res.status} ${await res.text()}`);
  const json = await res.json();
  return json.token;
}

async function fetchJson(url, headers = {}) {
  const res = await fetch(url, { headers });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}: ${await res.text()}`);
  return await res.json();
}

async function fetchBlob(registry, repo, digest, authHeader) {
  const url = `https://${registry}/v2/${repo}/blobs/${digest}`;
  return await fetchJson(url, {
    Accept: 'application/octet-stream',
    ...(authHeader ? { Authorization: authHeader } : {}),
  });
}

async function getConfig(registry, repo, digest) {
  // We fetch the manifest, then the config blob.
  const accept = [
    'application/vnd.oci.image.manifest.v1+json',
    'application/vnd.docker.distribution.manifest.v2+json',
  ].join(', ');

  let authHeader = null;
  if (registry === 'registry-1.docker.io' || registry === 'docker.io') {
    // Manifest endpoint host is registry-1.docker.io
    registry = 'registry-1.docker.io';
    const token = await getDockerHubToken(repo);
    authHeader = `Bearer ${token}`;
  }

  const manifestUrl = `https://${registry}/v2/${repo}/manifests/${digest}`;
  const manifest = await fetchJson(manifestUrl, {
    Accept: accept,
    ...(authHeader ? { Authorization: authHeader } : {}),
  });

  const cfgDigest = manifest?.config?.digest;
  if (!cfgDigest) throw new Error('No config.digest in manifest');

  const config = await fetchBlob(registry, repo, cfgDigest, authHeader);
  const labels = config?.config?.Labels ?? {};

  return {
    registry,
    repo,
    digest,
    cfgDigest,
    created: config?.created ?? null,
    labels,
  };
}

function pick(meta) {
  const l = meta.labels || {};
  return {
    created: meta.created,
    revision: l['org.opencontainers.image.revision'] || l['org.label-schema.vcs-ref'] || null,
    source: l['org.opencontainers.image.source'] || l['org.label-schema.vcs-url'] || null,
    url: l['org.opencontainers.image.url'] || null,
  };
}

function compareLink(oldRev, newRev, sourceUrl) {
  // best-effort GitHub compare link
  if (!sourceUrl) return null;
  const m = sourceUrl.match(/^https?:\/\/github\.com\/([^/]+)\/([^/#?]+)(?:\.git)?/i);
  if (!m) return null;
  const base = `https://github.com/${m[1]}/${m[2].replace(/\.git$/,'')}`;
  if (oldRev && newRev) return `${base}/compare/${oldRev}...${newRev}`;
  return `${base}/commits`;
}

const { registry, repo } = splitImage(depName);
const sourceUrl = sourceUrlArg && sourceUrlArg !== 'null' ? sourceUrlArg : null;

let oldMeta, newMeta, err = null;
try {
  oldMeta = await getConfig(registry, repo, currentDigest);
  newMeta = await getConfig(registry, repo, newDigest);
} catch (e) {
  err = String(e?.message || e);
}

const outDir = path.join('renovate', 'image-diff');
fs.mkdirSync(outDir, { recursive: true });
const outPath = path.join(outDir, `${sanitize(depName)}.md`);

if (err) {
  fs.writeFileSync(outPath, `# Image metadata (best effort)\n\n- Image: \`${depName}\`\n- From: \`${currentDigest}\`\n- To: \`${newDigest}\`\n\n⚠️ Could not fetch image metadata from registry: ${err}\n`);
  process.exit(0);
}

const oldPicked = pick(oldMeta);
const newPicked = pick(newMeta);
const cmp = compareLink(oldPicked.revision, newPicked.revision, oldPicked.source || newPicked.source || sourceUrl);

const md = `# Image metadata (best effort)\n\n- Image: \`${depName}\`\n- Registry: \`${oldMeta.registry}\`\n- Repo: \`${oldMeta.repo}\`\n\n## Digests\n\n- From: \`${currentDigest}\`\n- To:   \`${newDigest}\`\n\n## OCI labels\n\n| Field | From | To |\n|---|---|---|\n| created | ${oldPicked.created ?? ''} | ${newPicked.created ?? ''} |\n| revision | ${oldPicked.revision ?? ''} | ${newPicked.revision ?? ''} |\n| source | ${oldPicked.source ?? ''} | ${newPicked.source ?? ''} |\n| url | ${oldPicked.url ?? ''} | ${newPicked.url ?? ''} |\n\n${cmp ? `## Git compare\n\n- ${cmp}\n\n` : ''}`;

fs.writeFileSync(outPath, md);
