import { useState, useEffect, useRef } from 'react';
import {
  View, Text, TextInput, TouchableOpacity, StyleSheet,
  ScrollView, Alert, ActivityIndicator, Image, KeyboardAvoidingView, Platform,
} from 'react-native';
import MapView, { Marker } from 'react-native-maps';
import * as ImagePicker from 'expo-image-picker';
import { router } from 'expo-router';
import { supabase } from '../lib/supabase';
import { uploadPhoto } from '../lib/storage';

const MAPBOX_TOKEN = process.env.EXPO_PUBLIC_MAPBOX_TOKEN!;

type LatLng = { latitude: number; longitude: number };

interface SearchResult {
  id: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
}

const ST_AUGUSTINE = {
  latitude: 29.8943,
  longitude: -81.3145,
  latitudeDelta: 0.12,
  longitudeDelta: 0.12,
};

const POS_OPTIONS = ['Square', 'Toast', 'Clover', 'Other / None'];

async function searchBusiness(query: string): Promise<SearchResult[]> {
  const url = `https://api.mapbox.com/geocoding/v5/mapbox.places/${encodeURIComponent(query)}.json`
    + `?types=poi,address&country=US&bbox=-81.7,29.5,-80.9,30.3&fuzzyMatch=true&limit=6&access_token=${MAPBOX_TOKEN}`;
  const res = await fetch(url);
  const data = await res.json();
  if (!data.features) return [];
  return data.features.map((f: any) => ({
    id: f.id,
    name: f.place_type.includes('poi') ? f.text : f.place_name.split(',')[0],
    address: f.place_name,
    latitude: f.center[1],
    longitude: f.center[0],
  }));
}

