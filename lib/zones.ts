import { cfg, config, type ConfigContext } from './config';

export type Zone = 1 | 2 | 3;

export interface ZoneInfo {
  zone: Zone;
  label: string;
  range: string;
  fee: number;
  driverPayout: number;
  platformCut: number;
  distanceMiles: number;
  durationMinutes: number;
  routePolyline: string;
}

/**
 * Get zone from distance using config-driven distance bands
 * Replaces hardcoded zone boundaries
 */
export async function getZone(miles: number, ctx?: ConfigContext): Promise<Zone> {
  const bands = await cfg.pricing.getDistanceBands(ctx);
  if (miles <= bands[0]) return 1;
  if (miles <= bands[1]) return 2;
  if (miles <= bands[2]) return 3;
  throw new Error('OUTSIDE_SERVICE_AREA');
}

/**
 * Get zone pricing from config (replaces hardcoded ZONES object)
 */
async function getZonePricing(zone: Zone, ctx?: ConfigContext): Promise<{ fee: number; driverPayout: number; platformCut: number; label: string; range: string }> {
  const [fee, driverPayout, platformCut] = await Promise.all([
    cfg.pricing.getZoneFee(zone, ctx),
    cfg.driverPay.getPayoutRate(ctx), // This returns pct or per-mile depending on strategy
    cfg.platform.getCutPct(ctx)
  ]);

  const ranges = ['0–5 miles', '5–10 miles', '10–20 miles'];
  const labels = ['Zone 1', 'Zone 2', 'Zone 3'];

  return {
    fee,
    driverPayout,
    platformCut,
    label: labels[zone - 1],
    range: ranges[zone - 1]
  };
}

/**
 * Calculate delivery pricing using config-driven strategy
 * Replaces calcDelivery that used hardcoded ZONES and Mapbox client-side
 *
 * NOTE: This function now requires server-side execution (Edge Function)
 * because Mapbox token is server-side only. Client should call
 * create_delivery Edge Function instead.
 *
 * @deprecated Use create_delivery Edge Function for pricing
 */
export async function calcDelivery(
  pickupLat: number, pickupLng: number,
  dropoffLat: number, dropoffLng: number,
  ctx?: ConfigContext
): Promise<ZoneInfo> {
  // This is a stub - actual implementation moved to Edge Function
  // Client should NOT call this directly; it exists for type compatibility
  const strategy = await cfg.pricing.getStrategy(ctx);

  if (strategy === 'distance_time_v1') {
    const dt = await cfg.pricing.getDistanceTime(ctx);
    // Would need Mapbox distance/duration from Edge Function
    throw new Error('distance_time_v1 pricing requires Edge Function');
  }

  // zone_v1 strategy - still needs distance from Mapbox
  throw new Error('zone_v1 pricing requires Edge Function for Mapbox distance');
}

/**
 * Get mileage deduction using date-effective IRS rates from config
 * Replaces hardcoded IRS_RATE = 0.67
 */
export interface MileageEntry {
  date: string;
  pickupAddress: string;
  dropoffAddress: string;
  miles: number;
  deductibleValue: number;
  deliveryId: string;
}

export async function calcMileageDeduction(miles: number, date: Date = new Date()): Promise<number> {
  const rate = await config.getMileageRate(date);
  if (!rate) {
    // Fallback to current year rate if not found (in dollars per mile)
    const currentYear = date.getFullYear();
    const fallbackRates: Record<number, number> = {
      2024: 0.67,
      2025: 0.70,
      2026: 0.725 // H1, but we'll use 0.725 as average
    };
    const dollarsPerMile = fallbackRates[currentYear] || 0.67;
    return parseFloat((miles * dollarsPerMile).toFixed(2));
  }
  // rate.business_cents is now in dollars per mile (e.g., 0.6700)
  return parseFloat((miles * rate.business_cents).toFixed(2));
}

export async function formatMileageEntry(
  deliveryId: string,
  date: string,
  pickupAddress: string,
  dropoffAddress: string,
  miles: number
): Promise<MileageEntry> {
  const entryDate = new Date(date);
  return {
    deliveryId,
    date,
    pickupAddress,
    dropoffAddress,
    miles: parseFloat(miles.toFixed(2)),
    deductibleValue: await calcMileageDeduction(miles, entryDate)
  };
}

// Re-export config for direct access
export { config } from './config';