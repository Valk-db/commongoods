import { supabase } from './supabase';
import type { Database, Json } from './supabase.types';

type ConfigValue = string | number | boolean | object | null;

export interface ConfigContext {
  zone_id?: string;
  partner_id?: string;
  driver_id?: string;
  customer_id?: string;
  cohort_id?: string;
  experiment_arm_id?: string;
}

interface ConfigSnapshot {
  snapshot_id: string;
  config: Record<string, ConfigValue>;
}

interface RegistryEntry {
  key: string;
  type: string;
  json_schema: object;
  unit: string | null;
  default_value: ConfigValue;
  min_value: ConfigValue;
  max_value: ConfigValue;
  category: string;
  description: string;
  risk_level: 'low' | 'medium' | 'high';
  requires_approval: boolean;
}

class ConfigClient {
  private cache: Map<string, { value: ConfigValue; expires: number }> = new Map();
  private snapshotCache: ConfigSnapshot | null = null;
  private ttlMs: number = 5 * 60 * 1000; // 5 minutes default, overridden by config

  /**
   * Resolve a single config key for the given context
   */
  async get<K extends string>(key: K, ctx: ConfigContext = {}): Promise<ConfigValue> {
    const cacheKey = `${key}:${JSON.stringify(ctx)}`;
    const cached = this.cache.get(cacheKey);
    if (cached && cached.expires > Date.now()) {
      return cached.value;
    }

    const { data, error } = await supabase.rpc('resolve_config', {
      p_key: key,
      p_ctx: ctx as unknown as Json,
      p_at: new Date().toISOString()
    });

    if (error) {
      console.warn(`Config resolve failed for ${key}:`, error.message);
      // Fall back to registry default
      const defaultVal = await this.getDefault(key);
      this.cache.set(cacheKey, { value: defaultVal, expires: Date.now() + this.ttlMs });
      return defaultVal;
    }

    this.cache.set(cacheKey, { value: data, expires: Date.now() + this.ttlMs });
    return data;
  }

  /**
   * Get registry default for a key (no context resolution)
   */
  async getDefault(key: string): Promise<ConfigValue> {
    const { data, error } = await supabase
      .from('config_registry')
      .select('default_value')
      .eq('key', key)
      .single();

    if (error || !data) {
      console.warn(`No registry entry for ${key}`);
      return null;
    }
    return data.default_value;
  }

  /**
   * Resolve all config for a context, returns snapshot ID and full config
   */
  async getAll(ctx: ConfigContext = {}): Promise<ConfigSnapshot> {
    const cacheKey = `all:${JSON.stringify(ctx)}`;
    const cached = this.cache.get(cacheKey);
    if (cached && cached.expires > Date.now()) {
      return cached.value as ConfigSnapshot;
    }

    const { data, error } = await supabase.rpc('resolve_all_config', {
      p_ctx: ctx as unknown as Json,
      p_at: new Date().toISOString()
    });

    if (error) {
      console.warn('Config resolve_all failed:', error.message);
      // Fallback: resolve each registry key individually
      const registry = await this.getRegistry();
      const config: Record<string, ConfigValue> = {};
      for (const entry of registry) {
        config[entry.key] = await this.get(entry.key, ctx);
      }
      const fallback: ConfigSnapshot = { snapshot_id: 'fallback', config };
      this.cache.set(cacheKey, { value: fallback, expires: Date.now() + this.ttlMs });
      return fallback;
    }

    const snapshot: ConfigSnapshot = {
      snapshot_id: data[0].snapshot_id,
      config: data[0].config as unknown as Record<string, ConfigValue>
    };

    // Update TTL from config if available
    const ttlConfig = snapshot.config.telemetry as Record<string, unknown> | undefined;
    if (ttlConfig && typeof ttlConfig.config_ttl_seconds === 'number') {
      this.ttlMs = ttlConfig.config_ttl_seconds * 1000;
    }

    this.cache.set(cacheKey, { value: snapshot, expires: Date.now() + this.ttlMs });
    return snapshot;
  }

  /**
   * Get the full registry (for validation, UI, etc.)
   */
  async getRegistry(): Promise<RegistryEntry[]> {
    const { data, error } = await supabase
      .from('config_registry')
      .select('*')
      .order('category', { ascending: true });

    if (error) {
      console.warn('Failed to fetch config registry:', error.message);
      return [];
    }
    return data as unknown as RegistryEntry[];
  }

