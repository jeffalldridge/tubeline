// Validates GLB files with the Khronos glTF Validator and fails on any error or warning.
// Usage: install gltf-validator@2.0.0-dev.3.10 next to this script, then
//   node validate-glb.mjs out/*.glb
// (CI does this in .github/workflows/ci.yml.)
import validator from 'gltf-validator';
import fs from 'node:fs';
import path from 'node:path';

const files = process.argv.slice(2);
if (files.length === 0) {
    console.error('No GLB files given.');
    process.exit(2);
}
let failed = 0;
for (const file of files) {
    const report = await validator.validateBytes(new Uint8Array(fs.readFileSync(file)));
    const { numErrors, numWarnings, messages } = report.issues;
    if (numErrors || numWarnings) {
        failed += 1;
        console.error(`✗ ${path.basename(file)}: ${numErrors} errors, ${numWarnings} warnings`);
        for (const m of messages.slice(0, 5)) console.error(`    ${m.code}: ${m.message}`);
    }
}
console.log(`${files.length - failed} of ${files.length} GLB files passed the glTF Validator.`);
process.exit(failed ? 1 : 0);
