ALTER TABLE rucio.claude_history
  ADD COLUMN IF NOT EXISTS metadata JSONB,
  ADD COLUMN IF NOT EXISTS model TEXT;

NOTIFY pgrst, 'reload schema';