  /**
   * Validate proposed config changes against constraints
   */
  async validate(proposed: Record<string, ConfigValue>): Promise<Array<{
    constraint_name: string;
    passed: boolean;
    message: string;
  }>> {
    const { data, error } = await supabase.rpc('validate_config_constraints', {
      p_proposed: proposed as unknown as Json
    });

    if (error) {
      console.warn('Config validation failed:', error.message);
      return [];
    }
    return data as Array<{ constraint_name: string; passed: boolean; message: string }>;
  }

  /**
   * Preview impact of proposed config changes
   */
  async previewImpact(proposed: Record<string, ConfigValue>, daysLookback: number = 7): Promise<Array<{
    metric: string;
    current_value: number;
    proposed_value: number;
    delta: number;
    delta_pct: number;
  }>> {
    const { data, error } = await supabase.rpc('preview_config_impact', {
      p_proposed: proposed as unknown as Json,
      p_days_lookback: daysLookback
    });

    if (error) {
      console.warn('Impact preview failed:', error.message);
      return [];
    }
    return data as Array<{
      metric: string;
      current_value: number;
      proposed_value: number;
      delta: number;
      delta_pct: number;
    }>;
  }

  /**
   * Get mileage rate for a specific date
   */
  async getMileageRate(date: Date): Promise<{ business_cents: number; medical_cents: number | null; charity_cents: number | null } | null> {
    const { data, error } = await supabase.rpc('get_mileage_rate', {
      p_date: date.toISOString().split('T')[0]
    });

    if (error || !data || data.length === 0) {
      return null;
    }
    return data[0] as { business_cents: number; medical_cents: number | null; charity_cents: number | null };
  }

  /**
   * Clear cache (e.g., after config publish)
   */
  clearCache(): void {
    this.cache.clear();
    this.snapshotCache = null;
  }

  /**
   * Subscribe to config changes (real-time)
   */
  subscribeToChanges(callback: (key: string, newValue: ConfigValue) => void): () => void {
    const channel = supabase.channel('config_changes');

    channel.on(
      'postgres_changes',
      { event: '*', schema: 'public', table: 'config_values' },
      (payload) => {
        const newRecord = payload.new as { key: string; value: ConfigValue; status: string } | null;
        if (newRecord && newRecord.status === 'active') {
          this.cache.clear(); // Invalidate cache on any active config change
          callback(newRecord.key, newRecord.value);
        }
      }
    );

    channel.subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }
}

// Singleton instance
export const config = new ConfigClient();

// Typed config accessors for common keys
export const pricing = {
  async getStrategy(ctx?: ConfigContext) {
    return (await config.get('pricing.strategy', ctx)) as 'zone_v1' | 'distance_time_v1';
  },
  async getBaseFee(ctx?: ConfigContext) {
    return (await config.get('pricing.base_fee', ctx)) as number;
  },
  async getPerMile(ctx?: ConfigContext) {
    return (await config.get('pricing.per_mile', ctx)) as number;
  },
  async getPerMinute(ctx?: ConfigContext) {
    return (await config.get('pricing.per_minute', ctx)) as number;
  },
  async getMinFee(ctx?: ConfigContext) {
    return (await config.get('pricing.min_fee', ctx)) as number;
  },
  async getMaxFee(ctx?: ConfigContext) {
    return (await config.get('pricing.max_fee', ctx)) as number;
  },
  async getZoneFee(zone: 1 | 2 | 3, ctx?: ConfigContext) {
    return (await config.get(`pricing.zone.${zone}.fee`, ctx)) as number;
  },
  async getDistanceBands(ctx?: ConfigContext) {
    return (await config.get('pricing.distance_bands', ctx)) as number[];
  },
  async getDemandMultiplier(ctx?: ConfigContext) {
    return {
      min: (await config.get('pricing.demand_multiplier.min', ctx)) as number,
      max: (await config.get('pricing.demand_multiplier.max', ctx)) as number,
      curve: (await config.get('pricing.demand_multiplier.curve', ctx)) as 'linear' | 'exponential' | 'step'
    };
  },
  async getPeakHours(ctx?: ConfigContext) {
    return (await config.get('pricing.peak_hours', ctx)) as Array<{ start: string; end: string; days: number[] }>;
  },
  async getWeatherSurcharge(ctx?: ConfigContext) {
    return (await config.get('pricing.weather_surcharge', ctx)) as number;
  },
  async getTipPresets(ctx?: ConfigContext) {
    return (await config.get('pricing.tip_presets', ctx)) as number[];
  },
  async getFeeRounding(ctx?: ConfigContext) {
    return (await config.get('pricing.fee_rounding', ctx)) as 'none' | 'round' | 'ceil_0.25' | 'ceil_0.50';
  },
  // Distance-time strategy
  async getDistanceTime(ctx?: ConfigContext) {
    return {
      baseFee: (await config.get('pricing.distance_time.base_fee', ctx)) as number,
      perMile: (await config.get('pricing.distance_time.per_mile', ctx)) as number,
      perMinute: (await config.get('pricing.distance_time.per_minute', ctx)) as number,
      minFee: (await config.get('pricing.distance_time.min_fee', ctx)) as number
    };
  }
};

