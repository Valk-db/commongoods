import React, { useState } from 'react';
import {
  View, Text, TextInput, TouchableOpacity, StyleSheet,
  Alert, KeyboardAvoidingView, Platform, ScrollView,
  ActivityIndicator,
} from 'react-native';
import { useRouter } from 'expo-router';
import { supabase } from '../lib/supabase';
import { useAppMode, type AppMode } from '../lib/appMode';

type AuthTab  = 'login' | 'signup';
type SignupStep = 'code' | 'details' | 'confirmed';

export default function AuthScreen() {
  const router = useRouter();
  const { syncAvailableModes } = useAppMode();

  // Shared
  const [tab,      setTab]      = useState<AuthTab>('login');
  const [loading,  setLoading]  = useState(false);

  // Login
  const [loginEmail,    setLoginEmail]    = useState('');
  const [loginPassword, setLoginPassword] = useState('');

  // Signup
  const [signupStep, setSignupStep]   = useState<SignupStep>('code');
  const [refCode,    setRefCode]      = useState('');
  const [refRole,    setRefRole]      = useState<AppMode>('customer');
  const [refLabel,   setRefLabel]     = useState('');
  const [refId,      setRefId]        = useState('');
  const [fullName,   setFullName]     = useState('');
  const [email,      setEmail]        = useState('');
  const [password,   setPassword]     = useState('');

  // ── Login ────────────────────────────────────────────────────────────────
  async function handleLogin() {
    if (!loginEmail || !loginPassword) {
      Alert.alert('Required', 'Enter your email and password.');
      return;
    }
    setLoading(true);
    const { error } = await supabase.auth.signInWithPassword({
      email: loginEmail,
      password: loginPassword,
    });
    if (error) {
      setLoading(false);
      Alert.alert('Login failed', error.message);
      return;
    }
    await syncAvailableModes();
    setLoading(false);
    router.replace('/');
  }

  // ── Referral code validation ─────────────────────────────────────────────
  async function handleValidateCode() {
    const trimmed = refCode.trim().toUpperCase();
    if (!trimmed) { Alert.alert('Required', 'Enter a referral code.'); return; }

    setLoading(true);
    const { data, error } = await supabase
      .from('referral_codes')
      .select('id, role, label, is_active, used_by, expires_at')
      .eq('code', trimmed)
      .maybeSingle();
    setLoading(false);

    if (error || !data) {
      Alert.alert('Invalid code', 'That referral code doesn\'t exist. Check with whoever invited you.');
      return;
    }
    if (!data.is_active) {
      Alert.alert('Code inactive', 'This referral code has been deactivated.');
      return;
    }
    if (data.used_by) {
      Alert.alert('Already used', 'This referral code has already been used.');
      return;
    }
    if (data.expires_at && new Date(data.expires_at) < new Date()) {
      Alert.alert('Expired', 'This referral code has expired.');
      return;
    }

    setRefId(data.id);
    setRefRole(data.role as AppMode);
    setRefLabel(data.label ?? '');
    setRefCode(trimmed);
    setSignupStep('details');
  }

  // ── Signup ───────────────────────────────────────────────────────────────
  async function handleSignup() {
    if (!email || !password) {
      Alert.alert('Required', 'Email and password are required.');
      return;
    }
    if (password.length < 8) {
      Alert.alert('Weak password', 'Password must be at least 8 characters.');
      return;
    }

    setLoading(true);
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          full_name: fullName.trim() || null,
          role: refRole,
        },
      },
    });

    if (error) {
      setLoading(false);
      Alert.alert('Signup failed', error.message);
      return;
    }

    // Mark referral code as used
    await supabase
      .from('referral_codes')
      .update({ is_active: false })
      .eq('id', refId);

    setLoading(false);
    setSignupStep('confirmed');
  }

  // ── Confirmed screen ─────────────────────────────────────────────────────
  if (tab === 'signup' && signupStep === 'confirmed') {
    const roleLabel = refRole === 'driver' ? 'Driver' : refRole === 'partner' ? 'Restaurant Partner' : 'Customer';
    return (
      <View style={styles.centered}>
        <Text style={styles.logo}>commongood<Text style={styles.accent}>s</Text></Text>
        <Text style={styles.confirmIcon}>✉️</Text>
        <Text style={styles.confirmTitle}>Check your email</Text>
        <Text style={styles.confirmBody}>
          We sent a confirmation link to{'\n'}
          <Text style={styles.confirmEmail}>{email}</Text>
          {'\n\n'}You&apos;re joining as a <Text style={styles.confirmEmail}>{roleLabel}</Text>.
          {refRole === 'driver' && '\n\nOnce confirmed, your account will be reviewed before your first delivery.'}
          {refRole === 'partner' && '\n\nOnce confirmed, your restaurant will be set up by our team.'}
        </Text>
        <TouchableOpacity
          style={[styles.primaryButton, { marginTop: 40, width: '100%' }]}
          onPress={() => { setSignupStep('code'); setTab('login'); }}
        >
          <Text style={styles.primaryButtonText}>Back to Log In</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={styles.scroll} contentContainerStyle={styles.container} keyboardShouldPersistTaps="handled">

        <Text style={styles.logo}>commongood<Text style={styles.accent}>s</Text></Text>
        <Text style={styles.tagline}>driver-owned delivery</Text>

        {/* Tab toggle */}
        <View style={styles.toggle}>
          {(['login', 'signup'] as AuthTab[]).map((t) => (
            <TouchableOpacity
              key={t}
              style={[styles.toggleBtn, tab === t && styles.toggleActive]}
              onPress={() => { setTab(t); setSignupStep('code'); }}
            >
              <Text style={[styles.toggleText, tab === t && styles.toggleTextActive]}>
                {t === 'login' ? 'Log In' : 'Sign Up'}
              </Text>
            </TouchableOpacity>
          ))}
        </View>

        {/* ── LOGIN ── */}
        {tab === 'login' && (
          <>
            <TextInput
              style={styles.input}
              placeholder="Email"
              placeholderTextColor="#4a7a7a"
              keyboardType="email-address"
              autoCapitalize="none"
              value={loginEmail}
              onChangeText={setLoginEmail}
            />
            <TextInput
              style={styles.input}
              placeholder="Password"
              placeholderTextColor="#4a7a7a"
              secureTextEntry
              value={loginPassword}
              onChangeText={setLoginPassword}
            />
            <TouchableOpacity
              style={[styles.primaryButton, loading && styles.disabled]}
              onPress={handleLogin}
              disabled={loading}
            >
              {loading
                ? <ActivityIndicator color="#f5f5f5" />
                : <Text style={styles.primaryButtonText}>Log In</Text>
              }
            </TouchableOpacity>
          </>
        )}

        {/* ── SIGNUP: Step 1 — Referral code ── */}
        {tab === 'signup' && signupStep === 'code' && (
          <>
            <View style={styles.infoBox}>
              <Text style={styles.infoText}>
                CommonGoods is invite-only during our St. Augustine launch. Enter your referral code to continue.
              </Text>
            </View>
            <TextInput
              style={[styles.input, styles.codeInput]}
              placeholder="REFERRAL CODE"
              placeholderTextColor="#4a7a7a"
              autoCapitalize="characters"
              autoCorrect={false}
              value={refCode}
              onChangeText={setRefCode}
            />
            <TouchableOpacity
              style={[styles.primaryButton, loading && styles.disabled]}
              onPress={handleValidateCode}
              disabled={loading}
            >
              {loading
                ? <ActivityIndicator color="#f5f5f5" />
                : <Text style={styles.primaryButtonText}>Validate Code</Text>
              }
            </TouchableOpacity>
          </>
        )}

        {/* ── SIGNUP: Step 2 — Account details ── */}
        {tab === 'signup' && signupStep === 'details' && (
          <>
            <View style={styles.roleBadge}>
              <Text style={styles.roleBadgeText}>
                {refRole === 'driver'  && '🚗 Driver Account'}
                {refRole === 'partner' && '🤝 Restaurant Partner Account'}
                {refRole === 'customer' && '📦 Customer Account'}
                {refLabel ? `  ·  ${refLabel}` : ''}
              </Text>
            </View>

            <TextInput
              style={styles.input}
              placeholder="Full name"
              placeholderTextColor="#4a7a7a"
              value={fullName}
              onChangeText={setFullName}
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
              placeholder="Password (min 8 characters)"
              placeholderTextColor="#4a7a7a"
              secureTextEntry
              value={password}
              onChangeText={setPassword}
            />

            <TouchableOpacity
              style={[styles.primaryButton, loading && styles.disabled]}
              onPress={handleSignup}
              disabled={loading}
            >
              {loading
                ? <ActivityIndicator color="#f5f5f5" />
                : <Text style={styles.primaryButtonText}>Create Account</Text>
              }
            </TouchableOpacity>

            <TouchableOpacity onPress={() => setSignupStep('code')} style={{ marginTop: 16, alignItems: 'center' }}>
              <Text style={styles.backLink}>← Use a different code</Text>
            </TouchableOpacity>
          </>
        )}

      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  scroll:               { backgroundColor: '#0a1a1a', flex: 1 },
  container:            { padding: 32, paddingTop: 80, paddingBottom: 48 },
  centered:             { flex: 1, backgroundColor: '#0a1a1a', alignItems: 'center', justifyContent: 'center', padding: 32 },
  logo:                 { fontSize: 38, fontWeight: '800', color: '#f5f5f5', letterSpacing: -1, marginBottom: 8, textAlign: 'center' },
  accent:               { color: '#f5a623' },
  tagline:              { fontSize: 13, color: '#7a9e9e', letterSpacing: 2, textTransform: 'uppercase', marginBottom: 40, textAlign: 'center' },
  toggle:               { flexDirection: 'row', backgroundColor: '#122828', borderRadius: 8, marginBottom: 28, padding: 4 },
  toggleBtn:            { flex: 1, paddingVertical: 10, alignItems: 'center', borderRadius: 6 },
  toggleActive:         { backgroundColor: '#1a6b6b' },
  toggleText:           { color: '#7a9e9e', fontSize: 14, fontWeight: '600' },
  toggleTextActive:     { color: '#f5f5f5' },
  input:                { backgroundColor: '#122828', borderRadius: 8, padding: 16, color: '#f5f5f5', fontSize: 15, marginBottom: 12, borderWidth: 1, borderColor: '#1a6b6b' },
  codeInput:            { fontSize: 18, fontWeight: '700', letterSpacing: 3, textAlign: 'center' },
  primaryButton:        { backgroundColor: '#1a6b6b', paddingVertical: 18, borderRadius: 8, alignItems: 'center', marginTop: 8 },
  primaryButtonText:    { color: '#f5f5f5', fontSize: 16, fontWeight: '700' },
  disabled:             { opacity: 0.5 },
  infoBox:              { backgroundColor: '#0f2020', borderRadius: 8, padding: 14, marginBottom: 20, borderWidth: 1, borderColor: '#1a4040' },
  infoText:             { color: '#7a9e9e', fontSize: 13, lineHeight: 20, textAlign: 'center' },
  roleBadge:            { backgroundColor: '#0f2020', borderRadius: 8, padding: 14, marginBottom: 20, alignItems: 'center', borderWidth: 1, borderColor: '#1a6b6b' },
  roleBadgeText:        { color: '#f5a623', fontSize: 13, fontWeight: '700' },
  backLink:             { color: '#4a7a7a', fontSize: 13 },
  confirmIcon:          { fontSize: 48, marginVertical: 24 },
  confirmTitle:         { color: '#f5f5f5', fontSize: 22, fontWeight: '700', marginBottom: 16, textAlign: 'center' },
  confirmBody:          { color: '#7a9e9e', fontSize: 14, textAlign: 'center', lineHeight: 24 },
  confirmEmail:         { color: '#f5a623', fontWeight: '600' },
});