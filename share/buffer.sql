CREATE TABLE window_buffer (
  id INT NOT NULL PRIMARY KEY AUTO_INCREMENT,
  msgid INT NOT NULL,
  window_id INT NOT NULL,
  message BLOB
);
