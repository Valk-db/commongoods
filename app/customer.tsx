import { useState, useEffect, useRef, useCallback } from 'react';
import {
  View, Text, TouchableOpacity, StyleSheet,
  ScrollView, Alert, ActivityIndicator, TextInput,
  KeyboardAvoidingView, Platform, Dimensions,
} from 'react-native';
import MapView, { Marker } from 'react-native-maps';
import BottomSheet, { BottomSheetScrollView } from '@gorhom/bottom-sheet';
import * as Location from 'expo-location';
import { supabase } from '../lib/supabase';
import { cfg } from '../lib/config';

const CREATE_DELIVERY_URL = process.env.EXPO_PUBLIC_SUPABASE_URL! + '/functions/v1/create_delivery';
const GET_QUOTE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL! + '/functions/v1/get_quote';
const MAPBOX_TOKEN = process.env.EXPO_PUBLIC_MAPBOX_TOKEN!;
const SCREEN_HEIGHT = Dimensions.get('window').height;

type LatLng  = { latitude: number; longitude: number };
type PinMode = 'pickup' | 'dropoff';

interface SearchResult {
  id: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  type: 'business' | 'address';
}

interface PricingBreakdown {
  customer_total: number;
  components: Array<{ name: string; amount: number; description: string }>;
  platform_cut: number;
  driver_payout: number;
  zone: number;
  distance_miles: number;
  strategy: string;
  estimated_duration_minutes?: number;
  is_peak_hour?: boolean;
  demand_multiplier?: number;
}

interface CreateDeliveryResponse {
  success: boolean;
  error?: string;
  delivery_id?: string;
  quote_id?: string;
  pricing_breakdown?: PricingBreakdown;
}

const ST_AUGUSTINE = {
  latitude: 29.8943,
  longitude: -81.3145,
  latitudeDelta: 0.12,
  longitudeDelta: 0.12,
};

// CATEGORIES will be loaded from config

// Snap points — collapsed (peek), half, full
const SNAP_POINTS = ['18%', '52%', '92%'];

