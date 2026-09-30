# CommonGoods

A cooperative delivery platform built with Expo, React Native, and Supabase.

## Overview

CommonGoods is a community-owned delivery platform connecting customers, drivers, and partner restaurants. It implements a cooperative model where drivers are members with equity stakes and governance rights.

## Tech Stack

- **Frontend**: Expo 54 (React Native), TypeScript, Expo Router
- **Backend**: Supabase (PostgreSQL, Auth, Realtime, Storage, Edge Functions)
- **Maps**: Mapbox (Directions, Geocoding)
- **State**: Zustand
- **CI**: GitHub Actions (typecheck, lint, gitleaks)

## Getting Started

### Prerequisites

- Node.js 20+
- npm
- Supabase CLI (`npm i -g supabase`)
- Expo CLI (`npm i -g expo-cli`)

### Installation

```bash
# Clone the repo
git clone https://github.com/Valk-db/commongoods.git
cd commongoods

# Install dependencies
npm ci

# Copy environment template
cp .env.example .env
# Fill in your values in .env

# Start the app
npm start
```

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `EXPO_PUBLIC_SUPABASE_URL` | Supabase project URL | Yes |
| `EXPO_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon key | Yes |
| `EXPO_PUBLIC_MAPBOX_TOKEN` | Mapbox **public** token (pk.*) | Yes |
| `SUPABASE_ACCESS_TOKEN` | Supabase personal access token (CLI only) | For CI/deploys |

**Important**: Never use a Mapbox secret token (`sk.*`) in the app. Use a URL-restricted public token (`pk.*`) for map display. Directions/geocoding should be server-side.

## Project Structure

```
app/                    # Expo Router pages
  _layout.tsx           # Root layout, providers, auth gate
  index.tsx             # Landing / onboarding
  auth.tsx              # Signup / login
  customer.tsx          # Customer order flow
  driver.tsx            # Driver dashboard
  driver-history.tsx    # Driver earnings history
  admin.tsx             # Admin dashboard
  orders.tsx            # Shared order view
  partner*.tsx          # Partner (restaurant) screens
lib/
  supabase.ts           # Supabase client, types
  appMode.ts            # Customer/Driver/Partner mode switching
  zones.ts              # Zone pricing logic
  storage.ts            # File upload helpers
  navigation.ts         # Navigation utilities
supabase/
  migrations/           # SQL migrations (run via Supabase CLI)
  .temp/                # Linked project metadata
.github/workflows/
  ci.yml                # CI pipeline
```

## Database

Migrations are the source of truth. Apply with:

```bash
supabase link --project-ref <ref>
supabase db push
```

Generate TypeScript types:

```bash
supabase gen types typescript --linked > lib/supabase.types.ts
```

## Key Features (Implemented)

- Multi-role auth (customer, driver, partner, admin)
- Zone-based pricing
- Real-time order tracking
- Partner menu management
- Driver approval workflow
- Secure file uploads (partner photos)

## Work in Progress

- Job claim/release RPC with state machine
- `create_delivery` Edge Function (server-side pricing)
- Co-op membership & governance tables
- Stripe Connect for driver payouts
- Push notifications

## Contributing

1. Create a feature branch
2. Make changes with tests
3. Run `npm run lint && npx tsc --noEmit`
4. Open a PR

## Security

- All secrets in `.env` (gitignored)
- Gitleaks in CI prevents secret commits
- RLS policies enforce data access
- Mapbox secret tokens never in client code

## License

TBD