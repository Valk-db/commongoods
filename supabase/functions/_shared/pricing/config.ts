/**
 * Pricing Config Interface for Edge Functions
 * Mirrors lib/pricing/config.ts but for Deno runtime
 */

export interface PricingConfig {
  strategy: 'zone_v1' | 'distance_time_v1';
  feeRounding: 'none' | 'round' | 'ceil_0.25' | 'ceil_0.50';
  minFee: number;
  maxFee: number;
  platformCutPct: number;
  patronageReservePct: number;

  // Zone-based pricing
  zoneFee: { 1: number; 2: number; 3: number };
  distanceBands: [number, number, number];

  // Distance-time pricing
  distanceTime: {
    baseFee: number;
    perMile: number;
    perMinute: number;
    minFee: number;
  };

  // Demand multiplier
  demandMultiplier: {
    min: number;
    max: number;
    curve: 'linear' | 'exponential' | 'step';
  };
  peakHours: Array<{ start: string; end: string; days: number[] }>;
  weatherSurcharge: number;

  // Driver pay
  payStrategy: 'pct_v1' | 'per_mile_v1' | 'hourly_floor_v1';
  payoutPctOrPerMile: number;
  minPayout: number;
  payFloorPerHour: number;
  waitPayPerMinute: number;
  waitPayGraceMinutes: number;
}

export interface PricingInput {
  distanceMiles: number;
  estimatedDurationMinutes: number;
  zone: 1 | 2 | 3;
  isPeakHour: boolean;
  weatherSurcharge: number;
}

export interface PricingComponent {
  name: string;
  amount: number;
  description: string;
  isAdjustment?: boolean;
}

export interface PricingResult {
  customerTotal: number;
  components: PricingComponent[];
  platformCut: number;
  driverPayout: number;
  zone: number;
  distanceMiles: number;
  strategy: string;
}