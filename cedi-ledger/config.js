// Cedi Ledger connection settings.
// Leave supabaseUrl empty to run in single-device mode (no accounts).
// The anon key is safe to publish: row-level security in schema.sql decides
// what each signed-in person can read and write.
window.CEDI_CONFIG = {
  supabaseUrl: "",
  supabaseAnonKey: "",
  // Set to true once Google is switched on under Authentication > Providers in Supabase.
  googleEnabled: false
};
