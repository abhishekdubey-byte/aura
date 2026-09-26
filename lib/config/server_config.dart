/// Public client configuration. Never put a service-role key in the app.
class ServerConfig {
  static const url = String.fromEnvironment(
    'AURA_SUPABASE_URL',
    defaultValue: 'https://stjogqzjlbiuuubjsosd.supabase.co',
  );
  static const publicKey = String.fromEnvironment(
    'AURA_SUPABASE_PUBLIC_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN0am9ncXpqbGJpdXV1Ympzb3NkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzODg3NTIsImV4cCI6MjEwNDk2NDc1Mn0.Xkb2Bq90XQyVbEosexfhCbHarYsWDXrzyRr39FDw50g',
  );
  static const captureBucket = 'captures';
}
