/**
 * Pricing Engine for Edge Functions
 * Pure TypeScript implementation - single source of truth
 * Used by: get_quote, create_delivery Edge Functions
 * SQL functions should ONLY validate stored results against this.
 */

import type { PricingConfig, PricingInput, PricingResult, PricingComponent } from './config.ts';

/**
 * Check if current time falls within peak hours
 */
export function isPeakHour(peakHours: PricingConfig['peakHours'], date: Date = new Date()): boolean {
  const dayOfWeek = date.getDay(); // 0 = Sunday
  const timeStr = date.toTimeString().slice(0, 5); // "HH:MM"

  for (const period of peakHours) {
    if (period.days.includes(dayOfWeek)) {
      if (timeStr >= period.start && timeStr <= period.end) {
        return true;
      }
    }
  }
  return false;
}

/**
 * Calculate demand multiplier based on config
 * Currently uses min for peak hours, could be enhanced with curve logic
 */
export function calculateDemandMultiplier(
  config: PricingConfig,
  isPeak: boolean
): number {
  if (!isPeak) return 1.0;

  // For now, use min as the peak multiplier
  // Could enhance with curve logic based on demand level
  return config.demandMultiplier.min;
}

/**
 * Round fee according to config
 */
export function roundFee(fee: number, rounding: PricingConfig['feeRounding']): number {
  switch (rounding) {
    case 'ceil_0.25':
      return Math.ceil(fee * 4) / 4;
    case 'ceil_0.50':
      return Math.ceil(fee * 2) / 2;
    case 'round':
      return Math.round(fee * 100) / 100;
    case 'none':
    default:
      return fee;
  }
}

/**
 * Calculate zone-based pricing (zone_v1 strategy)
 */
export function calculateZonePricing(
  config: PricingConfig,
  input: PricingInput
): PricingResult {
  // Get base zone fee
  const baseFee = config.zoneFee[input.zone];

  // Apply demand multiplier if peak hour
  const demandMultiplier = calculateDemandMultiplier(config, input.isPeakHour);
  let fee = baseFee * demandMultiplier;

  // Add weather surcharge
  fee += input.weatherSurcharge;

  // Round fee
  fee = roundFee(fee, config.feeRounding);

  // Apply min/max - track adjustments for components
  const preMinMaxFee = fee;
  fee = Math.max(fee, config.minFee);
  fee = Math.min(fee, config.maxFee);

  // Calculate driver payout
  let driverPayout: number;
  if (config.payStrategy === 'pct_v1') {
    driverPayout = fee * config.payoutPctOrPerMile;
  } else if (config.payStrategy === 'per_mile_v1') {
    driverPayout = input.distanceMiles * config.payoutPctOrPerMile;
  } else {
    // hourly_floor_v1 - simplified, would need actual duration
    driverPayout = fee * config.payoutPctOrPerMile;
  }
  driverPayout = Math.max(driverPayout, config.minPayout);

  // Platform cut is fee minus driver payout (NOT using platformCutPct to avoid divergence)
  const platformCut = fee - driverPayout;

  // Build components - these should sum to customerTotal
  const components: PricingComponent[] = [
    {
      name: 'base_fee',
      amount: baseFee,
      description: `Zone ${input.zone} fee`
    }
  ];

  // Add demand multiplier component if applied
  if (demandMultiplier !== 1.0) {
    const multiplierAmount = baseFee * (demandMultiplier - 1);
    components.push({
      name: 'demand_multiplier',
      amount: multiplierAmount,
      description: `Peak demand adjustment (${(demandMultiplier * 100).toFixed(0)}%)`
    });
  }

  // Add weather surcharge if applied
  if (input.weatherSurcharge > 0) {
    components.push({
      name: 'weather_surcharge',
      amount: input.weatherSurcharge,
      description: 'Weather surcharge'
    });
  }

  // Add rounding adjustment if any
  const roundedFee = roundFee(preMinMaxFee, config.feeRounding);
  if (roundedFee !== preMinMaxFee) {
    components.push({
      name: 'rounding_adjustment',
      amount: roundedFee - preMinMaxFee,
      description: `Fee rounding (${config.feeRounding})`,
      isAdjustment: true
    });
  }

  // Add min fee adjustment if applied
  if (fee !== preMinMaxFee && fee === config.minFee && preMinMaxFee < config.minFee) {
    components.push({
      name: 'min_fee_adjustment',
      amount: config.minFee - preMinMaxFee,
      description: `Minimum fee adjustment ($${config.minFee.toFixed(2)} minimum)`,
      isAdjustment: true
    });
  }

  // Add max fee adjustment if applied
  if (fee !== preMinMaxFee && fee === config.maxFee && preMinMaxFee > config.maxFee) {
    components.push({
      name: 'max_fee_adjustment',
      amount: config.maxFee - preMinMaxFee,
      description: `Maximum fee adjustment ($${config.maxFee.toFixed(2)} maximum)`,
      isAdjustment: true
    });
  }

  return {
    customerTotal: fee,
    components,
    platformCut,
    driverPayout,
    zone: input.zone,
    distanceMiles: input.distanceMiles,
    strategy: 'zone_v1'
  };
}

