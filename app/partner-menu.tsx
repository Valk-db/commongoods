import { useState, useEffect, useCallback } from 'react';
import {
  View, Text, TextInput, TouchableOpacity, StyleSheet,
  ScrollView, Alert, ActivityIndicator, Image,
  KeyboardAvoidingView, Platform,
} from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import { router } from 'expo-router';
import { supabase } from '../lib/supabase';
import { uploadPhoto } from '../lib/storage';

interface MenuItem {
  id: string;
  partner_id: string | null;
  name: string;
  description: string | null;
  price: number;
  category: string | null;
  photo_url: string | null;
  active: boolean | null;
  created_at: string | null;
}

export default function PartnerMenuScreen() {
  const [partnerId, setPartnerId] = useState<string | null | undefined>(undefined);
  const [items,     setItems]     = useState<MenuItem[]>([]);
  const [loading,   setLoading]   = useState(true);

  const [editingId,        setEditingId]        = useState<string | null>(null);
  const [name,              setName]            = useState('');
  const [price,             setPrice]           = useState('');
  const [category,          setCategory]        = useState('');
  const [photoUri,          setPhotoUri]        = useState<string | null>(null);
  const [existingPhotoUrl,  setExistingPhotoUrl] = useState<string | null>(null);
  const [saving,            setSaving]          = useState(false);

  const fetchItems = useCallback(async (pid: string) => {
    const { data } = await supabase
      .from('menu_items')
      .select('*')
      .eq('partner_id', pid)
      .order('category', { ascending: true })
      .order('name', { ascending: true });
    setItems(data ?? []);
    setLoading(false);
  }, []);

  useEffect(() => {
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;
      const { data: partner } = await supabase
        .from('partners')
        .select('id')
        .eq('profile_id', user.id)
        .maybeSingle();
      setPartnerId(partner?.id ?? null);
      if (partner?.id) fetchItems(partner.id);
      else setLoading(false);
    })();
  }, [fetchItems]);

  function resetForm() {
    setEditingId(null);
    setName(''); setPrice(''); setCategory('');
    setPhotoUri(null); setExistingPhotoUrl(null);
  }

  function startEdit(item: MenuItem) {
    setEditingId(item.id);
    setName(item.name);
    setPrice(String(item.price));
    setCategory(item.category ?? '');
    setExistingPhotoUrl(item.photo_url);
    setPhotoUri(null);
  }

  function choosePhoto() {
    Alert.alert('Item photo', undefined, [
      { text: 'Take Photo', onPress: takePhoto },
      { text: 'Choose from Library', onPress: pickFromLibrary },
      { text: 'Cancel', style: 'cancel' },
    ]);
  }

  async function takePhoto() {
    const { status } = await ImagePicker.requestCameraPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Camera access needed', 'Enable camera access in Settings to add photos.');
      return;
    }
    const result = await ImagePicker.launchCameraAsync({ mediaTypes: ImagePicker.MediaTypeOptions.Images, quality: 0.7 });
    if (!result.canceled) setPhotoUri(result.assets[0].uri);
  }

  async function pickFromLibrary() {
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Photo access needed', 'Enable photo library access in Settings to add photos.');
      return;
    }
    const result = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ImagePicker.MediaTypeOptions.Images, quality: 0.7 });
    if (!result.canceled) setPhotoUri(result.assets[0].uri);
  }

  async function handleSave() {
    if (!partnerId) return;
    if (!name.trim() || !price.trim()) {
      Alert.alert('Missing info', 'Item name and price are required.');
      return;
    }
    const parsedPrice = parseFloat(price);
    if (isNaN(parsedPrice) || parsedPrice < 0) {
      Alert.alert('Invalid price', 'Enter a valid price.');
      return;
    }

    setSaving(true);

    let photoUrl = existingPhotoUrl;
    if (photoUri) {
      photoUrl = await uploadPhoto(photoUri, `menu/${partnerId}`, name.replace(/\s+/g, '-').toLowerCase());
    }

    if (editingId) {
      const { error } = await supabase
        .from('menu_items')
        .update({ name: name.trim(), price: parsedPrice, category: category.trim() || 'General', photo_url: photoUrl })
        .eq('id', editingId);
      setSaving(false);
      if (error) { Alert.alert('Error', error.message); return; }
    } else {
      const { error } = await supabase.from('menu_items').insert({
        partner_id: partnerId,
        name: name.trim(),
        price: parsedPrice,
        category: category.trim() || 'General',
        photo_url: photoUrl,
        active: true,
      });
      setSaving(false);
      if (error) { Alert.alert('Error', error.message); return; }
    }

    resetForm();
    fetchItems(partnerId);
  }

  async function toggleActive(item: MenuItem) {
    const { error } = await supabase.from('menu_items').update({ active: !item.active }).eq('id', item.id);
    if (error) { Alert.alert('Error', error.message); return; }
    if (partnerId) fetchItems(partnerId);
  }

  if (partnerId === undefined || loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator color="#f5a623" size="large" />
      </View>
    );
  }

  if (partnerId === null) {
    return (
      <View style={styles.centered}>
        <Text style={styles.notLinkedIcon}>🍽️</Text>
        <Text style={styles.notLinkedTitle}>Account not linked yet</Text>
        <Text style={styles.notLinkedBody}>
          We&apos;re still setting up your restaurant in CommonGoods. You&apos;ll be able to manage your menu here once it&apos;s ready.
        </Text>
        <TouchableOpacity onPress={() => router.back()}>
          <Text style={styles.backLink}>← Go back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const grouped = items.reduce<Record<string, MenuItem[]>>((acc, item) => {
    const key = item.category || 'General';
    (acc[key] ??= []).push(item);
    return acc;
  }, {});

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={styles.scroll} contentContainerStyle={styles.container}>
        <Text style={styles.label}>MENU</Text>

        <Text style={styles.sectionTitle}>{editingId ? 'Edit Item' : 'Add Item'}</Text>

        <TextInput style={styles.input} placeholder="Item name" placeholderTextColor="#4a7a7a" value={name} onChangeText={setName} />
        <TextInput style={styles.input} placeholder="Price (e.g. 12.99)" placeholderTextColor="#4a7a7a" keyboardType="decimal-pad" value={price} onChangeText={setPrice} />
        <TextInput style={styles.input} placeholder="Category (e.g. Entrees, Sides, Drinks)" placeholderTextColor="#4a7a7a" value={category} onChangeText={setCategory} />

        <TouchableOpacity style={styles.photoBtn} onPress={choosePhoto}>
          {(photoUri || existingPhotoUrl)
            ? <Image source={{ uri: photoUri ?? existingPhotoUrl! }} style={styles.photoPreview} />
            : <Text style={styles.photoBtnText}>📷 Add photo</Text>
          }
        </TouchableOpacity>

        <View style={styles.formActions}>
          {editingId && (
            <TouchableOpacity style={styles.cancelBtn} onPress={resetForm}>
              <Text style={styles.cancelBtnText}>Cancel</Text>
            </TouchableOpacity>
          )}
          <TouchableOpacity style={[styles.saveBtn, saving && { opacity: 0.6 }]} onPress={handleSave} disabled={saving}>
            {saving ? <ActivityIndicator color="#f5f5f5" /> : <Text style={styles.saveBtnText}>{editingId ? 'Save Changes' : '+ Add Item'}</Text>}
          </TouchableOpacity>
        </View>

        {Object.keys(grouped).length === 0 ? (
          <View style={styles.emptyState}>
            <Text style={styles.emptyText}>No menu items yet. Add your first one above.</Text>
          </View>
        ) : (
          Object.entries(grouped).map(([cat, catItems]) => (
            <View key={cat} style={styles.categoryGroup}>
              <Text style={styles.categoryLabel}>{cat.toUpperCase()}</Text>
              {catItems.map((item) => (
                <View key={item.id} style={styles.itemRow}>
                  {item.photo_url && <Image source={{ uri: item.photo_url }} style={styles.itemThumb} />}
                  <View style={styles.itemInfo}>
                    <Text style={[styles.itemName, !item.active && styles.itemNameInactive]}>{item.name}</Text>
                    <Text style={styles.itemPrice}>${item.price.toFixed(2)}</Text>
                  </View>
                  <TouchableOpacity onPress={() => toggleActive(item)} style={styles.statusChip}>
                    <Text style={[styles.statusChipText, item.active ? styles.statusActive : styles.statusInactive]}>
                      {item.active ? 'Active' : 'Hidden'}
                    </Text>
                  </TouchableOpacity>
                  <TouchableOpacity onPress={() => startEdit(item)} style={styles.editBtn}>
                    <Text style={styles.editBtnText}>Edit</Text>
                  </TouchableOpacity>
                </View>
              ))}
            </View>
          ))
        )}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  scroll:              { backgroundColor: '#0a1a1a' },
  container:           { padding: 20, paddingTop: 30, paddingBottom: 60 },
  centered:            { flex: 1, backgroundColor: '#0a1a1a', alignItems: 'center', justifyContent: 'center', padding: 32 },
  label:               { fontSize: 11, color: '#f5a623', letterSpacing: 2, marginBottom: 20 },

  notLinkedIcon:       { fontSize: 48, marginBottom: 20 },
  notLinkedTitle:      { color: '#f5f5f5', fontSize: 18, fontWeight: '700', marginBottom: 12, textAlign: 'center' },
  notLinkedBody:       { color: '#7a9e9e', fontSize: 14, textAlign: 'center', lineHeight: 22, marginBottom: 24 },
  backLink:            { color: '#4a7a7a', fontSize: 13 },

  sectionTitle:        { fontSize: 15, color: '#f5f5f5', fontWeight: '700', marginBottom: 12 },
  input:               { backgroundColor: '#122828', borderRadius: 8, padding: 14, color: '#f5f5f5', fontSize: 14, marginBottom: 10, borderWidth: 1, borderColor: '#1a6b6b' },

  photoBtn:            { backgroundColor: '#122828', borderRadius: 8, padding: 14, alignItems: 'center', marginBottom: 14, borderWidth: 1, borderColor: '#1a6b6b', borderStyle: 'dashed' },
  photoBtnText:        { color: '#f5a623', fontSize: 13, fontWeight: '600' },
  photoPreview:        { width: '100%', height: 140, borderRadius: 6 },

  formActions:         { flexDirection: 'row', gap: 10, marginBottom: 32 },
  saveBtn:             { flex: 1, backgroundColor: '#1a6b6b', paddingVertical: 14, borderRadius: 8, alignItems: 'center' },
  saveBtnText:         { color: '#f5f5f5', fontSize: 14, fontWeight: '700' },
  cancelBtn:           { paddingVertical: 14, paddingHorizontal: 18, borderRadius: 8, borderWidth: 1, borderColor: '#1a3a3a', alignItems: 'center' },
  cancelBtnText:       { color: '#7a9e9e', fontSize: 14, fontWeight: '600' },

  categoryGroup:       { marginBottom: 24 },
  categoryLabel:       { fontSize: 11, color: '#7a9e9e', letterSpacing: 2, marginBottom: 10 },
  itemRow:             { flexDirection: 'row', alignItems: 'center', backgroundColor: '#122828', borderRadius: 8, padding: 10, marginBottom: 8 },
  itemThumb:           { width: 44, height: 44, borderRadius: 6, marginRight: 12 },
  itemInfo:            { flex: 1 },
  itemName:            { color: '#f5f5f5', fontSize: 14, fontWeight: '600' },
  itemNameInactive:    { color: '#4a7a7a', textDecorationLine: 'line-through' },
  itemPrice:           { color: '#f5a623', fontSize: 13, marginTop: 2 },
  statusChip:          { paddingVertical: 5, paddingHorizontal: 10, borderRadius: 20, marginRight: 8 },
  statusChipText:      { fontSize: 11, fontWeight: '700' },
  statusActive:        { color: '#4ade80' },
  statusInactive:      { color: '#7a4a4a' },
  editBtn:             { paddingVertical: 6, paddingHorizontal: 12, backgroundColor: '#1a3a3a', borderRadius: 6 },
  editBtnText:         { color: '#7a9e9e', fontSize: 12, fontWeight: '600' },

  emptyState:          { alignItems: 'center', paddingVertical: 40 },
  emptyText:           { color: '#7a9e9e', fontSize: 14, textAlign: 'center' },
});