async function searchLocation(query: string, proximity: LatLng | null): Promise<SearchResult[]> {
  const prox = proximity
    ? `${proximity.longitude},${proximity.latitude}`
    : `-81.3145,29.8943`;

  // Search POI and address separately then merge, POIs first
  const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${encodeURIComponent(query)}.json`
    + `?types=poi,address`
    + `&country=US`
    + `&bbox=-81.7,29.5,-80.9,30.3`
    + `&proximity=${prox}`
    + `&fuzzyMatch=true`
    + `&limit=8`
    + `&access_token=${MAPBOX_TOKEN}`;

  const res = await fetch(url);
  const data = await res.json();
  if (!data.features) return [];

  // Sort: POIs first, then addresses
  const sorted = [...data.features].sort((a: any, b: any) => {
    const aIsPOI = a.place_type.includes('poi');
    const bIsPOI = b.place_type.includes('poi');
    if (aIsPOI && !bIsPOI) return -1;
    if (!aIsPOI && bIsPOI) return 1;
    return 0;
  });

  return sorted.map((f: any) => {
    const isPOI = f.place_type.includes('poi');
    const name = isPOI ? f.text : f.place_name.split(',')[0];
    const city = f.context?.find((c: any) => c.id.startsWith('place'))?.text ?? '';
    const street = f.properties?.address ?? '';
    const address = isPOI
      ? (street ? `${street}${city ? ', ' + city : ''}` : f.place_name)
      : f.place_name;
    return {
      id: f.id,
      name,
      address,
      latitude: f.center[1],
      longitude: f.center[0],
      type: isPOI ? 'business' : 'address',
    } as SearchResult;
  });
}

async function reverseGeocode(lat: number, lng: number): Promise<string> {
  const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${lng},${lat}.json`
    + `?types=poi,address`
    + `&access_token=${MAPBOX_TOKEN}`;
  const res = await fetch(url);
  const data = await res.json();
  if (data.features?.length > 0) return data.features[0].place_name;
  return `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
}

export default function CustomerScreen() {
  const [pickup,          setPickup]          = useState<LatLng | null>(null);
  const [dropoff,         setDropoff]         = useState<LatLng | null>(null);
  const [pickupAddress,   setPickupAddress]   = useState('');
  const [dropoffAddress,  setDropoffAddress]  = useState('');
  const [pinMode,         setPinMode]         = useState<PinMode>('pickup');
  const [category,        setCategory]        = useState('');
  const [notes,           setNotes]           = useState('');
  const [region,          setRegion]          = useState(ST_AUGUSTINE);
  const [delivery,        setDelivery]        = useState<PricingBreakdown | null>(null);
  const [zoneLoading,     setZoneLoading]     = useState(false);
  const [zoneError,       setZoneError]       = useState<string | null>(null);
  const [submitting,      setSubmitting]      = useState(false);
  const [quoteId,         setQuoteId]         = useState<string | null>(null);
  const [userLocation,    setUserLocation]    = useState<LatLng | null>(null);
  const [locationGranted, setLocationGranted] = useState(false);
  const [searchQuery,     setSearchQuery]     = useState('');
  const [searchResults,   setSearchResults]   = useState<SearchResult[]>([]);
  const [searching,       setSearching]       = useState(false);
  const [searchActive,    setSearchActive]    = useState(false);
  const [categories,      setCategories]      = useState<string[]>([]);
  const [outOfAreaMsg,    setOutOfAreaMsg]    = useState('');

  const mapRef    = useRef<MapView>(null);
  const sheetRef  = useRef<BottomSheet>(null);
  const searchTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Load categories and out-of-area message from config on mount
  useEffect(() => {
    (async () => {
      try {
        const [cats, msg] = await Promise.all([
          cfg.ux.getCategories(),
          cfg.ux.getOutOfAreaMessage(),
        ]);
        if (!cats || cats.length === 0) {
          throw new Error('Categories not configured');
        }
        setCategories(cats);
        setCategory(cats[0]);
        setOutOfAreaMsg(msg || "Sorry, we don't deliver to this area yet.");
      } catch (err) {
        console.error('Failed to load config:', err);
        Alert.alert('Configuration Error', 'Unable to load delivery options. Please try again later.');
      }
    })();
  }, []);

  // Location on mount
  useEffect(() => {
    (async () => {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') return;
      setLocationGranted(true);
      const loc = await Location.getCurrentPositionAsync({});
      const ul = { latitude: loc.coords.latitude, longitude: loc.coords.longitude };
      setUserLocation(ul);
      setRegion({ ...ul, latitudeDelta: 0.08, longitudeDelta: 0.08 });
    })();
  }, []);

  // Zone calc when both pins set - calls get_quote Edge Function for pricing preview
  useEffect(() => {
    if (!pickup || !dropoff) { setDelivery(null); setZoneError(null); return; }
    let cancelled = false;
    (async () => {
      setZoneLoading(true);
      setZoneError(null);
      try {
        const { data: { session } } = await supabase.auth.getSession();
        if (!session) throw new Error('Not authenticated');

        // Get a partner for the quote - use first approved partner
        const { data: partners, error: partnerError } = await supabase
          .from('partners')
          .select('id')
          .eq('approved', true)
          .limit(1);

        if (partnerError || !partners || partners.length === 0) {
          throw new Error('No approved partners available');
        }

        const partnerId = partners[0].id;

        const response = await fetch(GET_QUOTE_URL, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session.access_token}`,
          },
          body: JSON.stringify({
            customer_id: session.user.id,
            partner_id: partnerId,
            category: category,
            pickup_address: pickupAddress || `${pickup.latitude.toFixed(5)}, ${pickup.longitude.toFixed(5)}`,
            pickup_lat: pickup.latitude,
            pickup_lng: pickup.longitude,
            dropoff_address: dropoffAddress || `${dropoff.latitude.toFixed(5)}, ${dropoff.longitude.toFixed(5)}`,
            dropoff_lat: dropoff.latitude,
            dropoff_lng: dropoff.longitude,
            estimated_duration_minutes: 0,
            notes: notes.trim() || null,
          }),
        });

        const data: CreateDeliveryResponse = await response.json();
        if (!cancelled) {
          if (data.success && data.pricing_breakdown) {
            setDelivery(data.pricing_breakdown);
            setQuoteId(data.quote_id || null);
          } else {
            setZoneError(data.error === 'OUTSIDE_SERVICE_AREA'
              ? outOfAreaMsg
              : data.error || 'Could not calculate route. Try again.');
            setDelivery(null);
          }
        }
      } catch (err: any) {
        if (!cancelled) {
          setZoneError(err.message === 'OUTSIDE_SERVICE_AREA'
            ? outOfAreaMsg
            : 'Could not calculate route. Try again.');
          setDelivery(null);
        }
      } finally {
        if (!cancelled) setZoneLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [pickup, dropoff, category, pickupAddress, dropoffAddress, notes, outOfAreaMsg]);

  // Debounced search
  const handleSearchChange = useCallback((text: string) => {
    setSearchQuery(text);
    if (searchTimer.current) clearTimeout(searchTimer.current);
    if (!text.trim()) { setSearchResults([]); return; }
    searchTimer.current = setTimeout(async () => {
      setSearching(true);
      try {
        const results = await searchLocation(text, userLocation);
        setSearchResults(results);
      } catch {
        setSearchResults([]);
      } finally {
        setSearching(false);
      }
    }, 350);
  }, [userLocation]);

  function selectSearchResult(result: SearchResult) {
    const coord = { latitude: result.latitude, longitude: result.longitude };
    const label = result.type === 'business'
      ? `${result.name}${result.address ? ' — ' + result.address : ''}`
      : result.address;

    if (pinMode === 'pickup') {
      setPickup(coord);
      setPickupAddress(label);
      setPinMode('dropoff');
    } else {
      setDropoff(coord);
      setDropoffAddress(label);
    }

    mapRef.current?.animateToRegion({ ...coord, latitudeDelta: 0.04, longitudeDelta: 0.04 }, 400);
    setSearchQuery('');
    setSearchResults([]);
    setSearchActive(false);
    // Snap to half so map is visible
    sheetRef.current?.snapToIndex(1);
  }

  async function setCurrentLocationFor(mode: PinMode) {
    if (!userLocation) return;
    const address = await reverseGeocode(userLocation.latitude, userLocation.longitude);
    if (mode === 'pickup') {
      setPickup(userLocation);
      setPickupAddress(address);
      setPinMode('dropoff');
    } else {
      setDropoff(userLocation);
      setDropoffAddress(address);
    }
    mapRef.current?.animateToRegion({ ...userLocation, latitudeDelta: 0.06, longitudeDelta: 0.06 }, 400);
    sheetRef.current?.snapToIndex(1);
  }

  async function handleMapPress(e: any) {
    const coord: LatLng = e.nativeEvent.coordinate;
    const address = await reverseGeocode(coord.latitude, coord.longitude);
    if (pinMode === 'pickup') {
      setPickup(coord);
      setPickupAddress(address);
      setPinMode('dropoff');
    } else {
      setDropoff(coord);
      setDropoffAddress(address);
    }
  }

  async function handleRequest() {
    if (!pickup || !dropoff || !delivery) {
      Alert.alert('Missing info', 'Set both pickup and dropoff pins first.');
      return;
    }
    setSubmitting(true);
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) { setSubmitting(false); Alert.alert('Not logged in'); return; }

    // Get a partner - for now use first approved partner, but ideally user selects
    const { data: partners, error: partnerError } = await supabase
      .from('partners')
      .select('id')
      .eq('approved', true)
      .limit(1);

    if (partnerError || !partners || partners.length === 0) {
      setSubmitting(false);
      Alert.alert('Error', 'No approved partners available');
      return;
    }

    const response = await fetch(CREATE_DELIVERY_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({
        customer_id: session.user.id,
        partner_id: partners[0].id,
        category,
        pickup_address: pickupAddress || `${pickup.latitude.toFixed(5)}, ${pickup.longitude.toFixed(5)}`,
        pickup_lat: pickup.latitude,
        pickup_lng: pickup.longitude,
        dropoff_address: dropoffAddress || `${dropoff.latitude.toFixed(5)}, ${dropoff.longitude.toFixed(5)}`,
        dropoff_lat: dropoff.latitude,
        dropoff_lng: dropoff.longitude,
        estimated_duration_minutes: delivery.estimated_duration_minutes || 0,
        notes: notes.trim() || null,
        quote_id: quoteId,
      }),
    });

    const data: CreateDeliveryResponse = await response.json();
    setSubmitting(false);

    if (!data.success) {
      Alert.alert('Error', data.error || 'Failed to create delivery');
      return;
    }

    Alert.alert(
      '✅ Delivery Requested',
      `Zone ${data.pricing_breakdown?.zone}  ·  ${data.pricing_breakdown?.distance_miles.toFixed(1)} mi  ·  $${data.pricing_breakdown?.customer_total} flat fee\nA driver will claim your delivery shortly.`,
      [{ text: 'OK', onPress: () => {
        setPickup(null); setDropoff(null); setDelivery(null);
        setPickupAddress(''); setDropoffAddress('');
        setNotes(''); setPinMode('pickup');
        setQuoteId(null);
        sheetRef.current?.snapToIndex(1);
      }}]
    );
  }

  return (
    <View style={styles.container}>

      {/* Full screen map */}
      <MapView
        ref={mapRef}
        style={StyleSheet.absoluteFill}
        initialRegion={region}
        showsUserLocation
        onPress={handleMapPress}
      >
        {pickup  && <Marker coordinate={pickup}  pinColor="#f5a623" title="Pickup"  description={pickupAddress} />}
        {dropoff && <Marker coordinate={dropoff} pinColor="#1a6b6b" title="Dropoff" description={dropoffAddress} />}
      </MapView>

      {/* Search bar overlaid on map */}
      <View style={styles.searchOverlay}>
        <View style={styles.searchBar}>
          <Text style={styles.searchMode}>{pinMode === 'pickup' ? '📍' : '🏁'}</Text>
          <TextInput
            style={styles.searchInput}
            placeholder={pinMode === 'pickup'
              ? 'Business name or pickup address...'
              : 'Business name or dropoff address...'}
            placeholderTextColor="#4a7a7a"
            value={searchQuery}
            onChangeText={handleSearchChange}
            onFocus={() => { setSearchActive(true); sheetRef.current?.snapToIndex(2); }}
            onBlur={() => setTimeout(() => setSearchActive(false), 200)}
            autoCorrect={false}
            autoCapitalize="none"
          />
          {searchQuery.length > 0 && (
            <TouchableOpacity onPress={() => { setSearchQuery(''); setSearchResults([]); }}>
              <Text style={styles.searchClear}>✕</Text>
            </TouchableOpacity>
          )}
        </View>

        {/* Dropdown results */}
        {searchActive && (searchResults.length > 0 || searching) && (
          <View style={styles.searchResults}>
            {searching && <ActivityIndicator color="#f5a623" style={{ padding: 12 }} />}
            {searchResults.map((result) => (
              <TouchableOpacity
                key={result.id}
                style={styles.searchResultRow}
                onPress={() => selectSearchResult(result)}
              >
                <Text style={styles.searchResultIcon}>
                  {result.type === 'business' ? '🏢' : '📮'}
                </Text>
                <View style={styles.searchResultText}>
                  <Text style={styles.searchResultName}>{result.name}</Text>
                  {result.address ? (
                    <Text style={styles.searchResultAddress} numberOfLines={1}>{result.address}</Text>
                  ) : null}
                </View>
              </TouchableOpacity>
            ))}
          </View>
        )}
      </View>

      {/* Swipeable bottom sheet */}
      <BottomSheet
        ref={sheetRef}
        index={1}
        snapPoints={SNAP_POINTS}
        backgroundStyle={styles.sheetBg}
        handleIndicatorStyle={styles.sheetHandle}
        keyboardBehavior="interactive"
        keyboardBlurBehavior="restore"
      >
        <BottomSheetScrollView contentContainerStyle={styles.sheetContent}>

          {/* Current location buttons */}
          {locationGranted && (
            <View style={styles.locBtnRow}>
              {!pickup && (
                <TouchableOpacity style={styles.locBtn} onPress={() => setCurrentLocationFor('pickup')}>
                  <Text style={styles.locBtnText}>📱 My location as pickup</Text>
                </TouchableOpacity>
              )}
              {pickup && !dropoff && (
                <TouchableOpacity style={styles.locBtn} onPress={() => setCurrentLocationFor('dropoff')}>
                  <Text style={styles.locBtnText}>📱 My location as dropoff</Text>
                </TouchableOpacity>
              )}
              {pickup && dropoff && (
                <View style={styles.locBtnRow}>
                  <TouchableOpacity style={[styles.locBtn, { flex: 1, marginRight: 6 }]} onPress={() => setCurrentLocationFor('pickup')}>
                    <Text style={styles.locBtnText}>📍 Here as pickup</Text>
                  </TouchableOpacity>
                  <TouchableOpacity style={[styles.locBtn, { flex: 1 }]} onPress={() => setCurrentLocationFor('dropoff')}>
                    <Text style={styles.locBtnText}>🏁 Here as dropoff</Text>
                  </TouchableOpacity>
                </View>
              )}
            </View>
          )}

          {/* Pin mode toggle */}
          <View style={styles.pinToggle}>
            <TouchableOpacity
              style={[styles.pinBtn, pinMode === 'pickup' && styles.pinBtnActive]}
              onPress={() => setPinMode('pickup')}
            >
              <Text style={[styles.pinBtnText, pinMode === 'pickup' && styles.pinBtnTextActive]}>📍 Pickup</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[styles.pinBtn, pinMode === 'dropoff' && styles.pinBtnActive]}
              onPress={() => setPinMode('dropoff')}
            >
              <Text style={[styles.pinBtnText, pinMode === 'dropoff' && styles.pinBtnTextActive]}>🏁 Dropoff</Text>
            </TouchableOpacity>
          </View>

          {/* Address cards */}
          {pickupAddress ? (
            <View style={styles.addressRow}>
              <Text style={styles.addressLabel}>📍 PICKUP</Text>
              <Text style={styles.addressText}>{pickupAddress}</Text>
            </View>
          ) : (
            <Text style={styles.hint}>Search above or tap the map to set pickup</Text>
          )}

          {dropoffAddress ? (
            <View style={styles.addressRow}>
              <Text style={styles.addressLabel}>🏁 DROPOFF</Text>
              <Text style={styles.addressText}>{dropoffAddress}</Text>
            </View>
          ) : pickup ? (
            <Text style={styles.hint}>Now search or tap map for dropoff</Text>
          ) : null}

          {/* Pin accuracy warning — always shown when both pins set */}
          {pickup && dropoff && (
            <View style={styles.accuracyWarning}>
              <Text style={styles.accuracyIcon}>⚠️</Text>
              <Text style={styles.accuracyText}>
                Drivers navigate exactly to your pins. Confirm both are at the correct entrance — not the street or parking lot. Swipe the sheet down to check.
              </Text>
            </View>
          )}

          {/* Category */}
          <Text style={styles.sectionLabel}>CATEGORY</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.catScroll}>
            {categories.map((cat: string) => (
              <TouchableOpacity
                key={cat}
                style={[styles.catChip, category === cat && styles.catChipActive]}
                onPress={() => setCategory(cat)}
              >
                <Text style={[styles.catText, category === cat && styles.catTextActive]}>{cat}</Text>
              </TouchableOpacity>
            ))}
          </ScrollView>

          {/* Notes */}
          <Text style={styles.sectionLabel}>DELIVERY NOTES (OPTIONAL)</Text>
          <TextInput
            style={styles.notesInput}
            placeholder="Gate code, entrance instructions, call on arrival..."
            placeholderTextColor="#4a7a7a"
            value={notes}
            onChangeText={setNotes}
            multiline
            numberOfLines={2}
          />

          {/* Zone summary */}
          {zoneLoading && (
            <View style={styles.zoneRow}>
              <ActivityIndicator color="#f5a623" />
              <Text style={[styles.zoneDetail, { marginLeft: 10 }]}>Calculating route...</Text>
            </View>
          )}

          {zoneError && (
            <View style={[styles.zoneRow, styles.zoneRowError]}>
              <Text style={styles.zoneErrorText}>{zoneError}</Text>
            </View>
          )}

          {delivery && !zoneLoading && (
            <View style={styles.zoneRow}>
              <View>
                <Text style={styles.zoneName}>
                  Zone {delivery.zone}  ·  {delivery.distance_miles.toFixed(1)} mi  ·  ~{delivery.estimated_duration_minutes || 0} min
                </Text>
                <Text style={styles.zoneDetail}>Driver earns ${delivery.driver_payout.toFixed(2)}</Text>
              </View>
              <Text style={styles.zonePrice}>${delivery.customer_total.toFixed(2)}</Text>
            </View>
          )}

          <TouchableOpacity
            style={[
              styles.requestBtn,
              (!pickup || !dropoff || !delivery || submitting || zoneLoading) && styles.requestBtnDisabled,
            ]}
            onPress={handleRequest}
            disabled={!pickup || !dropoff || !delivery || submitting || zoneLoading}
          >
            {submitting
              ? <ActivityIndicator color="#f5f5f5" />
              : <Text style={styles.requestBtnText}>Request Delivery</Text>
            }
          </TouchableOpacity>

        </BottomSheetScrollView>
      </BottomSheet>

    </View>
  );
}