export default function AdminScreen() {
  const [authorized, setAuthorized] = useState<boolean | null>(null);

  // Restaurant form state
  const [businessName, setBusinessName] = useState('');
  const [address,      setAddress]      = useState('');
  const [pin,          setPin]          = useState<LatLng | null>(null);
  const [pickupNotes,  setPickupNotes]  = useState('');
  const [posSystem,    setPosSystem]    = useState('Square');
  const [entrancePhoto,setEntrancePhoto]= useState<string | null>(null);
  const [savingPartner,setSavingPartner]= useState(false);
  const [savedPartnerId, setSavedPartnerId] = useState<string | null>(null);

  // Search
  const [searchQuery,  setSearchQuery]  = useState('');
  const [searchResults,setSearchResults]= useState<SearchResult[]>([]);
  const [searching,    setSearching]    = useState(false);
  const searchTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const mapRef = useRef<MapView>(null);

  // Menu item form
  const [itemName,     setItemName]     = useState('');
  const [itemPrice,    setItemPrice]    = useState('');
  const [itemCategory, setItemCategory] = useState('');
  const [itemPhoto,    setItemPhoto]    = useState<string | null>(null);
  const [savingItem,   setSavingItem]   = useState(false);
  const [menuItems,    setMenuItems]    = useState<any[]>([]);

  useEffect(() => {
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { setAuthorized(false); return; }
      // is_admin lives in profiles, not on the session — and that column is
      // only ever flipped to true by us directly in the DB, never by the
      // client, so this can't be spoofed by editing local state or the
      // session's email.
      const { data: prof } = await supabase
        .from('profiles')
        .select('is_admin')
        .eq('id', user.id)
        .single();
      setAuthorized(prof?.is_admin === true);
    })();
  }, []);

  function handleSearchChange(text: string) {
    setSearchQuery(text);
    if (searchTimer.current) clearTimeout(searchTimer.current);
    if (!text.trim()) { setSearchResults([]); return; }
    searchTimer.current = setTimeout(async () => {
      setSearching(true);
      const results = await searchBusiness(text);
      setSearchResults(results);
      setSearching(false);
    }, 350);
  }

  function selectResult(r: SearchResult) {
    setBusinessName(r.name);
    setAddress(r.address);
    setPin({ latitude: r.latitude, longitude: r.longitude });
    mapRef.current?.animateToRegion({ latitude: r.latitude, longitude: r.longitude, latitudeDelta: 0.01, longitudeDelta: 0.01 }, 400);
    setSearchQuery('');
    setSearchResults([]);
  }

  function handleMapPress(e: any) {
    setPin(e.nativeEvent.coordinate);
  }

  
  async function pickEntrancePhoto() {
    const { status } = await ImagePicker.requestCameraPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Camera access needed', 'Enable camera access in Settings to add photos.');
      return;
    }
    const result = await ImagePicker.launchCameraAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      quality: 0.7,
    });
    if (!result.canceled) setEntrancePhoto(result.assets[0].uri);
  }

  async function pickItemPhoto() {
    const { status } = await ImagePicker.requestCameraPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Camera access needed', 'Enable camera access in Settings to add photos.');
      return;
   }
    const result = await ImagePicker.launchCameraAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      quality: 0.7,
    });
    if (!result.canceled) setItemPhoto(result.assets[0].uri);
  }

  async function saveRestaurant() {
    if (!businessName.trim() || !pin) {
      Alert.alert('Missing info', 'Business name and pin location are required.');
      return;
    }
    setSavingPartner(true);

    let photoUrl: string | null = null;
    if (entrancePhoto) {
      photoUrl = await uploadPhoto(entrancePhoto, 'entrances', businessName.replace(/\s+/g, '-').toLowerCase());
    }

    const { data: { user } } = await supabase.auth.getUser();

    const { data, error } = await supabase.from('partners').insert({
      profile_id: user?.id,
      business_name: businessName.trim(),
      address: address.trim() || `${pin.latitude.toFixed(5)}, ${pin.longitude.toFixed(5)}`,
      lat: pin.latitude,
      lng: pin.longitude,
      pickup_notes: pickupNotes.trim() + (photoUrl ? `\n\nEntrance photo: ${photoUrl}` : ''),
      pos_system: posSystem,
      approved: true,
      founding_merchant: true,
      joined_during_pilot: true,
      onboarding_fee_paid: false,
    }).select().single();

    setSavingPartner(false);

    if (error) { Alert.alert('Error', error.message); return; }

    setSavedPartnerId(data.id);
    Alert.alert('✅ Restaurant Added', `${businessName} is now live as a founding merchant. Add menu items below.`);
  }

  async function saveMenuItem() {
    if (!savedPartnerId) {
      Alert.alert('Save restaurant first', 'You need to save the restaurant before adding menu items.');
      return;
    }
    if (!itemName.trim() || !itemPrice.trim()) {
      Alert.alert('Missing info', 'Item name and price are required.');
      return;
    }

    setSavingItem(true);

    let photoUrl: string | null = null;
    if (itemPhoto) {
      photoUrl = await uploadPhoto(itemPhoto, `menu/${savedPartnerId}`, itemName.replace(/\s+/g, '-').toLowerCase());
    }

    const { data, error } = await supabase.from('menu_items').insert({
      partner_id: savedPartnerId,
      name: itemName.trim(),
      price: parseFloat(itemPrice),
      category: itemCategory.trim() || 'General',
      photo_url: photoUrl,
      active: true,
    }).select().single();

    setSavingItem(false);

    if (error) { Alert.alert('Error', error.message); return; }

    setMenuItems([...menuItems, data]);
    setItemName(''); setItemPrice(''); setItemCategory(''); setItemPhoto(null);
  }

  function resetForNewRestaurant() {
    setBusinessName(''); setAddress(''); setPin(null);
    setPickupNotes(''); setEntrancePhoto(null);
    setSavedPartnerId(null); setMenuItems([]);
  }

  // ---- Render states ----

  if (authorized === null) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color="#f5a623" size="large" />
      </View>
    );
  }

  if (authorized === false) {
    return (
      <View style={styles.center}>
        <Text style={styles.deniedText}>Not authorized.</Text>
        <TouchableOpacity onPress={() => router.replace('/')}>
          <Text style={styles.deniedLink}>Go home</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={styles.scroll} contentContainerStyle={styles.container}>

        <Text style={styles.label}>ADMIN — RESTAURANT ONBOARDING</Text>
        {savedPartnerId && (
          <TouchableOpacity onPress={resetForNewRestaurant} style={styles.newBtn}>
            <Text style={styles.newBtnText}>+ Add Another Restaurant</Text>
          </TouchableOpacity>
        )}

        {!savedPartnerId && (
          <>
            <Text style={styles.sectionTitle}>1. Find the business</Text>
            <TextInput
              style={styles.input}
              placeholder="Search business name..."
              placeholderTextColor="#4a7a7a"
              value={searchQuery}
              onChangeText={handleSearchChange}
            />
            {searching && <ActivityIndicator color="#f5a623" style={{ marginVertical: 8 }} />}
            {searchResults.map((r) => (
              <TouchableOpacity key={r.id} style={styles.searchResult} onPress={() => selectResult(r)}>
                <Text style={styles.searchResultName}>{r.name}</Text>
                <Text style={styles.searchResultAddr}>{r.address}</Text>
              </TouchableOpacity>
            ))}

            <Text style={styles.sectionTitle}>2. Confirm pickup pin</Text>
            <Text style={styles.hint}>Tap the exact togo pickup entrance, not the front door if different.</Text>
            <MapView
              ref={mapRef}
              style={styles.map}
              initialRegion={ST_AUGUSTINE}
              onPress={handleMapPress}
            >
              {pin && <Marker coordinate={pin} pinColor="#f5a623" />}
            </MapView>

            <Text style={styles.sectionTitle}>3. Business details</Text>
            <TextInput
              style={styles.input}
              placeholder="Business name"
              placeholderTextColor="#4a7a7a"
              value={businessName}
              onChangeText={setBusinessName}
            />
            <TextInput
              style={styles.input}
              placeholder="Address"
              placeholderTextColor="#4a7a7a"
              value={address}
              onChangeText={setAddress}
            />

            <Text style={styles.subLabel}>POS SYSTEM</Text>
            <View style={styles.posRow}>
              {POS_OPTIONS.map((p) => (
                <TouchableOpacity
                  key={p}
                  style={[styles.posChip, posSystem === p && styles.posChipActive]}
                  onPress={() => setPosSystem(p)}
                >
                  <Text style={[styles.posChipText, posSystem === p && styles.posChipTextActive]}>{p}</Text>
                </TouchableOpacity>
              ))}
            </View>

            <TextInput
              style={[styles.input, styles.notesInput]}
              placeholder="Pickup instructions for drivers (door, gate code, parking)"
              placeholderTextColor="#4a7a7a"
              multiline
              value={pickupNotes}
              onChangeText={setPickupNotes}
            />

            <TouchableOpacity style={styles.photoBtn} onPress={pickEntrancePhoto}>
              {entrancePhoto
                ? <Image source={{ uri: entrancePhoto }} style={styles.photoPreview} />
                : <Text style={styles.photoBtnText}>📷 Photograph entrance/pickup spot</Text>
              }
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.primaryButton, savingPartner && { opacity: 0.6 }]}
              onPress={saveRestaurant}
              disabled={savingPartner}
            >
              {savingPartner
                ? <ActivityIndicator color="#f5f5f5" />
                : <Text style={styles.primaryButtonText}>Save Restaurant — Founding Merchant</Text>
              }
            </TouchableOpacity>
          </>
        )}

        {savedPartnerId && (
          <>
            <Text style={styles.savedBanner}>✅ {businessName} — saved as founding merchant</Text>

            <Text style={styles.sectionTitle}>Add menu items</Text>
            <TextInput
              style={styles.input}
              placeholder="Item name"
              placeholderTextColor="#4a7a7a"
              value={itemName}
              onChangeText={setItemName}
            />
            <TextInput
              style={styles.input}
              placeholder="Price (e.g. 12.99)"
              placeholderTextColor="#4a7a7a"
              keyboardType="decimal-pad"
              value={itemPrice}
              onChangeText={setItemPrice}
            />
            <TextInput
              style={styles.input}
              placeholder="Category (e.g. Entrees, Sides, Drinks)"
              placeholderTextColor="#4a7a7a"
              value={itemCategory}
              onChangeText={setItemCategory}
            />
            <TouchableOpacity style={styles.photoBtn} onPress={pickItemPhoto}>
              {itemPhoto
                ? <Image source={{ uri: itemPhoto }} style={styles.photoPreview} />
                : <Text style={styles.photoBtnText}>📷 Photograph item</Text>
              }
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.secondaryButton, savingItem && { opacity: 0.6 }]}
              onPress={saveMenuItem}
              disabled={savingItem}
            >
              {savingItem
                ? <ActivityIndicator color="#f5f5f5" />
                : <Text style={styles.secondaryButtonText}>+ Add Menu Item</Text>
              }
            </TouchableOpacity>

            {menuItems.length > 0 && (
              <View style={styles.itemList}>
                <Text style={styles.subLabel}>ADDED ({menuItems.length})</Text>
                {menuItems.map((item) => (
                  <View key={item.id} style={styles.itemRow}>
                    <Text style={styles.itemRowName}>{item.name}</Text>
                    <Text style={styles.itemRowPrice}>${item.price.toFixed(2)}</Text>
                  </View>
                ))}
              </View>
            )}
          </>
        )}

      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  scroll:             { backgroundColor: '#0a1a1a' },
  container:          { padding: 20, paddingTop: 50, paddingBottom: 60 },
  center:             { flex: 1, backgroundColor: '#0a1a1a', alignItems: 'center', justifyContent: 'center' },
  deniedText:         { color: '#e05555', fontSize: 16, marginBottom: 12 },
  deniedLink:         { color: '#7a9e9e', fontSize: 14 },

  label:              { fontSize: 11, color: '#f5a623', letterSpacing: 2, marginBottom: 20 },
  sectionTitle:       { fontSize: 16, color: '#f5f5f5', fontWeight: '700', marginTop: 20, marginBottom: 10 },
  subLabel:           { fontSize: 11, color: '#7a9e9e', letterSpacing: 1, marginBottom: 8, marginTop: 4 },
  hint:               { color: '#4a7a7a', fontSize: 12, marginBottom: 10 },

  input:              { backgroundColor: '#122828', borderRadius: 8, padding: 14, color: '#f5f5f5', fontSize: 14, marginBottom: 10, borderWidth: 1, borderColor: '#1a6b6b' },
  notesInput:         { minHeight: 70, textAlignVertical: 'top' },

  searchResult:       { backgroundColor: '#122828', borderRadius: 8, padding: 12, marginBottom: 8, borderWidth: 1, borderColor: '#1a3a3a' },
  searchResultName:   { color: '#f5f5f5', fontSize: 14, fontWeight: '600' },
  searchResultAddr:   { color: '#7a9e9e', fontSize: 12, marginTop: 2 },

  map:                { height: 220, borderRadius: 8, marginBottom: 10 },

  posRow:             { flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginBottom: 14 },
  posChip:            { paddingVertical: 8, paddingHorizontal: 14, backgroundColor: '#122828', borderRadius: 20, borderWidth: 1, borderColor: '#1a6b6b' },
  posChipActive:      { backgroundColor: '#1a6b6b' },
  posChipText:        { color: '#7a9e9e', fontSize: 13, fontWeight: '600' },
  posChipTextActive:  { color: '#f5f5f5' },

  photoBtn:           { backgroundColor: '#122828', borderRadius: 8, padding: 14, alignItems: 'center', marginBottom: 14, borderWidth: 1, borderColor: '#1a6b6b', borderStyle: 'dashed' },
  photoBtnText:       { color: '#f5a623', fontSize: 13, fontWeight: '600' },
  photoPreview:        { width: '100%', height: 160, borderRadius: 6 },

  primaryButton:      { backgroundColor: '#1a6b6b', paddingVertical: 16, borderRadius: 8, alignItems: 'center', marginTop: 8 },
  primaryButtonText:  { color: '#f5f5f5', fontSize: 15, fontWeight: '700' },

  secondaryButton:    { backgroundColor: '#0f2818', paddingVertical: 14, borderRadius: 8, alignItems: 'center', marginTop: 8, borderWidth: 1, borderColor: '#1a6b3a' },
  secondaryButtonText:{ color: '#4ade80', fontSize: 14, fontWeight: '700' },

  savedBanner:        { backgroundColor: '#0f2818', color: '#4ade80', padding: 12, borderRadius: 8, fontSize: 13, fontWeight: '600', marginBottom: 10, borderWidth: 1, borderColor: '#1a6b3a' },

  newBtn:             { marginBottom: 16 },
  newBtnText:         { color: '#f5a623', fontSize: 13, fontWeight: '600' },

  itemList:           { marginTop: 16 },
  itemRow:            { flexDirection: 'row', justifyContent: 'space-between', backgroundColor: '#122828', padding: 12, borderRadius: 8, marginBottom: 6 },
  itemRowName:        { color: '#f5f5f5', fontSize: 14 },
  itemRowPrice:       { color: '#f5a623', fontSize: 14, fontWeight: '700' },
});