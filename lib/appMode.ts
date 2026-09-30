import { create } from 'zustand';
import { supabase } from './supabase';

export type AppMode = 'customer' | 'driver' | 'partner';

interface AppModeState {
  currentMode: AppMode;
  availableModes: AppMode[];
  isSwitching: boolean;
  setMode: (mode: AppMode) => void;
  syncAvailableModes: () => Promise<void>;
}

export const useAppMode = create<AppModeState>()((set, get) => ({
  currentMode:    'customer',
  availableModes: ['customer'],
  isSwitching:    false,

  setMode: (mode: AppMode) => {
    if (!get().availableModes.includes(mode)) return;
    set({ currentMode: mode });
  },

  syncAvailableModes: async () => {
    set({ isSwitching: true });
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session?.user) {
        set({ availableModes: ['customer'], currentMode: 'customer', isSwitching: false });
        return;
      }

      const modes: AppMode[] = ['customer'];

      // maybeSingle() returns null instead of throwing when no row exists
      const [driverCheck, partnerCheck] = await Promise.all([
        supabase.from('drivers').select('approved').eq('id', session.user.id).maybeSingle(),
        supabase.from('partners').select('approved').eq('profile_id', session.user.id).maybeSingle(),
      ]);

      if (driverCheck.data?.approved)  modes.push('driver');
      if (partnerCheck.data?.approved) modes.push('partner');

      set({
        availableModes: modes,
        currentMode: modes.includes(get().currentMode) ? get().currentMode : 'customer',
      });
    } catch (error) {
      console.error('syncAvailableModes error:', error);
    } finally {
      set({ isSwitching: false });
    }
  },
}));