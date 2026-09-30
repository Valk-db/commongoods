/**
 * Golden Test Fixtures for Pricing Engine
 * These fixtures define expected outputs for given inputs + config.
 * Used by tests to verify pricing engine correctness.
 * SQL functions should produce matching results.
 */

import type { PricingConfig, PricingInput, PricingResult } from '../../supabase/functions/_shared/pricing/config';
import { calculatePricing, getZoneFromDistance, verifyComponentsSum } from '../../supabase/functions/_shared/pricing/engine';

// Default test config (matches seeded config_registry defaults)
export const DEFAULT_TEST_CONFIG: PricingConfig = {
  strategy: 'zone_v1',
  feeRounding: 'ceil_0.25',
  minFee: 5.00,
  maxFee: 100.00,
  platformCutPct: 0.25,
  patronageReservePct: 0.05,
  zoneFee: {
    1: 8.00,
    2: 11.00,
    3: 15.00
  },
  distanceBands: [5, 10, 20],
  distanceTime: {
    baseFee: 5.00,
    perMile: 2.00,
    perMinute: 0.50,
    minFee: 7.00
  },
  demandMultiplier: {
    min: 1.25, // 1.25x during peak
    max: 2.0,
    curve: 'linear'
  },
  peakHours: [
    { start: '17:00', end: '20:00', days: [1, 2, 3, 4, 5] } // Mon-Fri 5-8pm
  ],
  weatherSurcharge: 0.00,
  payStrategy: 'pct_v1',
  payoutPctOrPerMile: 0.75,
  minPayout: 4.00,
  payFloorPerHour: 15.00,
  waitPayPerMinute: 0.25,
  waitPayGraceMinutes: 5
};

// Test fixtures: each defines input, config overrides, and expected output
export interface PricingFixture {
  name: string;
  description: string;
  input: PricingInput;
  configOverrides?: Partial<PricingConfig>;
  expected: Partial<PricingResult>; // Only check specified fields
}