const styles = StyleSheet.create({
  container:           { flex: 1, backgroundColor: '#0a1a1a' },

  searchOverlay:       { position: 'absolute', top: 52, left: 0, right: 0, zIndex: 10, padding: 12 },
  searchBar:           { flexDirection: 'row', alignItems: 'center', backgroundColor: '#0a1a1a', borderRadius: 10, paddingHorizontal: 12, paddingVertical: 10, borderWidth: 1, borderColor: '#1a6b6b', shadowColor: '#000', shadowOpacity: 0.4, shadowRadius: 8, shadowOffset: { width: 0, height: 2 } },
  searchMode:          { fontSize: 16, marginRight: 8 },
  searchInput:         { flex: 1, color: '#f5f5f5', fontSize: 14 },
  searchClear:         { color: '#4a7a7a', fontSize: 16, paddingLeft: 8 },
  searchResults:       { backgroundColor: '#0e2222', borderRadius: 10, marginTop: 6, borderWidth: 1, borderColor: '#1a6b6b', overflow: 'hidden', maxHeight: 280 },
  searchResultRow:     { flexDirection: 'row', alignItems: 'center', padding: 12, borderBottomWidth: 1, borderBottomColor: '#122828' },
  searchResultIcon:    { fontSize: 18, marginRight: 10 },
  searchResultText:    { flex: 1 },
  searchResultName:    { color: '#f5f5f5', fontSize: 14, fontWeight: '600' },
  searchResultAddress: { color: '#7a9e9e', fontSize: 12, marginTop: 2 },

  sheetBg:             { backgroundColor: '#0a1a1a', borderTopLeftRadius: 16, borderTopRightRadius: 16 },
  sheetHandle:         { backgroundColor: '#1a6b6b', width: 40 },
  sheetContent:        { padding: 20, paddingBottom: 60 },

  locBtnRow:           { flexDirection: 'row', marginBottom: 14 },
  locBtn:              { backgroundColor: '#122828', borderRadius: 8, padding: 11, alignItems: 'center', borderWidth: 1, borderColor: '#1a6b6b' },
  locBtnText:          { color: '#f5a623', fontSize: 12, fontWeight: '600' },

  pinToggle:           { flexDirection: 'row', gap: 10, marginBottom: 14 },
  pinBtn:              { flex: 1, paddingVertical: 12, alignItems: 'center', backgroundColor: '#122828', borderRadius: 8, borderWidth: 1, borderColor: '#1a3a3a' },
  pinBtnActive:        { backgroundColor: '#1a6b6b', borderColor: '#1a6b6b' },
  pinBtnText:          { color: '#7a9e9e', fontSize: 13, fontWeight: '600' },
  pinBtnTextActive:    { color: '#f5f5f5' },

  addressRow:          { backgroundColor: '#122828', borderRadius: 8, padding: 12, marginBottom: 10, borderLeftWidth: 3, borderLeftColor: '#1a6b6b' },
  addressLabel:        { fontSize: 10, color: '#7a9e9e', letterSpacing: 1, marginBottom: 4 },
  addressText:         { color: '#f5f5f5', fontSize: 13, lineHeight: 18 },

  hint:                { color: '#4a7a7a', fontSize: 12, textAlign: 'center', marginBottom: 12 },

  accuracyWarning:     { flexDirection: 'row', backgroundColor: '#1a1400', borderRadius: 8, padding: 12, marginBottom: 16, borderWidth: 1, borderColor: '#5a4a00', alignItems: 'flex-start' },
  accuracyIcon:        { fontSize: 16, marginRight: 10, marginTop: 1 },
  accuracyText:        { flex: 1, color: '#c8a800', fontSize: 12, lineHeight: 18 },

  sectionLabel:        { fontSize: 11, color: '#7a9e9e', letterSpacing: 2, marginBottom: 10 },
  catScroll:           { marginBottom: 16 },
  catChip:             { paddingVertical: 8, paddingHorizontal: 14, backgroundColor: '#122828', borderRadius: 20, marginRight: 8, borderWidth: 1, borderColor: '#1a6b6b' },
  catChipActive:       { backgroundColor: '#1a6b6b' },
  catText:             { color: '#7a9e9e', fontSize: 13, fontWeight: '600' },
  catTextActive:       { color: '#f5f5f5' },

  notesInput:          { backgroundColor: '#122828', borderRadius: 8, padding: 14, color: '#f5f5f5', fontSize: 14, borderWidth: 1, borderColor: '#1a3a3a', marginBottom: 16, minHeight: 70, textAlignVertical: 'top' },

  zoneRow:             { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', backgroundColor: '#122828', borderRadius: 8, padding: 14, marginBottom: 14 },
  zoneRowError:        { backgroundColor: '#2a1010', borderWidth: 1, borderColor: '#6b1a1a' },
  zoneErrorText:       { color: '#e05555', fontSize: 13 },
  zoneName:            { color: '#f5f5f5', fontSize: 14, fontWeight: '600' },
  zoneDetail:          { color: '#7a9e9e', fontSize: 12, marginTop: 2 },
  zonePrice:           { color: '#f5a623', fontSize: 28, fontWeight: '700' },

  requestBtn:          { backgroundColor: '#1a6b6b', paddingVertical: 16, borderRadius: 8, alignItems: 'center' },
  requestBtnDisabled:  { opacity: 0.4 },
  requestBtnText:      { color: '#f5f5f5', fontSize: 16, fontWeight: '700' },
});