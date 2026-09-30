import mbxDirections from '@mapbox/mapbox-sdk/services/directions';

const MAPBOX_TOKEN = process.env.EXPO_PUBLIC_MAPBOX_TOKEN!;
const directionsClient = mbxDirections({ accessToken: MAPBOX_TOKEN });

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

const ZONES: Record<Zone, Omit<ZoneInfo, 'zone' | 'distanceMiles' | 'durationMinutes' | 'routePolyline'>> = {
  1: { label: 'Zone 1', range: '0–5 miles',   fee: 8,  driverPayout: 6.00,  platformCut: 2.00 },
  2: { label: 'Zone 2', range: '5–10 miles',  fee: 11, driverPayout: 8.25,  platformCut: 2.75 },
  3: { label: 'Zone 3', range: '10–20 miles', fee: 15, driverPayout: 11.25, platformCut: 3.75 },
};

export function getZone(miles: number): Zone {
  if (miles <= 5) return 1;
  if (miles <= 10) return 2;
  if (miles <= 20) return 3;
  throw new Error('OUTSIDE_SERVICE_AREA');
}

export async function calcDelivery(
  pickupLat: number, pickupLng: number,
  dropoffLat: number, dropoffLng: number
): Promise<ZoneInfo> {
  const response = await directionsClient.getDirections({
    profile: 'driving',
    geometries: 'polyline6',
    overview: 'full',
    waypoints: [
      { coordinates: [pickupLng, pickupLat] },
      { coordinates: [dropoffLng, dropoffLat] },
    ],
  }).send();

  const route = response.body.routes[0];
  if (!route) throw new Error('NO_ROUTE_FOUND');

  const distanceMiles = route.distance * 0.000621371;
  const durationMinutes = Math.ceil(route.duration / 60);
  const routePolyline = route.geometry;
  const zone = getZone(distanceMiles);

  return {
    zone,
    ...ZONES[zone],
    distanceMiles,
    durationMinutes,
    routePolyline,
  };
}

// IRS mileage rate 2024
const IRS_RATE = 0.67;

export interface MileageEntry {
  date: string;
  pickupAddress: string;
  dropoffAddress: string;
  miles: number;
  deductibleValue: number;
  deliveryId: string;
}

export function calcMileageDeduction(miles: number): number {
  return parseFloat((miles * IRS_RATE).toFixed(2));
}

export function formatMileageEntry(
  deliveryId: string,
  date: string,
  pickupAddress: string,
  dropoffAddress: string,
  miles: number
): MileageEntry {
  return {
    deliveryId,
    date,
    pickupAddress,
    dropoffAddress,
    miles: parseFloat(miles.toFixed(2)),
    deductibleValue: calcMileageDeduction(miles),
  };
}