export const driverPay = {
  async getStrategy(ctx?: ConfigContext) {
    return (await config.get('pay.strategy', ctx)) as 'pct_v1' | 'per_mile_v1' | 'hourly_floor_v1';
  },
  async getPayoutRate(ctx?: ConfigContext) {
    return (await config.get('pay.payout_pct_or_per_mile', ctx)) as number;
  },
  async getMinPayout(ctx?: ConfigContext) {
    return (await config.get('pay.min_payout', ctx)) as number;
  },
  async getPayFloorPerHour(ctx?: ConfigContext) {
    return (await config.get('pay.pay_floor_per_hour', ctx)) as number;
  },
  async getWaitPayPerMinute(ctx?: ConfigContext) {
    return (await config.get('pay.wait_pay_per_minute', ctx)) as number;
  },
  async getWaitPayGraceMinutes(ctx?: ConfigContext) {
    return (await config.get('pay.wait_pay_grace_minutes', ctx)) as number;
  },
  async getBonusRules(ctx?: ConfigContext) {
    return (await config.get('pay.bonus.rules', ctx)) as object[];
  }
};

export const platform = {
  async getCutPct(ctx?: ConfigContext) {
    return (await config.get('platform_cut_pct', ctx)) as number;
  },
  async getPatronageReservePct(ctx?: ConfigContext) {
    return (await config.get('patronage_reserve_pct', ctx)) as number;
  }
};

export const cancellation = {
  async getFreeStages(ctx?: ConfigContext) {
    return (await config.get('cancel.free_stages', ctx)) as string[];
  },
  async getCompensationEnRoute(ctx?: ConfigContext) {
    return (await config.get('cancel.comp.en_route', ctx)) as number;
  },
  async getCompensationInProgress(ctx?: ConfigContext) {
    return (await config.get('cancel.comp.in_progress', ctx)) as number;
  },
  async getCustomerFee(stage: 'pending' | 'claimed' | 'en_route', ctx?: ConfigContext) {
    return (await config.get(`cancel.customer_fee.${stage}`, ctx)) as number;
  },
  async getLockoutAfterStatus(ctx?: ConfigContext) {
    return (await config.get('cancel.lockout_after_status', ctx)) as 'claimed' | 'en_route' | 'in_progress';
  }
};

export const dispatch = {
  async getStrategy(ctx?: ConfigContext) {
    return (await config.get('dispatch.strategy', ctx)) as 'broadcast_v1' | 'nearest_first_v1' | 'tiered_v1';
  },
  async getOfferMode(ctx?: ConfigContext) {
    return (await config.get('dispatch.offer_mode', ctx)) as 'broadcast' | 'sequential' | 'tiered';
  },
  async getOfferTtlSeconds(ctx?: ConfigContext) {
    return (await config.get('dispatch.offer_ttl_seconds', ctx)) as number;
  },
  async getSearchRadiusMiles(ctx?: ConfigContext) {
    return (await config.get('dispatch.search_radius_miles', ctx)) as number;
  },
  async getRadiusExpansionSteps(ctx?: ConfigContext) {
    return (await config.get('dispatch.radius_expansion_steps', ctx)) as number[];
  },
  async getRankingWeights(ctx?: ConfigContext) {
    return (await config.get('dispatch.ranking_weights', ctx)) as { distance: number; rating: number; acceptance: number; idle_time: number };
  },
  async getMaxConcurrentOffers(ctx?: ConfigContext) {
    return (await config.get('dispatch.max_concurrent_offers', ctx)) as number;
  },
  async getReofferDelaySeconds(ctx?: ConfigContext) {
    return (await config.get('dispatch.reoffer_delay_seconds', ctx)) as number;
  },
  async getStaleClaimTimeoutMinutes(ctx?: ConfigContext) {
    return (await config.get('dispatch.stale_claim_timeout_minutes', ctx)) as number;
  }
};

