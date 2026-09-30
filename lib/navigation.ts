import { Linking, Platform } from 'react-native';

export type LatLng = { latitude: number; longitude: number };

/**
 * Opens the device's native maps app with turn-by-turn driving directions
 * to `destination`, optionally from a given `origin` (defaults to current
 * location when omitted, which is what you want for drivers en route).
 *
 * iOS     -> Apple Maps app (maps://), falls back to maps.apple.com
 * Android -> Google Maps turn-by-turn nav mode (google.navigation:),
 *            falls back to the Google Maps app/web directions URL
 */
export async function openDriveNavigation(
  destination: LatLng,
  label?: string,
  origin?: LatLng
) {
  const dest = `${destination.latitude},${destination.longitude}`;
  const orig = origin ? `${origin.latitude},${origin.longitude}` : undefined;

  if (Platform.OS === 'ios') {
    const params = [
      `daddr=${dest}`,
      orig ? `saddr=${orig}` : null,
      'dirflg=d', // driving
      label ? `q=${encodeURIComponent(label)}` : null,
    ].filter(Boolean).join('&');

    const appleUrl = `maps://?${params}`;
    const canOpenApp = await Linking.canOpenURL(appleUrl);
    if (canOpenApp) return Linking.openURL(appleUrl);

    // Simulator / Maps not installed — web fallback still deep-links into Maps on a real device
    return Linking.openURL(`https://maps.apple.com/?${params}`);
  }

  if (Platform.OS === 'android') {
    const navUrl = `google.navigation:q=${dest}&mode=d`;
    const canOpenApp = await Linking.canOpenURL(navUrl);
    if (canOpenApp) return Linking.openURL(navUrl);
  }

  // Universal fallback (Android w/o Maps app, web, etc.)
  const params = [
    `destination=${dest}`,
    orig ? `origin=${orig}` : null,
    'travelmode=driving',
  ].filter(Boolean).join('&');

  return Linking.openURL(`https://www.google.com/maps/dir/?api=1&${params}`);
}