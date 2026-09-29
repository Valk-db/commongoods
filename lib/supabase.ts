import { createClient } from '@supabase/supabase-js';
import * as SecureStore from 'expo-secure-store';
import { Database } from './supabase.types';

const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!;

const SecureStoreAdapter = {
  getItem:    (key: string)              => SecureStore.getItemAsync(key),
  setItem:    (key: string, val: string) => SecureStore.setItemAsync(key, val),
  removeItem: (key: string)             => SecureStore.deleteItemAsync(key),
};

export const supabase = createClient<Database>(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    storage: SecureStoreAdapter,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
});

export type Role = 'customer' | 'driver' | 'partner';

export type Profile = Database['public']['Tables']['profiles']['Row'];
export type Delivery = Database['public']['Tables']['deliveries']['Row'];
export type Driver = Database['public']['Tables']['drivers']['Row'];
export type Partner = Database['public']['Tables']['partners']['Row'];
export type MenuItem = Database['public']['Tables']['menu_items']['Row'];
export type ReferralCode = Database['public']['Tables']['referral_codes']['Row'];
export type Earnings = Database['public']['Tables']['earnings']['Row'];
export type RoutePoint = Database['public']['Tables']['route_points']['Row'];
export type DeliveryItem = Database['public']['Tables']['delivery_items']['Row'];
export type DeliveryItemOption = Database['public']['Tables']['delivery_item_options']['Row'];
export type DeliveryMessage = Database['public']['Tables']['delivery_messages']['Row'];
export type DeliveryStatusHistory = Database['public']['Tables']['delivery_status_history']['Row'];
export type PartnerApplication = Database['public']['Tables']['partner_applications']['Row'];
export type MenuItemOption = Database['public']['Tables']['menu_item_options']['Row'];
export type PerformanceMetric = Database['public']['Tables']['performance_metrics']['Row'];
export type RatingAndReview = Database['public']['Tables']['ratings_and_reviews']['Row'];