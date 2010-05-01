CREATE TABLE messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  time INT,
  user VARCHAR(16),
  nick VARCHAR(16),
  channel VARCHAR(16),
  body TEXT
);