import { createClient } from '@supabase/supabase-js';
import * as SecureStore from 'expo-secure-store';

const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!;

const SecureStoreAdapter = {
  getItem:    (key: string)              => SecureStore.getItemAsync(key),
  setItem:    (key: string, val: string) => SecureStore.setItemAsync(key, val),
  removeItem: (key: string)             => SecureStore.deleteItemAsync(key),
};

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    storage: SecureStoreAdapter,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
});

export type Role = 'customer' | 'driver' | 'partner';

export type Profile = {
  id: string;
  role: Role;
  full_name: string | null;
  phone: string | null;
  is_admin: boolean;
  created_at: string;
};

export type Delivery = {
  id: string;
  customer_id: string;
  driver_id: string | null;
  partner_id: string | null;
  status: 'pending' | 'claimed' | 'in_progress' | 'completed' | 'cancelled';
  category: string;
  pickup_address: string;
  pickup_lat: number;
  pickup_lng: number;
  dropoff_address: string;
  dropoff_lat: number;
  dropoff_lng: number;
  distance_miles: number | null;
  zone_assigned: 1 | 2 | 3 | null;
  fee_charged: number | null;
  driver_payout: number | null;
  platform_cut: number | null;
  estimated_duration_minutes: number | null;
  actual_duration_minutes: number | null;
  route_polyline: string | null;
  requested_at: string;
  claimed_at: string | null;
  picked_up_at: string | null;
  delivered_at: string | null;
  notes: string | null;
};