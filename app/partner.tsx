import { useState } from 'react';
import {
  View, Text, TextInput, TouchableOpacity, StyleSheet,
  ScrollView, Alert, ActivityIndicator, KeyboardAvoidingView, Platform,
} from 'react-native';
import { supabase } from '../lib/supabase';

export default function PartnerScreen() {
  const [businessName, setBusinessName] = useState('');
  const [contactName,  setContactName]  = useState('');
  const [email,        setEmail]        = useState('');
  const [phone,        setPhone]        = useState('');
  const [notes,        setNotes]        = useState('');
  const [submitting,   setSubmitting]   = useState(false);
  const [submitted,    setSubmitted]    = useState(false);

  async function handleSubmit() {
    if (!businessName.trim() || !contactName.trim() || !email.trim() || !phone.trim()) {
      Alert.alert('Missing info', 'Please fill in business name, your name, email, and phone.');
      return;
    }

    setSubmitting(true);
    const { error } = await supabase.from('partner_applications').insert({
      business_name: businessName.trim(),
      contact_name:  contactName.trim(),
      contact_email: email.trim(),
      contact_phone: phone.trim(),
      address:       'TBD — to be confirmed with merchant',
      notes:         notes.trim() || null,
      status:        'pending',
    });

    setSubmitting(false);
    if (error) { Alert.alert('Error', error.message); return; }
    setSubmitted(true);
  }

  if (submitted) {
    return (
      <View style={styles.confirmContainer}>
        <Text style={styles.confirmIcon}>🤝</Text>
        <Text style={styles.confirmTitle}>Thanks for reaching out!</Text>
        <Text style={styles.confirmBody}>
          We&apos;ll be in touch within a day or two to set up your free pilot listing —
          no commitment, no fees, no contracts.{'\n\n'}
          As a founding merchant, you&apos;ll never pay an onboarding fee, even after the pilot ends.
        </Text>
      </View>
    );
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={styles.scroll} contentContainerStyle={styles.container}>

        <Text style={styles.label}>RESTAURANT PARTNERS</Text>
        <Text style={styles.title}>Join the pilot. Free, forever.</Text>
        <Text style={styles.subtitle}>
          CommonGoods is launching in St. Augustine with a small group of founding merchants.
          We&apos;re handling setup ourselves — photos, menu, pickup instructions — at no cost to you.
        </Text>

        <View style={styles.pilotBox}>
          <Text style={styles.pilotHeading}>FOUNDING MERCHANT BENEFITS</Text>
          <Text style={styles.pilotItem}>✓ Free during the entire pilot period</Text>
          <Text style={styles.pilotItem}>✓ Never pay an onboarding fee — permanently</Text>
          <Text style={styles.pilotItem}>✓ No commission on sales, ever</Text>
          <Text style={styles.pilotItem}>✓ We handle photos, menu entry, and setup for you</Text>
        </View>

        <View style={styles.benefitsSection}>
          {[
            { title: 'No Commission', body: 'Flat delivery fee only. We never take a cut of your sale.' },
            { title: 'Your POS System', body: 'Drivers place orders through your existing setup — no integration needed.' },
            { title: 'Local Drivers', body: 'St. Augustine-based cooperative. People who know your neighborhood.' },
            { title: 'Transparent Fees', body: '75% to the driver. 25% to platform ops. Published, not hidden.' },
          ].map((b) => (
            <View key={b.title} style={styles.benefitCard}>
              <Text style={styles.benefitTitle}>{b.title}</Text>
              <Text style={styles.benefitBody}>{b.body}</Text>
            </View>
          ))}
        </View>

        <Text style={styles.sectionLabel}>INTERESTED? LET&apos;S TALK</Text>

        <TextInput
          style={styles.input}
          placeholder="Business name"
          placeholderTextColor="#4a7a7a"
          value={businessName}
          onChangeText={setBusinessName}
        />
        <TextInput
          style={styles.input}
          placeholder="Your name"
          placeholderTextColor="#4a7a7a"
          value={contactName}
          onChangeText={setContactName}
        />
        <TextInput
          style={styles.input}
          placeholder="Email"
          placeholderTextColor="#4a7a7a"
          keyboardType="email-address"
          autoCapitalize="none"
          value={email}
          onChangeText={setEmail}
        />
        <TextInput
          style={styles.input}
          placeholder="Phone"
          placeholderTextColor="#4a7a7a"
          keyboardType="phone-pad"
          value={phone}
          onChangeText={setPhone}
        />
        <TextInput
          style={[styles.input, styles.notesInput]}
          placeholder="Anything we should know? (optional)"
          placeholderTextColor="#4a7a7a"
          multiline
          numberOfLines={3}
          value={notes}
          onChangeText={setNotes}
        />

        <TouchableOpacity
          style={[styles.primaryButton, submitting && { opacity: 0.6 }]}
          onPress={handleSubmit}
          disabled={submitting}
        >
          {submitting
            ? <ActivityIndicator color="#f5f5f5" />
            : <Text style={styles.primaryButtonText}>Request a Call</Text>
          }
        </TouchableOpacity>

        <Text style={styles.fine}>
          Florida SB 676 compliant. Restaurant Partner Operating Agreement provided before launch.
        </Text>

      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  scroll:            { backgroundColor: '#0a1a1a' },
  container:         { padding: 24, paddingTop: 40, paddingBottom: 60 },
  label:             { fontSize: 11, color: '#f5a623', letterSpacing: 2, marginBottom: 8 },
  title:             { fontSize: 28, fontWeight: '700', color: '#f5f5f5', marginBottom: 12 },
  subtitle:          { fontSize: 15, color: '#7a9e9e', lineHeight: 22, marginBottom: 24 },

  pilotBox:          { backgroundColor: '#0f2818', borderRadius: 10, padding: 18, marginBottom: 32, borderWidth: 1, borderColor: '#1a6b3a' },
  pilotHeading:      { fontSize: 11, color: '#4ade80', letterSpacing: 2, marginBottom: 12, fontWeight: '700' },
  pilotItem:         { color: '#d5ede0', fontSize: 14, marginBottom: 8, lineHeight: 20 },

  benefitsSection:   { marginBottom: 32 },
  benefitCard:       { backgroundColor: '#122828', borderRadius: 8, padding: 16, marginBottom: 10 },
  benefitTitle:      { color: '#f5a623', fontSize: 14, fontWeight: '700', marginBottom: 6 },
  benefitBody:       { color: '#7a9e9e', fontSize: 13, lineHeight: 20 },

  sectionLabel:      { fontSize: 11, color: '#7a9e9e', letterSpacing: 2, marginBottom: 14 },
  input:             { backgroundColor: '#122828', borderRadius: 8, padding: 16, color: '#f5f5f5', fontSize: 15, marginBottom: 12, borderWidth: 1, borderColor: '#1a6b6b' },
  notesInput:        { minHeight: 80, textAlignVertical: 'top' },

  primaryButton:     { backgroundColor: '#1a6b6b', paddingVertical: 18, borderRadius: 8, alignItems: 'center', marginTop: 8, marginBottom: 20 },
  primaryButtonText: { color: '#f5f5f5', fontSize: 16, fontWeight: '700' },
  fine:              { color: '#4a7a7a', fontSize: 11, textAlign: 'center', lineHeight: 18 },

  confirmContainer:  { flex: 1, backgroundColor: '#0a1a1a', alignItems: 'center', justifyContent: 'center', padding: 32 },
  confirmIcon:       { fontSize: 56, marginBottom: 24 },
  confirmTitle:      { color: '#f5f5f5', fontSize: 22, fontWeight: '700', marginBottom: 16, textAlign: 'center' },
  confirmBody:       { color: '#7a9e9e', fontSize: 14, textAlign: 'center', lineHeight: 24 },
});