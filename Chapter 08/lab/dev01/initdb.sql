CREATE ROLE paymentsvc LOGIN PASSWORD 'hunter2-payments-prod';
CREATE DATABASE paymentsdb OWNER paymentsvc;

\connect paymentsdb

CREATE TABLE payments (
    id           integer PRIMARY KEY,
    reference    text    NOT NULL,
    amount_cents integer NOT NULL,
    currency     char(3) NOT NULL,
    status       text    NOT NULL
);

INSERT INTO payments (id, reference, amount_cents, currency, status) VALUES
  (1001, 'INV-2026-0001', 249900, 'EUR', 'settled'),
  (1002, 'INV-2026-0002',  18050, 'EUR', 'pending'),
  (1003, 'INV-2026-0003', 990000, 'GBP', 'failed');

ALTER TABLE payments OWNER TO paymentsvc;
