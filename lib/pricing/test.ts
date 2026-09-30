/**
 * Pricing Engine Tests
 * Run with: npx tsx lib/pricing/test.ts
 */

import { runFixtures, runZoneBoundaryTests, DEFAULT_TEST_CONFIG } from './fixtures';
import { getZoneFromDistance, isPeakHour, calculatePricing } from '../../supabase/functions/_shared/pricing/engine';

// Run fixture tests
console.log('=== Running Pricing Fixtures ===\n');
const fixtureResults = runFixtures();

let passed = 0;
let failed = 0;

for (const { fixture, result, passed: fixturePassed, errors } of fixtureResults) {
  if (fixturePassed) {
    console.log(`✅ ${fixture.name}`);
    passed++;
  } else {
    console.log(`❌ ${fixture.name}`);
    console.log(`   ${fixture.description}`);
    for (const error of errors) {
      console.log(`   - ${error}`);
    }
    failed++;
  }
  console.log(`   Result: $${result.customerTotal.toFixed(2)} (driver: $${result.driverPayout.toFixed(2)}, platform: $${result.platformCut.toFixed(2)})`);
  console.log(`   Components: ${result.components.map(c => `${c.name}=$${c.amount.toFixed(2)}`).join(', ')}`);
  console.log();
}

// Run zone boundary tests
console.log('=== Running Zone Boundary Tests ===\n');
const zoneResults = runZoneBoundaryTests();

for (const { distanceMiles, expectedZone, passed: zonePassed } of zoneResults) {
  if (zonePassed) {
    console.log(`✅ ${distanceMiles} mi → Zone ${expectedZone}`);
    passed++;
  } else {
    try {
      const actualZone = getZoneFromDistance(distanceMiles, DEFAULT_TEST_CONFIG.distanceBands);
      console.log(`❌ ${distanceMiles} mi → Expected Zone ${expectedZone}, got Zone ${actualZone}`);
    } catch {
      console.log(`❌ ${distanceMiles} mi → Expected Zone ${expectedZone}, got error (OUTSIDE_SERVICE_AREA)`);
    }
    failed++;
  }
}

// Test peak hour detection
console.log('\n=== Testing Peak Hour Detection ===\n');
const testConfig = { ...DEFAULT_TEST_CONFIG };
const peakTests = [
  { date: new Date('2026-01-05T18:00:00'), expected: true, desc: 'Monday 6pm (peak)' },
  { date: new Date('2026-01-05T14:00:00'), expected: false, desc: 'Monday 2pm (off-peak)' },
  { date: new Date('2026-01-10T18:00:00'), expected: false, desc: 'Saturday 6pm (off-peak)' },
  { date: new Date('2026-01-07T19:30:00'), expected: true, desc: 'Wednesday 7:30pm (peak)' },
  { date: new Date('2026-01-07T20:01:00'), expected: false, desc: 'Wednesday 8:01pm (off-peak)' }
];

for (const { date, expected, desc } of peakTests) {
  const result = isPeakHour(testConfig.peakHours, date);
  if (result === expected) {
    console.log(`✅ ${desc}: ${result}`);
    passed++;
  } else {
    console.log(`❌ ${desc}: expected ${expected}, got ${result}`);
    failed++;
  }
}

// Test components sum verification
console.log('\n=== Testing Components Sum Verification ===\n');
const testInput = {
  distanceMiles: 5.0,
  estimatedDurationMinutes: 20,
  zone: 2 as const,
  isPeakHour: true,
  weatherSurcharge: 1.50
};
const testResult = calculatePricing(testConfig, testInput);
const sum = testResult.components.reduce((acc, c) => acc + c.amount, 0);
console.log(`Customer total: $${testResult.customerTotal.toFixed(2)}`);
console.log(`Components sum: $${sum.toFixed(2)}`);
console.log(`Match: ${Math.abs(sum - testResult.customerTotal) < 0.01 ? '✅' : '❌'}`);
if (Math.abs(sum - testResult.customerTotal) < 0.01) passed++; else failed++;

console.log(`\n=== Summary ===`);
console.log(`Passed: ${passed}`);
console.log(`Failed: ${failed}`);
console.log(`Total:  ${passed + failed}`);

if (failed > 0) {
  process.exit(1);
}