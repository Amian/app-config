#!/usr/bin/env node
// Checks public/endpoints.json before it is published. The apps reject a whole file that breaks
// these rules (and keep their saved copy), so a bad publish is harmless but also useless.
//   node validate.mjs          shape only
//   node validate.mjs --live   also checks every address answers over HTTPS

import { readFileSync } from 'node:fs'

const file = JSON.parse(readFileSync(new URL('./public/endpoints.json', import.meta.url), 'utf8'))
const problems = []
const urls = new Set()

const isObject = v => v !== null && typeof v === 'object' && !Array.isArray(v)

function checkServices (where, services) {
  if (!isObject(services)) return problems.push(`${where} must be an object of name: url`)
  for (const [name, value] of Object.entries(services)) {
    if (!/^[a-z][a-zA-Z0-9]*$/.test(name)) problems.push(`${where}.${name}: names are camelCase letters and digits`)
    let url
    try { url = new URL(value) } catch { problems.push(`${where}.${name}: not a URL`); continue }
    if (url.protocol !== 'https:' || !url.hostname) problems.push(`${where}.${name}: must be https`)
    if (url.pathname !== '/' || url.search || url.hash || value.endsWith('/')) {
      problems.push(`${where}.${name}: base address only, no path or trailing slash`)
    }
    urls.add(value)
  }
}

if (file.version !== 1) problems.push('version must be 1 (apps ignore any other version)')
checkServices('default', file.default ?? {})
if (!isObject(file.apps)) problems.push('apps must be an object keyed by app ID')
for (const [appId, services] of Object.entries(file.apps ?? {})) {
  if (!/^[A-Za-z0-9.-]+$/.test(appId)) problems.push(`apps.${appId}: not a bundle ID`)
  checkServices(`apps.${appId}`, services)
}

if (process.argv.includes('--live')) {
  await Promise.all([...urls].map(async url => {
    try {
      await fetch(url, { method: 'HEAD', signal: AbortSignal.timeout(20000) })
    } catch (error) {
      problems.push(`${url}: no answer (${error.cause?.code || error.message})`)
    }
  }))
}

if (problems.length) {
  console.error(problems.map(p => `✗ ${p}`).join('\n'))
  process.exit(1)
}
console.log(`✓ endpoints.json is valid: ${Object.keys(file.apps).length} apps, ${urls.size} addresses${process.argv.includes('--live') ? ', all answering' : ''}`)
