-- Migration 212: Add roomchargesposted column to night audit table
-- Applied: 2026-08-26

ALTER TABLE hotelnightaudits ADD COLUMN IF NOT EXISTS roomchargesposted INT DEFAULT 0;
