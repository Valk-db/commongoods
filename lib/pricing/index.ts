/**
 * Pricing Module - Single Source of Truth for Pricing Logic
 *
 * This module contains:
 * - config.ts: TypeScript interfaces for pricing config
 * - engine.ts: Pure pricing calculation functions
 * - fixtures.ts: Golden test fixtures for validation
 *
 * Used by: Edge Functions, simulators, tests.
 * SQL functions should ONLY validate stored results against this.
 */

export * from './config';
export * from './engine';
export * from './fixtures';

// Re-export types explicitly to avoid duplicate export warnings
export type { PricingConfig, DriverPayConfig, PlatformConfig } from './config';
export type { PricingInput, PricingComponent, PricingResult } from './config';