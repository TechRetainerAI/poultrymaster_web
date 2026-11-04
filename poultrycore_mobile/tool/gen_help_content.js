// Regenerates lib/pages/shared/help/poultry_help_content.dart from the web's
// content. Run from poultrymaster_web/:
//   node poultrycore_mobile/tool/gen_help_content.js poultrycore-main/lib/help/poultry-help-content.ts poultrycore_mobile/lib/pages/shared/help/poultry_help_content.dart
const fs = require('fs')
const [src, out] = process.argv.slice(2)
const ts = fs.readFileSync(src, 'utf8')
const start = ts.indexOf('export const FEATURE_GUIDES')
const fg = ts.slice(start, ts.indexOf('// ---', start))
const guides = [...fg.matchAll(/\{ icon: (\w+), title: "([^"]+)", description: "([^"]+)", path: "([^"]+)", tint: "bg-(\w+)-\d+ /g)]
  .map(m => ({ icon: m[1], title: m[2], description: m[3], path: m[4], tone: m[5] }))
let body = ts.slice(ts.indexOf('export const HELP_ENTRIES'))
body = body.replace('export const HELP_ENTRIES: HelpEntry[] =', 'const HELP_ENTRIES =')
const faq = e => ({ ...e, kind: 'faq' }), fix = e => ({ ...e, kind: 'fix' }), term = e => ({ ...e, kind: 'term' })
const HELP_ENTRIES = eval(body + '\n;HELP_ENTRIES')
const BS = String.fromCharCode(92)
const q = s => "'" + s.split(BS).join(BS + BS).split("'").join(BS + "'").split('$').join(BS + '$').split('\n').join(BS + 'n') + "'"
const iconMap = {
  Bird: 'Icons.flutter_dash', Egg: 'Icons.egg_outlined', Package: 'Icons.inventory_2_outlined',
  ShoppingCart: 'Icons.shopping_cart_outlined', Users: 'Icons.people_outline', DollarSign: 'Icons.attach_money',
  CalendarCheck: 'Icons.event_available_outlined', BarChart3: 'Icons.bar_chart', Activity: 'Icons.monitor_heart_outlined',
  FileText: 'Icons.description_outlined', Settings: 'Icons.settings_outlined',
}
let d = `// GENERATED from poultrycore-main/lib/help/poultry-help-content.ts by a script
// (the web content, word for word). When the web file changes, regenerate it
// rather than editing here: the answers quote the web's button labels.

import 'package:flutter/material.dart';

import 'help_types.dart';

/// The Feature Guide grid: icon, title, description, path, colour family.
const featureGuides = <FeatureGuide>[
`
for (const g of guides) d += `  FeatureGuide(${iconMap[g.icon] ?? 'Icons.help_outline'}, ${q(g.title)}, ${q(g.description)}, ${q(g.path)}, ${q(g.tone)}),\n`
d += `];\n\n/// Questions, troubleshooting and glossary, in the web's order.\nconst helpEntries = <HelpEntry>[\n`
for (const e of HELP_ENTRIES) {
  d += `  HelpEntry(\n    id: ${q(e.id)},\n    kind: HelpKind.${e.kind},\n    category: ${q(e.category)},\n    title: ${q(e.title)},\n    body: ${q(e.body)},\n`
  if (e.keywords && e.keywords.length) d += `    keywords: [${e.keywords.map(q).join(', ')}],\n`
  if (e.links && e.links.length) d += `    links: [${e.links.map(l => `HelpLink(${q(l.label)}, ${q(l.href)})`).join(', ')}],\n`
  d += `  ),\n`
}
d += `];\n`
fs.writeFileSync(out, d)
const kinds = {}
for (const e of HELP_ENTRIES) kinds[e.kind] = (kinds[e.kind] || 0) + 1
console.log('guides', guides.length, 'entries', HELP_ENTRIES.length, JSON.stringify(kinds), [...new Set(HELP_ENTRIES.map(e => e.category))].join(' | '))
