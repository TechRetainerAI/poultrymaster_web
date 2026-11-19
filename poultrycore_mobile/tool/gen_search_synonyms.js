// Prints page-index.ts TITLE_SYNONYMS as Dart, for the end of
// lib/pages/shared/help/help_search.dart (replace the titleSynonyms list). Run from poultrymaster_web/:
//   node poultrycore_mobile/tool/gen_search_synonyms.js poultrycore-main/lib/search/page-index.ts
const fs = require('fs')
const ts = fs.readFileSync(process.argv[2], 'utf8').split(String.fromCharCode(13)).join('')
const a = ts.indexOf('const TITLE_SYNONYMS')
const block = ts.slice(ts.indexOf('[', ts.indexOf('=', a)), ts.indexOf('\n]\n', a) + 2)
const list = eval(block)
const q = s => "'" + s.split("'").join("\\'") + "'"
let d = '/// TITLE_SYNONYMS: words people use for a page that are not in its title.\n/// A leading `=` means the whole title, not a substring.\nconst titleSynonyms = <(String, List<String>)>[\n'
for (const [needle, words] of list) d += `  (${q(needle)}, [${words.map(q).join(', ')}]),\n`
d += '];\n'
process.stdout.write(d)
