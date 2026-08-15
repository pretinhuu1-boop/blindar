-- +goose Up
ALTER TABLE users DROP COLUMN legacy_token;

-- +goose Down
ALTER TABLE users ADD COLUMN legacy_token text;