/**
 * Calculate distance-time pricing (distance_time_v1 strategy)
 */
export function calculateDistanceTimePricing(
  config: PricingConfig,
  input: PricingInput
): PricingResult {
  const dt = config.distanceTime;

  // Base calculation
  const baseFee = dt.baseFee
    + input.distanceMiles * dt.perMile
    + input.estimatedDurationMinutes * dt.perMinute;

  // Apply demand multiplier if peak hour
  const demandMultiplier = calculateDemandMultiplier(config, input.isPeakHour);
  let fee = baseFee * demandMultiplier;

  // Add weather surcharge
  fee += input.weatherSurcharge;

  // Apply min fee - track for components
  const preMinFee = fee;
  fee = Math.max(fee, dt.minFee);

  // Calculate driver payout
  let driverPayout: number;
  if (config.payStrategy === 'pct_v1') {
    driverPayout = fee * config.payoutPctOrPerMile;
  } else if (config.payStrategy === 'per_mile_v1') {
    driverPayout = input.distanceMiles * config.payoutPctOrPerMile;
  } else {
    driverPayout = fee * config.payoutPctOrPerMile;
  }
  driverPayout = Math.max(driverPayout, config.minPayout);

  // Platform cut is fee minus driver payout
  const platformCut = fee - driverPayout;

  // Build components - should sum to customerTotal
  const components: PricingComponent[] = [
    {
      name: 'base_fee',
      amount: dt.baseFee,
      description: 'Base fee'
    },
    {
      name: 'per_mile',
      amount: input.distanceMiles * dt.perMile,
      description: `${input.distanceMiles.toFixed(1)} miles @ $${dt.perMile.toFixed(2)}/mile`
    },
    {
      name: 'per_minute',
      amount: input.estimatedDurationMinutes * dt.perMinute,
      description: `${input.estimatedDurationMinutes} minutes @ $${dt.perMinute.toFixed(2)}/min`
    }
  ];

  // Add demand multiplier component if applied
  if (demandMultiplier !== 1.0) {
    const multiplierAmount = baseFee * (demandMultiplier - 1);
    components.push({
      name: 'demand_multiplier',
      amount: multiplierAmount,
      description: `Peak demand adjustment (${(demandMultiplier * 100).toFixed(0)}%)`
    });
  }

  // Add weather surcharge if applied
  if (input.weatherSurcharge > 0) {
    components.push({
      name: 'weather_surcharge',
      amount: input.weatherSurcharge,
      description: 'Weather surcharge'
    });
  }

  // Add min fee adjustment if applied
  if (fee !== preMinFee && fee === dt.minFee && preMinFee < dt.minFee) {
    components.push({
      name: 'min_fee_adjustment',
      amount: dt.minFee - preMinFee,
      description: `Minimum fee adjustment ($${dt.minFee.toFixed(2)} minimum)`,
      isAdjustment: true
    });
  }

  return {
    customerTotal: fee,
    components,
    platformCut,
    driverPayout,
    zone: input.zone,
    distanceMiles: input.distanceMiles,
    strategy: 'distance_time_v1'
  };
}

/**
 * Main pricing function - routes to appropriate strategy
 */
export function calculatePricing(
  config: PricingConfig,
  input: PricingInput
): PricingResult {
  if (config.strategy === 'zone_v1') {
    return calculateZonePricing(config, input);
  } else if (config.strategy === 'distance_time_v1') {
    return calculateDistanceTimePricing(config, input);
  }
  throw new Error(`Unknown pricing strategy: ${config.strategy}`);
}

/**
 * Determine zone from distance using config distance bands
 */
export function getZoneFromDistance(distanceMiles: number, distanceBands: PricingConfig['distanceBands']): 1 | 2 | 3 {
  if (distanceMiles <= distanceBands[0]) return 1;
  if (distanceMiles <= distanceBands[1]) return 2;
  if (distanceMiles <= distanceBands[2]) return 3;
  throw new Error('OUTSIDE_SERVICE_AREA');
}

/**
 * Verify components sum to customerTotal (for testing/validation)
 */
export function verifyComponentsSum(result: PricingResult): boolean {
  const sum = result.components.reduce((acc, c) => acc + c.amount, 0);
  // Allow small floating point difference
  return Math.abs(sum - result.customerTotal) < 0.01;
}