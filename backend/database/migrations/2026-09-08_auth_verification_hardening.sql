-- Verification attempts are shared by phone, email, and password-reset flows.
ALTER TABLE phone_verifications
    ADD COLUMN IF NOT EXISTS attempts INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_phone_verifications_active
    ON phone_verifications (user_id, phone_number, created_at DESC)
    WHERE used = FALSE;
