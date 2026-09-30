/**
 * Pricing Module - Single Source of Truth for Pricing Logic
 *
 * This module re-exports the shared pricing engine from supabase/functions/_shared/pricing/
 * to ensure there's only ONE source of truth for pricing calculations.
 *
 * Used by: Edge Functions, simulators, tests.
 * SQL functions should ONLY validate stored results against this.
 */

export * from '../../supabase/functions/_shared/pricing/index';

// Re-export types explicitly
export type { PricingConfig } from '../../supabase/functions/_shared/pricing/config';
export type { PricingInput, PricingComponent, PricingResult } from '../../supabase/functions/_shared/pricing/config';