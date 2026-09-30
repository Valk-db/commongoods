export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  private: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      check_user_role: { Args: { required_role: string }; Returns: boolean }
      current_role_is: { Args: { target_role: string }; Returns: boolean }
      get_my_role: { Args: never; Returns: string }
      is_admin: { Args: never; Returns: boolean }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      algorithm_versions: {
        Row: {
          code_ref: string
          config_schema: Json
          created_at: string
          created_by: string
          deprecated_at: string | null
          description: string | null
          id: string
          kind: string
          name: string
          status: string
          version: string
        }
        Insert: {
          code_ref: string
          config_schema?: Json
          created_at?: string
          created_by: string
          deprecated_at?: string | null
          description?: string | null
          id?: string
          kind: string
          name: string
          status?: string
          version: string
        }
        Update: {
          code_ref?: string
          config_schema?: Json
          created_at?: string
          created_by?: string
          deprecated_at?: string | null
          description?: string | null
          id?: string
          kind?: string
          name?: string
          status?: string
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "algorithm_versions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      config_audit: {
        Row: {
          changed_by: string
          created_at: string
          id: string
          ip_address: unknown
          key: string
          new_value: Json | null
          old_value: Json | null
          reason: string | null
          scope_id: string | null
          scope_type: string | null
          user_agent: string | null
        }
        Insert: {
          changed_by: string
          created_at?: string
          id?: string
          ip_address?: unknown
          key: string
          new_value?: Json | null
          old_value?: Json | null
          reason?: string | null
          scope_id?: string | null
          scope_type?: string | null
          user_agent?: string | null
        }
        Update: {
          changed_by?: string
          created_at?: string
          id?: string
          ip_address?: unknown
          key?: string
          new_value?: Json | null
          old_value?: Json | null
          reason?: string | null
          scope_id?: string | null
          scope_type?: string | null
          user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "config_audit_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      config_constraints: {
        Row: {
          created_at: string
          expression: string
          id: string
          is_active: boolean
          message: string
          name: string
          severity: string
        }
        Insert: {
          created_at?: string
          expression: string
          id?: string
          is_active?: boolean
          message: string
          name: string
          severity?: string
        }
        Update: {
          created_at?: string
          expression?: string
          id?: string
          is_active?: boolean
          message?: string
          name?: string
          severity?: string
        }
        Relationships: []
      }
      config_registry: {
        Row: {
          category: string
          created_at: string
          default_value: Json
          description: string
          json_schema: Json
          key: string
          max_value: Json | null
          min_value: Json | null
          requires_approval: boolean
          risk_level: string
          type: string
          unit: string | null
          updated_at: string
        }
        Insert: {
          category: string
          created_at?: string
          default_value: Json
          description: string
          json_schema: Json
          key: string
          max_value?: Json | null
          min_value?: Json | null
          requires_approval?: boolean
          risk_level?: string
          type: string
          unit?: string | null
          updated_at?: string
        }
        Update: {
          category?: string
          created_at?: string
          default_value?: Json
          description?: string
          json_schema?: Json
          key?: string
          max_value?: Json | null
          min_value?: Json | null
          requires_approval?: boolean
          risk_level?: string
          type?: string
          unit?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      config_snapshots: {
        Row: {
          created_at: string
          hash: string
          id: string
          resolved: Json
        }
        Insert: {
          created_at?: string
          hash: string
          id?: string
          resolved: Json
        }
        Update: {
          created_at?: string
          hash?: string
          id?: string
          resolved?: Json
        }
        Relationships: []
      }
      config_values: {
        Row: {
          approved_by: string | null
          created_at: string
          created_by: string
          effective_from: string
          effective_to: string | null
          governance_proposal_id: string | null
          id: string
          key: string
          reason: string
          scope_id: string | null
          scope_type: string
          status: string
          value: Json
        }
        Insert: {
          approved_by?: string | null
          created_at?: string
          created_by: string
          effective_from?: string
          effective_to?: string | null
          governance_proposal_id?: string | null
          id?: string
          key: string
          reason: string
          scope_id?: string | null
          scope_type: string
          status?: string
          value: Json
        }
        Update: {
          approved_by?: string | null
          created_at?: string
          created_by?: string
          effective_from?: string
          effective_to?: string | null
          governance_proposal_id?: string | null
          id?: string
          key?: string
          reason?: string
          scope_id?: string | null
          scope_type?: string
          status?: string
          value?: Json
        }
        Relationships: [
          {
            foreignKeyName: "config_values_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "config_values_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "config_values_key_fkey"
            columns: ["key"]
            isOneToOne: false
            referencedRelation: "config_registry"
            referencedColumns: ["key"]
          },
        ]
      }
      deliveries: {
        Row: {
          actual_duration_minutes: number | null
          arrived_dropoff_at: string | null
          arrived_pickup_at: string | null
          base_fee_applied: number | null
          cancel_reason_code: string | null
          cancel_stage: string | null
          cancellation_reason_code: string | null
          cancelled_by: string | null
          category: string
          claimed_at: string | null
          compensation_amount: number | null
          customer_id: string | null
          delivered_at: string | null
          distance_miles: number | null
          driver_arrived_at_dropoff_at: string | null
          driver_arrived_at_pickup_at: string | null
          driver_id: string | null
          driver_payout: number | null
          dropoff_address: string
          dropoff_lat: number
          dropoff_lng: number
          dynamic_boost_incentive: number | null
          en_route_at: string | null
          estimated_duration_minutes: number | null
          fee_charged: number | null
          id: string
          notes: string | null
          offered_at: string | null
          partner_id: string | null
          per_mile_rate_applied: number | null
          picked_up_at: string | null
          pickup_address: string
          pickup_lat: number
          pickup_lng: number
          platform_cut: number | null
          ready_for_pickup_at: string | null
          requested_at: string | null
          route_polyline: string | null
          status: string | null
          surge_multiplier_applied: number | null
          tip_amount: number | null
          transport_type: string | null
          zone_assigned: number | null
        }
        Insert: {
          actual_duration_minutes?: number | null
          arrived_dropoff_at?: string | null
          arrived_pickup_at?: string | null
          base_fee_applied?: number | null
          cancel_reason_code?: string | null
          cancel_stage?: string | null
          cancellation_reason_code?: string | null
          cancelled_by?: string | null
          category: string
          claimed_at?: string | null
          compensation_amount?: number | null
          customer_id?: string | null
          delivered_at?: string | null
          distance_miles?: number | null
          driver_arrived_at_dropoff_at?: string | null
          driver_arrived_at_pickup_at?: string | null
          driver_id?: string | null
          driver_payout?: number | null
          dropoff_address: string
          dropoff_lat: number
          dropoff_lng: number
          dynamic_boost_incentive?: number | null
          en_route_at?: string | null
          estimated_duration_minutes?: number | null
          fee_charged?: number | null
          id?: string
          notes?: string | null
          offered_at?: string | null
          partner_id?: string | null
          per_mile_rate_applied?: number | null
          picked_up_at?: string | null
          pickup_address: string
          pickup_lat: number
          pickup_lng: number
          platform_cut?: number | null
          ready_for_pickup_at?: string | null
          requested_at?: string | null
          route_polyline?: string | null
          status?: string | null
          surge_multiplier_applied?: number | null
          tip_amount?: number | null
          transport_type?: string | null
          zone_assigned?: number | null
        }
        Update: {
          actual_duration_minutes?: number | null
          arrived_dropoff_at?: string | null
          arrived_pickup_at?: string | null
          base_fee_applied?: number | null
          cancel_reason_code?: string | null
          cancel_stage?: string | null
          cancellation_reason_code?: string | null
          cancelled_by?: string | null
          category?: string
          claimed_at?: string | null
          compensation_amount?: number | null
          customer_id?: string | null
          delivered_at?: string | null
          distance_miles?: number | null
          driver_arrived_at_dropoff_at?: string | null
          driver_arrived_at_pickup_at?: string | null
          driver_id?: string | null
          driver_payout?: number | null
          dropoff_address?: string
          dropoff_lat?: number
          dropoff_lng?: number
          dynamic_boost_incentive?: number | null
          en_route_at?: string | null
          estimated_duration_minutes?: number | null
          fee_charged?: number | null
          id?: string
          notes?: string | null
          offered_at?: string | null
          partner_id?: string | null
          per_mile_rate_applied?: number | null
          picked_up_at?: string | null
          pickup_address?: string
          pickup_lat?: number
          pickup_lng?: number
          platform_cut?: number | null
          ready_for_pickup_at?: string | null
          requested_at?: string | null
          route_polyline?: string | null
          status?: string | null
          surge_multiplier_applied?: number | null
          tip_amount?: number | null
          transport_type?: string | null
          zone_assigned?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "deliveries_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliveries_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliveries_partner_id_fkey"
            columns: ["partner_id"]
            isOneToOne: false
            referencedRelation: "partners"
            referencedColumns: ["id"]
          },
        ]
      }
      delivery_item_options: {
        Row: {
          delivery_item_id: string | null
          id: string
          menu_item_option_id: string | null
          price_at_purchase: number
        }
        Insert: {
          delivery_item_id?: string | null
          id?: string
          menu_item_option_id?: string | null
          price_at_purchase: number
        }
        Update: {
          delivery_item_id?: string | null
          id?: string
          menu_item_option_id?: string | null
          price_at_purchase?: number
        }
        Relationships: [
          {
            foreignKeyName: "delivery_item_options_delivery_item_id_fkey"
            columns: ["delivery_item_id"]
            isOneToOne: false
            referencedRelation: "delivery_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_item_options_menu_item_option_id_fkey"
            columns: ["menu_item_option_id"]
            isOneToOne: false
            referencedRelation: "menu_item_options"
            referencedColumns: ["id"]
          },
        ]
      }
      delivery_items: {
        Row: {
          delivery_id: string | null
          id: string
          menu_item_id: string | null
          price_at_purchase: number
          quantity: number
        }
        Insert: {
          delivery_id?: string | null
          id?: string
          menu_item_id?: string | null
          price_at_purchase: number
          quantity?: number
        }
        Update: {
          delivery_id?: string | null
          id?: string
          menu_item_id?: string | null
          price_at_purchase?: number
          quantity?: number
        }
        Relationships: [
          {
            foreignKeyName: "delivery_items_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_items_menu_item_id_fkey"
            columns: ["menu_item_id"]
            isOneToOne: false
            referencedRelation: "menu_items"
            referencedColumns: ["id"]
          },
        ]
      }
      delivery_messages: {
        Row: {
          created_at: string | null
          delivery_id: string | null
          id: string
          message_text: string
          sender_id: string | null
        }
        Insert: {
          created_at?: string | null
          delivery_id?: string | null
          id?: string
          message_text: string
          sender_id?: string | null
        }
        Update: {
          created_at?: string | null
          delivery_id?: string | null
          id?: string
          message_text?: string
          sender_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "delivery_messages_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_messages_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      delivery_status_history: {
        Row: {
          actor_id: string | null
          changed_at: string | null
          delivery_id: string | null
          id: string
          lat: number | null
          lng: number | null
          status: string
        }
        Insert: {
          actor_id?: string | null
          changed_at?: string | null
          delivery_id?: string | null
          id?: string
          lat?: number | null
          lng?: number | null
          status: string
        }
        Update: {
          actor_id?: string | null
          changed_at?: string | null
          delivery_id?: string | null
          id?: string
          lat?: number | null
          lng?: number | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "delivery_status_history_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "delivery_status_history_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
      dispatch_decisions: {
        Row: {
          candidates: Json
          chosen_driver_id: string | null
          config_snapshot_id: string
          created_at: string
          delivery_id: string
          dispatch_algorithm_version: string
          id: string
          inputs: Json
          reason: string | null
        }
        Insert: {
          candidates?: Json
          chosen_driver_id?: string | null
          config_snapshot_id: string
          created_at?: string
          delivery_id: string
          dispatch_algorithm_version: string
          id?: string
          inputs: Json
          reason?: string | null
        }
        Update: {
          candidates?: Json
          chosen_driver_id?: string | null
          config_snapshot_id?: string
          created_at?: string
          delivery_id?: string
          dispatch_algorithm_version?: string
          id?: string
          inputs?: Json
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "dispatch_decisions_chosen_driver_id_fkey"
            columns: ["chosen_driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dispatch_decisions_config_snapshot_id_fkey"
            columns: ["config_snapshot_id"]
            isOneToOne: false
            referencedRelation: "config_snapshots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dispatch_decisions_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dispatch_decisions_dispatch_algorithm_version_fkey"
            columns: ["dispatch_algorithm_version"]
            isOneToOne: false
            referencedRelation: "algorithm_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      dispatch_offers: {
        Row: {
          alternatives_shown: number | null
          config_snapshot_id: string
          created_at: string
          decline_reason: string | null
          delivery_id: string
          dispatch_algorithm_version: string
          driver_acceptance_rate: number | null
          driver_distance_to_pickup_miles: number | null
          driver_id: string
          driver_idle_time_minutes: number | null
          driver_rating: number | null
          id: string
          latency_ms: number | null
          offered_at: string
          offered_pay: number
          rank: number
          responded_at: string | null
          response: string | null
          score: number
          viewed_at: string | null
        }
        Insert: {
          alternatives_shown?: number | null
          config_snapshot_id: string
          created_at?: string
          decline_reason?: string | null
          delivery_id: string
          dispatch_algorithm_version: string
          driver_acceptance_rate?: number | null
          driver_distance_to_pickup_miles?: number | null
          driver_id: string
          driver_idle_time_minutes?: number | null
          driver_rating?: number | null
          id?: string
          latency_ms?: number | null
          offered_at?: string
          offered_pay: number
          rank: number
          responded_at?: string | null
          response?: string | null
          score: number
          viewed_at?: string | null
        }
        Update: {
          alternatives_shown?: number | null
          config_snapshot_id?: string
          created_at?: string
          decline_reason?: string | null
          delivery_id?: string
          dispatch_algorithm_version?: string
          driver_acceptance_rate?: number | null
          driver_distance_to_pickup_miles?: number | null
          driver_id?: string
          driver_idle_time_minutes?: number | null
          driver_rating?: number | null
          id?: string
          latency_ms?: number | null
          offered_at?: string
          offered_pay?: number
          rank?: number
          responded_at?: string | null
          response?: string | null
          score?: number
          viewed_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "dispatch_offers_config_snapshot_id_fkey"
            columns: ["config_snapshot_id"]
            isOneToOne: false
            referencedRelation: "config_snapshots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dispatch_offers_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dispatch_offers_dispatch_algorithm_version_fkey"
            columns: ["dispatch_algorithm_version"]
            isOneToOne: false
            referencedRelation: "algorithm_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "dispatch_offers_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      drivers: {
        Row: {
          approved: boolean | null
          id: string
          is_online: boolean
          updated_at: string | null
          vehicle_type: string | null
        }
        Insert: {
          approved?: boolean | null
          id: string
          is_online?: boolean
          updated_at?: string | null
          vehicle_type?: string | null
        }
        Update: {
          approved?: boolean | null
          id?: string
          is_online?: boolean
          updated_at?: string | null
          vehicle_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "drivers_id_fkey"
            columns: ["id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      earnings: {
        Row: {
          amount: number
          created_at: string | null
          delivery_id: string | null
          driver_id: string | null
          id: string
          paid_out: boolean | null
          platform_cut: number
        }
        Insert: {
          amount: number
          created_at?: string | null
          delivery_id?: string | null
          driver_id?: string | null
          id?: string
          paid_out?: boolean | null
          platform_cut: number
        }
        Update: {
          amount?: number
          created_at?: string | null
          delivery_id?: string | null
          driver_id?: string | null
          id?: string
          paid_out?: boolean | null
          platform_cut?: number
        }
        Relationships: [
          {
            foreignKeyName: "earnings_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "earnings_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      event_catalog: {
        Row: {
          category: string
          created_at: string
          description: string
          is_active: boolean
          json_schema: Json
          name: string
          retention_days: number
          updated_at: string
        }
        Insert: {
          category: string
          created_at?: string
          description: string
          is_active?: boolean
          json_schema: Json
          name: string
          retention_days?: number
          updated_at?: string
        }
        Update: {
          category?: string
          created_at?: string
          description?: string
          is_active?: boolean
          json_schema?: Json
          name?: string
          retention_days?: number
          updated_at?: string
        }
        Relationships: []
      }
      events: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_config_snapshot_id_fkey"
            columns: ["config_snapshot_id"]
            isOneToOne: false
            referencedRelation: "config_snapshots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_name_fkey"
            columns: ["name"]
            isOneToOne: false
            referencedRelation: "event_catalog"
            referencedColumns: ["name"]
          },
        ]
      }
      events_2026_09: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: []
      }
      events_2026_10: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: []
      }
      events_2026_11: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: []
      }
      events_2026_12: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: []
      }
      events_2027_01: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: []
      }
      events_2027_02: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: []
      }
      events_2027_03: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: []
      }
      events_2027_04: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: []
      }
      events_2027_05: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: []
      }
      events_2027_06: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: []
      }
      events_2027_07: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: []
      }
      events_2027_08: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: []
      }
      events_2027_09: {
        Row: {
          actor_id: string | null
          actor_type: string
          app_version: string | null
          config_snapshot_id: string | null
          created_at: string
          device_id: string | null
          entity_id: string | null
          entity_type: string | null
          experiment_assignments: Json | null
          id: string
          idempotency_key: string | null
          name: string
          occurred_at: string
          os: string | null
          props: Json
          received_at: string
          session_id: string | null
        }
        Insert: {
          actor_id?: string | null
          actor_type: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name: string
          occurred_at: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Update: {
          actor_id?: string | null
          actor_type?: string
          app_version?: string | null
          config_snapshot_id?: string | null
          created_at?: string
          device_id?: string | null
          entity_id?: string | null
          entity_type?: string | null
          experiment_assignments?: Json | null
          id?: string
          idempotency_key?: string | null
          name?: string
          occurred_at?: string
          os?: string | null
          props?: Json
          received_at?: string
          session_id?: string | null
        }
        Relationships: []
      }
      menu_item_options: {
        Row: {
          id: string
          is_available: boolean | null
          menu_item_id: string | null
          name: string
          price_modifier: number | null
        }
        Insert: {
          id?: string
          is_available?: boolean | null
          menu_item_id?: string | null
          name: string
          price_modifier?: number | null
        }
        Update: {
          id?: string
          is_available?: boolean | null
          menu_item_id?: string | null
          name?: string
          price_modifier?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "menu_item_options_menu_item_id_fkey"
            columns: ["menu_item_id"]
            isOneToOne: false
            referencedRelation: "menu_items"
            referencedColumns: ["id"]
          },
        ]
      }
      menu_items: {
        Row: {
          active: boolean | null
          category: string | null
          created_at: string | null
          description: string | null
          id: string
          name: string
          partner_id: string | null
          photo_url: string | null
          price: number
        }
        Insert: {
          active?: boolean | null
          category?: string | null
          created_at?: string | null
          description?: string | null
          id?: string
          name: string
          partner_id?: string | null
          photo_url?: string | null
          price: number
        }
        Update: {
          active?: boolean | null
          category?: string | null
          created_at?: string | null
          description?: string | null
          id?: string
          name?: string
          partner_id?: string | null
          photo_url?: string | null
          price?: number
        }
        Relationships: [
          {
            foreignKeyName: "menu_items_partner_id_fkey"
            columns: ["partner_id"]
            isOneToOne: false
            referencedRelation: "partners"
            referencedColumns: ["id"]
          },
        ]
      }
      partner_applications: {
        Row: {
          address: string
          business_name: string
          contact_email: string
          contact_name: string
          contact_phone: string
          id: string
          notes: string | null
          pos_system: string | null
          status: string | null
          submitted_at: string | null
        }
        Insert: {
          address: string
          business_name: string
          contact_email: string
          contact_name: string
          contact_phone: string
          id?: string
          notes?: string | null
          pos_system?: string | null
          status?: string | null
          submitted_at?: string | null
        }
        Update: {
          address?: string
          business_name?: string
          contact_email?: string
          contact_name?: string
          contact_phone?: string
          id?: string
          notes?: string | null
          pos_system?: string | null
          status?: string | null
          submitted_at?: string | null
        }
        Relationships: []
      }
      partners: {
        Row: {
          address: string
          approved: boolean | null
          average_prep_time_minutes: number | null
          business_name: string
          created_at: string | null
          founding_merchant: boolean | null
          id: string
          joined_during_pilot: boolean | null
          lat: number | null
          lng: number | null
          merchant_priority_score: number | null
          onboarding_fee_paid: boolean | null
          pickup_notes: string | null
          pos_system: string | null
          profile_id: string | null
        }
        Insert: {
          address: string
          approved?: boolean | null
          average_prep_time_minutes?: number | null
          business_name: string
          created_at?: string | null
          founding_merchant?: boolean | null
          id?: string
          joined_during_pilot?: boolean | null
          lat?: number | null
          lng?: number | null
          merchant_priority_score?: number | null
          onboarding_fee_paid?: boolean | null
          pickup_notes?: string | null
          pos_system?: string | null
          profile_id?: string | null
        }
        Update: {
          address?: string
          approved?: boolean | null
          average_prep_time_minutes?: number | null
          business_name?: string
          created_at?: string | null
          founding_merchant?: boolean | null
          id?: string
          joined_during_pilot?: boolean | null
          lat?: number | null
          lng?: number | null
          merchant_priority_score?: number | null
          onboarding_fee_paid?: boolean | null
          pickup_notes?: string | null
          pos_system?: string | null
          profile_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "partners_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      performance_metrics: {
        Row: {
          actual_prep_minutes: number | null
          actual_transit_minutes: number | null
          delivery_id: string
          driver_wait_at_merchant_minutes: number | null
          estimated_prep_minutes: number | null
          estimated_transit_minutes: number | null
          had_interaction_issues: boolean | null
          prep_delay_minutes: number | null
          transit_delay_minutes: number | null
        }
        Insert: {
          actual_prep_minutes?: number | null
          actual_transit_minutes?: number | null
          delivery_id: string
          driver_wait_at_merchant_minutes?: number | null
          estimated_prep_minutes?: number | null
          estimated_transit_minutes?: number | null
          had_interaction_issues?: boolean | null
          prep_delay_minutes?: number | null
          transit_delay_minutes?: number | null
        }
        Update: {
          actual_prep_minutes?: number | null
          actual_transit_minutes?: number | null
          delivery_id?: string
          driver_wait_at_merchant_minutes?: number | null
          estimated_prep_minutes?: number | null
          estimated_transit_minutes?: number | null
          had_interaction_issues?: boolean | null
          prep_delay_minutes?: number | null
          transit_delay_minutes?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "performance_metrics_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: true
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
      pricing_decisions: {
        Row: {
          actual_distance_miles: number | null
          actual_duration_minutes: number | null
          adjustments: Json | null
          components: Json
          config_snapshot_id: string
          created_at: string
          customer_total: number
          delivery_id: string
          driver_payout: number
          id: string
          inputs: Json
          platform_cut: number
          pricing_algorithm_version: string
          zone_assigned: number
        }
        Insert: {
          actual_distance_miles?: number | null
          actual_duration_minutes?: number | null
          adjustments?: Json | null
          components?: Json
          config_snapshot_id: string
          created_at?: string
          customer_total: number
          delivery_id: string
          driver_payout: number
          id?: string
          inputs: Json
          platform_cut: number
          pricing_algorithm_version: string
          zone_assigned: number
        }
        Update: {
          actual_distance_miles?: number | null
          actual_duration_minutes?: number | null
          adjustments?: Json | null
          components?: Json
          config_snapshot_id?: string
          created_at?: string
          customer_total?: number
          delivery_id?: string
          driver_payout?: number
          id?: string
          inputs?: Json
          platform_cut?: number
          pricing_algorithm_version?: string
          zone_assigned?: number
        }
        Relationships: [
          {
            foreignKeyName: "pricing_decisions_config_snapshot_id_fkey"
            columns: ["config_snapshot_id"]
            isOneToOne: false
            referencedRelation: "config_snapshots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pricing_decisions_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: true
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pricing_decisions_pricing_algorithm_version_fkey"
            columns: ["pricing_algorithm_version"]
            isOneToOne: false
            referencedRelation: "algorithm_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          cancellation_rate: number | null
          created_at: string | null
          full_name: string | null
          historical_tip_ratio: number | null
          id: string
          is_admin: boolean
          lifetime_deliveries: number | null
          phone: string | null
          priority_score: number | null
          role: string
        }
        Insert: {
          cancellation_rate?: number | null
          created_at?: string | null
          full_name?: string | null
          historical_tip_ratio?: number | null
          id: string
          is_admin?: boolean
          lifetime_deliveries?: number | null
          phone?: string | null
          priority_score?: number | null
          role: string
        }
        Update: {
          cancellation_rate?: number | null
          created_at?: string | null
          full_name?: string | null
          historical_tip_ratio?: number | null
          id?: string
          is_admin?: boolean
          lifetime_deliveries?: number | null
          phone?: string | null
          priority_score?: number | null
          role?: string
        }
        Relationships: []
      }
      quotes: {
        Row: {
          accepted_at: string | null
          components: Json
          config_snapshot_id: string
          created_at: string
          customer_id: string
          customer_total: number
          delivery_id: string | null
          distance_miles: number
          driver_payout: number
          dropoff_lat: number
          dropoff_lng: number
          estimated_duration_minutes: number | null
          expires_at: string
          id: string
          partner_id: string | null
          pickup_lat: number
          pickup_lng: number
          platform_cut: number
          pricing_algorithm_version: string
          status: string
          zone_assigned: number
        }
        Insert: {
          accepted_at?: string | null
          components?: Json
          config_snapshot_id: string
          created_at?: string
          customer_id: string
          customer_total: number
          delivery_id?: string | null
          distance_miles: number
          driver_payout: number
          dropoff_lat: number
          dropoff_lng: number
          estimated_duration_minutes?: number | null
          expires_at?: string
          id?: string
          partner_id?: string | null
          pickup_lat: number
          pickup_lng: number
          platform_cut: number
          pricing_algorithm_version: string
          status?: string
          zone_assigned: number
        }
        Update: {
          accepted_at?: string | null
          components?: Json
          config_snapshot_id?: string
          created_at?: string
          customer_id?: string
          customer_total?: number
          delivery_id?: string | null
          distance_miles?: number
          driver_payout?: number
          dropoff_lat?: number
          dropoff_lng?: number
          estimated_duration_minutes?: number | null
          expires_at?: string
          id?: string
          partner_id?: string | null
          pickup_lat?: number
          pickup_lng?: number
          platform_cut?: number
          pricing_algorithm_version?: string
          status?: string
          zone_assigned?: number
        }
        Relationships: [
          {
            foreignKeyName: "quotes_config_snapshot_id_fkey"
            columns: ["config_snapshot_id"]
            isOneToOne: false
            referencedRelation: "config_snapshots"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_partner_id_fkey"
            columns: ["partner_id"]
            isOneToOne: false
            referencedRelation: "partners"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_pricing_algorithm_version_fkey"
            columns: ["pricing_algorithm_version"]
            isOneToOne: false
            referencedRelation: "algorithm_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      ratings_and_reviews: {
        Row: {
          created_at: string | null
          delivery_id: string | null
          id: string
          rating_stars: number
          reviewee_id: string | null
          reviewee_type: string
          reviewer_id: string | null
          tags: string[] | null
          written_review: string | null
        }
        Insert: {
          created_at?: string | null
          delivery_id?: string | null
          id?: string
          rating_stars: number
          reviewee_id?: string | null
          reviewee_type: string
          reviewer_id?: string | null
          tags?: string[] | null
          written_review?: string | null
        }
        Update: {
          created_at?: string | null
          delivery_id?: string | null
          id?: string
          rating_stars?: number
          reviewee_id?: string | null
          reviewee_type?: string
          reviewer_id?: string | null
          tags?: string[] | null
          written_review?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ratings_and_reviews_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ratings_and_reviews_reviewee_id_fkey"
            columns: ["reviewee_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ratings_and_reviews_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      referral_codes: {
        Row: {
          code: string
          created_at: string | null
          expires_at: string | null
          id: string
          is_active: boolean | null
          label: string | null
          role: string
          used_at: string | null
          used_by: string | null
        }
        Insert: {
          code: string
          created_at?: string | null
          expires_at?: string | null
          id?: string
          is_active?: boolean | null
          label?: string | null
          role: string
          used_at?: string | null
          used_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string | null
          expires_at?: string | null
          id?: string
          is_active?: boolean | null
          label?: string | null
          role?: string
          used_at?: string | null
          used_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "referral_codes_used_by_fkey"
            columns: ["used_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      referral_redemptions: {
        Row: {
          created_at: string
          id: string
          redeemed_at: string
          redeemed_by: string
          referral_code_id: string
          role: string
        }
        Insert: {
          created_at?: string
          id?: string
          redeemed_at?: string
          redeemed_by: string
          referral_code_id: string
          role: string
        }
        Update: {
          created_at?: string
          id?: string
          redeemed_at?: string
          redeemed_by?: string
          referral_code_id?: string
          role?: string
        }
        Relationships: [
          {
            foreignKeyName: "referral_redemptions_redeemed_by_fkey"
            columns: ["redeemed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_redemptions_referral_code_id_fkey"
            columns: ["referral_code_id"]
            isOneToOne: false
            referencedRelation: "referral_codes"
            referencedColumns: ["id"]
          },
        ]
      }
      route_points: {
        Row: {
          delivery_id: string | null
          driver_speed: number | null
          id: string
          lat: number
          lng: number
          recorded_at: string | null
        }
        Insert: {
          delivery_id?: string | null
          driver_speed?: number | null
          id?: string
          lat: number
          lng: number
          recorded_at?: string | null
        }
        Update: {
          delivery_id?: string | null
          driver_speed?: number | null
          id?: string
          lat?: number
          lng?: number
          recorded_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "route_points_delivery_id_fkey"
            columns: ["delivery_id"]
            isOneToOne: false
            referencedRelation: "deliveries"
            referencedColumns: ["id"]
          },
        ]
      }
      tax_mileage_rates: {
        Row: {
          business_cents: number
          charity_cents: number | null
          created_at: string
          effective_from: string
          effective_to: string | null
          id: string
          medical_cents: number | null
          notes: string | null
          source_url: string | null
        }
        Insert: {
          business_cents: number
          charity_cents?: number | null
          created_at?: string
          effective_from: string
          effective_to?: string | null
          id?: string
          medical_cents?: number | null
          notes?: string | null
          source_url?: string | null
        }
        Update: {
          business_cents?: number
          charity_cents?: number | null
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          id?: string
          medical_cents?: number | null
          notes?: string | null
          source_url?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      advance_delivery_status: {
        Args: { p_delivery_id: string; p_new_status: string }
        Returns: {
          error: string
          success: boolean
        }[]
      }
      check_referral_code: { Args: { p_code: string }; Returns: boolean }
      check_user_role: { Args: { required_role: string }; Returns: boolean }
      claim_delivery: {
        Args: { p_delivery_id: string }
        Returns: {
          delivery_id: string
          error: string
          success: boolean
        }[]
      }
      create_delivery: {
        Args: {
          p_category: string
          p_config_snapshot_id?: string
          p_customer_id: string
          p_distance_miles: number
          p_dropoff_address: string
          p_dropoff_lat: number
          p_dropoff_lng: number
          p_estimated_duration_minutes: number
          p_notes?: string
          p_partner_id: string
          p_pickup_address: string
          p_pickup_lat: number
          p_pickup_lng: number
        }
        Returns: {
          delivery_id: string
          error: string
          pricing_breakdown: Json
          quote_id: string
          success: boolean
        }[]
      }
      current_role_is: { Args: { target_role: string }; Returns: boolean }
      get_active_algorithm_version: {
        Args: { p_kind: string }
        Returns: string
      }
      get_available_jobs: {
        Args: never
        Returns: {
          category: string
          distance_miles: number
          driver_payout: number
          dropoff_address: string
          dropoff_lat: number
          dropoff_lng: number
          estimated_duration_minutes: number
          fee_charged: number
          id: string
          partner_name: string
          pickup_address: string
          pickup_lat: number
          pickup_lng: number
          pickup_notes: string
          platform_cut: number
          requested_at: string
          zone_assigned: number
        }[]
      }
      get_mileage_rate: {
        Args: { p_date: string }
        Returns: {
          business_cents: number
          charity_cents: number
          medical_cents: number
        }[]
      }
      get_my_role: { Args: never; Returns: string }
      is_admin: { Args: never; Returns: boolean }
      preview_config_impact: {
        Args: { p_days_lookback?: number; p_proposed: Json }
        Returns: {
          current_value: number
          delta: number
          delta_pct: number
          metric: string
          proposed_value: number
        }[]
      }
      redeem_referral_code: {
        Args: { p_code: string }
        Returns: {
          error: string
          profile_id: string
          role: string
          success: boolean
        }[]
      }
      release_delivery: {
        Args: { p_delivery_id: string }
        Returns: {
          error: string
          success: boolean
        }[]
      }
      resolve_all_config: {
        Args: { p_at?: string; p_ctx?: Json }
        Returns: {
          config: Json
          snapshot_id: string
        }[]
      }
      resolve_config: {
        Args: { p_at?: string; p_ctx?: Json; p_key: string }
        Returns: Json
      }
      validate_config_constraints: {
        Args: { p_proposed: Json }
        Returns: {
          constraint_name: string
          message: string
          passed: boolean
        }[]
      }
      zone_pricing: {
        Args: { miles: number }
        Returns: {
          driver_payout: number
          fee: number
          platform_cut: number
          zone: number
        }[]
      }
    }
    Enums: {
      delivery_stage:
        | "pending"
        | "offered"
        | "claimed"
        | "en_route"
        | "in_progress"
        | "completed"
        | "cancelled"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  private: {
    Enums: {},
  },
  public: {
    Enums: {
      delivery_stage: [
        "pending",
        "offered",
        "claimed",
        "en_route",
        "in_progress",
        "completed",
        "cancelled",
      ],
    },
  },
} as const
