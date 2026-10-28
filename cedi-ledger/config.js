// Cedi Ledger connection settings.
// Leave supabaseUrl empty to run in single-device mode (no accounts).
// The publishable key is safe to publish: row-level security in schema.sql
// decides what each signed-in person can read and write.
window.CEDI_CONFIG = {
  supabaseUrl: "https://xtmqkcatnoyrdsyyulag.supabase.co",
  supabaseAnonKey: "sb_publishable_VPIQV7H0fLzpDkyfmHmN3A_DDJQj4Ho",
  // Set to true once Google is switched on under Authentication > Providers in Supabase.
  googleEnabled: true,
  // Set to true once the Supabase email templates include {{ .Token }} (needs custom SMTP).
  emailCodes: false
};
