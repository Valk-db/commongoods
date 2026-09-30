import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

interface EventBatchRequest {
  events: Array<{
    name: string;
    occurred_at: string; // ISO timestamp from device
    props?: Record<string, unknown>;
    entity_type?: string;
    entity_id?: string;
    session_id?: string;
    device_id?: string;
    app_version?: string;
    os?: string;
    experiment_assignments?: Record<string, string>;
    idempotency_key?: string;
  }>;
}

interface EventBatchResponse {
  success: boolean;
  error?: string;
  accepted: number;
  rejected: Array<{ index: number; reason: string }>;
}

interface EventCatalogEntry {
  name: string;
  json_schema: Record<string, unknown>;
  audience: 'all' | 'customer' | 'driver' | 'partner' | 'admin' | 'system';
}

// Rate limiting: track requests per user per minute
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT_MAX = 50; // max 50 events per minute per user
const RATE_LIMIT_WINDOW_MS = 60 * 1000;

// Idempotency key storage
const idempotencyStore = new Map<string, { expiresAt: number }>();
const IDEMPOTENCY_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

function checkRateLimit(userId: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(userId);

  if (!entry || entry.resetAt < now) {
    rateLimitMap.set(userId, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
    return true;
  }

  if (entry.count >= RATE_LIMIT_MAX) {
    return false;
  }

  entry.count++;
  return true;
}

function checkIdempotency(key: string): boolean {
  const entry = idempotencyStore.get(key);
  if (!entry) return false;

  if (entry.expiresAt < Date.now()) {
    idempotencyStore.delete(key);
    return false;
  }

  return true;
}

function storeIdempotency(key: string): void {
  idempotencyStore.set(key, {
    expiresAt: Date.now() + IDEMPOTENCY_TTL_MS
  });
}

function validateEventAgainstSchema(event: { name: string; props: Record<string, unknown> }, schema: Record<string, unknown>): { valid: boolean; error?: string } {
  // Simple JSON schema validation (in production, use a proper validator like ajv)
  // For now, just check required fields
  const required = schema.required as string[] | undefined;
  if (required) {
    for (const field of required) {
      if (!(field in event.props)) {
        return { valid: false, error: `Missing required field: ${field}` };
      }
    }
  }
  return { valid: true };
}

Deno.serve(async (req: Request) => {
  // CORS headers
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ success: false, error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // Verify JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ success: false, error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const token = authHeader.replace("Bearer ", "");
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${token}` } } }
    );

    const { data: { user }, error: userError } = await supabase.auth.getUser(token);
    if (userError || !user) {
      return new Response(JSON.stringify({ success: false, error: "Invalid token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check rate limit
    if (!checkRateLimit(user.id)) {
      return new Response(JSON.stringify({ success: false, error: "Rate limit exceeded" }), {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json", "Retry-After": "60" },
      });
    }

    // Get user's role
    const { data: profile } = await supabase
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single();

    const userRole = profile?.role || 'customer';

    const body: EventBatchRequest = await req.json();

    if (!body.events || !Array.isArray(body.events)) {
      return new Response(JSON.stringify({ success: false, error: "Invalid events array" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Validate batch size
    if (body.events.length > 100) {
      return new Response(JSON.stringify({ success: false, error: "Batch too large (max 100 events)" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Service role client for DB operations
    const serviceRoleSupabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Fetch active event catalog for validation
    const { data: catalog, error: catalogError } = await serviceRoleSupabase
      .from('event_catalog')
      .select('name, json_schema, audience')
      .eq('is_active', true);

    if (catalogError || !catalog) {
      console.error("Failed to fetch event catalog:", catalogError);
      return new Response(JSON.stringify({ success: false, error: "Internal server error" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const catalogMap = new Map<string, EventCatalogEntry>();
    for (const entry of catalog) {
      catalogMap.set(entry.name, entry as EventCatalogEntry);
    }

    // Process each event
    const accepted: Array<{
      occurred_at: string;
      received_at: string;
      actor_id: string;
      actor_type: string;
      session_id: string | null;
      device_id: string | null;
      app_version: string | null;
      os: string | null;
      entity_type: string | null;
      entity_id: string | null;
      name: string;
      props: Record<string, unknown>;
      config_snapshot_id: string | null;
      experiment_assignments: Record<string, string>;
      idempotency_key: string | null;
    }> = [];

    const rejected: Array<{ index: number; reason: string }> = [];

    for (let i = 0; i < body.events.length; i++) {
      const event = body.events[i];

      // Check idempotency
      if (event.idempotency_key) {
        if (checkIdempotency(event.idempotency_key)) {
          rejected.push({ index: i, reason: "Duplicate idempotency_key" });
          continue;
        }
      }

      // Validate event name exists in catalog
      const catalogEntry = catalogMap.get(event.name);
      if (!catalogEntry) {
        rejected.push({ index: i, reason: `Unknown event: ${event.name}` });
        continue;
      }

      // Validate audience - don't let clients send events for other audiences
      const allowedAudiences = ['all', userRole, 'system'];
      if (!allowedAudiences.includes(catalogEntry.audience)) {
        rejected.push({ index: i, reason: `Event ${event.name} not allowed for ${userRole}` });
        continue;
      }

      // Validate against schema
      const props = event.props || {};
      const validation = validateEventAgainstSchema({ name: event.name, props }, catalogEntry.json_schema);
      if (!validation.valid) {
        rejected.push({ index: i, reason: validation.error! });
        continue;
      }

      // Validate occurred_at is not too far in future/past
      const occurredAt = new Date(event.occurred_at);
      const now = new Date();
      const fiveMinutesAgo = new Date(now.getTime() - 5 * 60 * 1000);
      const oneHourFuture = new Date(now.getTime() + 60 * 60 * 1000);

      if (occurredAt < fiveMinutesAgo || occurredAt > oneHourFuture) {
        rejected.push({ index: i, reason: "occurred_at out of acceptable range" });
        continue;
      }

      // Get current config snapshot ID
      let configSnapshotId: string | null = null;
      const { data: snapshotData } = await serviceRoleSupabase
        .rpc('resolve_all_config', { p_ctx: {}, p_at: now.toISOString() });
      if (snapshotData && snapshotData.length > 0) {
        configSnapshotId = snapshotData[0].snapshot_id;
      }

      accepted.push({
        occurred_at: event.occurred_at,
        received_at: now.toISOString(),
        actor_id: user.id,
        actor_type: userRole,
        session_id: event.session_id || null,
        device_id: event.device_id || null,
        app_version: event.app_version || null,
        os: event.os || null,
        entity_type: event.entity_type || null,
        entity_id: event.entity_id || null,
        name: event.name,
        props,
        config_snapshot_id: configSnapshotId,
        experiment_assignments: event.experiment_assignments || {},
        idempotency_key: event.idempotency_key || null
      });

      // Store idempotency key
      if (event.idempotency_key) {
        storeIdempotency(event.idempotency_key);
      }
    }

    // Batch insert accepted events
    if (accepted.length > 0) {
      const { error: insertError } = await serviceRoleSupabase
        .from('events')
        .insert(accepted);

      if (insertError) {
        console.error("Event insert error:", insertError);
        return new Response(JSON.stringify({ success: false, error: "Failed to store events" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    return new Response(JSON.stringify({
      success: true,
      accepted: accepted.length,
      rejected
    }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("ingest_events error:", err);
    return new Response(JSON.stringify({ success: false, error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});