import React, { useEffect } from 'react';
import { View, ActivityIndicator } from 'react-native';
import { Stack, useRouter, useSegments } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { useAppMode } from '../lib/appMode';
import { supabase } from '../lib/supabase';

export default function RootLayout() {
  const { syncAvailableModes, isSwitching } = useAppMode();
  const segments = useSegments();
  const router = useRouter();

  // 1. Sync available sub-profiles on mount or auth state changes
  useEffect(() => {
    syncAvailableModes();

    const { data: { subscription } } = supabase.auth.onAuthStateChange(() => {
      syncAvailableModes();
    });

    return () => subscription.unsubscribe();
  }, []);

  // 2. Route Protection Guard Loop
  useEffect(() => {
    const checkAuth = async () => {
      const { data: { session } } = await supabase.auth.getSession();
      const inAuthGroup = segments[0] === 'auth';

      if (!session && !inAuthGroup) {
        // Force unauthenticated users to the login screen
        router.replace('/auth');
      } else if (session && inAuthGroup) {
        // Send logged-in users straight to the workspace root
        router.replace('/');
      }
    };

    checkAuth();
  }, [segments]);

  // Loading state using your dark theme color
  if (isSwitching) {
    return (
      <GestureHandlerRootView style={{ flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#0a1a1a' }}>
        <StatusBar style="light" />
        <ActivityIndicator size="large" color="#f5f5f5" />
      </GestureHandlerRootView>
    );
  }

  // Your exact UI tree and Stack definitions
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <StatusBar style="light" />
      <Stack
        screenOptions={{
          headerStyle: { backgroundColor: '#0a1a1a' },
          headerTintColor: '#f5f5f5',
          headerTitleStyle: { fontWeight: 'bold' },
          contentStyle: { backgroundColor: '#0a1a1a' },
        }}
      >
        <Stack.Screen name="index" options={{ headerShown: false }} />
        <Stack.Screen name="auth" options={{ headerShown: false }} />
        <Stack.Screen name="customer" options={{ title: 'Request Delivery' }} />
        <Stack.Screen name="driver" options={{ title: 'Driver Dashboard' }} />
        <Stack.Screen name="partner" options={{ title: 'Partner With Us' }} />
        <Stack.Screen name="orders" options={{ title: 'My Orders' }} />
        <Stack.Screen name="admin" options={{ title: 'Admin' }} />
        <Stack.Screen name="partner-home" options={{ title: 'Your Restaurant' }} />
        <Stack.Screen name="partner-orders" options={{ title: 'Orders & Sales' }} />
        <Stack.Screen name="partner-menu" options={{ title: 'Menu' }} />
        <Stack.Screen name="partner-settings" options={{ title: 'Restaurant Settings' }} />
      </Stack>
    </GestureHandlerRootView>
  );
}