export const PRICING_FIXTURES: PricingFixture[] = [
  // Zone 1, off-peak, no weather
  {
    name: 'zone1_off_peak_no_weather',
    description: 'Zone 1 delivery off-peak, no weather surcharge',
    input: {
      distanceMiles: 3.0,
      estimatedDurationMinutes: 15,
      zone: 1,
      isPeakHour: false,
      weatherSurcharge: 0
    },
    expected: {
      customerTotal: 8.00, // zone 1 fee, no multiplier
      zone: 1,
      strategy: 'zone_v1',
      driverPayout: 6.00, // 8.00 * 0.75
      platformCut: 2.00  // 8.00 - 6.00
    }
  },

  // Zone 1, peak hour
  {
    name: 'zone1_peak_hour',
    description: 'Zone 1 delivery during peak hour (1.25x multiplier)',
    input: {
      distanceMiles: 3.0,
      estimatedDurationMinutes: 15,
      zone: 1,
      isPeakHour: true,
      weatherSurcharge: 0
    },
    expected: {
      // 8.00 * 1.25 = 10.00, rounded to nearest 0.25 = 10.00
      customerTotal: 10.00,
      zone: 1,
      strategy: 'zone_v1',
      driverPayout: 7.50, // 10.00 * 0.75
      platformCut: 2.50  // 10.00 - 7.50
    }
  },

  // Zone 2, off-peak
  {
    name: 'zone2_off_peak',
    description: 'Zone 2 delivery off-peak',
    input: {
      distanceMiles: 7.5,
      estimatedDurationMinutes: 25,
      zone: 2,
      isPeakHour: false,
      weatherSurcharge: 0
    },
    expected: {
      customerTotal: 11.00,
      zone: 2,
      strategy: 'zone_v1',
      driverPayout: 8.25, // 11.00 * 0.75
      platformCut: 2.75
    }
  },

  // Zone 3, peak hour with weather surcharge
  {
    name: 'zone3_peak_weather',
    description: 'Zone 3 delivery peak hour with weather surcharge',
    input: {
      distanceMiles: 15.0,
      estimatedDurationMinutes: 40,
      zone: 3,
      isPeakHour: true,
      weatherSurcharge: 2.00
    },
    expected: {
      // 15.00 * 1.25 = 18.75 + 2.00 = 20.75, ceil_0.25 = 20.75
      // wait: 15 * 1.25 = 18.75, round to ceil_0.25 = 18.75, + 2.00 = 20.75
      customerTotal: 20.75,
      zone: 3,
      strategy: 'zone_v1',
      driverPayout: 15.56, // 20.75 * 0.75 = 15.5625, max(4.00)
      platformCut: 5.19   // 20.75 - 15.56 = 5.1875
    }
  },

  // Zone 1, at min fee boundary
  {
    name: 'zone1_min_fee',
    description: 'Zone 1 fee below min_fee, should be raised to min',
    input: {
      distanceMiles: 1.0,
      estimatedDurationMinutes: 5,
      zone: 1,
      isPeakHour: false,
      weatherSurcharge: 0
    },
    configOverrides: {
      zoneFee: { 1: 3.00, 2: 11.00, 3: 15.00 }, // Zone 1 fee below min
      minFee: 5.00
    },
    expected: {
      customerTotal: 5.00, // raised to min
      zone: 1,
      driverPayout: 4.00, // max(5.00 * 0.75, 4.00) = max(3.75, 4.00) = 4.00
      platformCut: 1.00  // 5.00 - 4.00
    }
  },

  // Zone 1, at max fee boundary
  {
    name: 'zone1_max_fee',
    description: 'Zone 1 fee above max_fee, should be capped',
    input: {
      distanceMiles: 4.0,
      estimatedDurationMinutes: 10,
      zone: 1,
      isPeakHour: true,
      weatherSurcharge: 10
    },
    configOverrides: {
      zoneFee: { 1: 50.00, 2: 11.00, 3: 15.00 },
      maxFee: 20.00,
      demandMultiplier: { min: 1.5, max: 2.0, curve: 'linear' }
    },
    expected: {
      customerTotal: 20.00, // capped at max
      zone: 1,
      // Note: components show pre-cap values, so they won't sum to capped total
      // This is expected behavior - components are informational
    }
  },

  // Distance-time strategy, off-peak
  {
    name: 'distance_time_off_peak',
    description: 'Distance-time pricing off-peak',
    input: {
      distanceMiles: 10.0,
      estimatedDurationMinutes: 30,
      zone: 1, // not used in distance_time
      isPeakHour: false,
      weatherSurcharge: 0
    },
    configOverrides: {
      strategy: 'distance_time_v1',
      distanceTime: { baseFee: 5.00, perMile: 2.00, perMinute: 0.50, minFee: 7.00 }
    },
    expected: {
      // 5 + 10*2 + 30*0.5 = 5 + 20 + 15 = 40
      customerTotal: 40.00,
      strategy: 'distance_time_v1',
      zone: 1,
      driverPayout: 30.00, // 40 * 0.75
      platformCut: 10.00
    }
  },

  // Distance-time strategy, peak hour
  {
    name: 'distance_time_peak',
    description: 'Distance-time pricing peak hour',
    input: {
      distanceMiles: 10.0,
      estimatedDurationMinutes: 30,
      zone: 1,
      isPeakHour: true,
      weatherSurcharge: 0
    },
    configOverrides: {
      strategy: 'distance_time_v1',
      distanceTime: { baseFee: 5.00, perMile: 2.00, perMinute: 0.50, minFee: 7.00 },
      demandMultiplier: { min: 1.25, max: 2.0, curve: 'linear' }
    },
    expected: {
      // (5 + 20 + 15) * 1.25 = 40 * 1.25 = 50
      customerTotal: 50.00,
      strategy: 'distance_time_v1',
      driverPayout: 37.50, // 50 * 0.75
      platformCut: 12.50
    }
  },

  // Per-mile driver pay strategy
  {
    name: 'per_mile_driver_pay',
    description: 'Per-mile driver pay strategy',
    input: {
      distanceMiles: 10.0,
      estimatedDurationMinutes: 30,
      zone: 1,
      isPeakHour: false,
      weatherSurcharge: 0
    },
    configOverrides: {
      strategy: 'zone_v1',
      zoneFee: { 1: 20.00, 2: 11.00, 3: 15.00 },
      payStrategy: 'per_mile_v1',
      payoutPctOrPerMile: 1.50, // $1.50/mile
      minPayout: 4.00
    },
    expected: {
      customerTotal: 20.00,
      driverPayout: 15.00, // 10 miles * 1.50
      platformCut: 5.00
    }
  },

  // Test zone determination from distance
  {
    name: 'zone_determination',
    description: 'Verify zone boundaries from distance bands',
    input: {
      distanceMiles: 0,
      estimatedDurationMinutes: 0,
      zone: 1,
      isPeakHour: false,
      weatherSurcharge: 0
    },
    configOverrides: {
      distanceBands: [5, 10, 20]
    },
    expected: {}
  }
];

