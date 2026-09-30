import { useState, useEffect, useRef } from 'react';
import {
  View, Text, TextInput, TouchableOpacity, StyleSheet,
  ScrollView, Alert, ActivityIndicator,
  KeyboardAvoidingView, Platform,
} from 'react-native';
import MapView, { Marker } from 'react-native-maps';
import { router } from 'expo-router';
import { supabase } from '../lib/supabase';

type LatLng = { latitude: number; longitude: number };

const POS_OPTIONS = ['Square', 'Toast', 'Clover', 'Other / None'];

const ST_AUGUSTINE = {
  latitude: 29.8943,
  longitude: -81.3145,
  latitudeDelta: 0.12,
  longitudeDelta: 0.12,
};

export default function PartnerSettingsScreen() {
  const [partnerId,    setPartnerId]    = useState<string | null>(null);
  const [loading,      setLoading]      = useState(true);
  const [businessName, setBusinessName] = useState('');
  const [address,      setAddress]      = useState('');
  const [pickupNotes,  setPickupNotes]  = useState('');
  const [posSystem,    setPosSystem]    = useState('Square');
  const [pin,          setPin]          = useState<LatLng | null>(null);
  const [foundingMerchant, setFoundingMerchant] = useState(false);
  const [saving,       setSaving]       = useState(false);

  const mapRef = useRef<MapView>(null);

  useEffect(() => {
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { setLoading(false); return; }

      const { data: partner } = await supabase
        .from('partners')
        .select('*')
        .eq('profile_id', user.id)
        .maybeSingle();

      if (partner) {
        setPartnerId(partner.id);
        setBusinessName(partner.business_name ?? '');
        setAddress(partner.address ?? '');
        setPickupNotes(partner.pickup_notes ?? '');
        setPosSystem(partner.pos_system ?? 'Square');
        setFoundingMerchant(!!partner.founding_merchant);
        if (partner.lat && partner.lng) setPin({ latitude: partner.lat, longitude: partner.lng });
      }
      setLoading(false);
    })();
  }, []);

  function handleMapPress(e: any) {
    setPin(e.nativeEvent.coordinate);
  }

  async function handleSave() {
    if (!partnerId) return;
    if (!businessName.trim()) {
      Alert.alert('Missing info', 'Business name is required.');
      return;
    }

    setSaving(true);
    const { error } = await supabase
      .from('partners')
      .update({
        business_name: businessName.trim(),
        address: address.trim(),
        pickup_notes: pickupNotes.trim(),
        pos_system: posSystem,
        lat: pin?.latitude,
        lng: pin?.longitude,
      })
      .eq('id', partnerId);

    setSaving(false);
    if (error) { Alert.alert('Error', error.message); return; }
    Alert.alert('✅ Saved', 'Your restaurant settings have been updated.');
  }

  if (loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator color="#f5a623" size="large" />
      </View>
    );
  }

  if (!partnerId) {
    return (
      <View style={styles.centered}>
        <Text style={styles.notLinkedIcon}>⚙️</Text>
        <Text style={styles.notLinkedTitle}>Account not linked yet</Text>
        <Text style={styles.notLinkedBody}>
          We're still setting up your restaurant in CommonGoods. Settings will be available here once it's ready.
        </Text>
        <TouchableOpacity onPress={() => router.back()}>
          <Text style={styles.backLink}>← Go back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={styles.scroll} contentContainerStyle={styles.container}>
        <Text style={styles.label}>RESTAURANT SETTINGS</Text>

        {foundingMerchant && (
          <View style={styles.foundingBadge}>
            <Text style={styles.foundingBadgeText}>★ Founding Merchant — never pays an onboarding fee</Text>
          </View>
        )}

        <Text style={styles.fieldLabel}>BUSINESS NAME</Text>
        <TextInput style={styles.input} placeholderTextColor="#4a7a7a" value={businessName} onChangeText={setBusinessName} />

        <Text style={styles.fieldLabel}>ADDRESS</Text>
        <TextInput style={styles.input} placeholderTextColor="#4a7a7a" value={address} onChangeText={setAddress} />

        <Text style={styles.fieldLabel}>POS SYSTEM</Text>
        <View style={styles.posRow}>
          {POS_OPTIONS.map((p) => (
            <TouchableOpacity key={p} style={[styles.posChip, posSystem === p && styles.posChipActive]} onPress={() => setPosSystem(p)}>
              <Text style={[styles.posChipText, posSystem === p && styles.posChipTextActive]}>{p}</Text>
            </TouchableOpacity>
          ))}
        </View>

        <Text style={styles.fieldLabel}>PICKUP INSTRUCTIONS FOR DRIVERS</Text>
        <TextInput
          style={[styles.input, styles.notesInput]}
          placeholder="Door, gate code, parking..."
          placeholderTextColor="#4a7a7a"
          multiline
          value={pickupNotes}
          onChangeText={setPickupNotes}
        />

        <Text style={styles.fieldLabel}>PICKUP PIN</Text>
        <Text style={styles.hint}>Tap the map to move your exact pickup spot.</Text>
        <MapView
          ref={mapRef}
          style={styles.map}
          initialRegion={pin ? { ...pin, latitudeDelta: 0.01, longitudeDelta: 0.01 } : ST_AUGUSTINE}
          onPress={handleMapPress}
        >
          {pin && <Marker coordinate={pin} pinColor="#f5a623" />}
        </MapView>

        <TouchableOpacity style={[styles.saveBtn, saving && { opacity: 0.6 }]} onPress={handleSave} disabled={saving}>
          {saving ? <ActivityIndicator color="#f5f5f5" /> : <Text style={styles.saveBtnText}>Save Changes</Text>}
        </TouchableOpacity>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  scroll:             { backgroundColor: '#0a1a1a' },
  container:          { padding: 20, paddingTop: 30, paddingBottom: 60 },
  centered:           { flex: 1, backgroundColor: '#0a1a1a', alignItems: 'center', justifyContent: 'center', padding: 32 },
  label:              { fontSize: 11, color: '#f5a623', letterSpacing: 2, marginBottom: 20 },

  notLinkedIcon:      { fontSize: 48, marginBottom: 20 },
  notLinkedTitle:     { color: '#f5f5f5', fontSize: 18, fontWeight: '700', marginBottom: 12, textAlign: 'center' },
  notLinkedBody:      { color: '#7a9e9e', fontSize: 14, textAlign: 'center', lineHeight: 22, marginBottom: 24 },
  backLink:           { color: '#4a7a7a', fontSize: 13 },

  foundingBadge:      { backgroundColor: '#0f2818', borderRadius: 8, padding: 12, marginBottom: 24, borderWidth: 1, borderColor: '#1a6b3a' },
  foundingBadgeText:  { color: '#4ade80', fontSize: 12, fontWeight: '700' },

  fieldLabel:         { fontSize: 11, color: '#7a9e9e', letterSpacing: 1, marginBottom: 8, marginTop: 4 },
  input:              { backgroundColor: '#122828', borderRadius: 8, padding: 14, color: '#f5f5f5', fontSize: 14, marginBottom: 16, borderWidth: 1, borderColor: '#1a6b6b' },
  notesInput:         { minHeight: 70, textAlignVertical: 'top' },

  posRow:             { flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginBottom: 16 },
  posChip:            { paddingVertical: 8, paddingHorizontal: 14, backgroundColor: '#122828', borderRadius: 20, borderWidth: 1, borderColor: '#1a6b6b' },
  posChipActive:      { backgroundColor: '#1a6b6b' },
  posChipText:        { color: '#7a9e9e', fontSize: 13, fontWeight: '600' },
  posChipTextActive:  { color: '#f5f5f5' },

  hint:               { color: '#4a7a7a', fontSize: 12, marginBottom: 10 },
  map:                { height: 200, borderRadius: 8, marginBottom: 24 },

  saveBtn:            { backgroundColor: '#1a6b6b', paddingVertical: 16, borderRadius: 8, alignItems: 'center', marginBottom: 20 },
  saveBtnText:        { color: '#f5f5f5', fontSize: 15, fontWeight: '700' },
});