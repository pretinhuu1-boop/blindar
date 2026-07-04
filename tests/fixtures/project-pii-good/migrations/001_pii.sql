-- FIXTURE SEGURA — colunas cifradas.
ALTER TABLE patients ADD COLUMN dek_ciphertext BYTEA;
ALTER TABLE patients ADD COLUMN phone_cipher BYTEA;
ALTER TABLE patients ADD COLUMN email_cipher BYTEA;