// Expected zone for distance values (for zone_determination test)
export const ZONE_BOUNDARY_TESTS: Array<{ distanceMiles: number; expectedZone: 1 | 2 | 3 | null }> = [
  { distanceMiles: 0.1, expectedZone: 1 },
  { distanceMiles: 5.0, expectedZone: 1 },
  { distanceMiles: 5.01, expectedZone: 2 },
  { distanceMiles: 10.0, expectedZone: 2 },
  { distanceMiles: 10.01, expectedZone: 3 },
  { distanceMiles: 20.0, expectedZone: 3 },
  { distanceMiles: 20.01, expectedZone: null } // OUTSIDE_SERVICE_AREA
];

/**
 * Run all fixtures and return results
 */
export function runFixtures(): Array<{ fixture: PricingFixture; result: PricingResult; passed: boolean; errors: string[] }> {
  const results = [];

  for (const fixture of PRICING_FIXTURES) {
    const config = { ...DEFAULT_TEST_CONFIG, ...fixture.configOverrides };
    const result = calculatePricing(config, fixture.input);
    const errors: string[] = [];

    // Check expected fields
    for (const [key, expectedValue] of Object.entries(fixture.expected)) {
      const actualValue = (result as unknown as Record<string, unknown>)[key];
      if (actualValue !== expectedValue) {
        // Allow small floating point difference for numeric fields
        if (typeof expectedValue === 'number' && typeof actualValue === 'number') {
          if (Math.abs(actualValue - expectedValue) > 0.01) {
            errors.push(`${key}: expected ${expectedValue}, got ${actualValue}`);
          }
        } else {
          errors.push(`${key}: expected ${expectedValue}, got ${actualValue}`);
        }
      }
    }

    // Verify components sum to total
    if (!verifyComponentsSum(result)) {
      errors.push('Components do not sum to customerTotal');
    }

    results.push({
      fixture,
      result,
      passed: errors.length === 0,
      errors
    });
  }

  return results;
}

/**
 * Run zone boundary tests
 */
export function runZoneBoundaryTests(): Array<{ distanceMiles: number; expectedZone: 1 | 2 | 3 | null; passed: boolean }> {
  return ZONE_BOUNDARY_TESTS.map(({ distanceMiles, expectedZone }) => {
    try {
      const zone = getZoneFromDistance(distanceMiles, DEFAULT_TEST_CONFIG.distanceBands);
      return { distanceMiles, expectedZone, passed: zone === expectedZone };
    } catch {
      return { distanceMiles, expectedZone, passed: expectedZone === null };
    }
  });
}