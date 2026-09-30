/**
 * Test: No Direct Table Mutations in App Code
 *
 * This test ensures that the app/ directory never directly calls .update()
 * or .insert() on protected tables. All mutations must go through
 * server-side RPC functions (Edge Functions).
 *
 * Protected tables:
 * - deliveries
 * - referral_codes
 * - profiles
 * - drivers
 * - partners
 * - earnings
 * - route_points
 * - delivery_messages
 * - delivery_status_history
 * - ratings_and_reviews
 */

import { readFileSync, readdirSync, statSync } from 'fs';
import { join, extname, relative } from 'path';

interface Violation {
  file: string;
  line: number;
  code: string;
  table: string;
  method: 'update' | 'insert';
}

const PROTECTED_TABLES = [
  'deliveries',
  'referral_codes',
  'profiles',
  'drivers',
  'partners',
  'earnings',
  'route_points',
  'delivery_messages',
  'delivery_status_history',
  'ratings_and_reviews',
];

const APP_DIR = join(__dirname, '..', '..', 'app');

function findTsxFiles(dir: string): string[] {
  const files: string[] = [];
  const entries = readdirSync(dir, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...findTsxFiles(fullPath));
    } else if (extname(entry.name) === '.tsx' || extname(entry.name) === '.ts') {
      files.push(fullPath);
    }
  }
  return files;
}

function checkFile(filePath: string): Violation[] {
  const violations: Violation[] = [];
  const content = readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');

  // Skip admin.tsx - admin-only screen with legitimate direct writes
  if (filePath.includes('admin.tsx')) return [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    // Skip comments and test files
    if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;
    if (filePath.includes('.test.') || filePath.includes('.spec.')) continue;

    // Check for .from('table').update() or .from('table').insert()
    for (const table of PROTECTED_TABLES) {
      // Pattern: .from('table') or .from("table") followed by .update() or .insert()
      const fromPattern = new RegExp(`\\.from\\(['"]${table}['"]\\)`);
      const updatePattern = new RegExp(`\\.from\\(['"]${table}['"]\\)\\s*\\.update\\(`);
      const insertPattern = new RegExp(`\\.from\\(['"]${table}['"]\\)\\s*\\.insert\\(`);

      if (updatePattern.test(line)) {
        violations.push({
          file: relative(process.cwd(), filePath),
          line: i + 1,
          code: line.trim(),
          table,
          method: 'update',
        });
      }
      if (insertPattern.test(line)) {
        violations.push({
          file: relative(process.cwd(), filePath),
          line: i + 1,
          code: line.trim(),
          table,
          method: 'insert',
        });
      }
    }
  }

  return violations;
}

function runTest(): void {
  const tsxFiles = findTsxFiles(APP_DIR);
  const allViolations: Violation[] = [];

  for (const file of tsxFiles) {
    const violations = checkFile(file);
    allViolations.push(...violations);
  }

  if (allViolations.length > 0) {
    console.error('\n❌ FAIL: Direct table mutations found in app/ code\n');
    console.error('All mutations must go through server-side RPC functions.\n');

    for (const v of allViolations) {
      console.error(`${v.file}:${v.line}`);
      console.error(`  Table: ${v.table} | Method: ${v.method}`);
      console.error(`  Code: ${v.code}`);
      console.error('');
    }

    console.error(`Total violations: ${allViolations.length}`);
    process.exit(1);
  } else {
    console.log('✅ PASS: No direct table mutations in app/ code');
    console.log(`Scanned ${tsxFiles.length} files`);
  }
}

runTest();