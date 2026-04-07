CREATE DATABASE IF NOT EXISTS stakpak_agent_db;
USE stakpak_agent_db;

CREATE TABLE IF NOT EXISTS tasks (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  title       VARCHAR(255)  NOT NULL,
  description TEXT          DEFAULT NULL,
  status      ENUM('pending', 'in_progress', 'done') NOT NULL DEFAULT 'pending',
  created_at  TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
