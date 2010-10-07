CREATE TABLE window_buffer (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  msgid INT NOT NULL,
  window_id INT NOT NULL,
  message BLOB
);