export const geo = {
  async getMaxDistanceMiles(ctx?: ConfigContext) {
    return (await config.get('geo.max_distance_miles', ctx)) as number;
  },
  async getServiceHours(ctx?: ConfigContext) {
    return (await config.get('geo.service_hours', ctx)) as { start: string; end: string };
  },
  async getHolidayCalendar(ctx?: ConfigContext) {
    return (await config.get('geo.holiday_calendar', ctx)) as string[];
  }
};

export const limits = {
  async getMaxActiveJobsPerDriver(ctx?: ConfigContext) {
    return (await config.get('limits.max_active_jobs_per_driver', ctx)) as number;
  },
  async getMaxOrdersPerCustomerPerHour(ctx?: ConfigContext) {
    return (await config.get('limits.max_orders_per_customer_per_hour', ctx)) as number;
  },
  async getReferralCodeLength(ctx?: ConfigContext) {
    return (await config.get('limits.referral_code_length', ctx)) as number;
  },
  async getReferralTtlDays(ctx?: ConfigContext) {
    return (await config.get('limits.referral_ttl_days', ctx)) as number;
  }
};

export const telemetry = {
  async getGpsSampleIntervalS(ctx?: ConfigContext) {
    return (await config.get('telemetry.gps.sample_interval_s', ctx)) as number;
  },
  async getGpsDistanceFilterM(ctx?: ConfigContext) {
    return (await config.get('telemetry.gps.distance_filter_m', ctx)) as number;
  },
  async getGpsAccuracyThresholdM(ctx?: ConfigContext) {
    return (await config.get('telemetry.gps.accuracy_threshold_m', ctx)) as number;
  },
  async getGpsUploadBatchSize(ctx?: ConfigContext) {
    return (await config.get('telemetry.gps.upload_batch_size', ctx)) as number;
  },
  async getGpsIdleSamplingMultiplier(ctx?: ConfigContext) {
    return (await config.get('telemetry.gps.idle_sampling_multiplier', ctx)) as number;
  },
  async getRetentionLocationPingsDays(ctx?: ConfigContext) {
    return (await config.get('telemetry.retention.location_pings_days', ctx)) as number;
  },
  async getRetentionEventsDays(ctx?: ConfigContext) {
    return (await config.get('telemetry.retention.events_days', ctx)) as number;
  },
  async getRetentionMileageYears(ctx?: ConfigContext) {
    return (await config.get('telemetry.retention.mileage_years', ctx)) as number;
  }
};

export const flags = {
  async isNewDriverOnboardingEnabled(ctx?: ConfigContext) {
    return (await config.get('flag.new_driver_onboarding', ctx)) as boolean;
  },
  async isPartnerSelfServeMenuEnabled(ctx?: ConfigContext) {
    return (await config.get('flag.partner_self_serve_menu', ctx)) as boolean;
  },
  async isExperimentalDispatchEnabled(ctx?: ConfigContext) {
    return (await config.get('flag.experimental_dispatch', ctx)) as boolean;
  }
};

export const ux = {
  async getTipPrompt(ctx?: ConfigContext) {
    return (await config.get('ux.copy.tip_prompt', ctx)) as string;
  },
  async getOutOfAreaMessage(ctx?: ConfigContext) {
    return (await config.get('ux.copy.out_of_area', ctx)) as string;
  }
};

// Export all as a single namespace for convenience
export const cfg = {
  pricing,
  driverPay,
  platform,
  cancellation,
  dispatch,
  geo,
  limits,
  telemetry,
  flags,
  ux
};

export default config;